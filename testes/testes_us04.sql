-- =====================================================================
-- CollectionLine · US04 — Testes de aceitação (editar e excluir cobrança)
-- Mesmo formato das outras histórias: transação que termina em ROLLBACK.
-- =====================================================================
\set ON_ERROR_STOP on
BEGIN;
-- Sem isso as linhas "OK ..." (RAISE NOTICE) não aparecem.
SET client_min_messages = notice;
-- Garante que os ASSERT rodem (se alguém desligar, os testes passariam vazios).
SET plpgsql.check_asserts = on;

-- Clientes de teste da US04: CPFs começando com 6.
INSERT INTO cliente (cpf, nome, telefone) VALUES
    ('60000000001', 'Cliente Teste US04 Um',   '5583600000001'),
    ('60000000002', 'Cliente Teste US04 Dois', '5583600000002');

-- ---------------------------------------------------------------------
-- CA1 – Mudar valor total e quantidade recalcula as parcelas
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_cob     INTEGER;
    v_retorno INTEGER;
BEGIN
    v_cob := cadastrar_cobranca_parcelada(
        p_cpf_cliente => '60000000001', p_valor => 100.00, p_qtd_parcelas => 3,
        p_primeiro_vencimento => '2027-01-10', p_data_emissao => '2027-01-05');

    v_retorno := editar_cobranca(p_id_cobranca => v_cob, p_cpf_cliente => '60000000001',
                                 p_valor => 200.00, p_qtd_parcelas => 4,
                                 p_primeiro_vencimento => '2027-01-10');

    ASSERT v_retorno = v_cob, 'CA1: a função deveria devolver o id da cobrança';
    ASSERT (SELECT valor FROM cobranca WHERE id = v_cob) = 200.00,
           'CA1: o valor da cobrança deveria ser 200.00';
    ASSERT (SELECT array_agg(valor ORDER BY numero_parcela) FROM parcela WHERE id_cobranca = v_cob)
           = ARRAY[50.00, 50.00, 50.00, 50.00]::NUMERIC[],
           'CA1: deveriam existir 4 parcelas de 50.00';
    ASSERT (SELECT bool_and(total_parcelas = 4 AND status = 'pendente') FROM parcela WHERE id_cobranca = v_cob),
           'CA1: todas as parcelas deveriam ser x/4 e pendentes';
    ASSERT (SELECT data_vencimento FROM cobranca WHERE id = v_cob) = DATE '2027-04-10',
           'CA1: o vencimento da cobrança deveria ser o da última parcela (2027-04-10)';
    ASSERT (SELECT data_emissao FROM cobranca WHERE id = v_cob) = DATE '2027-01-05',
           'CA1: a data de emissão não deveria mudar';

    RAISE NOTICE 'OK  CA1 - mudar valor e quantidade recalcula as parcelas (100,00 em 3x -> 200,00 em 4x)';
END $$;

-- ---------------------------------------------------------------------
-- CA2 – Mudar o primeiro vencimento refaz todas as datas (com arredondamento)
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_cob INTEGER;
BEGIN
    v_cob := cadastrar_cobranca_parcelada(
        p_cpf_cliente => '60000000001', p_valor => 300.00, p_qtd_parcelas => 3,
        p_primeiro_vencimento => '2027-01-10', p_data_emissao => '2027-01-05');

    PERFORM editar_cobranca(v_cob, '60000000001', 100.00, 3, '2027-01-31');

    ASSERT (SELECT array_agg(data_vencimento ORDER BY numero_parcela) FROM parcela WHERE id_cobranca = v_cob)
           = ARRAY['2027-01-31', '2027-02-28', '2027-03-31']::DATE[],
           'CA2: vencimentos deveriam ser 31/01, 28/02 e 31/03';
    ASSERT (SELECT array_agg(valor ORDER BY numero_parcela) FROM parcela WHERE id_cobranca = v_cob)
           = ARRAY[33.33, 33.33, 33.34]::NUMERIC[],
           'CA2: as parcelas deveriam seguir a regra do cadastro (33,33 + 33,33 + 33,34)';

    RAISE NOTICE 'OK  CA2 - mudar o 1º vencimento refaz as datas com a regra do cadastro';
END $$;

-- ---------------------------------------------------------------------
-- CA3 – Trocar o cliente
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_cob INTEGER;
BEGIN
    v_cob := cadastrar_cobranca_parcelada(
        p_cpf_cliente => '60000000001', p_valor => 90.00, p_qtd_parcelas => 2,
        p_primeiro_vencimento => '2027-01-10', p_data_emissao => '2027-01-05');

    PERFORM editar_cobranca(v_cob, '60000000002', 90.00, 2, '2027-01-10');

    ASSERT (SELECT cpf_cliente FROM cobranca WHERE id = v_cob) = '60000000002',
           'CA3: a cobrança deveria passar para o outro cliente';
    ASSERT (SELECT count(*) FROM vw_parcelas_pendentes WHERE id_cobranca = v_cob AND cpf = '60000000002') = 2,
           'CA3: as parcelas pendentes deveriam aparecer para o novo cliente';

    RAISE NOTICE 'OK  CA3 - trocar o cliente da cobrança';
END $$;

-- ---------------------------------------------------------------------
-- CA4 – Dados inválidos são recusados e nada muda
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_cob   INTEGER;
    v_antes TEXT;
BEGIN
    v_cob := cadastrar_cobranca_parcelada(
        p_cpf_cliente => '60000000001', p_valor => 100.00, p_qtd_parcelas => 2,
        p_primeiro_vencimento => '2027-01-10', p_data_emissao => '2027-01-05');
    -- Foto da cobrança e das parcelas antes, para conferir que nada mudou.
    SELECT c.cpf_cliente || c.valor || c.data_vencimento
           || string_agg(p.id::text || ' ' || p.valor || ' ' || p.data_vencimento, '|' ORDER BY p.numero_parcela)
      INTO v_antes
      FROM cobranca c JOIN parcela p ON p.id_cobranca = c.id
     WHERE c.id = v_cob GROUP BY c.id;

    -- valor zero
    BEGIN
        PERFORM editar_cobranca(v_cob, '60000000001', 0, 2, '2027-01-10');
        RAISE EXCEPTION 'FALHOU CA4: valor 0 deveria ser recusado';
    EXCEPTION WHEN invalid_parameter_value THEN NULL;
    END;

    -- parcela ficaria com zero centavos
    BEGIN
        PERFORM editar_cobranca(v_cob, '60000000001', 0.02, 3, '2027-01-10');
        RAISE EXCEPTION 'FALHOU CA4: 0.02 em 3x deveria ser recusado';
    EXCEPTION WHEN invalid_parameter_value THEN NULL;
    END;

    -- primeiro vencimento antes da emissão (05/01)
    BEGIN
        PERFORM editar_cobranca(v_cob, '60000000001', 100.00, 2, '2027-01-04');
        RAISE EXCEPTION 'FALHOU CA4: vencimento antes da emissão deveria ser recusado';
    EXCEPTION WHEN invalid_parameter_value THEN NULL;
    END;

    -- mais de 360 parcelas
    BEGIN
        PERFORM editar_cobranca(v_cob, '60000000001', 1000.00, 361, '2027-01-10');
        RAISE EXCEPTION 'FALHOU CA4: 361 parcelas deveria ser recusado';
    EXCEPTION WHEN invalid_parameter_value THEN NULL;
    END;

    -- cliente inexistente
    BEGIN
        PERFORM editar_cobranca(v_cob, '99999999999', 100.00, 2, '2027-01-10');
        RAISE EXCEPTION 'FALHOU CA4: cliente inexistente deveria gerar no_data_found';
    EXCEPTION WHEN no_data_found THEN NULL;
    END;

    -- cobrança inexistente
    BEGIN
        PERFORM editar_cobranca(-1, '60000000001', 100.00, 2, '2027-01-10');
        RAISE EXCEPTION 'FALHOU CA4: cobrança inexistente deveria gerar no_data_found';
    EXCEPTION WHEN no_data_found THEN NULL;
    END;

    ASSERT (SELECT c.cpf_cliente || c.valor || c.data_vencimento
                   || string_agg(p.id::text || ' ' || p.valor || ' ' || p.data_vencimento, '|' ORDER BY p.numero_parcela)
              FROM cobranca c JOIN parcela p ON p.id_cobranca = c.id
             WHERE c.id = v_cob GROUP BY c.id) = v_antes,
           'CA4: a cobrança e as parcelas não deveriam ter mudado';

    RAISE NOTICE 'OK  CA4 - dados inválidos são recusados (6 casos)';
END $$;

-- ---------------------------------------------------------------------
-- CA5 – Cobrança com parcela paga não pode ser editada
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_cob INTEGER;
BEGIN
    v_cob := cadastrar_cobranca_parcelada(
        p_cpf_cliente => '60000000001', p_valor => 100.00, p_qtd_parcelas => 2,
        p_primeiro_vencimento => '2027-01-10', p_data_emissao => '2027-01-05');
    PERFORM pagar_parcela((SELECT id FROM parcela WHERE id_cobranca = v_cob AND numero_parcela = 1));

    BEGIN
        PERFORM editar_cobranca(v_cob, '60000000001', 500.00, 5, '2027-01-10');
        RAISE EXCEPTION 'FALHOU CA5: cobrança com parcela paga não deveria ser editada';
    EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
    END;

    ASSERT (SELECT valor FROM cobranca WHERE id = v_cob) = 100.00,
           'CA5: o valor da cobrança não deveria ter mudado';
    ASSERT (SELECT count(*) FROM parcela WHERE id_cobranca = v_cob) = 2,
           'CA5: as parcelas não deveriam ter mudado';

    RAISE NOTICE 'OK  CA5 - cobrança com parcela paga não pode ser editada';
END $$;

-- ---------------------------------------------------------------------
-- CA6 – Excluir apaga a cobrança e as parcelas
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_cob INTEGER;
BEGIN
    v_cob := cadastrar_cobranca_parcelada(
        p_cpf_cliente => '60000000001', p_valor => 100.00, p_qtd_parcelas => 3,
        p_primeiro_vencimento => '2027-01-10', p_data_emissao => '2027-01-05');

    PERFORM excluir_cobranca(v_cob);

    ASSERT NOT EXISTS (SELECT 1 FROM cobranca WHERE id = v_cob), 'CA6: a cobrança deveria ter sido apagada';
    ASSERT NOT EXISTS (SELECT 1 FROM parcela WHERE id_cobranca = v_cob),
           'CA6: as parcelas deveriam ter sido apagadas junto (ON DELETE CASCADE)';

    RAISE NOTICE 'OK  CA6 - excluir apaga a cobrança e as parcelas';
END $$;

-- ---------------------------------------------------------------------
-- CA7 – Não exclui cobrança com parcela paga nem cobrança inexistente
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_cob INTEGER;
BEGIN
    v_cob := cadastrar_cobranca_parcelada(
        p_cpf_cliente => '60000000001', p_valor => 100.00, p_qtd_parcelas => 2,
        p_primeiro_vencimento => '2027-01-10', p_data_emissao => '2027-01-05');
    PERFORM pagar_parcela((SELECT id FROM parcela WHERE id_cobranca = v_cob AND numero_parcela = 2));

    BEGIN
        PERFORM excluir_cobranca(v_cob);
        RAISE EXCEPTION 'FALHOU CA7: cobrança com parcela paga não deveria ser excluída';
    EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
    END;

    BEGIN
        PERFORM excluir_cobranca(-1);
        RAISE EXCEPTION 'FALHOU CA7: cobrança inexistente deveria gerar no_data_found';
    EXCEPTION WHEN no_data_found THEN NULL;
    END;

    ASSERT (SELECT count(*) FROM parcela WHERE id_cobranca = v_cob) = 2,
           'CA7: a cobrança com parcela paga deveria continuar inteira';

    RAISE NOTICE 'OK  CA7 - não exclui cobrança com parcela paga nem inexistente';
END $$;

\echo 'TODOS OS TESTES DA US04 PASSARAM'
ROLLBACK;
