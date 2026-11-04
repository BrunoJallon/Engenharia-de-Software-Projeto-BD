-- =====================================================================
-- CollectionLine · US02 — Testes de aceitação (editar e pagar parcelas)
-- Mesmo formato da US01: tudo numa transação que termina em ROLLBACK.
-- =====================================================================
\set ON_ERROR_STOP on
BEGIN;
-- Sem isso as linhas "OK ..." (RAISE NOTICE) não aparecem.
SET client_min_messages = notice;
-- Garante que os ASSERT rodem (se alguém desligar, os testes passariam vazios).
SET plpgsql.check_asserts = on;

-- Cliente de teste da US02: CPF começando com 8, independente dos outros testes.
INSERT INTO cliente (cpf, nome, telefone) VALUES
    ('80000000001', 'Cliente Teste US02', '5583800000001');

-- ---------------------------------------------------------------------
-- CA1 – Editar o valor de uma parcela ajusta o total da cobrança
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_cob     INTEGER;
    v_par     INTEGER;
    v_retorno INTEGER;
BEGIN
    v_cob := cadastrar_cobranca_parcelada(
        p_cpf_cliente => '80000000001', p_valor => 100.00, p_qtd_parcelas => 3,
        p_primeiro_vencimento => '2027-01-10', p_data_emissao => '2027-01-05');
    SELECT id INTO v_par FROM parcela WHERE id_cobranca = v_cob AND numero_parcela = 2;

    v_retorno := editar_parcela(p_id_parcela => v_par, p_valor => 40.00,
                                p_data_vencimento => '2027-02-10');

    ASSERT v_retorno = v_cob, 'CA1: a função deveria devolver o id da cobrança';
    ASSERT (SELECT array_agg(valor ORDER BY numero_parcela)
              FROM parcela WHERE id_cobranca = v_cob) = ARRAY[33.33, 40.00, 33.34]::NUMERIC[],
           'CA1: só a parcela 2 deveria mudar, para 40.00';
    ASSERT (SELECT valor FROM cobranca WHERE id = v_cob) = 106.67,
           'CA1: o valor da cobrança deveria virar a nova soma das parcelas (106.67)';

    RAISE NOTICE 'OK  CA1 - editar valor ajusta o total da cobrança (100,00 -> 106,67)';
END $$;

-- ---------------------------------------------------------------------
-- CA2 – Editar o vencimento de uma parcela do meio
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_cob INTEGER;
    v_par INTEGER;
BEGIN
    v_cob := cadastrar_cobranca_parcelada(
        p_cpf_cliente => '80000000001', p_valor => 300.00, p_qtd_parcelas => 3,
        p_primeiro_vencimento => '2027-01-10', p_data_emissao => '2027-01-05');
    SELECT id INTO v_par FROM parcela WHERE id_cobranca = v_cob AND numero_parcela = 2;

    PERFORM editar_parcela(p_id_parcela => v_par, p_valor => 100.00,
                           p_data_vencimento => '2027-02-20');

    ASSERT (SELECT array_agg(data_vencimento ORDER BY numero_parcela)
              FROM parcela WHERE id_cobranca = v_cob)
           = ARRAY['2027-01-10', '2027-02-20', '2027-03-10']::DATE[],
           'CA2: só o vencimento da parcela 2 deveria mudar, para 2027-02-20';
    ASSERT (SELECT data_vencimento FROM cobranca WHERE id = v_cob) = DATE '2027-03-10',
           'CA2: o vencimento da cobrança deveria continuar sendo o da última parcela';
    ASSERT (SELECT valor FROM cobranca WHERE id = v_cob) = 300.00,
           'CA2: o valor da cobrança não deveria mudar';

    RAISE NOTICE 'OK  CA2 - editar vencimento de parcela do meio';
END $$;

-- ---------------------------------------------------------------------
-- CA3 – Editar o vencimento da última parcela muda o vencimento da cobrança
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_cob INTEGER;
    v_par INTEGER;
BEGIN
    v_cob := cadastrar_cobranca_parcelada(
        p_cpf_cliente => '80000000001', p_valor => 300.00, p_qtd_parcelas => 3,
        p_primeiro_vencimento => '2027-01-10', p_data_emissao => '2027-01-05');
    SELECT id INTO v_par FROM parcela WHERE id_cobranca = v_cob AND numero_parcela = 3;

    PERFORM editar_parcela(p_id_parcela => v_par, p_valor => 100.00,
                           p_data_vencimento => '2027-04-15');

    ASSERT (SELECT data_vencimento FROM cobranca WHERE id = v_cob) = DATE '2027-04-15',
           'CA3: o vencimento da cobrança deveria virar o novo vencimento da última parcela';

    RAISE NOTICE 'OK  CA3 - editar vencimento da última parcela atualiza a cobrança';
END $$;

-- ---------------------------------------------------------------------
-- CA4 – Vencimento fora de ordem ou antes da emissão é recusado
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_cob    INTEGER;
    v_par1   INTEGER;
    v_par2   INTEGER;
    v_antes  TEXT;
BEGIN
    v_cob := cadastrar_cobranca_parcelada(
        p_cpf_cliente => '80000000001', p_valor => 300.00, p_qtd_parcelas => 3,
        p_primeiro_vencimento => '2027-01-10', p_data_emissao => '2027-01-05');
    SELECT id INTO v_par1 FROM parcela WHERE id_cobranca = v_cob AND numero_parcela = 1;
    SELECT id INTO v_par2 FROM parcela WHERE id_cobranca = v_cob AND numero_parcela = 2;
    -- Foto das parcelas antes, para conferir que nada mudou.
    SELECT string_agg(valor || ' ' || data_vencimento, ' | ' ORDER BY numero_parcela)
      INTO v_antes FROM parcela WHERE id_cobranca = v_cob;

    -- parcela 2 antes da parcela 1 (10/01)
    BEGIN
        PERFORM editar_parcela(v_par2, 100.00, '2027-01-09');
        RAISE EXCEPTION 'FALHOU CA4: parcela 2 antes da parcela 1 deveria ser recusada';
    EXCEPTION WHEN invalid_parameter_value THEN NULL;
    END;

    -- parcela 2 depois da parcela 3 (10/03)
    BEGIN
        PERFORM editar_parcela(v_par2, 100.00, '2027-03-11');
        RAISE EXCEPTION 'FALHOU CA4: parcela 2 depois da parcela 3 deveria ser recusada';
    EXCEPTION WHEN invalid_parameter_value THEN NULL;
    END;

    -- parcela 1 antes da emissão (05/01)
    BEGIN
        PERFORM editar_parcela(v_par1, 100.00, '2027-01-04');
        RAISE EXCEPTION 'FALHOU CA4: vencimento antes da emissão deveria ser recusado';
    EXCEPTION WHEN invalid_parameter_value THEN NULL;
    END;

    ASSERT (SELECT string_agg(valor || ' ' || data_vencimento, ' | ' ORDER BY numero_parcela)
              FROM parcela WHERE id_cobranca = v_cob) = v_antes,
           'CA4: nenhuma parcela deveria ter mudado';

    -- Limite inclusivo: vencer no mesmo dia da parcela vizinha é aceito.
    PERFORM editar_parcela(v_par2, 100.00, '2027-01-10');
    ASSERT (SELECT data_vencimento FROM parcela WHERE id = v_par2) = DATE '2027-01-10',
           'CA4: vencer no mesmo dia da parcela anterior deveria ser aceito';

    RAISE NOTICE 'OK  CA4 - vencimento fora de ordem ou antes da emissão é recusado';
END $$;

-- ---------------------------------------------------------------------
-- CA5 – Valores inválidos e parcela inexistente são recusados
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_cob   INTEGER;
    v_par   INTEGER;
    v_antes TEXT;
BEGIN
    v_cob := cadastrar_cobranca_parcelada(
        p_cpf_cliente => '80000000001', p_valor => 90.00, p_qtd_parcelas => 1,
        p_primeiro_vencimento => '2027-01-10', p_data_emissao => '2027-01-05');
    SELECT id INTO v_par FROM parcela WHERE id_cobranca = v_cob;
    SELECT valor || ' ' || data_vencimento INTO v_antes FROM parcela WHERE id = v_par;

    -- valor 0
    BEGIN
        PERFORM editar_parcela(v_par, 0, '2027-01-10');
        RAISE EXCEPTION 'FALHOU CA5: valor 0 deveria ser recusado';
    EXCEPTION WHEN invalid_parameter_value THEN NULL;
    END;

    -- valor negativo
    BEGIN
        PERFORM editar_parcela(v_par, -1.00, '2027-01-10');
        RAISE EXCEPTION 'FALHOU CA5: valor negativo deveria ser recusado';
    EXCEPTION WHEN invalid_parameter_value THEN NULL;
    END;

    -- mais de 2 casas decimais
    BEGIN
        PERFORM editar_parcela(v_par, 10.005, '2027-01-10');
        RAISE EXCEPTION 'FALHOU CA5: valor 10.005 deveria ser recusado';
    EXCEPTION WHEN invalid_parameter_value THEN NULL;
    END;

    -- valor nulo
    BEGIN
        PERFORM editar_parcela(v_par, NULL, '2027-01-10');
        RAISE EXCEPTION 'FALHOU CA5: valor nulo deveria ser recusado';
    EXCEPTION WHEN invalid_parameter_value THEN NULL;
    END;

    -- vencimento nulo
    BEGIN
        PERFORM editar_parcela(v_par, 50.00, NULL);
        RAISE EXCEPTION 'FALHOU CA5: vencimento nulo deveria ser recusado';
    EXCEPTION WHEN invalid_parameter_value THEN NULL;
    END;

    -- NaN ("não é um número")
    BEGIN
        PERFORM editar_parcela(v_par, 'NaN', '2027-01-10');
        RAISE EXCEPTION 'FALHOU CA5: NaN deveria ser recusado';
    EXCEPTION WHEN invalid_parameter_value THEN NULL;
    END;

    -- vencimento infinito
    BEGIN
        PERFORM editar_parcela(v_par, 50.00, 'infinity');
        RAISE EXCEPTION 'FALHOU CA5: vencimento infinito deveria ser recusado';
    EXCEPTION WHEN invalid_parameter_value THEN NULL;
    END;

    -- parcela inexistente
    BEGIN
        PERFORM editar_parcela(-1, 50.00, '2027-01-10');
        RAISE EXCEPTION 'FALHOU CA5: parcela inexistente deveria gerar no_data_found';
    EXCEPTION WHEN no_data_found THEN NULL;
    END;

    ASSERT (SELECT valor || ' ' || data_vencimento FROM parcela WHERE id = v_par) = v_antes,
           'CA5: a parcela não deveria ter mudado';
    ASSERT (SELECT valor FROM cobranca WHERE id = v_cob) = 90.00,
           'CA5: o valor da cobrança não deveria ter mudado';

    RAISE NOTICE 'OK  CA5 - valores inválidos e parcela inexistente são recusados (8 casos)';
END $$;

-- ---------------------------------------------------------------------
-- CA6 – Pagar parcelas; com todas pagas, a cobrança fica paga
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_cob     INTEGER;
    v_ids     INTEGER[];
    v_retorno INTEGER;
BEGIN
    v_cob := cadastrar_cobranca_parcelada(
        p_cpf_cliente => '80000000001', p_valor => 300.00, p_qtd_parcelas => 3,
        p_primeiro_vencimento => '2027-01-10', p_data_emissao => '2027-01-05');
    SELECT array_agg(id ORDER BY numero_parcela) INTO v_ids FROM parcela WHERE id_cobranca = v_cob;

    v_retorno := pagar_parcela(v_ids[1]);
    ASSERT v_retorno = v_cob, 'CA6: a função deveria devolver o id da cobrança';
    ASSERT (SELECT status FROM parcela WHERE id = v_ids[1]) = 'paga',
           'CA6: a parcela 1 deveria ficar paga';
    ASSERT (SELECT status_pagamento FROM cobranca WHERE id = v_cob) = 'pendente',
           'CA6: com parcelas em aberto, a cobrança deveria continuar pendente';
    ASSERT (SELECT array_agg(parcela ORDER BY data_vencimento)
              FROM vw_parcelas_pendentes WHERE id_cobranca = v_cob) = ARRAY['2/3', '3/3'],
           'CA6: a parcela paga deveria sair da lista de pendentes';

    PERFORM pagar_parcela(v_ids[2]);
    PERFORM pagar_parcela(v_ids[3]);
    ASSERT (SELECT status_pagamento FROM cobranca WHERE id = v_cob) = 'paga',
           'CA6: com todas as parcelas pagas, a cobrança deveria ficar paga';
    ASSERT NOT EXISTS (SELECT 1 FROM vw_parcelas_pendentes WHERE id_cobranca = v_cob),
           'CA6: a cobrança paga não deveria ter parcelas pendentes';

    RAISE NOTICE 'OK  CA6 - pagar parcelas (cobrança fica paga com todas pagas)';
END $$;

-- ---------------------------------------------------------------------
-- CA7 – Parcela paga fica travada
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_cob   INTEGER;
    v_par   INTEGER;
    v_antes TEXT;
BEGIN
    v_cob := cadastrar_cobranca_parcelada(
        p_cpf_cliente => '80000000001', p_valor => 200.00, p_qtd_parcelas => 2,
        p_primeiro_vencimento => '2027-01-10', p_data_emissao => '2027-01-05');
    SELECT id INTO v_par FROM parcela WHERE id_cobranca = v_cob AND numero_parcela = 1;
    PERFORM pagar_parcela(v_par);
    SELECT valor || ' ' || data_vencimento || ' ' || status INTO v_antes FROM parcela WHERE id = v_par;

    -- editar parcela paga
    BEGIN
        PERFORM editar_parcela(v_par, 50.00, '2027-01-10');
        RAISE EXCEPTION 'FALHOU CA7: editar parcela paga deveria ser recusado';
    EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
    END;

    -- pagar de novo
    BEGIN
        PERFORM pagar_parcela(v_par);
        RAISE EXCEPTION 'FALHOU CA7: pagar parcela já paga deveria ser recusado';
    EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
    END;

    -- pagar parcela inexistente
    BEGIN
        PERFORM pagar_parcela(-1);
        RAISE EXCEPTION 'FALHOU CA7: pagar parcela inexistente deveria gerar no_data_found';
    EXCEPTION WHEN no_data_found THEN NULL;
    END;

    ASSERT (SELECT valor || ' ' || data_vencimento || ' ' || status FROM parcela WHERE id = v_par) = v_antes,
           'CA7: a parcela paga não deveria ter mudado';

    RAISE NOTICE 'OK  CA7 - parcela paga fica travada (3 casos)';
END $$;

-- ---------------------------------------------------------------------
-- CA8 – Desfazer pagamento volta a parcela e a cobrança para pendente
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_cob     INTEGER;
    v_ids     INTEGER[];
    v_retorno INTEGER;
BEGIN
    v_cob := cadastrar_cobranca_parcelada(
        p_cpf_cliente => '80000000001', p_valor => 200.00, p_qtd_parcelas => 2,
        p_primeiro_vencimento => '2027-01-10', p_data_emissao => '2027-01-05');
    SELECT array_agg(id ORDER BY numero_parcela) INTO v_ids FROM parcela WHERE id_cobranca = v_cob;
    PERFORM pagar_parcela(v_ids[1]);
    PERFORM pagar_parcela(v_ids[2]);

    v_retorno := desfazer_pagamento_parcela(v_ids[2]);
    ASSERT v_retorno = v_cob, 'CA8: a função deveria devolver o id da cobrança';
    ASSERT (SELECT status FROM parcela WHERE id = v_ids[2]) = 'pendente',
           'CA8: a parcela deveria voltar para pendente';
    ASSERT (SELECT status_pagamento FROM cobranca WHERE id = v_cob) = 'pendente',
           'CA8: a cobrança deveria voltar para pendente';
    ASSERT (SELECT array_agg(parcela) FROM vw_parcelas_pendentes WHERE id_cobranca = v_cob) = ARRAY['2/2'],
           'CA8: a parcela deveria voltar para a lista de pendentes';

    -- desfazer de parcela que não está paga
    BEGIN
        PERFORM desfazer_pagamento_parcela(v_ids[2]);
        RAISE EXCEPTION 'FALHOU CA8: desfazer parcela pendente deveria ser recusado';
    EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
    END;

    -- desfazer de parcela inexistente
    BEGIN
        PERFORM desfazer_pagamento_parcela(-1);
        RAISE EXCEPTION 'FALHOU CA8: parcela inexistente deveria gerar no_data_found';
    EXCEPTION WHEN no_data_found THEN NULL;
    END;

    RAISE NOTICE 'OK  CA8 - desfazer pagamento volta parcela e cobrança para pendente';
END $$;

\echo 'TODOS OS TESTES DA US02 PASSARAM'
ROLLBACK;
