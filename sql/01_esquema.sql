-- =====================================================================
-- CollectionLine · US01 — Esquema: cliente, cobranca e parcela
-- Recorte do DER: Cliente --(Deve)--> Cobrança --(Possui)--> Parcela
-- =====================================================================

-- Esconde os avisos "não existe, ignorando" dos DROP ... IF EXISTS.
SET client_min_messages = warning;

-- Ordem de remoção: a view depende das tabelas; sem CASCADE para não
-- apagar sem querer nenhum objeto que não seja desta entrega.
DROP VIEW IF EXISTS vw_parcelas_pendentes;
DROP TABLE IF EXISTS parcela, cobranca, cliente;

-- ---------------------------------------------------------------------
-- Cliente: o endereço (atributo composto no DER) vira uma coluna por
-- componente: rua, numero, bairro e cep.
-- ---------------------------------------------------------------------
CREATE TABLE cliente (
    cpf      CHAR(11)     NOT NULL,
    nome     VARCHAR(100) NOT NULL,
    email    VARCHAR(100),
    telefone VARCHAR(13)  NOT NULL,  -- número do WhatsApp: DDI + DDD + número
    rua      VARCHAR(100),
    numero   VARCHAR(10),            -- texto para aceitar "S/N"
    bairro   VARCHAR(60),
    cep      CHAR(8),
    CONSTRAINT pk_cliente PRIMARY KEY (cpf),
    CONSTRAINT ck_cliente_cpf      CHECK (cpf ~ '^[0-9]{11}$'),
    CONSTRAINT ck_cliente_telefone CHECK (telefone ~ '^[0-9]{10,13}$'),
    CONSTRAINT ck_cliente_cep      CHECK (cep ~ '^[0-9]{8}$')
);

-- ---------------------------------------------------------------------
-- Cobrança: relacionamento Deve (1:N) -> a FK fica no lado N.
-- data_vencimento guarda o vencimento da última parcela.
-- ---------------------------------------------------------------------
CREATE TABLE cobranca (
    id               SERIAL        NOT NULL,
    cpf_cliente      CHAR(11)      NOT NULL,
    data_emissao     DATE          NOT NULL DEFAULT CURRENT_DATE,
    data_vencimento  DATE          NOT NULL,
    valor            NUMERIC(10,2) NOT NULL,
    status_pagamento VARCHAR(10)   NOT NULL DEFAULT 'pendente',
    CONSTRAINT pk_cobranca PRIMARY KEY (id),
    -- RESTRICT: não se apaga cliente que ainda tem cobranças.
    CONSTRAINT fk_cobranca_cliente FOREIGN KEY (cpf_cliente)
        REFERENCES cliente (cpf) ON DELETE RESTRICT,
    CONSTRAINT ck_cobranca_vencimento CHECK (data_vencimento >= data_emissao),
    CONSTRAINT ck_cobranca_valor      CHECK (valor > 0),
    CONSTRAINT ck_cobranca_status     CHECK (status_pagamento IN ('pendente', 'paga', 'vencida'))
);

-- ---------------------------------------------------------------------
-- Parcela: relacionamento Possui (1:N) -> a FK fica no lado N.
-- ---------------------------------------------------------------------
CREATE TABLE parcela (
    id              SERIAL        NOT NULL,
    id_cobranca     INTEGER       NOT NULL,
    numero_parcela  SMALLINT      NOT NULL,
    total_parcelas  SMALLINT      NOT NULL,
    valor           NUMERIC(10,2) NOT NULL,
    data_vencimento DATE          NOT NULL,
    status          VARCHAR(10)   NOT NULL DEFAULT 'pendente',
    CONSTRAINT pk_parcela PRIMARY KEY (id),
    -- CASCADE: parcela não existe sem a sua cobrança.
    CONSTRAINT fk_parcela_cobranca FOREIGN KEY (id_cobranca)
        REFERENCES cobranca (id) ON DELETE CASCADE,
    -- Uma cobrança não pode ter duas parcelas com o mesmo número.
    -- Este UNIQUE também cria o índice usado nas buscas por id_cobranca.
    CONSTRAINT uq_parcela_cobranca_numero UNIQUE (id_cobranca, numero_parcela),
    CONSTRAINT ck_parcela_numero CHECK (numero_parcela >= 1),
    CONSTRAINT ck_parcela_total  CHECK (numero_parcela <= total_parcelas),
    CONSTRAINT ck_parcela_valor  CHECK (valor > 0),
    CONSTRAINT ck_parcela_status CHECK (status IN ('pendente', 'paga', 'vencida'))
);

-- Acelera "cobranças de um cliente" (e a checagem do ON DELETE RESTRICT).
CREATE INDEX idx_cobranca_cpf_cliente ON cobranca (cpf_cliente);
