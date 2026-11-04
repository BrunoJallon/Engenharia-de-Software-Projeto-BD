-- =====================================================================
-- CollectionLine · US08 — Abas "Em aberto", "Atrasadas" e "Pagas" e
-- navegação por mês. O mês é só um período de vencimento (do dia 1 ao
-- último dia), que as pesquisas já aceitam (p_de e p_ate).
--  - "Em aberto": nova situação 'em_aberto' (vence hoje ou a vencer);
--  - "Atrasadas": a situação 'atrasada', que já existia (US03);
--  - "Pagas":     nova função pesquisar_parcelas_pagas.
-- =====================================================================
SET client_min_messages = warning;

-- ---------------------------------------------------------------------
-- 1) Regra da busca num lugar só (usada pelas duas pesquisas)
-- ---------------------------------------------------------------------
-- O nome é comparado sem acentos e sem maiúsculas; o CPF, só pelos dígitos
-- (assim "111.111" também acha). Busca vazia = sem busca = sempre combina.
CREATE OR REPLACE FUNCTION cliente_combina_com_busca(p_nome TEXT, p_cpf TEXT, p_busca TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v_texto   TEXT := NULLIF(normalizar_texto(btrim(p_busca)), '');
    v_digitos TEXT := NULLIF(regexp_replace(COALESCE(p_busca, ''), '[^0-9]', '', 'g'), '');
BEGIN
    RETURN v_texto IS NULL
        OR strpos(normalizar_texto(p_nome), v_texto) > 0           -- strpos: "contém", sem curingas
        OR (v_digitos IS NOT NULL AND strpos(p_cpf, v_digitos) > 0);
END;
$$;

-- Período de/até: o mesmo erro nas duas pesquisas.
CREATE OR REPLACE FUNCTION validar_periodo(p_de DATE, p_ate DATE)
RETURNS VOID
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    IF p_de IS NOT NULL AND p_ate IS NOT NULL AND p_de > p_ate THEN
        RAISE EXCEPTION 'Período inválido: a data inicial (%) é depois da data final (%).',
            to_char(p_de, 'DD/MM/YYYY'), to_char(p_ate, 'DD/MM/YYYY')
            USING ERRCODE = 'invalid_parameter_value';
    END IF;
END;
$$;

-- ---------------------------------------------------------------------
-- 2) Pesquisa de pendentes aceita a situação 'em_aberto'
-- ---------------------------------------------------------------------
-- Mesmos parâmetros e colunas da versão da US06: OR REPLACE basta.
CREATE OR REPLACE FUNCTION pesquisar_parcelas_pendentes(
    p_cpf      CHAR(11) DEFAULT NULL,  -- CPF exato (o filtro da US01)
    p_busca    TEXT     DEFAULT NULL,  -- parte do nome ou do CPF
    p_situacao TEXT     DEFAULT NULL,  -- 'atrasada', 'vence_hoje', 'a_vencer' ou 'em_aberto' (US08)
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
    id_parcela       INTEGER
)
LANGUAGE plpgsql
STABLE  -- só lê dados: não altera nada no banco
AS $$
BEGIN
    IF p_situacao IS NOT NULL
       AND p_situacao NOT IN ('atrasada', 'vence_hoje', 'a_vencer', 'em_aberto') THEN
        RAISE EXCEPTION 'Situação inválida: "%". Use atrasada, vence_hoje, a_vencer ou em_aberto.', p_situacao
            USING ERRCODE = 'invalid_parameter_value';
    END IF;
    PERFORM validar_periodo(p_de, p_ate);

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
       AND (p_situacao IS NULL
            OR s.situacao = p_situacao
            OR (p_situacao = 'em_aberto' AND s.situacao <> 'atrasada'))   -- "em aberto" = ainda não venceu
       AND cliente_combina_com_busca(s.nome, s.cpf, p_busca)
       AND (p_de  IS NULL OR s.data_vencimento >= p_de)
       AND (p_ate IS NULL OR s.data_vencimento <= p_ate);
END;
$$;

-- ---------------------------------------------------------------------
-- 3) Pesquisa de parcelas PAGAS (aba "Pagas")
-- ---------------------------------------------------------------------
-- Mesmos filtros (menos a situação). O período e o mês olham o
-- VENCIMENTO, como nas outras abas: no mês de novembro aparecem as
-- parcelas que venciam em novembro, pagas em qualquer dia.
CREATE OR REPLACE FUNCTION pesquisar_parcelas_pagas(
    p_cpf   CHAR(11) DEFAULT NULL,
    p_busca TEXT     DEFAULT NULL,
    p_de    DATE     DEFAULT NULL,
    p_ate   DATE     DEFAULT NULL
) RETURNS TABLE (
    id_parcela            INTEGER,
    cpf                   CHAR(11),
    nome                  VARCHAR(100),
    telefone              VARCHAR(13),
    id_cobranca           INTEGER,
    parcela               TEXT,
    valor                 NUMERIC(10,2),
    data_vencimento       DATE,
    data_pagamento        DATE,
    dias_atraso_pagamento INTEGER
)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    PERFORM validar_periodo(p_de, p_ate);

    RETURN QUERY
    SELECT p.id,
           cl.cpf,
           cl.nome,
           cl.telefone,
           co.id,
           p.numero_parcela || '/' || p.total_parcelas,
           p.valor,
           p.data_vencimento,
           p.data_pagamento,
           p.dias_atraso_pagamento   -- calculado pelo banco (US06)
      FROM parcela  p
      JOIN cobranca co ON co.id  = p.id_cobranca
      JOIN cliente  cl ON cl.cpf = co.cpf_cliente
     WHERE p.status = 'paga'
       AND (p_cpf IS NULL OR cl.cpf = p_cpf)
       AND cliente_combina_com_busca(cl.nome, cl.cpf, p_busca)
       AND (p_de  IS NULL OR p.data_vencimento >= p_de)
       AND (p_ate IS NULL OR p.data_vencimento <= p_ate);
END;
$$;
