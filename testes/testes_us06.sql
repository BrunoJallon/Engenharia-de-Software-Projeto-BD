-- =====================================================================
-- CollectionLine · US06 — Testes de aceitação (data do pagamento e id
-- da parcela na pesquisa). Mesmo formato das outras histórias:
-- transação que termina em ROLLBACK. As datas são relativas a
-- CURRENT_DATE porque "no futuro" depende do dia em que o teste roda.
-- =====================================================================
\set ON_ERROR_STOP on
BEGIN;
SET client_min_messages = notice;
SET plpgsql.check_asserts = on;

INSERT INTO cliente (cpf, nome, telefone) VALUES
    ('60000000001', 'Cliente Pagamento Um', '5583600000001');

-- Cobrança de apoio: emitida há 40 dias, R$ 90,00 em 3x, com a 1ª parcela
-- vencida há 20 dias (as outras vencem 1 e 2 meses depois).
CREATE TEMP TABLE apoio AS
SELECT cadastrar_cobranca_parcelada('60000000001', 90.00, 3, CURRENT_DATE - 20, CURRENT_DATE - 40) AS id_cobranca;

-- Atalho: id da parcela N da cobrança de apoio.
CREATE FUNCTION pg_temp.parcela_n(n INTEGER) RETURNS INTEGER LANGUAGE sql AS $$
    SELECT p.id FROM parcela p JOIN apoio a ON a.id_cobranca = p.id_cobranca WHERE p.numero_parcela = n
$$;

-- ---------------------------------------------------------------------
-- CA1 – Pagar com a data informada: em dia ou com atraso
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_r parcela%ROWTYPE;
BEGIN
    -- Paga 5 dias ANTES do vencimento: em dia (0 dias de atraso).
    PERFORM pagar_parcela(pg_temp.parcela_n(1), CURRENT_DATE - 25);
    SELECT * INTO v_r FROM parcela WHERE id = pg_temp.parcela_n(1);
    ASSERT v_r.status = 'paga', 'CA1: a parcela deveria ficar paga';
    ASSERT v_r.data_pagamento = CURRENT_DATE - 25, 'CA1: data do pagamento errada';
    ASSERT v_r.dias_atraso_pagamento = 0, 'CA1: paga antes do vencimento deveria ter 0 dias de atraso';

    -- Desfaz e paga 7 dias DEPOIS do vencimento: 7 dias de atraso.
    PERFORM desfazer_pagamento_parcela(pg_temp.parcela_n(1));
    PERFORM pagar_parcela(pg_temp.parcela_n(1), CURRENT_DATE - 13);
    SELECT * INTO v_r FROM parcela WHERE id = pg_temp.parcela_n(1);
    ASSERT v_r.dias_atraso_pagamento = 7, 'CA1: paga 7 dias depois do vencimento deveria ter 7 dias de atraso';

    RAISE NOTICE 'OK  CA1 - pagar com data: antes do vencimento = em dia; 7 dias depois = 7 dias de atraso';
END $$;

-- ---------------------------------------------------------------------
-- CA2 – Sem data informada, o pagamento é de hoje
-- ---------------------------------------------------------------------
DO $$
BEGIN
    PERFORM pagar_parcela(pg_temp.parcela_n(2));
    ASSERT (SELECT data_pagamento FROM parcela WHERE id = pg_temp.parcela_n(2)) = CURRENT_DATE,
           'CA2: sem data, o pagamento deveria ser de hoje';
    RAISE NOTICE 'OK  CA2 - sem data informada, o pagamento fica com a data de hoje';
END $$;

-- ---------------------------------------------------------------------
-- CA3 – Datas inválidas são recusadas e nada muda
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_datas DATE[] := ARRAY[CURRENT_DATE + 1, CURRENT_DATE + 365, NULL];
    v_d     DATE;
BEGIN
    FOREACH v_d IN ARRAY v_datas LOOP
        BEGIN
            PERFORM pagar_parcela(pg_temp.parcela_n(3), v_d);
            RAISE EXCEPTION 'FALHOU CA3: a data % deveria ser recusada', COALESCE(v_d::TEXT, 'vazia');
        EXCEPTION WHEN invalid_parameter_value THEN NULL;
        END;
    END LOOP;

    ASSERT (SELECT status FROM parcela WHERE id = pg_temp.parcela_n(3)) = 'pendente',
           'CA3: a parcela deveria continuar pendente';
    RAISE NOTICE 'OK  CA3 - data no futuro ou vazia é recusada (3 casos)';
END $$;

-- ---------------------------------------------------------------------
-- CA4 – Corrigir a data de um pagamento já feito
-- ---------------------------------------------------------------------
DO $$
BEGIN
    -- A parcela 1 foi paga com 7 dias de atraso; corrige para o dia do vencimento.
    PERFORM editar_pagamento_parcela(pg_temp.parcela_n(1), CURRENT_DATE - 20);
    ASSERT (SELECT dias_atraso_pagamento FROM parcela WHERE id = pg_temp.parcela_n(1)) = 0,
           'CA4: pagar no dia do vencimento deveria contar como em dia';

    -- Data inválida na correção também é recusada.
    BEGIN
        PERFORM editar_pagamento_parcela(pg_temp.parcela_n(1), CURRENT_DATE + 1);
        RAISE EXCEPTION 'FALHOU CA4: data no futuro deveria ser recusada na correção';
    EXCEPTION WHEN invalid_parameter_value THEN NULL;
    END;

    -- Parcela que não está paga não tem pagamento para corrigir.
    BEGIN
        PERFORM editar_pagamento_parcela(pg_temp.parcela_n(3), CURRENT_DATE);
        RAISE EXCEPTION 'FALHOU CA4: parcela pendente não deveria aceitar correção de pagamento';
    EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
    END;

    -- Parcela inexistente.
    BEGIN
        PERFORM editar_pagamento_parcela(-1, CURRENT_DATE);
        RAISE EXCEPTION 'FALHOU CA4: parcela inexistente deveria ser recusada';
    EXCEPTION WHEN no_data_found THEN NULL;
    END;

    RAISE NOTICE 'OK  CA4 - corrigir a data do pagamento recalcula o atraso (e recusa 3 casos inválidos)';
END $$;

-- ---------------------------------------------------------------------
-- CA5 – Desfazer o pagamento apaga a data
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_r parcela%ROWTYPE;
BEGIN
    PERFORM desfazer_pagamento_parcela(pg_temp.parcela_n(2));
    SELECT * INTO v_r FROM parcela WHERE id = pg_temp.parcela_n(2);
    ASSERT v_r.status = 'pendente' AND v_r.data_pagamento IS NULL AND v_r.dias_atraso_pagamento IS NULL,
           'CA5: desfazer deveria deixar a parcela pendente e sem data de pagamento';
    RAISE NOTICE 'OK  CA5 - desfazer o pagamento apaga a data';
END $$;

-- ---------------------------------------------------------------------
-- CA6 – A tabela não aceita "paga sem data" nem "pendente com data"
-- ---------------------------------------------------------------------
DO $$
BEGIN
    BEGIN
        UPDATE parcela SET status = 'paga' WHERE id = pg_temp.parcela_n(3);
        RAISE EXCEPTION 'FALHOU CA6: parcela paga sem data deveria ser recusada';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    BEGIN
        UPDATE parcela SET data_pagamento = CURRENT_DATE WHERE id = pg_temp.parcela_n(3);
        RAISE EXCEPTION 'FALHOU CA6: parcela pendente com data de pagamento deveria ser recusada';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    RAISE NOTICE 'OK  CA6 - a tabela recusa paga sem data e pendente com data';
END $$;

-- ---------------------------------------------------------------------
-- CA7 – A pesquisa de pendentes traz o id da parcela
-- ---------------------------------------------------------------------
DO $$
BEGIN
    ASSERT (SELECT array_agg(id_parcela ORDER BY id_parcela)
              FROM pesquisar_parcelas_pendentes(p_cpf => '60000000001'))
           = ARRAY[pg_temp.parcela_n(2), pg_temp.parcela_n(3)],
           'CA7: a pesquisa deveria trazer o id das parcelas pendentes 2 e 3';
    RAISE NOTICE 'OK  CA7 - a pesquisa de pendentes traz o id da parcela';
END $$;

\echo 'TODOS OS TESTES DA US06 PASSARAM'
ROLLBACK;
