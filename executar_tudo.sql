-- Script mestre da US01. Uso: psql -d collectionline_xp -f executar_tudo.sql
-- \ir resolve o caminho a partir desta pasta, então funciona de qualquer diretório.
\set ON_ERROR_STOP on
\encoding UTF8

\ir sql/01_esquema.sql
\ir sql/02_funcoes.sql
\ir sql/03_dados_exemplo.sql
\ir sql/04_consultas.sql
\ir testes/testes_us01.sql
