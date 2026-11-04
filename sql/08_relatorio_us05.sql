-- =====================================================================
-- CollectionLine · US05 — Resumo de cobranças para as planilhas
-- Uma linha por cobrança que aparece na pesquisa de pendentes (US03),
-- com os mesmos filtros. Os totais olham TODAS as parcelas da cobrança
-- (pagas e pendentes). A aba "Parcelas" da planilha usa a própria
-- função pesquisar_parcelas_pendentes.
-- =====================================================================
CREATE OR REPLACE FUNCTION resumir_cobrancas_pesquisadas(
    p_cpf      CHAR(11) DEFAULT NULL,
    p_busca    TEXT     DEFAULT NULL,
    p_situacao TEXT     DEFAULT NULL,
    p_de       DATE     DEFAULT NULL,
    p_ate      DATE     DEFAULT NULL
) RETURNS TABLE (
    id_cobranca        INTEGER,
    cpf                CHAR(11),
    nome               VARCHAR(100),
    telefone           VARCHAR(13),
    data_emissao       DATE,
    data_vencimento    DATE,
    valor              NUMERIC(10,2),
    qtd_parcelas       INTEGER,
    parcelas_pagas     INTEGER,
    parcelas_pendentes INTEGER,
    valor_pendente     NUMERIC(10,2),
    status_pagamento   VARCHAR(10)
)
LANGUAGE plpgsql
STABLE  -- só lê dados
AS $$
BEGIN
    -- Os filtros (e as mensagens de erro para filtros inválidos) são os da
    -- pesquisa da US03: reaproveitamos a função em vez de repetir a regra.
    RETURN QUERY
    SELECT co.id,
           cl.cpf,
           cl.nome,
           cl.telefone,
           co.data_emissao,
           co.data_vencimento,
           co.valor,
           count(p.id)::INTEGER,
           (count(p.id) FILTER (WHERE p.status = 'paga'))::INTEGER,
           (count(p.id) FILTER (WHERE p.status <> 'paga'))::INTEGER,
           COALESCE(sum(p.valor) FILTER (WHERE p.status <> 'paga'), 0)::NUMERIC(10,2),
           co.status_pagamento
      FROM cobranca co
      JOIN cliente  cl ON cl.cpf = co.cpf_cliente
      JOIN parcela  p  ON p.id_cobranca = co.id
     WHERE co.id IN (SELECT pp.id_cobranca
                       FROM pesquisar_parcelas_pendentes(p_cpf, p_busca, p_situacao, p_de, p_ate) pp)
     GROUP BY co.id, cl.cpf, cl.nome, cl.telefone
     ORDER BY co.id;
END;
$$;
