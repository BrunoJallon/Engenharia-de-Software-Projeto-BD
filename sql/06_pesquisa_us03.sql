-- =====================================================================
-- CollectionLine · US03 — Pesquisa de parcelas pendentes
-- Todos os filtros são opcionais (nulo = não filtra): CPF exato, busca por
-- nome ou CPF, situação e período de vencimento. A ordenação das colunas
-- fica com a aplicação, que escolhe o ORDER BY numa lista fechada.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Auxiliar: minúsculas e sem acentos, para "jose" achar "José".
-- Sem extensões: só a função translate, que troca letra por letra.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION normalizar_texto(p_texto TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE  -- mesma entrada, mesma saída, sempre
AS $$
    SELECT lower(translate(p_texto,
        'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇáàâãäéèêëíìîïóòôõöúùûüç',
        'AAAAAEEEEIIIIOOOOOUUUUCaaaaaeeeeiiiiooooouuuuc'));
$$;

-- ---------------------------------------------------------------------
-- Pesquisa sobre a view vw_parcelas_pendentes (a regra de "pendente"
-- continua num lugar só) acrescentando a coluna situacao.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pesquisar_parcelas_pendentes(
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
    situacao         TEXT
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
           s.data_vencimento, s.dias_para_vencer, s.situacao
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
