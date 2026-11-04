-- =====================================================================
-- CollectionLine · US05 — Testes de aceitação (resumo para as planilhas)
-- Mesmo formato das outras histórias: transação que termina em ROLLBACK.
-- As datas são relativas a CURRENT_DATE porque o resumo segue a pesquisa
-- da US03, cuja situação depende do dia. Conferências só nos CPFs com 5.
-- =====================================================================
\set ON_ERROR_STOP on
BEGIN;
-- Sem isso as linhas "OK ..." (RAISE NOTICE) não aparecem.
SET client_min_messages = notice;
-- Garante que os ASSERT rodem (se alguém desligar, os testes passariam vazios).
SET plpgsql.check_asserts = on;

INSERT INTO cliente (cpf, nome, telefone) VALUES
    ('50000000001', 'Cliente Planilha Um',   '5583500000001'),
    ('50000000002', 'Cliente Planilha Dois', '5583500000002');

-- ---------------------------------------------------------------------
-- CA1 – Uma linha por cobrança, com os totais certos
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_cob INTEGER;
    v_r   RECORD;
BEGIN
    -- R$ 100,00 em 3x (33,33 + 33,33 + 33,34), com a parcela 1 paga.
    v_cob := cadastrar_cobranca_parcelada('50000000001', 100.00, 3, CURRENT_DATE + 10);
    PERFORM pagar_parcela((SELECT id FROM parcela WHERE id_cobranca = v_cob AND numero_parcela = 1));

    SELECT * INTO v_r FROM resumir_cobrancas_pesquisadas() WHERE id_cobranca = v_cob;

    ASSERT FOUND, 'CA1: a cobrança com parcelas pendentes deveria aparecer no resumo';
    ASSERT (SELECT count(*) FROM resumir_cobrancas_pesquisadas() WHERE id_cobranca = v_cob) = 1,
           'CA1: deveria haver uma linha só por cobrança';
    ASSERT v_r.cpf = '50000000001' AND v_r.nome = 'Cliente Planilha Um', 'CA1: cliente errado';
    ASSERT v_r.valor = 100.00, 'CA1: valor total deveria ser 100.00';
    ASSERT v_r.qtd_parcelas = 3, 'CA1: deveria ter 3 parcelas';
    ASSERT v_r.parcelas_pagas = 1, 'CA1: deveria ter 1 parcela paga';
    ASSERT v_r.parcelas_pendentes = 2, 'CA1: deveria ter 2 parcelas pendentes';
    ASSERT v_r.valor_pendente = 66.67, 'CA1: o valor pendente deveria ser 33,33 + 33,34 = 66,67';
    ASSERT v_r.status_pagamento = 'pendente', 'CA1: status deveria ser pendente';

    RAISE NOTICE 'OK  CA1 - uma linha por cobrança, com totais certos (100,00: 1 paga, 66,67 pendente)';
END $$;

-- ---------------------------------------------------------------------
-- CA2 – O resumo segue os filtros da pesquisa (US03)
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_cob1 INTEGER;
    v_cob2 INTEGER;
BEGIN
    v_cob1 := cadastrar_cobranca_parcelada('50000000001', 60.00, 2, CURRENT_DATE + 5);
    v_cob2 := cadastrar_cobranca_parcelada('50000000002', 90.00, 1, CURRENT_DATE - 3, CURRENT_DATE - 10);

    ASSERT (SELECT array_agg(id_cobranca) FROM resumir_cobrancas_pesquisadas(p_cpf => '50000000002'))
           = ARRAY[v_cob2], 'CA2: filtro por CPF deveria trazer só a cobrança do cliente 2';
    ASSERT (SELECT count(*) FROM resumir_cobrancas_pesquisadas(p_busca => 'planilha dois')) = 1,
           'CA2: a busca por nome deveria trazer só a cobrança do cliente 2';
    ASSERT EXISTS (SELECT 1 FROM resumir_cobrancas_pesquisadas(p_situacao => 'atrasada') WHERE id_cobranca = v_cob2)
       AND NOT EXISTS (SELECT 1 FROM resumir_cobrancas_pesquisadas(p_situacao => 'atrasada') WHERE id_cobranca = v_cob1),
           'CA2: "atrasada" deveria trazer a cobrança atrasada e não a que está a vencer';
    ASSERT (SELECT count(*) FROM resumir_cobrancas_pesquisadas(p_de => CURRENT_DATE + 1, p_ate => CURRENT_DATE + 6)
             WHERE cpf LIKE '5%') = 1,
           'CA2: o período deveria trazer só a cobrança com parcela nesse intervalo';

    RAISE NOTICE 'OK  CA2 - o resumo segue os filtros da pesquisa';
END $$;

-- ---------------------------------------------------------------------
-- CA3 – Cobrança toda paga não entra (não tem parcela pendente)
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_cob INTEGER;
BEGIN
    v_cob := cadastrar_cobranca_parcelada('50000000001', 50.00, 1, CURRENT_DATE + 3);
    PERFORM pagar_parcela((SELECT id FROM parcela WHERE id_cobranca = v_cob));

    ASSERT NOT EXISTS (SELECT 1 FROM resumir_cobrancas_pesquisadas() WHERE id_cobranca = v_cob),
           'CA3: cobrança toda paga não deveria aparecer no resumo';

    RAISE NOTICE 'OK  CA3 - cobrança toda paga não entra no resumo';
END $$;

-- ---------------------------------------------------------------------
-- CA4 – Filtros inválidos são recusados (os mesmos da pesquisa)
-- ---------------------------------------------------------------------
DO $$
BEGIN
    BEGIN
        PERFORM * FROM resumir_cobrancas_pesquisadas(p_situacao => 'cancelada');
        RAISE EXCEPTION 'FALHOU CA4: situação desconhecida deveria ser recusada';
    EXCEPTION WHEN invalid_parameter_value THEN NULL;
    END;

    BEGIN
        PERFORM * FROM resumir_cobrancas_pesquisadas(p_de => '2027-02-01', p_ate => '2027-01-01');
        RAISE EXCEPTION 'FALHOU CA4: período invertido deveria ser recusado';
    EXCEPTION WHEN invalid_parameter_value THEN NULL;
    END;

    RAISE NOTICE 'OK  CA4 - filtros inválidos são recusados (2 casos)';
END $$;

\echo 'TODOS OS TESTES DA US05 PASSARAM'
ROLLBACK;
