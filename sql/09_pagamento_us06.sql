-- =====================================================================
-- CollectionLine · US06 — Data do pagamento (em dia ou com atraso) e
-- id da parcela na pesquisa de pendentes.
-- Este arquivo ALTERA o que as histórias anteriores criaram, por isso
-- pode rodar num banco que já tem dados (não apaga nada).
-- =====================================================================
SET client_min_messages = warning;

-- ---------------------------------------------------------------------
-- 1) Parcela ganha a data do pagamento
-- ---------------------------------------------------------------------
ALTER TABLE parcela ADD COLUMN IF NOT EXISTS data_pagamento DATE;

-- Parcelas pagas antes desta história não tinham data. Supomos que foram
-- pagas no vencimento (ou hoje, se o vencimento ainda nem chegou).
UPDATE parcela
   SET data_pagamento = LEAST(data_vencimento, CURRENT_DATE)
 WHERE status = 'paga' AND data_pagamento IS NULL;

-- Coluna CALCULADA pelo próprio banco (GENERATED ... STORED): quantos dias
-- depois do vencimento a parcela foi paga. 0 = paga em dia (inclusive
-- antecipada); NULL = ainda não paga. Ninguém consegue gravar um valor
-- errado aqui, porque o PostgreSQL recalcula sozinho a cada mudança.
-- (O CASE é necessário: GREATEST ignora NULL e daria 0 para parcela não paga.
-- Apagar e recriar deixa o arquivo rodar de novo com a fórmula atualizada.)
ALTER TABLE parcela DROP COLUMN IF EXISTS dias_atraso_pagamento;
ALTER TABLE parcela ADD COLUMN dias_atraso_pagamento INTEGER
    GENERATED ALWAYS AS (CASE WHEN data_pagamento IS NULL THEN NULL
                              ELSE GREATEST(data_pagamento - data_vencimento, 0) END) STORED;

-- Paga <=> tem data de pagamento. (DROP antes para o arquivo poder rodar de novo.)
ALTER TABLE parcela DROP CONSTRAINT IF EXISTS ck_parcela_pagamento;
ALTER TABLE parcela ADD CONSTRAINT ck_parcela_pagamento
    CHECK ((status = 'paga') = (data_pagamento IS NOT NULL));

-- ---------------------------------------------------------------------
-- 2) Regra da data do pagamento (usada ao pagar e ao corrigir)
-- ---------------------------------------------------------------------
-- Não pode ser vazia nem no futuro. (Não pode ser CHECK na tabela porque
-- CURRENT_DATE muda todo dia.) Pagar antes da emissão é aceito: o cadastro
-- permite emissão futura e, desde a US02, essas parcelas podem ser pagas hoje.

CREATE OR REPLACE FUNCTION validar_data_pagamento(p_data DATE)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_data IS NULL THEN
        RAISE EXCEPTION 'Informe a data do pagamento.'
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    IF p_data > CURRENT_DATE THEN
        RAISE EXCEPTION 'A data do pagamento (%) não pode ser no futuro.', to_char(p_data, 'DD/MM/YYYY')
            USING ERRCODE = 'invalid_parameter_value';
    END IF;
END;
$$;

-- ---------------------------------------------------------------------
-- 3) Pagar recebe a data (hoje, se não for informada)
-- ---------------------------------------------------------------------
-- A versão antiga tinha só o id. Mudar os parâmetros com OR REPLACE criaria
-- uma SEGUNDA função com o mesmo nome; por isso a antiga é apagada antes.
DROP FUNCTION IF EXISTS pagar_parcela(INTEGER);

CREATE OR REPLACE FUNCTION pagar_parcela(p_id_parcela INTEGER, p_data_pagamento DATE DEFAULT CURRENT_DATE)
RETURNS INTEGER  -- id da cobrança da parcela
LANGUAGE plpgsql
AS $$
DECLARE
    v_parcela parcela%ROWTYPE;
BEGIN
    PERFORM travar_cobranca_da_parcela(p_id_parcela);
    SELECT * INTO v_parcela FROM parcela WHERE id = p_id_parcela;

    IF v_parcela.status = 'paga' THEN
        RAISE EXCEPTION 'A parcela %/% já está paga.',
            v_parcela.numero_parcela, v_parcela.total_parcelas
            USING ERRCODE = 'object_not_in_prerequisite_state';
    END IF;

    PERFORM validar_data_pagamento(p_data_pagamento);

    UPDATE parcela SET status = 'paga', data_pagamento = p_data_pagamento WHERE id = p_id_parcela;

    -- Se não sobrou nenhuma parcela em aberto, a cobrança inteira está paga.
    IF NOT EXISTS (SELECT 1 FROM parcela
                    WHERE id_cobranca = v_parcela.id_cobranca AND status <> 'paga') THEN
        UPDATE cobranca SET status_pagamento = 'paga' WHERE id = v_parcela.id_cobranca;
    END IF;

    RETURN v_parcela.id_cobranca;
END;
$$;

-- ---------------------------------------------------------------------
-- 4) Corrigir a data de um pagamento já feito
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION editar_pagamento_parcela(p_id_parcela INTEGER, p_data_pagamento DATE)
RETURNS INTEGER  -- id da cobrança da parcela
LANGUAGE plpgsql
AS $$
DECLARE
    v_parcela parcela%ROWTYPE;
BEGIN
    PERFORM travar_cobranca_da_parcela(p_id_parcela);
    SELECT * INTO v_parcela FROM parcela WHERE id = p_id_parcela;

    IF v_parcela.status <> 'paga' THEN
        RAISE EXCEPTION 'A parcela %/% não está paga: use "Marcar como paga".',
            v_parcela.numero_parcela, v_parcela.total_parcelas
            USING ERRCODE = 'object_not_in_prerequisite_state';
    END IF;

    PERFORM validar_data_pagamento(p_data_pagamento);

    UPDATE parcela SET data_pagamento = p_data_pagamento WHERE id = p_id_parcela;
    RETURN v_parcela.id_cobranca;
END;
$$;

-- ---------------------------------------------------------------------
-- 5) Desfazer o pagamento agora também apaga a data
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION desfazer_pagamento_parcela(p_id_parcela INTEGER)
RETURNS INTEGER  -- id da cobrança da parcela
LANGUAGE plpgsql
AS $$
DECLARE
    v_parcela parcela%ROWTYPE;
BEGIN
    PERFORM travar_cobranca_da_parcela(p_id_parcela);
    SELECT * INTO v_parcela FROM parcela WHERE id = p_id_parcela;

    IF v_parcela.status <> 'paga' THEN
        RAISE EXCEPTION 'A parcela %/% não está paga: não há pagamento para desfazer.',
            v_parcela.numero_parcela, v_parcela.total_parcelas
            USING ERRCODE = 'object_not_in_prerequisite_state';
    END IF;

    UPDATE parcela SET status = 'pendente', data_pagamento = NULL WHERE id = p_id_parcela;

    -- Com uma parcela em aberto de novo, a cobrança também volta a ficar pendente.
    UPDATE cobranca SET status_pagamento = 'pendente' WHERE id = v_parcela.id_cobranca;

    RETURN v_parcela.id_cobranca;
END;
$$;

-- ---------------------------------------------------------------------
-- 6) Id da parcela na view e na pesquisa de pendentes
-- ---------------------------------------------------------------------
-- OR REPLACE VIEW só aceita coluna nova no FIM da lista.
CREATE OR REPLACE VIEW vw_parcelas_pendentes AS
SELECT cl.cpf,
       cl.nome,
       cl.telefone,
       co.id                                       AS id_cobranca,
       p.numero_parcela || '/' || p.total_parcelas AS parcela,
       p.valor,
       p.data_vencimento,
       p.data_vencimento - CURRENT_DATE            AS dias_para_vencer,  -- negativo = atrasada
       p.id                                        AS id_parcela
  FROM parcela  p
  JOIN cobranca co ON co.id  = p.id_cobranca
  JOIN cliente  cl ON cl.cpf = co.cpf_cliente
 WHERE p.status = 'pendente';

-- Mudar as colunas que uma função devolve também exige apagar antes.
DROP FUNCTION IF EXISTS pesquisar_parcelas_pendentes(CHAR, TEXT, TEXT, DATE, DATE);

CREATE FUNCTION pesquisar_parcelas_pendentes(
    p_cpf      CHAR(11) DEFAULT NULL,  -- CPF exato (o filtro da US01)
    p_busca    TEXT     DEFAULT NULL,  -- parte do nome ou do CPF
    p_situacao TEXT     DEFAULT NULL,  -- 'atrasada', 'vence_hoje' ou 'a_vencer'
    p_de       DATE     DEFAULT NULL,  -- vencimento a partir desta data (inclusive)
    p_ate      DATE     DEFAULT NULL   -- vencimento até esta data (inclusive)
) RETURNS TABLE (
    cpf              CHAR(11),
    nome             VARCHAR(100),
    telefone         VARCHAR(13),
    id_cobranca      INTEGER,
    parcela          TEXT,
    valor            NUMERIC(10,2),
    data_vencimento  DATE,
    dias_para_vencer INTEGER,
    situacao         TEXT,
    id_parcela       INTEGER          -- US06
)
LANGUAGE plpgsql
STABLE  -- só lê dados: não altera nada no banco
AS $$
DECLARE
    v_texto   TEXT;
    v_digitos TEXT;
BEGIN
    IF p_situacao IS NOT NULL AND p_situacao NOT IN ('atrasada', 'vence_hoje', 'a_vencer') THEN
        RAISE EXCEPTION 'Situação inválida: "%". Use atrasada, vence_hoje ou a_vencer.', p_situacao
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    IF p_de IS NOT NULL AND p_ate IS NOT NULL AND p_de > p_ate THEN
        RAISE EXCEPTION 'Período inválido: a data inicial (%) é depois da data final (%).',
            to_char(p_de, 'DD/MM/YYYY'), to_char(p_ate, 'DD/MM/YYYY')
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    -- Busca: o nome é comparado sem acentos e sem maiúsculas; o CPF, só pelos
    -- dígitos (assim "111.111" também acha). Busca vazia vale como "sem busca".
    v_texto   := NULLIF(normalizar_texto(btrim(p_busca)), '');
    v_digitos := NULLIF(regexp_replace(COALESCE(p_busca, ''), '[^0-9]', '', 'g'), '');

    -- As colunas vão sempre com o prefixo "s." porque os nomes das colunas de
    -- saída (cpf, nome...) também são variáveis dentro da função.
    RETURN QUERY
    SELECT s.cpf, s.nome, s.telefone, s.id_cobranca, s.parcela, s.valor,
           s.data_vencimento, s.dias_para_vencer, s.situacao, s.id_parcela
      FROM (SELECT v.*,
                   CASE WHEN v.dias_para_vencer < 0 THEN 'atrasada'
                        WHEN v.dias_para_vencer = 0 THEN 'vence_hoje'
                        ELSE 'a_vencer'
                   END AS situacao
              FROM vw_parcelas_pendentes v) AS s
     WHERE (p_cpf IS NULL OR s.cpf = p_cpf)
       AND (p_situacao IS NULL OR s.situacao = p_situacao)
       AND (v_texto IS NULL
            OR strpos(normalizar_texto(s.nome), v_texto) > 0      -- strpos: "contém", sem curingas
            OR (v_digitos IS NOT NULL AND strpos(s.cpf, v_digitos) > 0))
       AND (p_de  IS NULL OR s.data_vencimento >= p_de)
       AND (p_ate IS NULL OR s.data_vencimento <= p_ate);
END;
$$;
