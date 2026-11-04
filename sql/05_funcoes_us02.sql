-- =====================================================================
-- CollectionLine · US02 — Funções para editar e pagar parcelas
-- Regras (decididas pelo cliente):
--   * editar valor  -> o valor da cobrança vira a nova soma das parcelas;
--   * editar data   -> nunca antes da emissão e sem sair da ordem
--                      (entre a parcela anterior e a próxima);
--   * parcela paga  -> fica travada; dá para desfazer o pagamento;
--   * todas pagas   -> a cobrança fica paga.
-- Cada função roda numa única transação: se algo falhar, nada fica gravado.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Auxiliar: confere se a parcela existe e TRAVA a cobrança dela.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION travar_cobranca_da_parcela(p_id_parcela INTEGER)
RETURNS INTEGER  -- id da cobrança (já travada)
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_cobranca INTEGER;
BEGIN
    IF p_id_parcela IS NULL THEN
        RAISE EXCEPTION 'Informe a parcela.'
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    SELECT id_cobranca INTO v_id_cobranca FROM parcela WHERE id = p_id_parcela;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Parcela % não encontrada.', p_id_parcela
            USING ERRCODE = 'no_data_found';
    END IF;

    -- FOR UPDATE trava a linha da cobrança até o fim da transação. Se duas
    -- pessoas mexerem na mesma cobrança ao mesmo tempo, a segunda espera a
    -- primeira terminar: assim a soma e o status da cobrança nunca se perdem.
    PERFORM 1 FROM cobranca WHERE id = v_id_cobranca FOR UPDATE;

    RETURN v_id_cobranca;
END;
$$;

-- ---------------------------------------------------------------------
-- Editar valor e vencimento de uma parcela pendente
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION editar_parcela(
    p_id_parcela      INTEGER,
    p_valor           NUMERIC,
    p_data_vencimento DATE
) RETURNS INTEGER  -- id da cobrança da parcela
LANGUAGE plpgsql
AS $$
DECLARE
    v_parcela    parcela%ROWTYPE;
    v_emissao    DATE;
    v_anterior   DATE;
    v_proxima    DATE;
    v_novo_total NUMERIC;
BEGIN
    -- 1) Todos os parâmetros são obrigatórios.
    IF p_id_parcela IS NULL OR p_valor IS NULL OR p_data_vencimento IS NULL THEN
        RAISE EXCEPTION 'Informe a parcela, o novo valor e o novo vencimento.'
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    -- 2) Mesmas regras de dinheiro do cadastro: positivo (e não NaN) e no
    --    máximo centavos.
    IF p_valor = 'NaN' OR p_valor <= 0 THEN
        RAISE EXCEPTION 'O valor da parcela deve ser maior que zero (recebido: %).',
            replace(p_valor::text, '.', ',')
            USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF p_valor <> round(p_valor, 2) THEN
        RAISE EXCEPTION 'O valor da parcela deve ter no máximo 2 casas decimais (recebido: %).',
            replace(p_valor::text, '.', ',')
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    -- 2b) Data de calendário de verdade: sem 'infinity' e com ano de até 4 dígitos.
    IF NOT isfinite(p_data_vencimento) OR p_data_vencimento > DATE '9999-12-31' THEN
        RAISE EXCEPTION 'O vencimento precisa ser uma data de calendário até 31/12/9999.'
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    -- 3) A parcela tem que existir; a cobrança dela fica travada até o fim.
    PERFORM travar_cobranca_da_parcela(p_id_parcela);
    -- Lê a parcela depois da trava, para enxergar a versão mais recente.
    SELECT * INTO v_parcela FROM parcela WHERE id = p_id_parcela;

    -- 4) Parcela paga não muda: é preciso desfazer o pagamento antes.
    IF v_parcela.status = 'paga' THEN
        RAISE EXCEPTION 'A parcela %/% já está paga e não pode ser alterada. Desfaça o pagamento antes.',
            v_parcela.numero_parcela, v_parcela.total_parcelas
            USING ERRCODE = 'object_not_in_prerequisite_state';
    END IF;

    -- 5) Vencimento nunca antes da emissão da cobrança...
    SELECT data_emissao INTO v_emissao FROM cobranca WHERE id = v_parcela.id_cobranca;
    IF p_data_vencimento < v_emissao THEN
        RAISE EXCEPTION 'O vencimento (%) não pode ser anterior à emissão da cobrança (%).',
            to_char(p_data_vencimento, 'DD/MM/YYYY'), to_char(v_emissao, 'DD/MM/YYYY')
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    -- ...e sem sair da ordem: entre a parcela anterior e a próxima.
    -- (Se não existir anterior ou próxima, a variável fica nula e a regra não se aplica.
    --  Vencer no mesmo dia da vizinha é aceito.)
    SELECT data_vencimento INTO v_anterior FROM parcela
     WHERE id_cobranca = v_parcela.id_cobranca AND numero_parcela = v_parcela.numero_parcela - 1;
    SELECT data_vencimento INTO v_proxima FROM parcela
     WHERE id_cobranca = v_parcela.id_cobranca AND numero_parcela = v_parcela.numero_parcela + 1;

    IF v_anterior IS NOT NULL AND p_data_vencimento < v_anterior THEN
        RAISE EXCEPTION 'A parcela %/% não pode vencer antes da parcela anterior (%).',
            v_parcela.numero_parcela, v_parcela.total_parcelas, to_char(v_anterior, 'DD/MM/YYYY')
            USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF v_proxima IS NOT NULL AND p_data_vencimento > v_proxima THEN
        RAISE EXCEPTION 'A parcela %/% não pode vencer depois da próxima parcela (%).',
            v_parcela.numero_parcela, v_parcela.total_parcelas, to_char(v_proxima, 'DD/MM/YYYY')
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    -- 6) O valor da cobrança vai virar a nova soma, e ela precisa caber em NUMERIC(10,2).
    SELECT COALESCE(sum(valor), 0) + p_valor INTO v_novo_total
      FROM parcela
     WHERE id_cobranca = v_parcela.id_cobranca AND id <> p_id_parcela;
    IF v_novo_total > 99999999.99 THEN
        RAISE EXCEPTION 'Com esse valor, o total da cobrança passaria do limite de R$ 99.999.999,99.'
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    -- 7) Grava a parcela...
    UPDATE parcela
       SET valor = p_valor,
           data_vencimento = p_data_vencimento
     WHERE id = p_id_parcela;

    -- ...e mantém as duas regras da cobrança: valor = soma das parcelas e
    -- vencimento = vencimento da última parcela.
    UPDATE cobranca
       SET valor = v_novo_total,
           data_vencimento = (SELECT data_vencimento FROM parcela
                               WHERE id_cobranca = v_parcela.id_cobranca
                               ORDER BY numero_parcela DESC
                               LIMIT 1)
     WHERE id = v_parcela.id_cobranca;

    RETURN v_parcela.id_cobranca;
END;
$$;

-- ---------------------------------------------------------------------
-- Marcar uma parcela como paga
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pagar_parcela(p_id_parcela INTEGER)
RETURNS INTEGER  -- id da cobrança da parcela
LANGUAGE plpgsql
AS $$
DECLARE
    v_parcela parcela%ROWTYPE;
BEGIN
    PERFORM travar_cobranca_da_parcela(p_id_parcela);
    SELECT * INTO v_parcela FROM parcela WHERE id = p_id_parcela;

    IF v_parcela.status = 'paga' THEN
        RAISE EXCEPTION 'A parcela %/% já está paga.',
            v_parcela.numero_parcela, v_parcela.total_parcelas
            USING ERRCODE = 'object_not_in_prerequisite_state';
    END IF;

    UPDATE parcela SET status = 'paga' WHERE id = p_id_parcela;

    -- Se não sobrou nenhuma parcela em aberto, a cobrança inteira está paga.
    IF NOT EXISTS (SELECT 1 FROM parcela
                    WHERE id_cobranca = v_parcela.id_cobranca AND status <> 'paga') THEN
        UPDATE cobranca SET status_pagamento = 'paga' WHERE id = v_parcela.id_cobranca;
    END IF;

    RETURN v_parcela.id_cobranca;
END;
$$;

-- ---------------------------------------------------------------------
-- Desfazer o pagamento de uma parcela (para corrigir um clique errado)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION desfazer_pagamento_parcela(p_id_parcela INTEGER)
RETURNS INTEGER  -- id da cobrança da parcela
LANGUAGE plpgsql
AS $$
DECLARE
    v_parcela parcela%ROWTYPE;
BEGIN
    PERFORM travar_cobranca_da_parcela(p_id_parcela);
    SELECT * INTO v_parcela FROM parcela WHERE id = p_id_parcela;

    IF v_parcela.status <> 'paga' THEN
        RAISE EXCEPTION 'A parcela %/% não está paga: não há pagamento para desfazer.',
            v_parcela.numero_parcela, v_parcela.total_parcelas
            USING ERRCODE = 'object_not_in_prerequisite_state';
    END IF;

    UPDATE parcela SET status = 'pendente' WHERE id = p_id_parcela;

    -- Com uma parcela em aberto de novo, a cobrança também volta a ficar pendente.
    UPDATE cobranca SET status_pagamento = 'pendente' WHERE id = v_parcela.id_cobranca;

    RETURN v_parcela.id_cobranca;
END;
$$;
