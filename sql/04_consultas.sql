-- =====================================================================
-- CollectionLine · US01 — View e consultas de demonstração
-- =====================================================================

\echo ''
\echo '== View vw_parcelas_pendentes =='
-- Parcelas ainda não pagas, com os dados de contato do cliente
-- (é o que o bot de WhatsApp vai precisar para mandar lembretes).
CREATE OR REPLACE VIEW vw_parcelas_pendentes AS
SELECT cl.cpf,
       cl.nome,
       cl.telefone,
       co.id                                       AS id_cobranca,
       p.numero_parcela || '/' || p.total_parcelas AS parcela,
       p.valor,
       p.data_vencimento,
       p.data_vencimento - CURRENT_DATE            AS dias_para_vencer  -- negativo = atrasada
  FROM parcela  p
  JOIN cobranca co ON co.id  = p.id_cobranca
  JOIN cliente  cl ON cl.cpf = co.cpf_cliente
 WHERE p.status = 'pendente';

\echo ''
\echo '== 1. Parcelas pendentes (ordem de vencimento) =='
SELECT *
  FROM vw_parcelas_pendentes
 ORDER BY data_vencimento, cpf;

\echo ''
\echo '== 2. Conferência: cobranças cuja soma das parcelas difere do valor (esperado: nenhuma linha) =='
-- JOIN (e não LEFT JOIN): só entram cobranças que têm parcelas,
-- porque o DER permite cobrança sem parcela.
SELECT co.id,
       co.valor,
       sum(p.valor) AS soma_parcelas
  FROM cobranca co
  JOIN parcela  p ON p.id_cobranca = co.id
 GROUP BY co.id, co.valor
HAVING sum(p.valor) <> co.valor;

\echo ''
\echo '== 3. Resumo por cobrança =='
SELECT co.id                                                   AS id_cobranca,
       cl.nome                                                 AS cliente,
       co.valor,
       count(p.id)                                             AS qtd_parcelas,
       count(p.id) FILTER (WHERE p.status = 'pendente')        AS parcelas_pendentes,
       COALESCE(sum(p.valor) FILTER (WHERE p.status = 'pendente'), 0) AS valor_pendente
  FROM cobranca co
  JOIN cliente  cl ON cl.cpf = co.cpf_cliente
  LEFT JOIN parcela p ON p.id_cobranca = co.id
 GROUP BY co.id, cl.nome, co.valor
 ORDER BY co.id;
