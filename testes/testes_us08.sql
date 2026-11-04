-- =====================================================================
-- CollectionLine · US08 — Testes de aceitação (abas e mês).
-- Transação que termina em ROLLBACK. Datas relativas a CURRENT_DATE,
-- porque "atrasada" e "em aberto" dependem do dia. Conferências só no
-- CPF com 8, para não depender dos dados de exemplo.
-- =====================================================================
\set ON_ERROR_STOP on
BEGIN;
SET client_min_messages = notice;
SET plpgsql.check_asserts = on;

INSERT INTO cliente (cpf, nome, telefone) VALUES
    ('80000000001', 'Cliente Abas Um', '5583800000001');

-- Uma parcela de cada tipo:
--  A: atrasada (venceu há 5 dias)   B: vence hoje   C: vence daqui a 10 dias
--  D: paga (venceu há 3 dias, paga ontem = 2 dias de atraso)
CREATE TEMP TABLE apoio AS
SELECT cadastrar_cobranca_parcelada('80000000001', 10.00, 1, CURRENT_DATE - 5,  CURRENT_DATE - 30) AS a,
       cadastrar_cobranca_parcelada('80000000001', 20.00, 1, CURRENT_DATE,      CURRENT_DATE - 30) AS b,
       cadastrar_cobranca_parcelada('80000000001', 30.00, 1, CURRENT_DATE + 10, CURRENT_DATE - 30) AS c,
       cadastrar_cobranca_parcelada('80000000001', 40.00, 1, CURRENT_DATE - 3,  CURRENT_DATE - 30) AS d;
SELECT pagar_parcela((SELECT id FROM parcela WHERE id_cobranca = (SELECT d FROM apoio)), CURRENT_DATE - 1);

-- ---------------------------------------------------------------------
-- CA1 – "Em aberto" traz o que ainda não venceu (hoje e a vencer)
-- ---------------------------------------------------------------------
DO $$
BEGIN
    ASSERT (SELECT array_agg(valor ORDER BY valor)
              FROM pesquisar_parcelas_pendentes(p_cpf => '80000000001', p_situacao => 'em_aberto'))
           = ARRAY[20.00, 30.00]::NUMERIC[],
           'CA1: "em aberto" deveria trazer só a que vence hoje (20) e a que vence depois (30)';
    RAISE NOTICE 'OK  CA1 - "em aberto" traz a que vence hoje e a que vence depois';
END $$;

-- ---------------------------------------------------------------------
-- CA2 – "Atrasadas" continua igual
-- ---------------------------------------------------------------------
DO $$
BEGIN
    ASSERT (SELECT array_agg(valor)
              FROM pesquisar_parcelas_pendentes(p_cpf => '80000000001', p_situacao => 'atrasada'))
           = ARRAY[10.00]::NUMERIC[], 'CA2: "atrasada" deveria trazer só a de 10,00';
    RAISE NOTICE 'OK  CA2 - "atrasada" traz só a parcela vencida';
END $$;

-- ---------------------------------------------------------------------
-- CA3 – "Pagas" traz a parcela paga, com data e atraso
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_r RECORD;
BEGIN
    ASSERT (SELECT count(*) FROM pesquisar_parcelas_pagas(p_cpf => '80000000001')) = 1,
           'CA3: deveria haver uma parcela paga';
    SELECT * INTO v_r FROM pesquisar_parcelas_pagas(p_cpf => '80000000001');
    ASSERT v_r.valor = 40.00 AND v_r.parcela = '1/1', 'CA3: parcela paga errada';
    ASSERT v_r.data_pagamento = CURRENT_DATE - 1, 'CA3: data do pagamento errada';
    ASSERT v_r.dias_atraso_pagamento = 2, 'CA3: deveria ter 2 dias de atraso';
    ASSERT (SELECT count(*) FROM pesquisar_parcelas_pagas(p_busca => 'abas um')) = 1,
           'CA3: a busca por nome deveria achar a parcela paga';
    RAISE NOTICE 'OK  CA3 - "pagas" traz a parcela paga, com data e 2 dias de atraso';
END $$;

-- ---------------------------------------------------------------------
-- CA4 – As três abas juntas não repetem nem perdem parcela
-- ---------------------------------------------------------------------
DO $$
BEGIN
    ASSERT (SELECT count(*) FROM pesquisar_parcelas_pendentes(p_cpf => '80000000001', p_situacao => 'em_aberto'))
         + (SELECT count(*) FROM pesquisar_parcelas_pendentes(p_cpf => '80000000001', p_situacao => 'atrasada'))
         + (SELECT count(*) FROM pesquisar_parcelas_pagas(p_cpf => '80000000001'))
         = (SELECT count(*) FROM parcela p JOIN cobranca co ON co.id = p.id_cobranca
             WHERE co.cpf_cliente = '80000000001'),
           'CA4: em aberto + atrasadas + pagas deveria dar o total de parcelas';
    RAISE NOTICE 'OK  CA4 - em aberto + atrasadas + pagas = todas as parcelas, sem repetir';
END $$;

-- ---------------------------------------------------------------------
-- CA5 – O mês (período de vencimento) vale para as pagas também
-- ---------------------------------------------------------------------
DO $$
BEGIN
    ASSERT (SELECT count(*) FROM pesquisar_parcelas_pagas(p_cpf => '80000000001',
                                                          p_de => CURRENT_DATE - 3, p_ate => CURRENT_DATE - 3)) = 1,
           'CA5: a paga deveria aparecer no período do vencimento dela';
    ASSERT (SELECT count(*) FROM pesquisar_parcelas_pagas(p_cpf => '80000000001',
                                                          p_de => CURRENT_DATE, p_ate => CURRENT_DATE + 30)) = 0,
           'CA5: fora do período do vencimento, a paga não deveria aparecer';
    BEGIN
        PERFORM * FROM pesquisar_parcelas_pagas(p_de => '2027-02-01', p_ate => '2027-01-01');
        RAISE EXCEPTION 'FALHOU CA5: período invertido deveria ser recusado';
    EXCEPTION WHEN invalid_parameter_value THEN NULL;
    END;
    RAISE NOTICE 'OK  CA5 - o período de vencimento filtra as pagas; período invertido é recusado';
END $$;

\echo 'TODOS OS TESTES DA US08 PASSARAM'
ROLLBACK;
