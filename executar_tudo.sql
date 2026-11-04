-- Script mestre. Uso: psql -d collectionline_xp -f executar_tudo.sql
-- \ir resolve o caminho a partir desta pasta, então funciona de qualquer diretório.
\set ON_ERROR_STOP on
\encoding UTF8

-- US01: cadastrar cobrança parcelada
\ir sql/01_esquema.sql
\ir sql/02_funcoes.sql
\ir sql/03_dados_exemplo.sql
\ir sql/04_consultas.sql
-- US02: editar e pagar parcelas / US03: pesquisa de pendentes
\ir sql/05_funcoes_us02.sql
\ir sql/06_pesquisa_us03.sql
-- US04: editar e excluir cobrança
\ir sql/07_funcoes_us04.sql
-- US05: resumo de cobranças para as planilhas
\ir sql/08_relatorio_us05.sql
-- US06: data do pagamento (em dia ou com atraso) e id da parcela na pesquisa
\ir sql/09_pagamento_us06.sql
-- US07: excluir uma parcela e pagar várias de uma vez (ações da lista)
\ir sql/10_acoes_lista_us07.sql

-- Testes de aceitação (cada arquivo termina em ROLLBACK)
\ir testes/testes_us01.sql
\ir testes/testes_us02.sql
\ir testes/testes_us03.sql
\ir testes/testes_us04.sql
\ir testes/testes_us05.sql
\ir testes/testes_us06.sql
\ir testes/testes_us07.sql
