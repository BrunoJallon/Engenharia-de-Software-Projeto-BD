// =====================================================================
// CollectionLine · US01 — lógica da tela
// A tela NÃO calcula parcelas (nem como prévia) e NÃO faz contas com
// dinheiro: ela só envia os dados para a API e mostra o que o banco
// respondeu. A regra de negócio fica no banco de dados.
//
// Segurança: tudo que vem da API entra na página só com textContent ou
// criando elementos (createElement / new Option). Nunca usamos innerHTML,
// para que um texto vindo do servidor nunca seja interpretado como HTML.
// =====================================================================
'use strict';

/** Atalho para pegar um elemento da página pelo id. */
function el(id) {
    return document.getElementById(id);
}

// ---------------------------------------------------------------------
// 1) Formatação (só muda a aparência; nenhum cálculo de negócio aqui)
// ---------------------------------------------------------------------

// Formatador de moeda brasileira: criado uma vez e reaproveitado.
const formatadorMoeda = new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' });

/**
 * 33.33 -> "R$ 33,33" (só formata o número que veio do banco).
 * O Number() é só uma conversão para o formatador conseguir exibir:
 * nenhuma conta é feita com o valor.
 */
function formatarMoeda(valor) {
    return formatadorMoeda.format(Number(valor));
}

/**
 * "2027-01-31" -> "31/01/2027", só quebrando o texto nos tracinhos.
 * Não usamos new Date('aaaa-mm-dd'): ele lê a data como UTC e, no Brasil,
 * ela apareceria um dia antes.
 */
function formatarData(iso) {
    const [ano, mes, dia] = iso.split('-');
    return `${dia}/${mes}/${ano}`;
}

/** "11111111111" -> "111.111.111-11" */
function formatarCpf(cpf) {
    return `${cpf.slice(0, 3)}.${cpf.slice(3, 6)}.${cpf.slice(6, 9)}-${cpf.slice(9)}`;
}

/** "pendente" -> "Pendente" */
function formatarStatus(status) {
    return status.charAt(0).toUpperCase() + status.slice(1);
}

/**
 * Texto e classe CSS da etiqueta "Situação", a partir dos dias que faltam
 * para vencer (o banco manda um número negativo quando já está atrasada).
 */
function formatarSituacao(dias) {
    if (dias === 0) {
        return { texto: 'Vence hoje', classe: 'etiqueta-hoje' };
    }
    if (dias > 0) {
        return { texto: dias === 1 ? 'Vence em 1 dia' : `Vence em ${dias} dias`, classe: 'etiqueta-a-vencer' };
    }
    const atraso = -dias;   // só tira o sinal: -3 vira 3, para escrever "há 3 dias"
    return { texto: atraso === 1 ? 'Atrasada há 1 dia' : `Atrasada há ${atraso} dias`, classe: 'etiqueta-atrasada' };
}

/**
 * Data de hoje + N dias no formato aaaa-mm-dd, no fuso do computador.
 * Não usamos toISOString(): ele converte para UTC e pode mudar o dia.
 */
function dataDaquiA(dias) {
    const d = new Date();
    d.setDate(d.getDate() + dias);   // o próprio Date cuida da virada de mês e de ano
    const ano = d.getFullYear();
    const mes = String(d.getMonth() + 1).padStart(2, '0');  // getMonth() começa em 0
    const dia = String(d.getDate()).padStart(2, '0');
    return `${ano}-${mes}-${dia}`;
}

// ---------------------------------------------------------------------
// 2) Comunicação com a API
// ---------------------------------------------------------------------

/**
 * Chama a API e devolve o JSON da resposta. Se a resposta for de erro,
 * lança um Error com a mensagem que o servidor mandou em {"erro": "..."}.
 */
async function chamarApi(url, opcoes) {
    let resposta;
    try {
        resposta = await fetch(url, opcoes);
    } catch (e) {
        // O fetch só cai aqui quando NÃO chega resposta nenhuma (servidor
        // desligado, rede fora). Erros 400, 404 e 500 chegam normalmente,
        // com resposta.ok = false, e são tratados mais abaixo.
        throw new Error('Não foi possível falar com o servidor. Ele está rodando?');
    }

    let corpo = null;
    try {
        corpo = await resposta.json();
    } catch (e) {
        // resposta sem JSON: tratada logo abaixo
    }

    if (!resposta.ok) {
        throw new Error(corpo && corpo.erro ? corpo.erro : `Erro ${resposta.status} ao chamar ${url}.`);
    }
    return corpo;
}

// ---------------------------------------------------------------------
// 3) Mensagens de aviso (sucesso e erro)
// ---------------------------------------------------------------------

/**
 * Escreve o texto numa área de aviso. O parágrafo nunca sai da página
 * (assim o leitor de tela anuncia quando o texto muda); a classe
 * "visivel" só liga a caixa colorida em volta, com o ícone.
 * Texto vazio = caixa escondida.
 *
 * Depende da estrutura do HTML: o <p> fica direto dentro da div.aviso,
 * por isso parentElement (o "pai" do parágrafo) é a caixa colorida.
 */
function escreverAviso(id, texto) {
    const paragrafo = el(id);
    paragrafo.textContent = texto;
    // classList.toggle(classe, condição): coloca a classe se a condição for
    // verdadeira e tira se for falsa. Aqui: tem texto -> caixa visível.
    paragrafo.parentElement.classList.toggle('visivel', texto !== '');
}

/** Apaga as mensagens do formulário. */
function limparMensagens() {
    escreverAviso('mensagem', '');
    escreverAviso('erro', '');
}

/**
 * Apaga só a mensagem de ERRO (a de sucesso pode ficar). Roda sempre que o
 * operador mexe num campo: assim um erro antigo não fica na tela confundindo
 * (por exemplo, quando o próprio navegador barra o envio por campo vazio).
 */
function apagarErro() {
    escreverAviso('erro', '');
}

/** Mostra a mensagem verde (e apaga a de erro). */
function mostrarSucesso(texto) {
    escreverAviso('erro', '');
    escreverAviso('mensagem', texto);
}

/** Mostra a mensagem vermelha (e apaga a de sucesso). */
function mostrarErro(texto) {
    escreverAviso('mensagem', '');
    escreverAviso('erro', texto);
}

// ---------------------------------------------------------------------
// 4) Peças das tabelas
// ---------------------------------------------------------------------

/** Cria uma célula <td> com texto e, se quiser, uma classe CSS. */
function criarCelula(texto, classe) {
    const td = document.createElement('td');
    td.textContent = texto;
    if (classe) {
        td.className = classe;
    }
    return td;
}

/** Célula "Situação": o texto vai dentro de uma etiqueta colorida. */
function criarCelulaSituacao(dias) {
    const situacao = formatarSituacao(dias);
    const etiqueta = document.createElement('span');
    etiqueta.className = `etiqueta ${situacao.classe}`;
    etiqueta.textContent = situacao.texto;
    const td = document.createElement('td');
    td.append(etiqueta);
    return td;
}

// ---------------------------------------------------------------------
// 5) Ações da tela
// ---------------------------------------------------------------------

/** Busca os clientes e preenche os dois selects (formulário e filtro). */
async function carregarClientes() {
    try {
        const clientes = await chamarApi('/api/clientes');
        const selectCliente = el('cliente');
        const selectFiltro = el('filtro-cliente');
        selectCliente.length = 1;   // mantém só a primeira opção ("Selecione um cliente")
        selectFiltro.length = 1;    // mantém só "Todos os clientes"
        for (const cliente of clientes) {
            const texto = `${cliente.nome} — ${formatarCpf(cliente.cpf)}`;   // "Nome — 000.000.000-00"
            selectCliente.add(new Option(texto, cliente.cpf));
            selectFiltro.add(new Option(texto, cliente.cpf));
        }
    } catch (e) {
        mostrarErro(e.message);
    }
}

/**
 * Liga ou desliga o "modo enviando" do botão: desabilitado (evita clique
 * duplo), texto "Cadastrando..." e spinner (desenhado pelo CSS quando o
 * botão tem a classe "carregando").
 */
function mostrarCarregando(ligado) {
    const botao = el('botao-cadastrar');
    botao.disabled = ligado;
    botao.classList.toggle('carregando', ligado);
    botao.textContent = ligado ? 'Cadastrando...' : 'Cadastrar cobrança';
}

/** Mostra a tabela com as parcelas que o banco acabou de criar. */
function mostrarParcelasCriadas(parcelas) {
    const corpo = el('corpo-parcelas-criadas');
    corpo.replaceChildren();   // apaga as linhas do cadastro anterior
    for (const p of parcelas) {
        const linha = document.createElement('tr');
        linha.append(
            criarCelula(`${p.numeroParcela}/${p.totalParcelas}`),
            criarCelula(formatarMoeda(p.valor), 'numero'),
            criarCelula(formatarData(p.dataVencimento)),
            criarCelula(formatarStatus(p.status)),
        );
        corpo.append(linha);
    }
    el('resultado').hidden = false;
}

/** Envia o formulário para POST /api/cobrancas. */
async function enviarCobranca(evento) {
    evento.preventDefault();   // impede o navegador de recarregar a página

    mostrarCarregando(true);
    limparMensagens();
    el('resultado').hidden = true;

    const dados = {
        cpfCliente: el('cliente').value,
        valor: el('valor').value,                             // vai como TEXTO: dinheiro não vira número quebrado
        qtdParcelas: el('qtd-parcelas').value,
        primeiroVencimento: el('primeiro-vencimento').value,  // o input date já dá aaaa-mm-dd
    };

    try {
        const resposta = await chamarApi('/api/cobrancas', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(dados),
        });
        mostrarSucesso(`Cobrança nº ${resposta.idCobranca} cadastrada`);
        mostrarParcelasCriadas(resposta.parcelas);
        // Limpa valor e quantidade (volta ao padrão 1) e mantém o cliente escolhido.
        el('valor').value = '';
        el('qtd-parcelas').value = '1';
        await carregarPendentes();
    } catch (e) {
        mostrarErro(e.message);   // os campos continuam como o operador digitou
    } finally {
        mostrarCarregando(false);   // roda tanto no sucesso quanto no erro
    }
}

/** Monta uma linha da tabela de pendentes. */
function criarLinhaPendente(p) {
    const linha = document.createElement('tr');
    linha.append(
        criarCelula(p.nome, 'coluna-cliente'),
        criarCelula(`nº ${p.idCobranca}`),
        criarCelula(p.parcela),
        criarCelula(formatarMoeda(p.valor), 'numero'),
        criarCelula(formatarData(p.dataVencimento)),
        criarCelulaSituacao(p.diasParaVencer),
    );
    return linha;
}

// Número da consulta de pendentes mais recente.
// Por quê: se o operador troca o filtro rápido (por exemplo, com as setas do
// teclado), duas consultas ficam em andamento ao mesmo tempo, e a resposta
// da consulta ANTIGA pode chegar DEPOIS da nova, mostrando o cliente errado.
// Cada consulta guarda o seu número; só a mais recente pode mexer na tela.
let ultimaConsulta = 0;

/** Lê as parcelas pendentes (todas ou de um cliente) e monta a tabela. */
async function carregarPendentes() {
    const estaConsulta = ++ultimaConsulta;   // soma 1 e guarda: esta é a consulta nº 1, 2, 3...
    const cpf = el('filtro-cliente').value;
    const url = cpf ? `/api/parcelas-pendentes?cpf=${encodeURIComponent(cpf)}` : '/api/parcelas-pendentes';
    escreverAviso('erro-pendentes', '');

    try {
        const parcelas = await chamarApi(url);
        if (estaConsulta !== ultimaConsulta) return;   // já existe consulta mais nova: ignora esta resposta
        const corpo = el('corpo-pendentes');
        corpo.replaceChildren();   // apaga as linhas antigas
        for (const p of parcelas) {
            corpo.append(criarLinhaPendente(p));
        }
        el('contador-pendentes').textContent = parcelas.length;   // só conta as linhas
        el('area-pendentes').hidden = parcelas.length === 0;
        el('sem-pendentes').hidden = parcelas.length > 0;
    } catch (e) {
        if (estaConsulta !== ultimaConsulta) return;   // erro de uma consulta velha: também ignora
        // Não deixa dados antigos na tela junto com o erro (poderiam ser de outro filtro).
        el('area-pendentes').hidden = true;
        el('sem-pendentes').hidden = true;
        el('contador-pendentes').textContent = '–';
        escreverAviso('erro-pendentes', e.message);
    }
}

// ---------------------------------------------------------------------
// 6) Início: roda quando a página termina de carregar
// ---------------------------------------------------------------------
document.addEventListener('DOMContentLoaded', () => {
    el('data-hoje').textContent = formatarData(dataDaquiA(0));   // "Hoje: dd/mm/aaaa" no topo
    el('primeiro-vencimento').value = dataDaquiA(30);             // começa com hoje + 30 dias
    el('form-cobranca').addEventListener('submit', enviarCobranca);
    // O evento "input" de qualquer campo "sobe" até o form: um só ouvinte basta.
    el('form-cobranca').addEventListener('input', apagarErro);
    el('filtro-cliente').addEventListener('change', carregarPendentes);
    carregarClientes();
    carregarPendentes();
});
