-- =====================================================================
-- CollectionLine · US01 — Dados de exemplo (todos fictícios)
-- CPFs repetidos de propósito (inválidos) para deixar claro que não são reais.
-- As cobranças são criadas SÓ pela função, como o sistema faria de verdade.
-- =====================================================================
INSERT INTO cliente (cpf, nome, email, telefone, rua, numero, bairro, cep) VALUES
    ('11111111111', 'Ana Beatriz Fictícia', 'ana.ficticia@exemplo.com', '5583999990001',
     'Rua das Acácias', '120', 'Centro', '58000000'),
    ('22222222222', 'Carlos Eduardo Exemplo', NULL, '5583999990002',
     'Avenida do Sol', 'S/N', 'Bancários', '58051000'),
    ('33333333333', 'Joana Demonstração', 'joana.demo@exemplo.com', '5583999990003',
     NULL, NULL, NULL, NULL);

-- Datas relativas a hoje para a demonstração parecer atual.
SELECT cadastrar_cobranca_parcelada('11111111111', 300.00, 3, CURRENT_DATE + 10) AS cobranca_cliente_1;
SELECT cadastrar_cobranca_parcelada('22222222222', 100.00, 3, CURRENT_DATE + 5)  AS cobranca_cliente_2;  -- mostra 33,33 + 33,33 + 33,34
SELECT cadastrar_cobranca_parcelada('33333333333',  89.90, 1, CURRENT_DATE + 15) AS cobranca_cliente_3;
