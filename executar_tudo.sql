-- Script mestre da US01. Uso: psql -d collectionline_xp -f executar_tudo.sql
-- \ir resolve o caminho a partir desta pasta, então funciona de qualquer diretório.
\set ON_ERROR_STOP on
\encoding UTF8

\ir sql/01_esquema.sql
