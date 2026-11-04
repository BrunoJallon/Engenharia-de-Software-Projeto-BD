-- =====================================================================
-- CollectionLine · US03 — Testes de aceitação (pesquisa de pendentes)
-- Mesmo formato das outras histórias: transação que termina em ROLLBACK.
-- Aqui as datas são relativas a CURRENT_DATE de propósito: a situação
-- (atrasada / vence hoje / a vencer) depende do dia em que o teste roda.
-- Todas as conferências olham só os clientes de teste (CPF começando com 7),
-- para não depender dos outros dados do banco.
-- =====================================================================
\set ON_ERROR_STOP on
BEGIN;
-- Sem isso as linhas "OK ..." (RAISE NOTICE) não aparecem.
SET client_min_messages = notice;
-- Garante que os ASSERT rodem (se alguém desligar, os testes passariam vazios).
SET plpgsql.check_asserts = on;

INSERT INTO cliente (cpf, nome, telefone) VALUES
    ('70000000001', 'José Antônio Teste',    '5583700000001'),
    ('70000000002', 'Maria Conceição Teste', '5583700000002');

DO $$
BEGIN
    -- José: uma parcela atrasada há 3 dias e outra vencendo hoje.
    PERFORM cadastrar_cobranca_parcelada('70000000001', 10.00, 1, CURRENT_DATE - 3, CURRENT_DATE - 10);
    PERFORM cadastrar_cobranca_parcelada('70000000001', 20.00, 1, CURRENT_DATE,     CURRENT_DATE - 10);
    -- Maria: 2 parcelas a vencer (daqui a 5 dias e um mês depois disso).
    PERFORM cadastrar_cobranca_parcelada('70000000002', 60.00, 2, CURRENT_DATE + 5);
END $$;

-- ---------------------------------------------------------------------
-- CA1 – Busca por nome ignora maiúsculas e acentos
-- ---------------------------------------------------------------------
DO $$
BEGIN
    ASSERT (SELECT count(*) FROM pesquisar_parcelas_pendentes(p_busca => 'jose antonio')
             WHERE cpf LIKE '7%') = 2,
           'CA1: "jose antonio" deveria achar as 2 parcelas do José Antônio';
    ASSERT (SELECT count(*) FROM pesquisar_parcelas_pendentes(p_busca => 'CONCEICAO')
             WHERE cpf LIKE '7%') = 2,
           'CA1: "CONCEICAO" deveria achar as 2 parcelas da Maria Conceição';
    ASSERT (SELECT count(*) FROM pesquisar_parcelas_pendentes(p_busca => 'ninguém com esse nome')) = 0,
           'CA1: um nome que não existe não deveria achar nada';

    RAISE NOTICE 'OK  CA1 - busca por nome ignora maiúsculas e acentos';
END $$;

-- ---------------------------------------------------------------------
-- CA2 – Busca por CPF, com ou sem pontuação
-- ---------------------------------------------------------------------
DO $$
BEGIN
    ASSERT (SELECT array_agg(DISTINCT cpf) FROM pesquisar_parcelas_pendentes(p_busca => '700.000.000-02'))
           = ARRAY['70000000002']::CHAR(11)[],
           'CA2: o CPF com pontuação deveria achar só a Maria';
    ASSERT (SELECT array_agg(DISTINCT cpf) FROM pesquisar_parcelas_pendentes(p_busca => '70000000001'))
           = ARRAY['70000000001']::CHAR(11)[],
           'CA2: o CPF só com dígitos deveria achar só o José';

    RAISE NOTICE 'OK  CA2 - busca por CPF, com ou sem pontuação';
END $$;

-- ---------------------------------------------------------------------
-- CA3 – Filtro por situação
-- ---------------------------------------------------------------------
DO $$
BEGIN
    ASSERT (SELECT array_agg(valor) FROM pesquisar_parcelas_pendentes(p_situacao => 'atrasada')
             WHERE cpf LIKE '7%') = ARRAY[10.00]::NUMERIC[],
           'CA3: "atrasada" deveria trazer só a parcela vencida há 3 dias';
    ASSERT (SELECT array_agg(valor) FROM pesquisar_parcelas_pendentes(p_situacao => 'vence_hoje')
             WHERE cpf LIKE '7%') = ARRAY[20.00]::NUMERIC[],
           'CA3: "vence_hoje" deveria trazer só a parcela que vence hoje';
    ASSERT (SELECT count(*) FROM pesquisar_parcelas_pendentes(p_situacao => 'a_vencer')
             WHERE cpf LIKE '7%') = 2,
           'CA3: "a_vencer" deveria trazer as 2 parcelas da Maria';
    ASSERT (SELECT bool_and(situacao = 'atrasada' AND dias_para_vencer < 0)
              FROM pesquisar_parcelas_pendentes(p_situacao => 'atrasada')),
           'CA3: toda linha "atrasada" deveria ter dias_para_vencer negativo';

    RAISE NOTICE 'OK  CA3 - filtro por situação (atrasada, vence hoje, a vencer)';
END $$;

-- ---------------------------------------------------------------------
-- CA4 – Filtro por período de vencimento (datas inclusivas)
-- ---------------------------------------------------------------------
DO $$
BEGIN
    ASSERT (SELECT array_agg(parcela) FROM pesquisar_parcelas_pendentes(
                p_de => CURRENT_DATE + 1, p_ate => CURRENT_DATE + 10)
             WHERE cpf LIKE '7%') = ARRAY['1/2'],
           'CA4: entre amanhã e daqui a 10 dias deveria vir só a parcela 1/2 da Maria';
    ASSERT (SELECT count(*) FROM pesquisar_parcelas_pendentes(
                p_de => CURRENT_DATE, p_ate => CURRENT_DATE)
             WHERE cpf LIKE '7%') = 1,
           'CA4: um período de um dia só (hoje) deveria trazer a parcela que vence hoje';
    ASSERT (SELECT count(*) FROM pesquisar_parcelas_pendentes(p_ate => CURRENT_DATE - 1)
             WHERE cpf LIKE '7%') = 1,
           'CA4: só a data final (até ontem) deveria trazer a parcela atrasada';

    RAISE NOTICE 'OK  CA4 - filtro por período de vencimento';
END $$;

-- ---------------------------------------------------------------------
-- CA5 – Filtros combinados, filtro por CPF exato e pesquisa sem filtros
-- ---------------------------------------------------------------------
DO $$
BEGIN
    ASSERT (SELECT count(*) FROM pesquisar_parcelas_pendentes(
                p_busca => 'jose', p_situacao => 'vence_hoje')) = 1,
           'CA5: "jose" + "vence_hoje" deveria trazer 1 parcela';
    ASSERT (SELECT count(*) FROM pesquisar_parcelas_pendentes(p_cpf => '70000000002')) = 2,
           'CA5: o filtro por CPF exato (o da US01) deveria continuar funcionando';
    ASSERT (SELECT count(*) FROM pesquisar_parcelas_pendentes(p_busca => '   ')
             WHERE cpf LIKE '7%') = 4,
           'CA5: uma busca só com espaços deveria valer como "sem busca"';
    ASSERT (SELECT count(*) FROM pesquisar_parcelas_pendentes())
           = (SELECT count(*) FROM vw_parcelas_pendentes),
           'CA5: sem filtros, a pesquisa deveria trazer a view inteira';

    RAISE NOTICE 'OK  CA5 - filtros combinados e pesquisa sem filtros';
END $$;

-- ---------------------------------------------------------------------
-- CA6 – Parâmetros inválidos
-- ---------------------------------------------------------------------
DO $$
BEGIN
    -- situação desconhecida
    BEGIN
        PERFORM * FROM pesquisar_parcelas_pendentes(p_situacao => 'cancelada');
        RAISE EXCEPTION 'FALHOU CA6: situação desconhecida deveria ser recusada';
    EXCEPTION WHEN invalid_parameter_value THEN NULL;
    END;

    -- período invertido
    BEGIN
        PERFORM * FROM pesquisar_parcelas_pendentes(p_de => '2027-02-01', p_ate => '2027-01-01');
        RAISE EXCEPTION 'FALHOU CA6: período com início depois do fim deveria ser recusado';
    EXCEPTION WHEN invalid_parameter_value THEN NULL;
    END;

    RAISE NOTICE 'OK  CA6 - parâmetros inválidos são recusados (2 casos)';
END $$;

\echo 'TODOS OS TESTES DA US03 PASSARAM'
ROLLBACK;
