-- =====================================================================
-- CollectionLine · US01 — Função cadastrar_cobranca_parcelada
-- Cria a cobrança e todas as suas parcelas numa única chamada.
-- Como uma função roda dentro de uma só transação, se qualquer passo
-- falhar nada fica gravado (por isso não há COMMIT aqui dentro).
-- =====================================================================
CREATE OR REPLACE FUNCTION cadastrar_cobranca_parcelada(
    p_cpf_cliente         CHAR(11),
    p_valor               NUMERIC,
    p_qtd_parcelas        INTEGER,
    p_primeiro_vencimento DATE,
    p_data_emissao        DATE DEFAULT CURRENT_DATE
) RETURNS INTEGER  -- id da cobrança criada
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_cobranca     INTEGER;
    v_valor_base      NUMERIC(10,2);
    v_valor_parcela   NUMERIC(10,2);
    v_vencimento      DATE;
    v_ultimo_venc     DATE;
    k                 INTEGER;
BEGIN
    -- 1) Nenhum parâmetro pode ser nulo: sem eles não há como calcular nada.
    IF p_cpf_cliente IS NULL OR p_valor IS NULL OR p_qtd_parcelas IS NULL
       OR p_primeiro_vencimento IS NULL OR p_data_emissao IS NULL THEN
        RAISE EXCEPTION 'Todos os parâmetros são obrigatórios (CPF, valor, quantidade de parcelas, primeiro vencimento e data de emissão).'
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    -- 2) Cobrança precisa ter valor positivo.
    IF p_valor <= 0 THEN
        RAISE EXCEPTION 'O valor da cobrança deve ser maior que zero (recebido: %).', p_valor
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    -- 3) Dinheiro tem no máximo centavos. A precisão de parâmetro é ignorada
    --    pelo PostgreSQL, então a checagem precisa ser explícita.
    IF p_valor <> round(p_valor, 2) THEN
        RAISE EXCEPTION 'O valor da cobrança deve ter no máximo 2 casas decimais (recebido: %).', p_valor
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    -- 4) Pelo menos uma parcela.
    IF p_qtd_parcelas < 1 THEN
        RAISE EXCEPTION 'A quantidade de parcelas deve ser pelo menos 1 (recebido: %).', p_qtd_parcelas
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    -- 5) Cada parcela precisa de pelo menos 1 centavo (senão violaria valor > 0).
    IF p_valor < p_qtd_parcelas * 0.01 THEN
        RAISE EXCEPTION 'O valor % não pode ser dividido em % parcelas: cada parcela precisa de pelo menos R$ 0,01.',
            p_valor, p_qtd_parcelas
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    -- 6) Não faz sentido a primeira parcela vencer antes da emissão.
    IF p_primeiro_vencimento < p_data_emissao THEN
        RAISE EXCEPTION 'O primeiro vencimento (%) não pode ser anterior à data de emissão (%).',
            to_char(p_primeiro_vencimento, 'DD/MM/YYYY'), to_char(p_data_emissao, 'DD/MM/YYYY')
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    -- 7) O cliente tem que existir. Checamos antes (em vez de deixar a FK
    --    estourar) para dar uma mensagem clara e um código específico.
    IF NOT EXISTS (SELECT 1 FROM cliente WHERE cpf = p_cpf_cliente) THEN
        RAISE EXCEPTION 'Cliente com CPF % não está cadastrado.', p_cpf_cliente
            USING ERRCODE = 'no_data_found';
    END IF;

    -- Vencimento da última parcela: sempre somando meses ao PRIMEIRO
    -- vencimento (31/01 + 2 meses = 31/03, e não 28/03).
    v_ultimo_venc := (p_primeiro_vencimento + make_interval(months => p_qtd_parcelas - 1))::date;

    -- A cobrança guarda o valor total e o vencimento da última parcela.
    INSERT INTO cobranca (cpf_cliente, data_emissao, data_vencimento, valor, status_pagamento)
    VALUES (p_cpf_cliente, p_data_emissao, v_ultimo_venc, p_valor, 'pendente')
    RETURNING id INTO v_id_cobranca;

    -- Valor base truncado nos centavos (100/3 = 33,33). A diferença que
    -- sobra vai toda para a última parcela, para a soma bater exatamente.
    v_valor_base := trunc(p_valor / p_qtd_parcelas, 2);

    FOR k IN 1 .. p_qtd_parcelas LOOP
        IF k < p_qtd_parcelas THEN
            v_valor_parcela := v_valor_base;
        ELSE
            v_valor_parcela := p_valor - v_valor_base * (p_qtd_parcelas - 1);
        END IF;

        v_vencimento := (p_primeiro_vencimento + make_interval(months => k - 1))::date;

        INSERT INTO parcela (id_cobranca, numero_parcela, total_parcelas,
                             valor, data_vencimento, status)
        VALUES (v_id_cobranca, k, p_qtd_parcelas,
                v_valor_parcela, v_vencimento, 'pendente');
    END LOOP;

    RETURN v_id_cobranca;
END;
$$;
