-- =====================================================================
-- CollectionLine · US01 — Testes de aceitação (CA1 a CA8)
-- Tudo roda dentro de uma transação que termina em ROLLBACK:
-- os testes não deixam nada gravado no banco.
-- =====================================================================
\set ON_ERROR_STOP on
BEGIN;
-- Sem isso as linhas "OK ..." (RAISE NOTICE) não aparecem.
SET client_min_messages = notice;
-- Garante que os ASSERT rodem (se alguém desligar, os testes passariam vazios).
SET plpgsql.check_asserts = on;

-- Clientes de teste: CPFs começando com 9, independentes dos dados de exemplo.
INSERT INTO cliente (cpf, nome, telefone) VALUES
    ('90000000001', 'Cliente Teste Um',   '5583900000001'),
    ('90000000002', 'Cliente Teste Dois', '5583900000002'),
    ('90000000003', 'Cliente Teste Tres', '5583900000003');

-- ---------------------------------------------------------------------
-- CA1 – Cadastro básico: 300.00 em 3x
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_id  INTEGER;
    v_cob cobranca%ROWTYPE;
BEGIN
    v_id := cadastrar_cobranca_parcelada(
        p_cpf_cliente => '90000000001', p_valor => 300.00, p_qtd_parcelas => 3,
        p_primeiro_vencimento => '2027-01-10', p_data_emissao => '2027-01-05');

    SELECT * INTO v_cob FROM cobranca WHERE id = v_id;
    ASSERT FOUND, 'CA1: a função não retornou o id de uma cobrança existente';
    ASSERT v_cob.valor = 300.00, 'CA1: valor da cobrança deveria ser 300.00';
    ASSERT v_cob.status_pagamento = 'pendente', 'CA1: status da cobrança deveria ser pendente';

    ASSERT (SELECT array_agg(numero_parcela ORDER BY numero_parcela)
              FROM parcela WHERE id_cobranca = v_id) = ARRAY[1, 2, 3]::SMALLINT[],
           'CA1: as parcelas deveriam ser numeradas 1, 2 e 3';
    ASSERT (SELECT count(*) FROM parcela
             WHERE id_cobranca = v_id AND valor = 100.00
               AND total_parcelas = 3 AND status = 'pendente') = 3,
           'CA1: as 3 parcelas deveriam ter valor 100.00, total_parcelas 3 e status pendente';

    RAISE NOTICE 'OK  CA1 - cadastro básico (300,00 em 3x de 100,00)';
END $$;

-- ---------------------------------------------------------------------
-- CA2 – Arredondamento: 100.00 em 3x -> 33.33, 33.33, 33.34
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_id INTEGER;
BEGIN
    v_id := cadastrar_cobranca_parcelada(
        p_cpf_cliente => '90000000001', p_valor => 100.00, p_qtd_parcelas => 3,
        p_primeiro_vencimento => '2027-01-10', p_data_emissao => '2027-01-05');

    ASSERT (SELECT array_agg(valor ORDER BY numero_parcela)
              FROM parcela WHERE id_cobranca = v_id) = ARRAY[33.33, 33.33, 33.34]::NUMERIC[],
           'CA2: as parcelas deveriam ser 33.33, 33.33 e 33.34, nessa ordem';
    ASSERT (SELECT sum(valor) FROM parcela WHERE id_cobranca = v_id) = 100.00,
           'CA2: a soma das parcelas deveria ser exatamente 100.00';

    RAISE NOTICE 'OK  CA2 - arredondamento (33,33 + 33,33 + 33,34 = 100,00)';
END $$;

-- ---------------------------------------------------------------------
-- CA3 – Vencimentos mensais a partir de 31/01
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_id INTEGER;
BEGIN
    v_id := cadastrar_cobranca_parcelada(
        p_cpf_cliente => '90000000001', p_valor => 150.00, p_qtd_parcelas => 3,
        p_primeiro_vencimento => '2027-01-31', p_data_emissao => '2027-01-05');

    ASSERT (SELECT array_agg(data_vencimento ORDER BY numero_parcela)
              FROM parcela WHERE id_cobranca = v_id)
           = ARRAY['2027-01-31', '2027-02-28', '2027-03-31']::DATE[],
           'CA3: vencimentos deveriam ser 2027-01-31, 2027-02-28 e 2027-03-31';
    ASSERT (SELECT data_vencimento FROM cobranca WHERE id = v_id) = DATE '2027-03-31',
           'CA3: o vencimento da cobrança deveria ser o da última parcela (2027-03-31)';

    RAISE NOTICE 'OK  CA3 - vencimentos mensais (31/01, 28/02, 31/03)';
END $$;

-- ---------------------------------------------------------------------
-- CA4 – Parcela única: 89.90 em 1x
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_id  INTEGER;
    v_par parcela%ROWTYPE;
BEGIN
    v_id := cadastrar_cobranca_parcelada(
        p_cpf_cliente => '90000000001', p_valor => 89.90, p_qtd_parcelas => 1,
        p_primeiro_vencimento => '2027-02-15', p_data_emissao => '2027-01-05');

    ASSERT (SELECT count(*) FROM parcela WHERE id_cobranca = v_id) = 1,
           'CA4: deveria existir exatamente uma parcela';
    SELECT * INTO v_par FROM parcela WHERE id_cobranca = v_id;
    ASSERT v_par.valor = 89.90, 'CA4: valor da parcela deveria ser 89.90';
    ASSERT v_par.numero_parcela = 1 AND v_par.total_parcelas = 1,
           'CA4: a parcela deveria ser 1/1';
    ASSERT v_par.data_vencimento = DATE '2027-02-15',
           'CA4: a parcela deveria vencer na data informada';
    ASSERT (SELECT data_vencimento FROM cobranca WHERE id = v_id) = DATE '2027-02-15',
           'CA4: o vencimento da cobrança deveria ser a data informada';

    RAISE NOTICE 'OK  CA4 - parcela única (89,90 em 1x)';
END $$;

-- ---------------------------------------------------------------------
-- CA5 – Cliente inexistente: no_data_found e nada gravado
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_cob_antes INTEGER := (SELECT count(*) FROM cobranca);
    v_par_antes INTEGER := (SELECT count(*) FROM parcela);
BEGIN
    BEGIN
        PERFORM cadastrar_cobranca_parcelada(
            p_cpf_cliente => '99999999999', p_valor => 100.00, p_qtd_parcelas => 2,
            p_primeiro_vencimento => '2027-01-10', p_data_emissao => '2027-01-05');
        RAISE EXCEPTION 'FALHOU CA5: cliente inexistente deveria gerar no_data_found';
    EXCEPTION WHEN no_data_found THEN
        NULL;  -- erro esperado
    END;

    ASSERT (SELECT count(*) FROM cobranca) = v_cob_antes, 'CA5: nenhuma cobrança deveria ser gravada';
    ASSERT (SELECT count(*) FROM parcela)  = v_par_antes, 'CA5: nenhuma parcela deveria ser gravada';

    RAISE NOTICE 'OK  CA5 - cliente inexistente é recusado';
END $$;

-- ---------------------------------------------------------------------
-- CA6 – Parâmetros inválidos: invalid_parameter_value e nada gravado
-- Cada caso fica no seu próprio bloco BEGIN ... EXCEPTION.
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_cob_antes INTEGER := (SELECT count(*) FROM cobranca);
    v_par_antes INTEGER := (SELECT count(*) FROM parcela);
BEGIN
    -- valor 0
    BEGIN
        PERFORM cadastrar_cobranca_parcelada(
            p_cpf_cliente => '90000000001', p_valor => 0, p_qtd_parcelas => 1,
            p_primeiro_vencimento => '2027-01-10', p_data_emissao => '2027-01-05');
        RAISE EXCEPTION 'FALHOU CA6: valor 0 deveria ser recusado';
    EXCEPTION WHEN invalid_parameter_value THEN NULL;
    END;

    -- valor negativo
    BEGIN
        PERFORM cadastrar_cobranca_parcelada(
            p_cpf_cliente => '90000000001', p_valor => -50.00, p_qtd_parcelas => 1,
            p_primeiro_vencimento => '2027-01-10', p_data_emissao => '2027-01-05');
        RAISE EXCEPTION 'FALHOU CA6: valor -50.00 deveria ser recusado';
    EXCEPTION WHEN invalid_parameter_value THEN NULL;
    END;

    -- mais de 2 casas decimais
    BEGIN
        PERFORM cadastrar_cobranca_parcelada(
            p_cpf_cliente => '90000000001', p_valor => 10.005, p_qtd_parcelas => 1,
            p_primeiro_vencimento => '2027-01-10', p_data_emissao => '2027-01-05');
        RAISE EXCEPTION 'FALHOU CA6: valor 10.005 deveria ser recusado';
    EXCEPTION WHEN invalid_parameter_value THEN NULL;
    END;

    -- quantidade 0
    BEGIN
        PERFORM cadastrar_cobranca_parcelada(
            p_cpf_cliente => '90000000001', p_valor => 100.00, p_qtd_parcelas => 0,
            p_primeiro_vencimento => '2027-01-10', p_data_emissao => '2027-01-05');
        RAISE EXCEPTION 'FALHOU CA6: quantidade 0 deveria ser recusada';
    EXCEPTION WHEN invalid_parameter_value THEN NULL;
    END;

    -- parcela ficaria com zero centavos: 0.02 em 3x
    BEGIN
        PERFORM cadastrar_cobranca_parcelada(
            p_cpf_cliente => '90000000001', p_valor => 0.02, p_qtd_parcelas => 3,
            p_primeiro_vencimento => '2027-01-10', p_data_emissao => '2027-01-05');
        RAISE EXCEPTION 'FALHOU CA6: 0.02 em 3x deveria ser recusado';
    EXCEPTION WHEN invalid_parameter_value THEN NULL;
    END;

    -- primeiro vencimento antes da emissão
    BEGIN
        PERFORM cadastrar_cobranca_parcelada(
            p_cpf_cliente => '90000000001', p_valor => 100.00, p_qtd_parcelas => 1,
            p_primeiro_vencimento => '2027-01-04', p_data_emissao => '2027-01-05');
        RAISE EXCEPTION 'FALHOU CA6: vencimento antes da emissão deveria ser recusado';
    EXCEPTION WHEN invalid_parameter_value THEN NULL;
    END;

    -- CPF nulo
    BEGIN
        PERFORM cadastrar_cobranca_parcelada(
            p_cpf_cliente => NULL, p_valor => 100.00, p_qtd_parcelas => 1,
            p_primeiro_vencimento => '2027-01-10', p_data_emissao => '2027-01-05');
        RAISE EXCEPTION 'FALHOU CA6: CPF nulo deveria ser recusado';
    EXCEPTION WHEN invalid_parameter_value THEN NULL;
    END;

    ASSERT (SELECT count(*) FROM cobranca) = v_cob_antes, 'CA6: nenhuma cobrança deveria ser gravada';
    ASSERT (SELECT count(*) FROM parcela)  = v_par_antes, 'CA6: nenhuma parcela deveria ser gravada';

    RAISE NOTICE 'OK  CA6 - parâmetros inválidos são recusados (7 casos)';
END $$;

-- ---------------------------------------------------------------------
-- CA7 – Integridade garantida pelo banco (INSERT direto, sem a função)
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_id INTEGER;
BEGIN
    -- Cobrança válida (1x) usada como base para os inserts de parcela.
    v_id := cadastrar_cobranca_parcelada(
        p_cpf_cliente => '90000000002', p_valor => 50.00, p_qtd_parcelas => 1,
        p_primeiro_vencimento => '2027-01-10', p_data_emissao => '2027-01-05');

    -- parcela de cobrança inexistente
    BEGIN
        INSERT INTO parcela (id_cobranca, numero_parcela, total_parcelas, valor, data_vencimento)
        VALUES (-1, 1, 1, 10.00, '2027-01-10');
        RAISE EXCEPTION 'FALHOU CA7: parcela sem cobrança deveria violar a FK';
    EXCEPTION WHEN foreign_key_violation THEN NULL;
    END;

    -- número de parcela repetido na mesma cobrança
    BEGIN
        INSERT INTO parcela (id_cobranca, numero_parcela, total_parcelas, valor, data_vencimento)
        VALUES (v_id, 1, 1, 10.00, '2027-01-10');
        RAISE EXCEPTION 'FALHOU CA7: parcela repetida deveria violar o UNIQUE';
    EXCEPTION WHEN unique_violation THEN NULL;
    END;

    -- status fora do domínio
    BEGIN
        INSERT INTO parcela (id_cobranca, numero_parcela, total_parcelas, valor, data_vencimento, status)
        VALUES (v_id, 2, 2, 10.00, '2027-02-10', 'cancelada');
        RAISE EXCEPTION 'FALHOU CA7: status cancelada deveria violar o CHECK';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    -- numero_parcela maior que total_parcelas
    BEGIN
        INSERT INTO parcela (id_cobranca, numero_parcela, total_parcelas, valor, data_vencimento)
        VALUES (v_id, 3, 2, 10.00, '2027-03-10');
        RAISE EXCEPTION 'FALHOU CA7: parcela 3/2 deveria violar o CHECK';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    -- cobrança para CPF inexistente
    BEGIN
        INSERT INTO cobranca (cpf_cliente, data_emissao, data_vencimento, valor)
        VALUES ('99999999999', '2027-01-05', '2027-01-10', 10.00);
        RAISE EXCEPTION 'FALHOU CA7: cobrança sem cliente deveria violar a FK';
    EXCEPTION WHEN foreign_key_violation THEN NULL;
    END;

    RAISE NOTICE 'OK  CA7 - integridade garantida pelo banco (5 casos)';
END $$;

-- ---------------------------------------------------------------------
-- CA8 – Consulta: a view mostra as 3 parcelas pendentes do cliente
-- ---------------------------------------------------------------------
DO $$
BEGIN
    PERFORM cadastrar_cobranca_parcelada(
        p_cpf_cliente => '90000000003', p_valor => 120.00, p_qtd_parcelas => 3,
        p_primeiro_vencimento => '2027-01-10', p_data_emissao => '2027-01-05');

    ASSERT (SELECT count(*) FROM vw_parcelas_pendentes WHERE cpf = '90000000003') = 3,
           'CA8: a view deveria trazer 3 linhas para o cliente';
    ASSERT (SELECT array_agg(parcela ORDER BY data_vencimento)
              FROM vw_parcelas_pendentes WHERE cpf = '90000000003')
           = ARRAY['1/3', '2/3', '3/3'],
           'CA8: a coluna parcela deveria ser 1/3, 2/3 e 3/3';

    RAISE NOTICE 'OK  CA8 - view de parcelas pendentes (1/3, 2/3, 3/3)';
END $$;

-- ---------------------------------------------------------------------
-- CA9 – Limites (premissa da equipe, criada depois da revisão): valor
-- acima de R$ 99.999.999,99, mais de 360 parcelas, datas infinitas ou
-- depois de 31/12/9999 e NaN são recusados, sem gravar nada
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_cob_antes INTEGER := (SELECT count(*) FROM cobranca);
    v_par_antes INTEGER := (SELECT count(*) FROM parcela);
BEGIN
    -- valor acima do limite da coluna NUMERIC(10,2)
    BEGIN
        PERFORM cadastrar_cobranca_parcelada(
            p_cpf_cliente => '90000000001', p_valor => 100000000.00, p_qtd_parcelas => 1,
            p_primeiro_vencimento => '2027-01-10', p_data_emissao => '2027-01-05');
        RAISE EXCEPTION 'FALHOU CA9: valor acima de 99.999.999,99 deveria ser recusado';
    EXCEPTION WHEN invalid_parameter_value THEN NULL;
    END;

    -- mais de 360 parcelas
    BEGIN
        PERFORM cadastrar_cobranca_parcelada(
            p_cpf_cliente => '90000000001', p_valor => 1000.00, p_qtd_parcelas => 361,
            p_primeiro_vencimento => '2027-01-10', p_data_emissao => '2027-01-05');
        RAISE EXCEPTION 'FALHOU CA9: 361 parcelas deveria ser recusado';
    EXCEPTION WHEN invalid_parameter_value THEN NULL;
    END;

    -- vencimento infinito
    BEGIN
        PERFORM cadastrar_cobranca_parcelada(
            p_cpf_cliente => '90000000001', p_valor => 100.00, p_qtd_parcelas => 1,
            p_primeiro_vencimento => 'infinity', p_data_emissao => '2027-01-05');
        RAISE EXCEPTION 'FALHOU CA9: vencimento infinito deveria ser recusado';
    EXCEPTION WHEN invalid_parameter_value THEN NULL;
    END;

    -- último vencimento depois de 31/12/9999
    BEGIN
        PERFORM cadastrar_cobranca_parcelada(
            p_cpf_cliente => '90000000001', p_valor => 100.00, p_qtd_parcelas => 3,
            p_primeiro_vencimento => '9999-12-31', p_data_emissao => '2027-01-05');
        RAISE EXCEPTION 'FALHOU CA9: último vencimento depois de 31/12/9999 deveria ser recusado';
    EXCEPTION WHEN invalid_parameter_value THEN NULL;
    END;

    -- NaN ("não é um número")
    BEGIN
        PERFORM cadastrar_cobranca_parcelada(
            p_cpf_cliente => '90000000001', p_valor => 'NaN', p_qtd_parcelas => 1,
            p_primeiro_vencimento => '2027-01-10', p_data_emissao => '2027-01-05');
        RAISE EXCEPTION 'FALHOU CA9: NaN deveria ser recusado';
    EXCEPTION WHEN invalid_parameter_value THEN NULL;
    END;

    ASSERT (SELECT count(*) FROM cobranca) = v_cob_antes, 'CA9: nenhuma cobrança deveria ser gravada';
    ASSERT (SELECT count(*) FROM parcela)  = v_par_antes, 'CA9: nenhuma parcela deveria ser gravada';

    RAISE NOTICE 'OK  CA9 - limites de valor, quantidade e datas (5 casos)';
END $$;

\echo 'TODOS OS TESTES DA US01 PASSARAM'
ROLLBACK;
