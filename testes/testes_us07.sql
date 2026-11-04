-- =====================================================================
-- CollectionLine · US07 — Testes de aceitação (excluir uma parcela e
-- pagar várias de uma vez). Transação que termina em ROLLBACK.
-- =====================================================================
\set ON_ERROR_STOP on
BEGIN;
SET client_min_messages = notice;
SET plpgsql.check_asserts = on;

INSERT INTO cliente (cpf, nome, telefone) VALUES
    ('70000000001', 'Cliente Lista Um', '5583700000001');

-- ---------------------------------------------------------------------
-- CA1 – Excluir uma parcela renumera as outras e ajusta a cobrança
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_cob INTEGER;
    v_co  cobranca%ROWTYPE;
BEGIN
    -- R$ 100,00 em 3x: 33,33 + 33,33 + 33,34, vencendo 10/01, 10/02 e 10/03/2027.
    v_cob := cadastrar_cobranca_parcelada('70000000001', 100.00, 3, DATE '2027-01-10');

    -- Exclui a do meio (2/3).
    PERFORM excluir_parcela((SELECT id FROM parcela WHERE id_cobranca = v_cob AND numero_parcela = 2));

    ASSERT (SELECT array_agg(numero_parcela || '/' || total_parcelas ORDER BY numero_parcela)
              FROM parcela WHERE id_cobranca = v_cob) = ARRAY['1/2', '2/2'],
           'CA1: deveriam sobrar as parcelas 1/2 e 2/2';
    ASSERT (SELECT array_agg(data_vencimento ORDER BY numero_parcela) FROM parcela WHERE id_cobranca = v_cob)
           = ARRAY[DATE '2027-01-10', DATE '2027-03-10'],
           'CA1: as parcelas que sobraram deveriam manter os vencimentos';

    SELECT * INTO v_co FROM cobranca WHERE id = v_cob;
    ASSERT v_co.valor = 66.67, 'CA1: a cobrança deveria valer 33,33 + 33,34 = 66,67';
    ASSERT v_co.data_vencimento = DATE '2027-03-10', 'CA1: o último vencimento deveria ser 10/03/2027';

    -- Excluindo a última (2/2), o último vencimento passa a ser o da 1/1.
    PERFORM excluir_parcela((SELECT id FROM parcela WHERE id_cobranca = v_cob AND numero_parcela = 2));
    SELECT * INTO v_co FROM cobranca WHERE id = v_cob;
    ASSERT v_co.valor = 33.33 AND v_co.data_vencimento = DATE '2027-01-10',
           'CA1: depois de excluir a 2/2, a cobrança deveria valer 33,33 e vencer em 10/01/2027';
    ASSERT (SELECT numero_parcela || '/' || total_parcelas FROM parcela WHERE id_cobranca = v_cob) = '1/1',
           'CA1: deveria sobrar só a 1/1';

    RAISE NOTICE 'OK  CA1 - excluir uma parcela renumera as outras e ajusta valor e último vencimento';
END $$;

-- ---------------------------------------------------------------------
-- CA2 – Não exclui parcela paga, a única parcela, nem parcela inexistente
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_cob  INTEGER;
    v_unica INTEGER;
BEGIN
    v_cob := cadastrar_cobranca_parcelada('70000000001', 50.00, 2, CURRENT_DATE + 5);
    PERFORM pagar_parcela((SELECT id FROM parcela WHERE id_cobranca = v_cob AND numero_parcela = 1));

    BEGIN
        PERFORM excluir_parcela((SELECT id FROM parcela WHERE id_cobranca = v_cob AND numero_parcela = 1));
        RAISE EXCEPTION 'FALHOU CA2: parcela paga não deveria ser excluída';
    EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
    END;

    v_unica := cadastrar_cobranca_parcelada('70000000001', 10.00, 1, CURRENT_DATE + 5);   -- cobrança à vista
    v_unica := (SELECT id FROM parcela WHERE id_cobranca = v_unica);                       -- a parcela dela
    BEGIN
        PERFORM excluir_parcela(v_unica);
        RAISE EXCEPTION 'FALHOU CA2: a única parcela não deveria ser excluída';
    EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
    END;

    BEGIN
        PERFORM excluir_parcela(-1);
        RAISE EXCEPTION 'FALHOU CA2: parcela inexistente deveria ser recusada';
    EXCEPTION WHEN no_data_found THEN NULL;
    END;

    ASSERT (SELECT count(*) FROM parcela WHERE id_cobranca = v_cob) = 2, 'CA2: nada deveria ter sido excluído';
    RAISE NOTICE 'OK  CA2 - não exclui parcela paga, a única parcela, nem inexistente (3 casos)';
END $$;

-- ---------------------------------------------------------------------
-- CA3 – Excluir a última pendente deixa a cobrança paga
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_cob INTEGER;
BEGIN
    v_cob := cadastrar_cobranca_parcelada('70000000001', 20.00, 2, CURRENT_DATE + 5);
    PERFORM pagar_parcela((SELECT id FROM parcela WHERE id_cobranca = v_cob AND numero_parcela = 1));
    PERFORM excluir_parcela((SELECT id FROM parcela WHERE id_cobranca = v_cob AND numero_parcela = 2));

    ASSERT (SELECT status_pagamento FROM cobranca WHERE id = v_cob) = 'paga',
           'CA3: sem parcela pendente, a cobrança deveria ficar paga';
    RAISE NOTICE 'OK  CA3 - excluir a última parcela pendente deixa a cobrança paga';
END $$;

-- ---------------------------------------------------------------------
-- CA4 – Pagar várias parcelas de uma vez
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_cob INTEGER;
    v_ids INTEGER[];
BEGIN
    v_cob := cadastrar_cobranca_parcelada('70000000001', 90.00, 3, CURRENT_DATE + 5);
    v_ids := ARRAY(SELECT id FROM parcela WHERE id_cobranca = v_cob ORDER BY numero_parcela);

    -- Duas específicas (a 1 e a 3), com o mesmo id repetido: conta uma vez.
    ASSERT pagar_parcelas(ARRAY[v_ids[1], v_ids[3], v_ids[3]], CURRENT_DATE - 1) = 2,
           'CA4: deveria pagar 2 parcelas';
    ASSERT (SELECT array_agg(status ORDER BY numero_parcela) FROM parcela WHERE id_cobranca = v_cob)
           = ARRAY['paga', 'pendente', 'paga']::VARCHAR[], 'CA4: só a 1 e a 3 deveriam estar pagas';
    ASSERT (SELECT bool_and(data_pagamento = CURRENT_DATE - 1) FROM parcela
             WHERE id_cobranca = v_cob AND status = 'paga'), 'CA4: as duas deveriam ter a data informada';
    ASSERT (SELECT status_pagamento FROM cobranca WHERE id = v_cob) = 'pendente', 'CA4: cobrança ainda pendente';

    -- A que faltava: agora a cobrança inteira fica paga.
    PERFORM pagar_parcelas(ARRAY[v_ids[2]]);
    ASSERT (SELECT status_pagamento FROM cobranca WHERE id = v_cob) = 'paga', 'CA4: cobrança deveria ficar paga';

    RAISE NOTICE 'OK  CA4 - pagar várias parcelas de uma vez (específicas e depois o resto)';
END $$;

-- ---------------------------------------------------------------------
-- CA5 – Pagar várias é "tudo ou nada"
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_cob INTEGER;
    v_ids INTEGER[];
BEGIN
    v_cob := cadastrar_cobranca_parcelada('70000000001', 40.00, 2, CURRENT_DATE + 5);
    v_ids := ARRAY(SELECT id FROM parcela WHERE id_cobranca = v_cob ORDER BY numero_parcela);
    PERFORM pagar_parcela(v_ids[2]);

    -- A 2 já está paga: a 1 também NÃO pode ficar paga.
    BEGIN
        PERFORM pagar_parcelas(v_ids);
        RAISE EXCEPTION 'FALHOU CA5: deveria recusar porque a parcela 2 já está paga';
    EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
    END;
    ASSERT (SELECT status FROM parcela WHERE id = v_ids[1]) = 'pendente',
           'CA5: a parcela 1 deveria continuar pendente';

    BEGIN
        PERFORM pagar_parcelas(ARRAY[]::INTEGER[]);
        RAISE EXCEPTION 'FALHOU CA5: lista vazia deveria ser recusada';
    EXCEPTION WHEN invalid_parameter_value THEN NULL;
    END;

    BEGIN
        PERFORM pagar_parcelas(ARRAY[v_ids[1]], CURRENT_DATE + 1);
        RAISE EXCEPTION 'FALHOU CA5: data no futuro deveria ser recusada';
    EXCEPTION WHEN invalid_parameter_value THEN NULL;
    END;

    RAISE NOTICE 'OK  CA5 - pagar várias é tudo ou nada; lista vazia e data futura são recusadas';
END $$;

\echo 'TODOS OS TESTES DA US07 PASSARAM'
ROLLBACK;
