-- =====================================================================
-- CollectionLine · US07 — Ações direto na lista de pendentes:
-- excluir uma parcela só e pagar várias parcelas de uma vez.
-- (Excluir a cobrança inteira já existe: excluir_cobranca, da US04.)
-- =====================================================================
SET client_min_messages = warning;

-- ---------------------------------------------------------------------
-- 1) Excluir uma parcela só
-- ---------------------------------------------------------------------
-- Regras:
--  - parcela paga não pode ser excluída (desfaça o pagamento antes);
--  - a única parcela da cobrança também não: exclua a cobrança inteira;
--  - as parcelas que sobram são renumeradas (excluir a 2/3 deixa 1/2 e 2/2);
--  - a cobrança passa a valer a soma das parcelas que sobraram (a mesma
--    regra da edição de parcela, US02), e o "último vencimento" é o da
--    última parcela que sobrou.
CREATE OR REPLACE FUNCTION excluir_parcela(p_id_parcela INTEGER)
RETURNS INTEGER  -- id da cobrança da parcela
LANGUAGE plpgsql
AS $$
DECLARE
    v_parcela parcela%ROWTYPE;
    v_qtd     INTEGER;
BEGIN
    PERFORM travar_cobranca_da_parcela(p_id_parcela);   -- confere se existe e trava a cobrança
    SELECT * INTO v_parcela FROM parcela WHERE id = p_id_parcela;

    IF v_parcela.status = 'paga' THEN
        RAISE EXCEPTION 'A parcela %/% está paga: desfaça o pagamento antes de excluir.',
            v_parcela.numero_parcela, v_parcela.total_parcelas
            USING ERRCODE = 'object_not_in_prerequisite_state';
    END IF;

    SELECT count(*) INTO v_qtd FROM parcela WHERE id_cobranca = v_parcela.id_cobranca;
    IF v_qtd = 1 THEN
        RAISE EXCEPTION 'Esta é a única parcela da cobrança nº %: exclua a cobrança inteira.',
            v_parcela.id_cobranca
            USING ERRCODE = 'object_not_in_prerequisite_state';
    END IF;

    DELETE FROM parcela WHERE id = p_id_parcela;

    -- Renumeração em dois passos. O UNIQUE (id_cobranca, numero_parcela) é
    -- conferido linha a linha durante o UPDATE: se a 3 virasse 2 enquanto a
    -- 2 antiga ainda existe, daria erro. Então primeiro todas "saem do
    -- caminho" (+400, acima do limite de 360 parcelas) e depois recebem o
    -- número novo, na ordem em que estavam.
    UPDATE parcela
       SET numero_parcela = numero_parcela + 400,
           total_parcelas = total_parcelas + 400
     WHERE id_cobranca = v_parcela.id_cobranca;

    UPDATE parcela p
       SET numero_parcela = n.novo_numero,
           total_parcelas = v_qtd - 1
      FROM (SELECT id, row_number() OVER (ORDER BY numero_parcela) AS novo_numero
              FROM parcela
             WHERE id_cobranca = v_parcela.id_cobranca) AS n
     WHERE p.id = n.id;

    UPDATE cobranca co
       SET valor            = s.soma,
           data_vencimento  = s.ultimo_vencimento,
           status_pagamento = CASE WHEN s.pendentes = 0 THEN 'paga' ELSE 'pendente' END
      FROM (SELECT sum(valor)                               AS soma,
                   max(data_vencimento)                     AS ultimo_vencimento,
                   count(*) FILTER (WHERE status <> 'paga') AS pendentes
              FROM parcela
             WHERE id_cobranca = v_parcela.id_cobranca) AS s
     WHERE co.id = v_parcela.id_cobranca;

    RETURN v_parcela.id_cobranca;
END;
$$;

-- ---------------------------------------------------------------------
-- 2) Pagar várias parcelas de uma vez, na mesma data
-- ---------------------------------------------------------------------
-- Usa a pagar_parcela (US06) para cada uma, então valem as mesmas regras.
-- É "tudo ou nada": se uma falhar (já paga, data no futuro...), a função
-- inteira é desfeita e nenhuma fica paga.
CREATE OR REPLACE FUNCTION pagar_parcelas(p_ids_parcelas INTEGER[], p_data_pagamento DATE DEFAULT CURRENT_DATE)
RETURNS INTEGER  -- quantas parcelas foram pagas
LANGUAGE plpgsql
AS $$
DECLARE
    v_id  INTEGER;
    v_qtd INTEGER := 0;
BEGIN
    IF p_ids_parcelas IS NULL OR cardinality(p_ids_parcelas) = 0 THEN
        RAISE EXCEPTION 'Escolha ao menos uma parcela para pagar.'
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    -- DISTINCT: o mesmo id duas vezes conta uma vez só. ORDER BY: travar
    -- sempre na mesma ordem evita que duas pessoas fiquem esperando uma
    -- pela outra para sempre (deadlock).
    FOR v_id IN SELECT DISTINCT x FROM unnest(p_ids_parcelas) AS x ORDER BY x LOOP
        PERFORM pagar_parcela(v_id, p_data_pagamento);
        v_qtd := v_qtd + 1;
    END LOOP;

    RETURN v_qtd;
END;
$$;
