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
- Registro de pagamento e baixa de parcelas.
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
