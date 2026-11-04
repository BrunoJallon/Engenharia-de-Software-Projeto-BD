-- =====================================================================
-- CollectionLine · US04 — Editar e excluir cobrança
-- Regras (decididas pelo cliente):
--   * só dá para editar ou excluir enquanto NENHUMA parcela estiver paga;
--   * editar = trocar cliente, valor total, quantidade e 1º vencimento: as
--     parcelas são apagadas e geradas de novo com a MESMA regra do cadastro
--     (US01); a data de emissão não muda;
--   * excluir apaga a cobrança e, pelo ON DELETE CASCADE, as parcelas.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Auxiliar: confere se a cobrança existe, TRAVA a linha (FOR UPDATE) e
-- recusa se alguma parcela já estiver paga. Devolve a data de emissão.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION travar_cobranca_sem_pagamento(p_id_cobranca INTEGER)
RETURNS DATE
LANGUAGE plpgsql
AS $$
DECLARE
    v_emissao DATE;
BEGIN
    IF p_id_cobranca IS NULL THEN
        RAISE EXCEPTION 'Informe a cobrança.' USING ERRCODE = 'invalid_parameter_value';
    END IF;

    -- Mesma trava da US02: quem mexer na mesma cobrança ao mesmo tempo espera.
    SELECT data_emissao INTO v_emissao FROM cobranca WHERE id = p_id_cobranca FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Cobrança % não encontrada.', p_id_cobranca USING ERRCODE = 'no_data_found';
    END IF;

    IF EXISTS (SELECT 1 FROM parcela WHERE id_cobranca = p_id_cobranca AND status = 'paga') THEN
        RAISE EXCEPTION 'A cobrança nº % já tem parcela paga e não pode ser alterada nem excluída. Desfaça os pagamentos antes.',
            p_id_cobranca
            USING ERRCODE = 'object_not_in_prerequisite_state';
    END IF;

    RETURN v_emissao;
END;
$$;

-- ---------------------------------------------------------------------
-- Editar a cobrança inteira
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION editar_cobranca(
    p_id_cobranca         INTEGER,
    p_cpf_cliente         CHAR(11),
    p_valor               NUMERIC,
    p_qtd_parcelas        INTEGER,
    p_primeiro_vencimento DATE
) RETURNS INTEGER  -- id da cobrança
LANGUAGE plpgsql
AS $$
DECLARE
    v_emissao       DATE;
    v_ultimo_venc   DATE;
    v_valor_base    NUMERIC(10,2);
    v_valor_parcela NUMERIC(10,2);
BEGIN
    -- 1) Todos os parâmetros são obrigatórios.
    IF p_id_cobranca IS NULL OR p_cpf_cliente IS NULL OR p_valor IS NULL
       OR p_qtd_parcelas IS NULL OR p_primeiro_vencimento IS NULL THEN
        RAISE EXCEPTION 'Todos os parâmetros são obrigatórios (cobrança, CPF, valor, quantidade de parcelas e primeiro vencimento).'
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    -- 2) A cobrança existe, fica travada e não tem parcela paga.
    v_emissao := travar_cobranca_sem_pagamento(p_id_cobranca);

    -- 3) As mesmas regras de valor, quantidade e datas do cadastro (US01).
    IF p_valor = 'NaN' OR p_valor <= 0 THEN
        RAISE EXCEPTION 'O valor da cobrança deve ser maior que zero (recebido: %).', replace(p_valor::text, '.', ',')
            USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF p_valor <> round(p_valor, 2) THEN
        RAISE EXCEPTION 'O valor da cobrança deve ter no máximo 2 casas decimais (recebido: %).', replace(p_valor::text, '.', ',')
            USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF p_valor > 99999999.99 THEN
        RAISE EXCEPTION 'O valor máximo de uma cobrança é R$ 99.999.999,99.'
            USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF p_qtd_parcelas < 1 OR p_qtd_parcelas > 360 THEN
        RAISE EXCEPTION 'A quantidade de parcelas deve ser de 1 a 360 (recebido: %).', p_qtd_parcelas
            USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF p_valor < p_qtd_parcelas * 0.01 THEN
        RAISE EXCEPTION 'O valor % não pode ser dividido em % parcelas: cada parcela precisa de pelo menos R$ 0,01.',
            replace(p_valor::text, '.', ','), p_qtd_parcelas
            USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF NOT isfinite(p_primeiro_vencimento) OR p_primeiro_vencimento > DATE '9999-12-31' THEN
        RAISE EXCEPTION 'O primeiro vencimento precisa ser uma data de calendário até 31/12/9999.'
            USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF p_primeiro_vencimento < v_emissao THEN
        RAISE EXCEPTION 'O primeiro vencimento (%) não pode ser anterior à data de emissão (%).',
            to_char(p_primeiro_vencimento, 'DD/MM/YYYY'), to_char(v_emissao, 'DD/MM/YYYY')
            USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM cliente WHERE cpf = p_cpf_cliente) THEN
        RAISE EXCEPTION 'Cliente com CPF % não está cadastrado.', p_cpf_cliente
            USING ERRCODE = 'no_data_found';
    END IF;

    v_ultimo_venc := (p_primeiro_vencimento + make_interval(months => p_qtd_parcelas - 1))::date;
    IF v_ultimo_venc > DATE '9999-12-31' THEN
        RAISE EXCEPTION 'Com % parcelas, o último vencimento passaria de 31/12/9999.', p_qtd_parcelas
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    -- 4) Atualiza a cobrança (a data de emissão fica como estava).
    UPDATE cobranca
       SET cpf_cliente = p_cpf_cliente,
           valor = p_valor,
           data_vencimento = v_ultimo_venc
     WHERE id = p_id_cobranca;

    -- 5) Apaga as parcelas antigas e gera as novas com a regra do cadastro:
    --    valor base truncado e a sobra na última; meses sempre a partir do 1º.
    DELETE FROM parcela WHERE id_cobranca = p_id_cobranca;

    v_valor_base := trunc(p_valor / p_qtd_parcelas, 2);
    FOR k IN 1 .. p_qtd_parcelas LOOP
        IF k < p_qtd_parcelas THEN
            v_valor_parcela := v_valor_base;
        ELSE
            v_valor_parcela := p_valor - v_valor_base * (p_qtd_parcelas - 1);
        END IF;

        INSERT INTO parcela (id_cobranca, numero_parcela, total_parcelas, valor, data_vencimento, status)
        VALUES (p_id_cobranca, k, p_qtd_parcelas, v_valor_parcela,
                (p_primeiro_vencimento + make_interval(months => k - 1))::date, 'pendente');
    END LOOP;

    RETURN p_id_cobranca;
END;
$$;

-- ---------------------------------------------------------------------
-- Excluir a cobrança (as parcelas vão junto pelo ON DELETE CASCADE)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION excluir_cobranca(p_id_cobranca INTEGER)
RETURNS INTEGER  -- id da cobrança excluída
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM travar_cobranca_sem_pagamento(p_id_cobranca);
    DELETE FROM cobranca WHERE id = p_id_cobranca;
    RETURN p_id_cobranca;
END;
$$;
