# CollectionLine — US01: cadastrar cobrança parcelada (Atividade 03 – XP)

Entrega mínima e funcional da User Story prioritária da **Atividade 03** de Fundamentos de Engenharia de Software (2026.2): banco em PostgreSQL com testes de aceitação, dados de exemplo e consultas de demonstração, e uma interface web simples para o operador (back-end em Java, front-end em HTML/CSS/JS puros).

## User Story

> **COMO** operador da loja **EU QUERO** cadastrar uma cobrança parcelada para um cliente **PARA QUE** o sistema acompanhe o vencimento e o status de cada parcela.

| | |
|---|---|
| **Prioridade** | prioritária |
| **Peso (planning poker)** | 3 |
| **Por que peso 3** | Usa só entidades que já existem no DER (Cliente, Cobrança e Parcela). A complexidade está no relacionamento 1:N e na regra de que a soma das parcelas tem que ser igual ao valor da cobrança. A interface é mínima (um formulário e uma tabela) e só chama a função e a view do banco. |

## Critérios de aceitação

Cada critério é um teste automatizado em [`testes/testes_us01.sql`](testes/testes_us01.sql), com datas fixas (emissão em 05/01/2027) e `ROLLBACK` no final, para não deixar nada gravado.

| CA | Critério | Resultado esperado |
|---|---|---|
| **CA1** | Cadastro básico: R$ 300,00 em 3x, primeiro vencimento em 10/01/2027 | A função retorna o id de uma cobrança de 300,00 com status `pendente`, que tem 3 parcelas numeradas 1, 2 e 3, todas de 100,00, com `total_parcelas = 3` e status `pendente`. |
| **CA2** | Arredondamento: R$ 100,00 em 3x | Parcelas de 33,33, 33,33 e 33,34, nessa ordem, somando exatamente 100,00. |
| **CA3** | Vencimentos mensais: primeiro vencimento em 31/01/2027, em 3x | Vencimentos em 31/01/2027, 28/02/2027 e 31/03/2027; o vencimento da cobrança é 31/03/2027. |
| **CA4** | Parcela única: R$ 89,90 em 1x | Uma parcela de 89,90, com número 1 e total 1, vencendo na data informada, que também é o vencimento da cobrança. |
| **CA5** | Cliente inexistente | Erro `no_data_found` e nenhuma cobrança ou parcela nova. |
| **CA6** | Parâmetros inválidos, cada caso isolado | Erro `invalid_parameter_value`, sem gravar nada, para: valor 0; valor −50,00; valor 10,005; quantidade 0; 0,02 em 3x; primeiro vencimento antes da emissão; CPF nulo. |
| **CA7** | Integridade garantida pelo banco (INSERT direto, sem a função) | Parcela de cobrança inexistente → `foreign_key_violation`; número de parcela repetido na mesma cobrança → `unique_violation`; status `cancelada` → `check_violation`; `numero_parcela` maior que `total_parcelas` → `check_violation`; cobrança para CPF inexistente → `foreign_key_violation`. |
| **CA8** | Consulta | Depois de cadastrar uma cobrança em 3x para um cliente de teste, `vw_parcelas_pendentes` traz 3 linhas para esse CPF, com a coluna `parcela` igual a `1/3`, `2/3` e `3/3`. |
| **CA9** | Limites (acrescentado pela equipe depois da revisão) | Erro `invalid_parameter_value`, sem gravar nada, para: valor acima de R$ 99.999.999,99; mais de 360 parcelas; vencimento infinito; último vencimento depois de 31/12/9999; valor `NaN`. |

## Arquitetura

```
Navegador (HTML/CSS/JS) ──HTTP/JSON──► Java (Controller → Repository) ──JDBC──► PostgreSQL (função e view)
```

- **Navegador:** mostra o formulário e as tabelas. Não calcula parcelas nem faz contas com dinheiro: só formata o que a API devolve e sugere o vencimento padrão (hoje + 30 dias).
- **Controller (`CobrancaController`):** recebe a requisição, confere só o formato dos dados (campo ausente, CPF sem 11 dígitos, número ou data impossíveis de converter) e traduz o resultado ou o erro do banco para HTTP.
- **Repository (`CobrancaRepository`):** concentra todo o SQL da aplicação, sempre com `PreparedStatement`; chama a função e lê a view.
- **PostgreSQL:** guarda os dados e é o dono da regra de negócio. A função `cadastrar_cobranca_parcelada` valida e calcula as parcelas; a view `vw_parcelas_pendentes` monta a lista de pendentes.

Como a regra fica só no banco, os testes de `testes/testes_us01.sql` valem para a aplicação inteira.

```
us01-cobranca-parcelada/
├── executar_tudo.sql            # script mestre do banco
├── sql/                         # esquema, função, dados de exemplo e consultas
├── testes/testes_us01.sql       # critérios de aceitação como testes
└── app/                         # interface: back-end Java + front-end
    ├── pom.xml
    ├── app.properties.example
    └── src/main/
        ├── java/br/com/collectionline/   # Main, Config, Database, Repository, Controller...
        └── resources/public/             # index.html, style.css, app.js
```

## Recorte do modelo

As três tabelas ficam em [`sql/01_esquema.sql`](sql/01_esquema.sql):

| tabela | colunas | chaves e restrições |
|---|---|---|
| `cliente` | `cpf`, `nome`, `email`, `telefone`, `rua`, `numero`, `bairro`, `cep` | PK `cpf`; CPF com 11 dígitos; telefone com 10 a 13 dígitos; CEP com 8 dígitos |
| `cobranca` | `id`, `cpf_cliente`, `data_emissao`, `data_vencimento`, `valor`, `status_pagamento` | PK `id`; FK `cpf_cliente` → `cliente` (`ON DELETE RESTRICT`); valor > 0; vencimento ≥ emissão; status `pendente`, `paga` ou `vencida` |
| `parcela` | `id`, `id_cobranca`, `numero_parcela`, `total_parcelas`, `valor`, `data_vencimento`, `status` | PK `id`; FK `id_cobranca` → `cobranca` (`ON DELETE CASCADE`); UNIQUE (`id_cobranca`, `numero_parcela`); 1 ≤ número ≤ total; valor > 0; status `pendente`, `paga` ou `vencida` |

Correspondência entre o DER e o banco:

| DER | banco |
|---|---|
| Cliente: CPF | `cliente.cpf` (PK) |
| Cliente: Nome, Email, Telefone | `cliente.nome`, `cliente.email`, `cliente.telefone` |
| Cliente: Endereço (composto por Rua, Bairro, CEP e Numero) | uma coluna por componente: `cliente.rua`, `cliente.bairro`, `cliente.cep`, `cliente.numero` |
| Cobrança: ID | `cobranca.id` (PK) |
| Cobrança: DataEmissao, DataVencimento | `cobranca.data_emissao`, `cobranca.data_vencimento` |
| Cobrança: Valor, StatusPagamento | `cobranca.valor`, `cobranca.status_pagamento` |
| Parcela: ID | `parcela.id` (PK) |
| Parcela: Num da Parcela | `parcela.numero_parcela` |
| Parcela: Dt Vencimento | `parcela.data_vencimento` |
| Parcela: Valor, Status, TotalParcelas | `parcela.valor`, `parcela.status`, `parcela.total_parcelas` |
| Relacionamento **Deve** (Cliente 1:N Cobrança) | `cobranca.cpf_cliente` (FK no lado N) |
| Relacionamento **Possui** (Cobrança 1:N Parcela) | `parcela.id_cobranca` (FK no lado N) |

## Regras de negócio e premissas

**Regras** — todas na função `cadastrar_cobranca_parcelada` ([`sql/02_funcoes.sql`](sql/02_funcoes.sql)):

- **Arredondamento:** valor base = valor ÷ quantidade, truncado nos centavos. As parcelas 1 a n−1 recebem o valor base e a última recebe a diferença. Exemplo: R$ 100,00 em 3x → 33,33 + 33,33 + 33,34. A soma é sempre exata.
- **Vencimentos mensais:** a parcela k vence k − 1 meses depois do primeiro vencimento, sempre contando a partir do primeiro. Assim, 31/01 em 3x vira 31/01, 28/02 e 31/03 (e não 28/03).
- **Vencimento da cobrança** = vencimento da última parcela.
- **Status inicial:** cobrança e parcelas começam como `pendente`, e todas as parcelas têm `total_parcelas` igual à quantidade informada.
- **Tudo ou nada:** a função roda numa única transação. Se qualquer passo falhar, nada fica gravado.
- **A regra fica só no banco:** o Java confere apenas o formato dos dados e o front-end não calcula parcelas, nem como prévia.

**Premissas assumidas nesta entrega:**

- Não havia dicionário de dados do grupo na pasta; valem os tipos, tamanhos e obrigatoriedades do prompt da atividade.
- **Evidência do test-first** (o git não mostra a fase vermelha): antes de a função existir, a primeira execução dos testes parou com `ERRO: função cadastrar_cobranca_parcelada(...) não existe` (SQLSTATE 42883); só depois a função foi escrita e os testes passaram. O CA8 testa a view, que só passou a existir no commit 3: ele foi escrito junto com ela e também falhou primeiro, com `relação "vw_parcelas_pendentes" não existe`.
- "Só dígitos" em CPF, telefone e CEP foi implementado com `CHECK` por expressão regular.
- Os ids (`SERIAL`) podem pular números: os testes fazem `ROLLBACK`, mas os valores já consumidos da sequência não voltam. É o comportamento normal do PostgreSQL.
- Depois de um cadastro com sucesso, a tela limpa o valor e volta a quantidade para 1 (o valor inicial do campo); cliente e vencimento continuam como estavam.
- Em `GET /api/parcelas-pendentes`, um `?cpf=` vazio é tratado como "sem filtro"; um `cpf` que não tenha 11 dígitos responde 400.
- **Limites validados pela função** (CA9): valor até R$ 99.999.999,99 (o máximo de `NUMERIC(10,2)`), no máximo 360 parcelas (30 anos de parcelas mensais, limite combinado pela equipe), datas finitas e com ano de até 4 dígitos, e `NaN` recusado. Sem isso, essas entradas estouravam no `INSERT` e a API respondia 500 em vez de 400.
- As mensagens da função escrevem valores com vírgula ("O valor 0,02 ...").
- `sql/01_esquema.sql` começa com uma trava: se o `psql` estiver conectado em outro banco que não `collectionline_xp`, o script para antes de qualquer `DROP`.
- Os arquivos de teste ligam `plpgsql.check_asserts`, para os `ASSERT` nunca serem ignorados.
- `Database` registra o driver com `Class.forName("org.postgresql.Driver")`: o `mvn exec:java` roda a aplicação num carregador de classes separado e, sem isso, o `DriverManager` responde "No suitable driver found".
- O servidor escuta só no endereço local (loopback), então não fica acessível pela rede.
- A data de emissão é o `CURRENT_DATE` do banco: a API não envia `p_data_emissao`.
- A API aceita `valor` e `qtdParcelas` também como número JSON (ex.: `300.00` sem aspas): o Gson entrega o texto original, que vira `BigDecimal` sem passar por `double`. Nas respostas, `valor` sai como número JSON com duas casas (ex.: `33.33`).
- `GET /index.html` também serve a página, além de `GET /`.
- **Tela em duas colunas a partir de 1280 px** de largura; abaixo disso, uma coluna, para a tabela de pendentes aparecer inteira (em 1024 px, resolução comum de projetor, ela cabe sem rolar). Quem quiser as duas colunas num projetor de 1024 px pode usar o zoom do navegador em 80% (1024 ÷ 0,8 = 1280).
- **Extras de tela**, além do que a atividade pede: a pílula "Hoje: dd/mm/aaaa" no cabeçalho (usa o relógio do computador, enquanto os "dias para vencer" vêm do `CURRENT_DATE` do banco; no mesmo computador, coincidem), o contador ao lado de "Parcelas pendentes", uma frase de ajuda no estado vazio e "Atrasada há 1 dia" no singular.
- Na tabela "Parcelas criadas", o status aparece como texto simples ("Pendente"): toda parcela nasce pendente, e uma etiqueta colorida se confundiria com a coluna Situação.

## Como executar

**Pré-requisitos:** PostgreSQL 12 ou superior (com `psql`), Java 17 ou superior e Maven 3.9 ou superior.

> ⚠️ **Compile uma vez antes da aula.** A primeira compilação do Maven baixa as dependências (driver do PostgreSQL e Gson) e precisa de internet. Depois disso, tudo funciona sem Wi-Fi.

### 1. Banco

Crie o banco dedicado (só na primeira vez):

```bash
createdb -U postgres collectionline_xp
```

Na pasta do projeto (`us01-cobranca-parcelada`), rode o script mestre. Ele recria as tabelas, carrega os dados de exemplo, mostra as consultas e executa os testes; pode ser rodado várias vezes seguidas:

```bash
psql -U postgres -d collectionline_xp -f executar_tudo.sql
```

- **No Windows (PowerShell)**, rode antes `chcp 65001` para os acentos aparecerem certos. Se `createdb` ou `psql` não forem reconhecidos, use o caminho completo: `& "C:\Program Files\PostgreSQL\17\bin\psql.exe" ...` (o mesmo vale para `createdb.exe`).
- **No Linux**, se aparecer "Peer authentication failed", acrescente `-h localhost`.
- Acrescente `-h` e `-p` se o PostgreSQL não estiver em `localhost:5432`.

### 2. Configuração

Copie o modelo de configuração e preencha a senha do banco em `db.password`:

```bash
cp app/app.properties.example app/app.properties
```

No Windows (PowerShell): `Copy-Item app\app.properties.example app\app.properties`.

O `app.properties` está no `.gitignore`: a senha nunca vai para o repositório.

### 3. Interface

```bash
cd app
mvn -q compile exec:java
```

Quando aparecer `Servidor em http://localhost:8080`, está no ar. Para parar, use `Ctrl+C`.

- Se `mvn` não for reconhecido, use o caminho completo do `mvn.cmd` ou abra a pasta `app` no IntelliJ/NetBeans, que já trazem Maven, e rode o objetivo `compile exec:java` por lá.
- Se a porta 8080 estiver ocupada (outro servidor aberto em outro terminal), feche o outro ou mude `server.port` no `app.properties`.
- O servidor entrega a tela a partir da pasta compilada (`target/classes`): depois de mudar algo em `src/main/resources/public`, pare o servidor e rode o comando de novo.

### 4. Abrir

Acesse **http://localhost:8080** no navegador.

## API

| método e caminho | o que faz | resposta |
|---|---|---|
| `GET /` | serve `index.html` | 200 |
| `GET /style.css` e `GET /app.js` | arquivos estáticos | 200 |
| `GET /api/clientes` | `SELECT cpf, nome FROM cliente ORDER BY nome` | 200 com `[{cpf, nome}]` |
| `POST /api/cobrancas` | recebe `{cpfCliente, valor, qtdParcelas, primeiroVencimento}`, chama `cadastrar_cobranca_parcelada` e busca as parcelas criadas | 201 com `{idCobranca, parcelas: [{numeroParcela, totalParcelas, valor, dataVencimento, status}]}` |
| `GET /api/parcelas-pendentes` (filtro opcional `?cpf=`) | lê `vw_parcelas_pendentes`, ordenada por vencimento e CPF | 200 com a lista |
| qualquer outro caminho ou método | — | 404 ou 405 com `{"erro": "..."}` |

- O `valor` trafega como **texto** (ex.: `"100.00"`) e as datas como texto ISO (`aaaa-mm-dd`).
- Erros do banco viram HTTP pelo SQLState: `22023` (parâmetro inválido) → **400**; `P0002` (cliente não encontrado) → **404**; classe `23` (violação de restrição) → **409**; qualquer outro → **500** com "Erro interno no servidor" (detalhes só no console). Erros de formato detectados no Java também dão **400**, sem chamar o banco.
- O formato de erro é sempre `{"erro": "mensagem"}`.
- O `POST` exige o cabeçalho `Content-Type: application/json` (senão, **415**) e corpo de até 10 KB (senão, **413**). Exigir JSON também impede que outra página aberta no navegador crie cobranças aqui (CSRF).
- O JSON é lido em modo estrito, o valor só aceita números simples (`100`, `100.50`, `.5`) e a data só aceita `aaaa-mm-dd` com ano de 4 dígitos.
- O cadastro e a leitura das parcelas criadas acontecem numa única transação no Java.
- O log mostra método, caminho e status, sem a query string (que pode ter CPF).

Exemplos no Linux, macOS ou Git Bash:

```bash
curl http://localhost:8080/api/clientes
```

```bash
curl -X POST http://localhost:8080/api/cobrancas -H "Content-Type: application/json" -d '{"cpfCliente":"11111111111","valor":"300.00","qtdParcelas":3,"primeiroVencimento":"2027-01-10"}'
```

```bash
curl "http://localhost:8080/api/parcelas-pendentes?cpf=22222222222"
```

No Windows PowerShell 5.1 (o que vem com o Windows), use `curl.exe` (o `curl` do PowerShell é outro comando) e escape as aspas do JSON com `\"`:

```powershell
curl.exe -X POST http://localhost:8080/api/cobrancas -H "Content-Type: application/json" -d '{\"cpfCliente\":\"11111111111\",\"valor\":\"300.00\",\"qtdParcelas\":3,\"primeiroVencimento\":\"2027-01-10\"}'
```

No PowerShell 7.3 ou mais novo, as aspas passam direto: escreva o JSON **sem** as barras (`'{"cpfCliente":"11111111111", ...}'`).

Respostas de exemplo:

```text
POST R$ 100,00 em 3x, primeiro vencimento em 2027-01-31 → 201
{"idCobranca":19,"parcelas":[{"numeroParcela":1,"totalParcelas":3,"valor":33.33,"dataVencimento":"2027-01-31","status":"pendente"},{"numeroParcela":2,"totalParcelas":3,"valor":33.33,"dataVencimento":"2027-02-28","status":"pendente"},{"numeroParcela":3,"totalParcelas":3,"valor":33.34,"dataVencimento":"2027-03-31","status":"pendente"}]}

POST R$ 0,02 em 3x → 400
{"erro":"O valor 0,02 não pode ser dividido em 3 parcelas: cada parcela precisa de pelo menos R$ 0,01."}

POST CPF 99999999999 → 404
{"erro":"Cliente com CPF 99999999999 não está cadastrado."}
```

## Saída esperada dos testes do banco

No final da execução do `executar_tudo.sql`, depois das consultas de demonstração:

```text
BEGIN
SET
SET
INSERT 0 3
psql:testes/testes_us01.sql:45: NOTA:  OK  CA1 - cadastro básico (300,00 em 3x de 100,00)
DO
psql:testes/testes_us01.sql:65: NOTA:  OK  CA2 - arredondamento (33,33 + 33,33 + 33,34 = 100,00)
DO
psql:testes/testes_us01.sql:86: NOTA:  OK  CA3 - vencimentos mensais (31/01, 28/02, 31/03)
DO
psql:testes/testes_us01.sql:112: NOTA:  OK  CA4 - parcela única (89,90 em 1x)
DO
psql:testes/testes_us01.sql:135: NOTA:  OK  CA5 - cliente inexistente é recusado
DO
psql:testes/testes_us01.sql:213: NOTA:  OK  CA6 - parâmetros inválidos são recusados (7 casos)
DO
psql:testes/testes_us01.sql:268: NOTA:  OK  CA7 - integridade garantida pelo banco (5 casos)
DO
psql:testes/testes_us01.sql:287: NOTA:  OK  CA8 - view de parcelas pendentes (1/3, 2/3, 3/3)
DO
psql:testes/testes_us01.sql:348: NOTA:  OK  CA9 - limites de valor, quantidade e datas (5 casos)
DO
TODOS OS TESTES DA US01 PASSARAM
ROLLBACK
```

Em seguida vêm os testes da US02 e da US03 (veja [Iteração 2](#iteração-2-us02-e-us03)), terminando em `TODOS OS TESTES DA US02 PASSARAM` e `TODOS OS TESTES DA US03 PASSARAM`.

Em um PostgreSQL configurado em inglês, `NOTA` aparece como `NOTICE`. Se algum critério falhar, o `psql` para na hora (`ON_ERROR_STOP`) e mostra a mensagem do `ASSERT` ou a linha `FALHOU CAx: ...`.

## Roteiro de teste manual da interface

Para o Douglas. Antes de começar, rode o `executar_tudo.sql` (dados limpos), suba a interface e deixe o filtro de pendentes em "Todos os clientes" (com outro cliente no filtro, a cobrança recém-criada não aparece na lista).

| # | Passo | Resultado esperado | CA |
|---|---|---|---|
| 1 | Cliente qualquer, **R$ 300,00** em **3x**, vencimento sugerido | "Cobrança nº X cadastrada" e três parcelas de **R$ 100,00** (1/3, 2/3 e 3/3), com status pendente | CA1 |
| 2 | **R$ 100,00** em **3x** | Parcelas de **R$ 33,33**, **R$ 33,33** e **R$ 33,34** | CA2 |
| 3 | Primeiro vencimento em **31/01/2027**, em **3x** | Vencimentos em **31/01**, **28/02** e **31/03/2027** | CA3 |
| 4 | **R$ 89,90** em **1x** | Uma parcela **1/1** de R$ 89,90 | CA4 |
| 5 | **R$ 0,02** em **3x** (digite `0,02` ou `0.02`, conforme o idioma do navegador) | Mensagem de erro vinda do banco; os campos continuam preenchidos e nada novo aparece na lista | CA6 |
| 6 | Primeiro vencimento **no passado** (ex.: 01/01/2020) | Mensagem de erro vinda do banco; nada novo aparece na lista | CA6 |
| 7 | Valor **0** ou quantidade **0** | O navegador barra antes de enviar (também é o comportamento esperado). O `step="0.01"` também barra 3 casas decimais, então o caso 10,005 só aparece nos testes do banco | CA6 |
| 8 | Em "Parcelas pendentes", filtrar por um cliente | Só as parcelas desse cliente, com a coluna Parcela no formato 1/3, 2/3, 3/3; "Todos os clientes" volta a lista completa | CA8 |

Para ver as cores de **"Atrasada"** e **"Vence hoje"** na demonstração, crie no `psql` uma cobrança com emissão no passado e outra vencendo hoje (rodar o `executar_tudo.sql` de novo volta tudo ao estado inicial):

```sql
SELECT cadastrar_cobranca_parcelada('33333333333', 50.00, 2, CURRENT_DATE - 40, CURRENT_DATE - 45);
SELECT cadastrar_cobranca_parcelada('11111111111', 25.00, 1, CURRENT_DATE);
```

## Time e divisão em pares

| papel | quem |
|---|---|
| Análise e projeto | Wesley |
| Testes | Douglas |
| Implementação | Lucas e Bruno Jallon |

- **Wesley + Douglas** modelam e escrevem os critérios de aceitação.
- **Lucas + Bruno** implementam em programação em par e refatoram.

## Fora do escopo desta iteração

- Vínculo com Loja, Operador e Dispositivo.
- Login de operador.
- Cadastro de clientes pela tela.
- Registro de pagamento e baixa de parcelas (a baixa simples, sem data nem valor pago, foi feita depois, na US02).
- Atualização automática do status `vencida`.
- Envio de mensagens pelo WhatsApp.
- Cobrança sem parcelas.

## Pontos técnicos para a discussão do Passo 5

Rascunho para o time completar:

- No DER, Cobrança não se liga diretamente a Loja (o caminho é Loja → Operador → Dispositivo → Cobrança), o que dificulta saber qual loja emitiu cada cobrança.
- TotalParcelas fica em Parcela no DER e repete a mesma informação em todas as parcelas; poderia ficar em Cobrança ou ser calculado.
- O status `vencida` existe no domínio, mas ainda nada o atualiza.
- Dificuldades da equipe: ______________________________________________

## Prints sugeridos

1. A tela logo depois de cadastrar uma cobrança.
2. A lista de parcelas pendentes.
3. A saída dos testes do banco (`psql ... -f executar_tudo.sql`).
4. O trecho da função que calcula as parcelas (`sql/02_funcoes.sql`, o laço `FOR k IN 1 .. p_qtd_parcelas`).

---

## Iteração 2: US02 e US03

Depois de entregar a US01, o cliente (no papel, o Bruno) pediu duas histórias novas. Elas seguiram o mesmo jeito XP: critérios de aceitação, testes escritos antes (fase vermelha) e commits próprios, só depois dos commits da US01.

### US02 — editar e pagar parcelas

> **COMO** operador da loja **EU QUERO** editar o valor e o vencimento de uma parcela e marcar parcelas como pagas **PARA QUE** a cobrança acompanhe renegociações e pagamentos do cliente.

Regras decididas pelo cliente, todas no banco ([`sql/05_funcoes_us02.sql`](sql/05_funcoes_us02.sql)):

- **Editar valor:** o valor da cobrança passa a ser a nova soma das parcelas (a regra "soma = valor" continua valendo).
- **Editar vencimento:** nunca antes da emissão e sem sair da ordem (entre a parcela anterior e a próxima; o mesmo dia da vizinha é aceito). O vencimento da cobrança continua sendo o da última parcela.
- **Marcar como paga:** a parcela fica travada (não muda valor nem data). Quando todas estão pagas, a cobrança vira `paga`.
- **Desfazer pagamento:** volta a parcela e a cobrança para `pendente`, para corrigir um clique errado.
- **Concorrência:** cada função trava a cobrança (`SELECT ... FOR UPDATE`) antes de mexer, para duas pessoas na mesma cobrança serem atendidas uma de cada vez.
- "Já paga" / "não está paga" usam o código `object_not_in_prerequisite_state` (55000), que a API devolve como **409**.

| CA | Critério | Resultado esperado |
|---|---|---|
| **CA1** | Editar valor | R$ 100,00 em 3x; parcela 2 vira 40,00 → parcelas 33,33 / 40,00 / 33,34 e cobrança de 106,67 |
| **CA2** | Editar vencimento do meio | só a parcela 2 muda; o vencimento da cobrança continua o da última |
| **CA3** | Editar vencimento da última | o vencimento da cobrança acompanha |
| **CA4** | Ordem das datas | antes da anterior, depois da próxima ou antes da emissão → `invalid_parameter_value`, nada muda; o mesmo dia da vizinha é aceito |
| **CA5** | Valores inválidos | 0, negativo, 3 casas, nulo, data nula, NaN, data infinita → `invalid_parameter_value`; parcela inexistente → `no_data_found` |
| **CA6** | Pagar | parcela fica `paga` e sai da lista de pendentes; com todas pagas, a cobrança fica `paga` |
| **CA7** | Paga travada | editar ou pagar de novo → `object_not_in_prerequisite_state` |
| **CA8** | Desfazer | parcela e cobrança voltam para `pendente`; desfazer de parcela pendente → `object_not_in_prerequisite_state` |

### US03 — pesquisar parcelas pendentes

> **COMO** operador da loja **EU QUERO** pesquisar as parcelas pendentes por cliente (nome ou CPF), situação e período, e ordenar a lista **PARA QUE** eu encontre rápido quem cobrar.

A pesquisa é a função `pesquisar_parcelas_pendentes` ([`sql/06_pesquisa_us03.sql`](sql/06_pesquisa_us03.sql)), feita sobre a view da US01:

- **Busca** por parte do nome (sem diferenciar maiúsculas nem acentos, com `translate`, sem extensões) ou por parte do CPF (só os dígitos contam, então `333.333` também acha). Usa `strpos` ("contém"), que não tem curingas como o `%` do `LIKE`.
- **Situação:** `atrasada`, `vence_hoje` ou `a_vencer`, calculada pelo banco a partir de `dias_para_vencer`.
- **Período** de vencimento, com datas inclusivas.
- **Ordenação** por cliente, cobrança, valor ou vencimento, crescente ou decrescente. Fica no Java, porque o `ORDER BY` não aceita `?`: a coluna sai de uma lista fechada e nunca do texto digitado.

| CA | Critério | Resultado esperado |
|---|---|---|
| **CA1** | Busca por nome | "jose antonio" acha "José Antônio"; "CONCEICAO" acha "Maria Conceição" |
| **CA2** | Busca por CPF | com ou sem pontuação |
| **CA3** | Situação | cada situação traz só as suas parcelas |
| **CA4** | Período | só os vencimentos dentro do intervalo, inclusive as pontas |
| **CA5** | Combinações | busca + situação; filtro por CPF exato da US01; busca vazia = sem busca; sem filtros = view inteira |
| **CA6** | Inválidos | situação desconhecida e período invertido → `invalid_parameter_value` |

Os testes da US03 usam datas relativas a hoje de propósito: a situação depende do dia em que o teste roda. As conferências olham só os clientes de teste (CPF começando com 7).

### API da iteração 2

| método e caminho | o que faz | resposta |
|---|---|---|
| `GET /api/cobrancas/{id}` | detalhe da cobrança com todas as parcelas | 200 `{idCobranca, cpfCliente, nomeCliente, dataEmissao, dataVencimento, valor, statusPagamento, parcelas: [{idParcela, numeroParcela, totalParcelas, valor, dataVencimento, status}]}`; 404 |
| `PUT /api/parcelas/{id}` | recebe `{valor, dataVencimento}` e chama `editar_parcela` | 200 com o detalhe atualizado; 400, 404 ou 409 |
| `POST /api/parcelas/{id}/pagamento` | marca a parcela como paga | 200 com o detalhe atualizado; 404 ou 409 |
| `DELETE /api/parcelas/{id}/pagamento` | desfaz o pagamento | 200 com o detalhe atualizado; 404 ou 409 |
| `GET /api/parcelas-pendentes?busca=&situacao=&de=&ate=&ordem=&direcao=` | pesquisa (todos opcionais; `cpf` da US01 continua valendo) | 200 com a lista, agora com `situacao` em cada item; 400 para filtros inválidos |

`POST` e `DELETE` no mesmo caminho seguem o sentido dos verbos HTTP: criar o pagamento e remover o pagamento.

### Saída esperada dos testes da iteração 2

```text
psql:testes/testes_us02.sql:41: NOTA:  OK  CA1 - editar valor ajusta o total da cobrança (100,00 -> 106,67)
psql:testes/testes_us02.sql:69: NOTA:  OK  CA2 - editar vencimento de parcela do meio
psql:testes/testes_us02.sql:91: NOTA:  OK  CA3 - editar vencimento da última parcela atualiza a cobrança
psql:testes/testes_us02.sql:143: NOTA:  OK  CA4 - vencimento fora de ordem ou antes da emissão é recusado
psql:testes/testes_us02.sql:222: NOTA:  OK  CA5 - valores inválidos e parcela inexistente são recusados (8 casos)
psql:testes/testes_us02.sql:256: NOTA:  OK  CA6 - pagar parcelas (cobrança fica paga com todas pagas)
psql:testes/testes_us02.sql:299: NOTA:  OK  CA7 - parcela paga fica travada (3 casos)
psql:testes/testes_us02.sql:341: NOTA:  OK  CA8 - desfazer pagamento volta parcela e cobrança para pendente
TODOS OS TESTES DA US02 PASSARAM
psql:testes/testes_us03.sql:44: NOTA:  OK  CA1 - busca por nome ignora maiúsculas e acentos
psql:testes/testes_us03.sql:59: NOTA:  OK  CA2 - busca por CPF, com ou sem pontuação
psql:testes/testes_us03.sql:80: NOTA:  OK  CA3 - filtro por situação (atrasada, vence hoje, a vencer)
psql:testes/testes_us03.sql:100: NOTA:  OK  CA4 - filtro por período de vencimento
psql:testes/testes_us03.sql:120: NOTA:  OK  CA5 - filtros combinados e pesquisa sem filtros
psql:testes/testes_us03.sql:142: NOTA:  OK  CA6 - parâmetros inválidos são recusados (2 casos)
TODOS OS TESTES DA US03 PASSARAM
```

### Roteiro de teste manual da iteração 2

| # | Passo | Resultado esperado | CA |
|---|---|---|---|
| 1 | Na lista de pendentes, clicar no "nº X" de uma cobrança em 3x | Abre o painel de detalhe com cliente, emissão, vencimento, valor total, status e as 3 parcelas | — |
| 2 | Editar a parcela 2 para um valor maior | O valor total da cobrança muda para a nova soma | US02-CA1 |
| 3 | Editar o vencimento da parcela 2 para depois da parcela 3 | Mensagem de erro do banco no painel; os campos continuam preenchidos | US02-CA4 |
| 4 | Marcar as 3 parcelas como pagas | Status da cobrança vira "Paga", ela some da lista de pendentes; parcela paga não tem "Editar" | US02-CA6 e CA7 |
| 5 | "Desfazer pagamento" numa parcela paga | Parcela e cobrança voltam para pendente e reaparecem na lista | US02-CA8 |
| 6 | Esc ou "Fechar" | O painel fecha e o foco volta para o "nº X" | — |
| 7 | Buscar "joana" e depois "demonstracao" (sem acento) | Só as parcelas da Joana Demonstração | US03-CA1 |
| 8 | Buscar "333.333.333-33" | Só as parcelas da Joana | US03-CA2 |
| 9 | Situação "A vencer", depois um período | Só as parcelas que atendem aos filtros | US03-CA3 e CA4 |
| 10 | Clicar duas vezes no título "Valor" | Ordena do menor para o maior (▲) e depois ao contrário (▼) | US03 |
| 11 | "Limpar filtros" | Volta a lista completa | US03-CA5 |

### Fora do escopo da iteração 2

- Guardar data e valor de cada pagamento (a entidade Pagamento do DER continua fora do recorte).
- Pagamento parcial de uma parcela.
- Excluir parcelas ou mudar a quantidade de parcelas de uma cobrança (feito na US04, abaixo).

---

## Iteração 3: US04

> **COMO** operador da loja **EU QUERO** editar ou excluir uma cobrança cadastrada **PARA QUE** eu corrija erros de cadastro (cliente errado, valor, quantidade de parcelas ou primeiro vencimento).

Regras decididas pelo cliente, todas no banco ([`sql/07_funcoes_us04.sql`](sql/07_funcoes_us04.sql)):

- **Só sem pagamento:** editar ou excluir só é possível enquanto nenhuma parcela da cobrança estiver paga (senão `object_not_in_prerequisite_state` → HTTP 409). Para corrigir, desfaz-se o pagamento antes.
- **Editar** troca cliente, valor total, quantidade e primeiro vencimento. As parcelas são apagadas e geradas de novo com a **mesma regra do cadastro** (valor truncado com a sobra na última; meses sempre a partir do primeiro vencimento), com as mesmas validações. A data de emissão não muda.
- **Excluir** apaga a cobrança e, pelo `ON DELETE CASCADE`, as parcelas. A tela pede confirmação antes.
- Cada função trava a cobrança (`FOR UPDATE`), como na US02.

| CA | Critério | Resultado esperado |
|---|---|---|
| **CA1** | Mudar valor e quantidade | R$ 100,00 em 3x vira R$ 200,00 em 4x: quatro parcelas de 50,00, todas x/4 e pendentes; vencimento da cobrança = o da última; emissão igual |
| **CA2** | Mudar o primeiro vencimento | 31/01/2027 em 3x → 31/01, 28/02 e 31/03, com 33,33 + 33,33 + 33,34 |
| **CA3** | Trocar o cliente | a cobrança e as parcelas pendentes passam para o novo cliente |
| **CA4** | Dados inválidos | valor 0, 0,02 em 3x, vencimento antes da emissão, 361 parcelas → `invalid_parameter_value`; cliente ou cobrança inexistente → `no_data_found`; nada muda |
| **CA5** | Com parcela paga | editar → `object_not_in_prerequisite_state`; nada muda |
| **CA6** | Excluir | a cobrança e as parcelas somem |
| **CA7** | Não exclui | com parcela paga → `object_not_in_prerequisite_state`; inexistente → `no_data_found` |

| método e caminho | o que faz | resposta |
|---|---|---|
| `PUT /api/cobrancas/{id}` | recebe os mesmos campos do cadastro (`cpfCliente`, `valor`, `qtdParcelas`, `primeiroVencimento`) e chama `editar_cobranca` | 200 com o detalhe atualizado; 400, 404 ou 409 |
| `DELETE /api/cobrancas/{id}` | chama `excluir_cobranca` | 200 `{"mensagem": "Cobrança nº X excluída."}`; 404 ou 409 |

No Java, a leitura e a conferência dos campos da cobrança ficaram num método só (`lerDadosCobranca`), usado pelo cadastro e pela edição.

Saída esperada dos testes da US04:

```text
psql:testes/testes_us04.sql:47: NOTA:  OK  CA1 - mudar valor e quantidade recalcula as parcelas (100,00 em 3x -> 200,00 em 4x)
psql:testes/testes_us04.sql:70: NOTA:  OK  CA2 - mudar o 1º vencimento refaz as datas com a regra do cadastro
psql:testes/testes_us04.sql:91: NOTA:  OK  CA3 - trocar o cliente da cobrança
psql:testes/testes_us04.sql:160: NOTA:  OK  CA4 - dados inválidos são recusados (6 casos)
psql:testes/testes_us04.sql:186: NOTA:  OK  CA5 - cobrança com parcela paga não pode ser editada
psql:testes/testes_us04.sql:206: NOTA:  OK  CA6 - excluir apaga a cobrança e as parcelas
psql:testes/testes_us04.sql:236: NOTA:  OK  CA7 - não exclui cobrança com parcela paga nem inexistente
TODOS OS TESTES DA US04 PASSARAM
```

Roteiro de teste manual da US04 (no painel de detalhe, aberto pelo "nº X"):

| # | Passo | Resultado esperado | CA |
|---|---|---|---|
| 1 | "Editar cobrança": R$ 200,00 em 4x | quatro parcelas de R$ 50,00 | CA1 |
| 2 | Primeiro vencimento 31/01/2027 em 3x | 31/01, 28/02 e 31/03 | CA2 |
| 3 | Trocar o cliente | a lista de pendentes mostra o novo nome | CA3 |
| 4 | R$ 0,02 em 3x | mensagem de erro do banco no painel | CA4 |
| 5 | Pagar uma parcela e tentar editar ou excluir a cobrança | botões desabilitados, com a explicação | CA5 e CA7 |
| 6 | "Excluir cobrança" e confirmar | a cobrança some da lista | CA6 |

## Iteração 4: US05

> **COMO** operador **EU QUERO** a opção de gerar planilhas (CSV/XLSX) com várias cobranças por vez **PARA QUE** eu possa gerar relatórios de forma mais prática.

Regras decididas pelo cliente:

- **O que entra:** as cobranças que aparecem na pesquisa de parcelas pendentes (US03), com os **mesmos filtros** que estiverem na tela (busca, cliente, situação e período). Cobrança toda paga não entra, porque não tem parcela pendente.
- **CSV:** só o resumo, com uma linha por cobrança. O separador é `;`, o decimal usa vírgula, as datas vêm como dd/mm/aaaa e o arquivo começa com BOM UTF-8, para o Excel em português abrir com acentos.
- **XLSX (Excel):** duas abas. **Cobranças** traz o mesmo resumo do CSV, e **Parcelas** traz as parcelas pendentes da pesquisa. Datas e valores ficam gravados como data e número de verdade (dá para somar e filtrar), e o cabeçalho fica congelado e com filtro.
- Os totais (parcelas pagas e pendentes, valor pendente) são calculados no banco, pela função `resumir_cobrancas_pesquisadas` ([`sql/08_relatorio_us05.sql`](sql/08_relatorio_us05.sql)). Ela reaproveita `pesquisar_parcelas_pendentes`, então a regra dos filtros fica num lugar só.
- **Injeção de CSV:** um nome de cliente que comece com `=`, `+`, `-` ou `@` ganha um apóstrofo na frente, para o Excel não executar o nome como fórmula. No XLSX o texto já é gravado como texto.

| CA | Critério | Resultado esperado |
|---|---|---|
| **CA1** | Uma linha por cobrança | R$ 100,00 em 3x com a 1ª paga → 3 parcelas, 1 paga, 2 pendentes, R$ 66,67 pendente |
| **CA2** | Segue os filtros da pesquisa | CPF, busca por nome, situação e período trazem as mesmas cobranças da lista |
| **CA3** | Cobrança toda paga | não entra |
| **CA4** | Filtros inválidos | situação desconhecida ou período invertido → `invalid_parameter_value` (HTTP 400) |

| método e caminho | o que faz | resposta |
|---|---|---|
| `GET /api/planilha?formato=csv` ou `xlsx`, com os filtros de `GET /api/parcelas-pendentes` | gera o arquivo | 200 com `Content-Disposition: attachment; filename="cobrancas-aaaa-mm-dd.csv"` (ou `.xlsx`); 400 para formato ou filtro inválido |

No Java, a leitura dos filtros passou para um método só (`lerFiltroPendentes`), usado pela lista e pela planilha. A montagem dos arquivos fica em `PlanilhaCobrancas`, e o XLSX é gerado com a biblioteca **Apache POI** (`poi-ooxml`, no `pom.xml`).

Saída esperada dos testes da US05:

```text
psql:testes/testes_us05.sql:44: NOTA:  OK  CA1 - uma linha por cobrança, com totais certos (100,00: 1 paga, 66,67 pendente)
psql:testes/testes_us05.sql:69: NOTA:  OK  CA2 - o resumo segue os filtros da pesquisa
psql:testes/testes_us05.sql:85: NOTA:  OK  CA3 - cobrança toda paga não entra no resumo
psql:testes/testes_us05.sql:105: NOTA:  OK  CA4 - filtros inválidos são recusados (2 casos)
TODOS OS TESTES DA US05 PASSARAM
```

Roteiro de teste manual da US05 (botões no canto da seção "Parcelas pendentes"):

| # | Passo | Resultado esperado | CA |
|---|---|---|---|
| 1 | Sem filtros, "Baixar CSV" e abrir no Excel | uma linha por cobrança pendente, com acentos, valores e datas certos | CA1 |
| 2 | "Baixar Excel" | abas "Cobranças" e "Parcelas"; os valores somam com `=SOMA()` | CA1 |
| 3 | Buscar "ana" e baixar de novo | só as cobranças que a lista mostra | CA2 |
| 4 | Pagar todas as parcelas de uma cobrança e baixar | ela não aparece | CA3 |
| 5 | Período "de" depois do "até" e baixar | mensagem de erro do banco acima da lista, nenhum arquivo | CA4 |

## Iteração 5: US06

> **COMO** operador **EU QUERO** ver o id de cada parcela na lista e registrar a data em que o cliente pagou **PARA QUE** eu identifique cada parcela e saiba se ela foi paga em dia ou com atraso.

Regras decididas pelo cliente, todas no banco ([`sql/09_pagamento_us06.sql`](sql/09_pagamento_us06.sql)). Diferente dos arquivos anteriores, este **altera** o que já existe (`ALTER TABLE`) e pode rodar num banco que já tem dados:

- **Id na lista:** a primeira coluna da lista de pendentes mostra o **id da parcela** no banco, que é fixo e único. Ela também é ordenável (`ordem=id`) e aparece na aba "Parcelas" do Excel. Para isso a view `vw_parcelas_pendentes` e a função `pesquisar_parcelas_pendentes` passaram a devolver `id_parcela`.
- **Data do pagamento:** a parcela ganhou a coluna `data_pagamento`. "Marcar como paga" agora abre um campo de data, que vem com a data de hoje. **Data no futuro ou vazia é recusada** (`invalid_parameter_value` → HTTP 400). Pagar antes da emissão é aceito, porque o cadastro permite emissão futura.
- **Em dia ou com atraso:** a coluna `dias_atraso_pagamento` é **calculada pelo próprio banco** (`GENERATED ALWAYS AS ... STORED`): mostra os dias entre o vencimento e o pagamento, 0 se foi pago até o vencimento, e fica vazia se a parcela não foi paga. O painel mostra a data com a etiqueta "Em dia" ou "Com atraso de N dias".
- **Corrigir a data:** parcela paga ganhou o botão "Editar pagamento" (`editar_pagamento_parcela`). Parcela que não está paga → `object_not_in_prerequisite_state` (HTTP 409).
- **Desfazer pagamento** agora também apaga a data.
- **Paga ⇔ tem data:** a restrição `ck_parcela_pagamento` impede uma parcela paga sem data ou pendente com data.
- Parcelas pagas antes desta história recebem como data de pagamento o próprio vencimento (ou hoje, se ele ainda não chegou).

| CA | Critério | Resultado esperado |
|---|---|---|
| **CA1** | Pagar com data | 5 dias antes do vencimento → 0 dias de atraso; 7 dias depois → 7 dias |
| **CA2** | Sem data | o pagamento fica com a data de hoje |
| **CA3** | Data inválida | amanhã, daqui a um ano ou vazia → `invalid_parameter_value`; a parcela continua pendente |
| **CA4** | Corrigir a data | o atraso é recalculado; data futura, parcela pendente ou inexistente são recusadas |
| **CA5** | Desfazer | a parcela volta a pendente, sem data nem atraso |
| **CA6** | Restrição da tabela | `UPDATE` deixando paga sem data, ou pendente com data → `check_violation` |
| **CA7** | Id na pesquisa | `pesquisar_parcelas_pendentes` devolve o `id_parcela` |

| método e caminho | o que faz | resposta |
|---|---|---|
| `POST /api/parcelas/{id}/pagamento` com `{"dataPagamento": "aaaa-mm-dd"}` | marca como paga na data informada (**o corpo agora é obrigatório**) | 200 com o detalhe; 400, 404 ou 409 |
| `PUT /api/parcelas/{id}/pagamento` com `{"dataPagamento": "aaaa-mm-dd"}` | corrige a data do pagamento | 200 com o detalhe; 400, 404 ou 409 |
| `GET /api/cobrancas/{id}` | cada parcela agora traz `dataPagamento` e `diasAtrasoPagamento` | — |
| `GET /api/parcelas-pendentes` | cada linha agora traz `idParcela`; `ordem` aceita `id` | — |

Saída esperada dos testes da US06:

```text
psql:testes/testes_us06.sql:46: NOTA:  OK  CA1 - pagar com data: antes do vencimento = em dia; 7 dias depois = 7 dias de atraso
psql:testes/testes_us06.sql:57: NOTA:  OK  CA2 - sem data informada, o pagamento fica com a data de hoje
psql:testes/testes_us06.sql:78: NOTA:  OK  CA3 - data no futuro ou vazia é recusada (3 casos)
psql:testes/testes_us06.sql:112: NOTA:  OK  CA4 - corrigir a data do pagamento recalcula o atraso (e recusa 3 casos inválidos)
psql:testes/testes_us06.sql:126: NOTA:  OK  CA5 - desfazer o pagamento apaga a data
psql:testes/testes_us06.sql:144: NOTA:  OK  CA6 - a tabela recusa paga sem data e pendente com data
psql:testes/testes_us06.sql:156: NOTA:  OK  CA7 - a pesquisa de pendentes traz o id da parcela
TODOS OS TESTES DA US06 PASSARAM
```

Roteiro de teste manual da US06:

| # | Passo | Resultado esperado | CA |
|---|---|---|---|
| 1 | Olhar a lista de pendentes e clicar no título "Id" | primeira coluna com o id da parcela, ordenável | CA7 |
| 2 | No painel, "Marcar como paga" e confirmar com a data de hoje | coluna "Pagamento" mostra a data e "Em dia" (se o vencimento ainda não passou) | CA1 e CA2 |
| 3 | Numa parcela atrasada, pagar com a data de hoje | "Com atraso de N dias" | CA1 |
| 4 | "Editar pagamento" e trocar a data | etiqueta recalculada | CA4 |
| 5 | Tentar uma data no futuro | o calendário não deixa; pela API, mensagem do banco | CA3 |
| 6 | "Desfazer pagamento" | a parcela volta para a lista, sem data | CA5 |

## Iteração 6: US07

> **COMO** operador **EU QUERO** editar, marcar como paga e excluir direto na lista de pendentes **PARA QUE** eu não precise abrir a cobrança para cada ação.

Mudanças na lista de pendentes:

- A coluna **"Cobrança" (nº X) saiu**: o id da parcela (US06) e a coluna "Parcela" já identificam a linha. O nº da cobrança continua aparecendo dentro das janelas.
- Nova coluna **"Ações"**, ao lado da situação, com três botões de ícone (cada um tem nome para leitor de tela e dica ao passar o mouse):
  - **lápis (Editar):** abre o painel da cobrança (US02/US04/US06), onde se edita a parcela ou a cobrança e se corrige ou desfaz um pagamento;
  - **✓ (Marcar como paga):** abre uma janela com **todas as parcelas pendentes da cobrança**, com caixinhas. A parcela da linha já vem marcada, e dá para marcar **todas** ("Todas as parcelas pendentes") ou **só algumas**. A data do pagamento vem com o dia de hoje;
  - **lixeira (Excluir):** pergunta se é para **excluir só a parcela** ou **a cobrança inteira**. Em cobrança à vista (1/1) só aparece a segunda opção.

Regras no banco ([`sql/10_acoes_lista_us07.sql`](sql/10_acoes_lista_us07.sql)):

- **`excluir_parcela`:** parcela paga não pode ser excluída, e a única parcela da cobrança também não (`object_not_in_prerequisite_state` → 409). As outras são **renumeradas** (excluir a 2/3 deixa 1/2 e 2/2). A cobrança passa a valer a **soma das parcelas que sobraram**, o "último vencimento" é o da última que sobrou e, se não sobrar nenhuma pendente, a cobrança fica paga. A renumeração é feita em dois passos por causa do `UNIQUE (id_cobranca, numero_parcela)`, que é conferido linha a linha.
- **`pagar_parcelas`:** paga uma lista de parcelas na mesma data usando a `pagar_parcela` da US06, então valem as mesmas regras. É **tudo ou nada**: se uma falhar, nenhuma fica paga.
- Excluir a cobrança inteira usa a `excluir_cobranca` da US04 (só sem parcela paga).

| CA | Critério | Resultado esperado |
|---|---|---|
| **CA1** | Excluir uma parcela | R$ 100,00 em 3x, excluindo a 2/3 → sobram 1/2 e 2/2, com os mesmos vencimentos; cobrança = R$ 66,67 e último vencimento = o da 2/2 |
| **CA2** | Não exclui | parcela paga ou única parcela → `object_not_in_prerequisite_state`; inexistente → `no_data_found` |
| **CA3** | Excluir a última pendente | a cobrança fica paga |
| **CA4** | Pagar várias | a 1ª e a 3ª de 3 (com id repetido) → 2 pagas, na data informada; depois a 2ª → cobrança paga |
| **CA5** | Tudo ou nada | uma já paga na lista → nenhuma é paga; lista vazia ou data futura → `invalid_parameter_value` |

| método e caminho | o que faz | resposta |
|---|---|---|
| `DELETE /api/parcelas/{id}` | chama `excluir_parcela` | 200 `{"mensagem": ...}`; 404 ou 409 |
| `POST /api/pagamentos` com `{"idsParcelas": [1, 2], "dataPagamento": "aaaa-mm-dd"}` | chama `pagar_parcelas` | 200 `{"mensagem": "2 parcelas marcadas como pagas em dd/mm/aaaa."}`; 400, 404 ou 409 |

Saída esperada dos testes da US07:

```text
psql:testes/testes_us07.sql:47: NOTA:  OK  CA1 - excluir uma parcela renumera as outras e ajusta valor e último vencimento
psql:testes/testes_us07.sql:82: NOTA:  OK  CA2 - não exclui parcela paga, a única parcela, nem inexistente (3 casos)
psql:testes/testes_us07.sql:98: NOTA:  OK  CA3 - excluir a última parcela pendente deixa a cobrança paga
psql:testes/testes_us07.sql:125: NOTA:  OK  CA4 - pagar várias parcelas de uma vez (específicas e depois o resto)
psql:testes/testes_us07.sql:161: NOTA:  OK  CA5 - pagar várias é tudo ou nada; lista vazia e data futura são recusadas
TODOS OS TESTES DA US07 PASSARAM
```

Roteiro de teste manual da US07 (com uma cobrança de R$ 100,00 em 4x):

| # | Passo | Resultado esperado | CA |
|---|---|---|---|
| 1 | Olhar a lista | sem a coluna "Cobrança"; três botões em "Ações" | — |
| 2 | Lixeira na 2/4 → "Excluir só a parcela" | sobram 1/3, 2/3 e 3/3 | CA1 |
| 3 | ✓ na 1/3, marcar também a 3/3, data de 3 dias atrás | "2 parcelas marcadas como pagas"; só a 2/3 continua na lista | CA4 |
| 4 | Lixeira na 2/3 → "Excluir a cobrança inteira" | mensagem do banco: a cobrança tem parcela paga | — |
| 5 | ✓ → desmarcar tudo → Confirmar | "Marque ao menos uma parcela." | CA5 |
| 6 | Lápis | abre o painel da cobrança, como o antigo "nº X" | — |
| 7 | Lixeira numa cobrança à vista (1/1) | só a opção "Excluir a cobrança" | CA2 |

## Iteração 7: US08

> **COMO** operador **EU QUERO** ver as parcelas separadas em abas (em aberto, atrasadas e pagas) e mês a mês **PARA QUE** a parcela paga não suma da tela e eu acompanhe cada mês, como no aplicativo do banco.

Mudanças na tela:

- **Abas "Em aberto", "Atrasadas" e "Pagas"**, cada uma com um contador. "Em aberto" = vence hoje ou depois; "Atrasadas" = venceu e não foi paga; "Pagas" = já paga. As três juntas mostram todas as parcelas, sem repetir. Uma parcela paga **sai de "Em aberto" e aparece em "Pagas"**. Na aba "Pagas", a coluna "Situação" vira "Pagamento" (data e "Em dia"/"Com atraso de N dias"), e a ação é o lápis, que abre o painel para corrigir ou desfazer o pagamento. As abas funcionam com as setas ← e → do teclado.
- **Mês:** as setas ‹ › trocam o mês, que começa no mês de hoje. As três abas mostram as parcelas que **vencem** no mês escolhido. "Todos os meses" mostra tudo. Por baixo, o mês só preenche os campos "Vencimento de" e "Vencimento até" com o dia 1 e o último dia. Se a pessoa digitar outras datas nesses campos, o título vira "Período escolhido nos filtros". "Limpar filtros" volta para o mês de hoje.
- O filtro **"Situação" saiu da tela** (as abas fazem esse papel). A API continua aceitando `situacao`.
- As planilhas (US05) seguem a busca, o cliente e o mês da tela.

Regras no banco ([`sql/11_abas_us08.sql`](sql/11_abas_us08.sql)):

- `pesquisar_parcelas_pendentes` aceita a situação **`em_aberto`** (vence hoje ou a vencer).
- Nova **`pesquisar_parcelas_pagas`**, com os mesmos filtros (CPF, busca, período de vencimento), a data do pagamento e os dias de atraso calculados pelo banco (US06).
- A regra da busca por nome/CPF e a do período passaram para funções auxiliares (`cliente_combina_com_busca`, `validar_periodo`), usadas pelas duas pesquisas.

| CA | Critério | Resultado esperado |
|---|---|---|
| **CA1** | Em aberto | traz a parcela que vence hoje e a que vence depois, e não a atrasada |
| **CA2** | Atrasadas | traz só a parcela vencida e não paga |
| **CA3** | Pagas | traz a parcela paga, com a data do pagamento e os dias de atraso; a busca por nome funciona |
| **CA4** | Sem repetir nem perder | em aberto + atrasadas + pagas = todas as parcelas do cliente |
| **CA5** | Mês nas pagas | a paga aparece no período do vencimento dela e some fora dele; período invertido é recusado |

| método e caminho | o que faz | resposta |
|---|---|---|
| `GET /api/parcelas-pendentes?situacao=em_aberto` | aba "Em aberto" (mais os filtros de sempre) | 200 com a lista |
| `GET /api/parcelas-pagas` com `cpf`, `busca`, `de`, `ate`, `ordem` e `direcao` | aba "Pagas" | 200 com a lista (inclui `dataPagamento` e `diasAtrasoPagamento`); 400 para filtro inválido |

Saída esperada dos testes da US08:

```text
psql:testes/testes_us08.sql:35: NOTA:  OK  CA1 - "em aberto" traz a que vence hoje e a que vence depois
psql:testes/testes_us08.sql:46: NOTA:  OK  CA2 - "atrasada" traz só a parcela vencida
psql:testes/testes_us08.sql:64: NOTA:  OK  CA3 - "pagas" traz a parcela paga, com data e 2 dias de atraso
psql:testes/testes_us08.sql:78: NOTA:  OK  CA4 - em aberto + atrasadas + pagas = todas as parcelas, sem repetir
psql:testes/testes_us08.sql:97: NOTA:  OK  CA5 - o período de vencimento filtra as pagas; período invertido é recusado
TODOS OS TESTES DA US08 PASSARAM
```

Roteiro de teste manual da US08:

| # | Passo | Resultado esperado | CA |
|---|---|---|---|
| 1 | Abrir a tela | mês de hoje, aba "Em aberto", contadores nas três abas | CA1 |
| 2 | ✓ numa parcela e confirmar | some de "Em aberto"; o contador de "Pagas" sobe e ela aparece lá, com "Em dia" | CA3 |
| 3 | Seta › | mês seguinte, com as parcelas que vencem nele | CA5 |
| 4 | "Todos os meses" | todas as parcelas da aba, de qualquer mês | CA4 |
| 5 | Aba "Atrasadas" | só parcelas vencidas e não pagas (contador em vermelho) | CA2 |
