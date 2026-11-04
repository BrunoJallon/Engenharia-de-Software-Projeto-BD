// =====================================================================
// CollectionLine — lógica da tela
// US01: cadastrar cobrança parcelada · US02: editar e pagar parcelas
// (painel de detalhe) · US03: pesquisar parcelas pendentes (filtros e ordem)
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

// ---------------------------------------------------------------------
// 6) Lista de pendentes: filtros (US03), ordenação e tabela
// ---------------------------------------------------------------------

// Ids dos campos de filtro (usados para montar a URL e para "Limpar filtros").
const CAMPOS_FILTRO = ['filtro-busca', 'filtro-cliente', 'filtro-situacao', 'filtro-de', 'filtro-ate'];

// Ordenação atual da tabela (padrão da API: vencimento crescente).
let ordemAtual = 'vencimento';
let direcaoAtual = 'asc';

// Guarda o "relógio" da busca enquanto a pessoa digita (ver agendarBusca).
let temporizadorBusca = null;

// Número da consulta de pendentes mais recente.
// Por quê: se o operador muda um filtro rápido (por exemplo, com as setas do
// teclado ou digitando na busca), duas consultas ficam em andamento ao mesmo
// tempo, e a resposta da consulta ANTIGA pode chegar DEPOIS da nova, mostrando
// a lista errada. Cada consulta guarda o seu número; só a mais recente pode
// mexer na tela. Vale para TODOS os filtros, porque todos passam por aqui.
let ultimaConsulta = 0;

/**
 * Monta a URL da consulta com os filtros preenchidos. URLSearchParams junta
 * os pares nome=valor e já codifica acentos, espaços e pontos do CPF.
 */
function montarUrlPendentes() {
    const parametros = new URLSearchParams();
    const busca = el('filtro-busca').value.trim();
    if (busca !== '') parametros.set('busca', busca);
    if (el('filtro-cliente').value !== '') parametros.set('cpf', el('filtro-cliente').value);
    if (el('filtro-situacao').value !== '') parametros.set('situacao', el('filtro-situacao').value);
    if (el('filtro-de').value !== '') parametros.set('de', el('filtro-de').value);
    if (el('filtro-ate').value !== '') parametros.set('ate', el('filtro-ate').value);
    parametros.set('ordem', ordemAtual);
    parametros.set('direcao', direcaoAtual);
    return `/api/parcelas-pendentes?${parametros}`;
}

/** true se algum filtro estiver preenchido (muda o texto do estado vazio). */
function haFiltrosAtivos() {
    return CAMPOS_FILTRO.some((id) => el(id).value.trim() !== '');
}

/** Textos do estado vazio: com filtros, a mensagem é outra. */
function atualizarTextoVazio() {
    if (haFiltrosAtivos()) {
        el('vazio-titulo').textContent = 'Nenhuma parcela encontrada com esses filtros.';
        el('vazio-texto').textContent = 'Mude os filtros ou clique em "Limpar filtros".';
    } else {
        el('vazio-titulo').textContent = 'Nenhuma parcela pendente.';
        el('vazio-texto').textContent = 'Cadastre uma cobrança para ver as parcelas aqui.';
    }
}

/**
 * Célula "Cobrança": um <button> de verdade (funciona com Tab e Enter) que
 * abre o detalhe. O aria-label repete o "nº X" visível com mais contexto.
 */
function criarCelulaCobranca(idCobranca) {
    const botao = document.createElement('button');
    botao.type = 'button';
    botao.className = 'botao-link';
    botao.textContent = `nº ${idCobranca}`;
    botao.dataset.cobranca = idCobranca;   // vira o atributo data-cobranca="X"
    botao.setAttribute('aria-label', `Abrir detalhe da cobrança nº ${idCobranca}`);
    botao.addEventListener('click', () => abrirDetalhe(idCobranca));
    const td = document.createElement('td');
    td.append(botao);
    return td;
}

/** Monta uma linha da tabela de pendentes. */
function criarLinhaPendente(p) {
    const linha = document.createElement('tr');
    linha.append(
        criarCelula(p.nome, 'coluna-cliente'),
        criarCelulaCobranca(p.idCobranca),
        criarCelula(p.parcela),
        criarCelula(formatarMoeda(p.valor), 'numero'),
        criarCelula(formatarData(p.dataVencimento)),
        criarCelulaSituacao(p.diasParaVencer),
    );
    return linha;
}

/** Lê as parcelas pendentes com os filtros e a ordem atuais e monta a tabela. */
async function carregarPendentes() {
    const estaConsulta = ++ultimaConsulta;   // soma 1 e guarda: esta é a consulta nº 1, 2, 3...
    escreverAviso('erro-pendentes', '');

    try {
        const parcelas = await chamarApi(montarUrlPendentes());
        if (estaConsulta !== ultimaConsulta) return;   // já existe consulta mais nova: ignora esta resposta
        const corpo = el('corpo-pendentes');
        corpo.replaceChildren();   // apaga as linhas antigas
        for (const p of parcelas) {
            corpo.append(criarLinhaPendente(p));
        }
        el('contador-pendentes').textContent = parcelas.length;   // só conta as linhas
        atualizarTextoVazio();
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

/**
 * Enquanto a pessoa digita na busca, espera 300 ms sem novas teclas antes de
 * consultar (assim não vai uma consulta por letra). Cada tecla "zera o relógio".
 */
function agendarBusca() {
    clearTimeout(temporizadorBusca);
    temporizadorBusca = setTimeout(carregarPendentes, 300);
}

/** Enter na busca: consulta na hora, sem esperar o relógio. */
function buscarAoApertarEnter(evento) {
    if (evento.key === 'Enter') {
        evento.preventDefault();
        clearTimeout(temporizadorBusca);
        carregarPendentes();
    }
}

/** Botão "Limpar filtros": esvazia todos os filtros (a ordenação fica). */
function limparFiltros() {
    for (const id of CAMPOS_FILTRO) {
        el(id).value = '';
    }
    clearTimeout(temporizadorBusca);
    carregarPendentes();
}

/**
 * Clique no título de uma coluna: se já é a coluna ordenada, inverte a
 * direção; se é outra coluna, passa a ordenar por ela, do menor para o maior.
 */
function ordenarPor(ordem) {
    if (ordem === ordemAtual) {
        direcaoAtual = direcaoAtual === 'asc' ? 'desc' : 'asc';
    } else {
        ordemAtual = ordem;
        direcaoAtual = 'asc';
    }
    atualizarIndicadoresOrdem();
    carregarPendentes();
}

/**
 * Mostra qual coluna está ordenada: aria-sort no <th> (o leitor de tela
 * anuncia "crescente"/"decrescente") e a seta ▲/▼ visível.
 */
function atualizarIndicadoresOrdem() {
    for (const botao of document.querySelectorAll('.botao-ordenar')) {
        const th = botao.parentElement;              // o botão fica direto dentro do <th>
        const seta = botao.querySelector('.seta');
        if (botao.dataset.ordem === ordemAtual) {
            th.setAttribute('aria-sort', direcaoAtual === 'asc' ? 'ascending' : 'descending');
            seta.textContent = direcaoAtual === 'asc' ? '▲' : '▼';
        } else {
            th.removeAttribute('aria-sort');
            seta.textContent = '';
        }
    }
}

// ---------------------------------------------------------------------
// 7) Detalhe da cobrança (US02): ver, editar, pagar e desfazer pagamento
// ---------------------------------------------------------------------

// Cobrança aberta no painel e parcela que está sendo editada (ou null).
let cobrancaAberta = null;
let parcelaEmEdicao = null;

/** Apaga as duas mensagens do painel. */
function limparAvisosDetalhe() {
    escreverAviso('mensagem-detalhe', '');
    escreverAviso('erro-detalhe', '');
}

/** Etiqueta "Pendente" (neutra) ou "Paga" (verde). */
function criarEtiquetaStatus(status) {
    const etiqueta = document.createElement('span');
    etiqueta.className = status === 'paga' ? 'etiqueta etiqueta-paga' : 'etiqueta etiqueta-pendente';
    etiqueta.textContent = formatarStatus(status);
    return etiqueta;
}

/**
 * Cria um botão de ação de uma parcela. A classe "acao" permite desabilitar
 * todos de uma vez enquanto uma ação roda (travarPainel). O aria-label diz
 * de qual parcela é o botão (na tabela há vários "Editar" iguais).
 */
function criarBotaoAcao(texto, rotuloParcela, aoClicar) {
    const botao = document.createElement('button');
    botao.type = 'button';
    botao.className = 'botao-secundario botao-pequeno acao';
    botao.textContent = texto;
    botao.setAttribute('aria-label', `${texto} — parcela ${rotuloParcela}`);
    botao.addEventListener('click', () => aoClicar(botao));
    return botao;
}

/** Linha da tabela do painel, com os botões que valem para aquela parcela. */
function criarLinhaDetalhe(p) {
    const rotulo = `${p.numeroParcela}/${p.totalParcelas}`;
    const tdStatus = document.createElement('td');
    tdStatus.append(criarEtiquetaStatus(p.status));

    const caixaAcoes = document.createElement('div');
    caixaAcoes.className = 'acoes-parcela';
    if (p.status === 'paga') {
        // Parcela paga fica travada: só dá para desfazer o pagamento.
        caixaAcoes.append(criarBotaoAcao('Desfazer pagamento', rotulo, (b) => desfazerPagamento(p, rotulo, b)));
    } else {
        caixaAcoes.append(
            criarBotaoAcao('Editar', rotulo, () => abrirEdicao(p, rotulo)),
            criarBotaoAcao('Marcar como paga', rotulo, (b) => pagarParcela(p, rotulo, b)),
        );
    }
    const tdAcoes = document.createElement('td');
    tdAcoes.append(caixaAcoes);

    const linha = document.createElement('tr');
    linha.append(
        criarCelula(rotulo),
        criarCelula(formatarMoeda(p.valor), 'numero'),
        criarCelula(formatarData(p.dataVencimento)),
        tdStatus,
        tdAcoes,
    );
    return linha;
}

/** Preenche o painel com o detalhe que a API devolveu. */
function mostrarDetalhe(d) {
    el('titulo-detalhe').textContent = `Cobrança nº ${d.idCobranca}`;
    el('detalhe-cliente').textContent = `${d.nomeCliente} — ${formatarCpf(d.cpfCliente)}`;
    el('detalhe-emissao').textContent = formatarData(d.dataEmissao);
    el('detalhe-vencimento').textContent = formatarData(d.dataVencimento);
    el('detalhe-valor').textContent = formatarMoeda(d.valor);   // total calculado pelo banco
    el('detalhe-status').replaceChildren(criarEtiquetaStatus(d.statusPagamento));
    const corpo = el('corpo-detalhe');
    corpo.replaceChildren();
    for (const p of d.parcelas) {
        corpo.append(criarLinhaDetalhe(p));
    }
}

/** Busca o detalhe de uma cobrança e abre o painel. */
async function abrirDetalhe(idCobranca) {
    try {
        const detalhe = await chamarApi(`/api/cobrancas/${encodeURIComponent(idCobranca)}`);
        cobrancaAberta = idCobranca;
        fecharEdicao();
        limparAvisosDetalhe();
        mostrarDetalhe(detalhe);
        el('dialogo-cobranca').showModal();   // modal: foco preso e Esc fecha
    } catch (e) {
        escreverAviso('erro-pendentes', e.message);
    }
}

/**
 * Fecha o painel (botão Fechar ou tecla Esc) e devolve o foco ao botão
 * "nº X" da cobrança. A lista pode ter sido recarregada (botão novo), por
 * isso procuramos o botão pelo data-cobranca. Se a cobrança saiu da lista
 * (todas as parcelas pagas), o foco vai para a busca.
 * Fechamos sempre por esta função para não depender do evento "close"
 * (num dos navegadores testados ele não disparou).
 */
function fecharDetalhe() {
    el('dialogo-cobranca').close();
    fecharEdicao();
    limparAvisosDetalhe();
    const botao = document.querySelector(`#corpo-pendentes [data-cobranca="${cobrancaAberta}"]`);
    (botao || el('filtro-busca')).focus();
}

/** Tecla Esc: o navegador avisa com o evento "cancel"; fechamos do nosso jeito. */
function aoApertarEsc(evento) {
    evento.preventDefault();   // não deixa o navegador fechar sozinho...
    fecharDetalhe();           // ...fechamos aqui, devolvendo o foco
}

/** Desabilita (ou reabilita) os botões de ação do painel: evita clique duplo. */
function travarPainel(travar) {
    for (const botao of el('dialogo-cobranca').querySelectorAll('.acao')) {
        botao.disabled = travar;
    }
}

/**
 * Roda uma ação da parcela na API (pagar, desfazer ou salvar edição).
 * Sucesso: mostra o detalhe devolvido, a mensagem verde e recarrega a lista.
 * Erro: mostra a mensagem do banco e NÃO mexe no que foi digitado.
 */
async function executarAcao(botao, textoSucesso, url, opcoes) {
    limparAvisosDetalhe();
    travarPainel(true);
    let deuCerto = false;
    try {
        const detalhe = await chamarApi(url, opcoes);
        mostrarDetalhe(detalhe);   // a tabela é refeita com o que o banco gravou
        fecharEdicao();
        escreverAviso('mensagem-detalhe', textoSucesso);
        deuCerto = true;
        carregarPendentes();
    } catch (e) {
        escreverAviso('erro-detalhe', e.message);
    } finally {
        travarPainel(false);
        // O botão clicado pode ter sumido (a tabela foi refeita): no sucesso o
        // foco vai para o título do painel; no erro, volta para o botão.
        if (deuCerto) {
            el('titulo-detalhe').focus();
        } else {
            botao.focus();
        }
    }
}

/** "Marcar como paga". */
function pagarParcela(p, rotulo, botao) {
    executarAcao(botao, `Parcela ${rotulo} marcada como paga.`,
        `/api/parcelas/${p.idParcela}/pagamento`, { method: 'POST' });
}

/** "Desfazer pagamento" (só aparece nas parcelas pagas). */
function desfazerPagamento(p, rotulo, botao) {
    executarAcao(botao, `Pagamento da parcela ${rotulo} desfeito.`,
        `/api/parcelas/${p.idParcela}/pagamento`, { method: 'DELETE' });
}

/** "Editar": mostra o formulário pequeno já preenchido com os dados atuais. */
function abrirEdicao(p, rotulo) {
    parcelaEmEdicao = { idParcela: p.idParcela, rotulo };
    limparAvisosDetalhe();
    el('legenda-edicao').textContent = `Editar parcela ${rotulo}`;
    el('edicao-valor').value = String(p.valor);         // só copia o texto do valor
    el('edicao-vencimento').value = p.dataVencimento;   // o input date já usa aaaa-mm-dd
    el('form-edicao').hidden = false;
    el('edicao-valor').focus();
}

/** Esconde o formulário de edição. */
function fecharEdicao() {
    el('form-edicao').hidden = true;
    parcelaEmEdicao = null;
}

/** "Cancelar": fecha a edição sem salvar. */
function cancelarEdicao() {
    fecharEdicao();
    el('titulo-detalhe').focus();
}

/** "Salvar": envia PUT /api/parcelas/{id} com valor (como TEXTO) e vencimento. */
function salvarEdicao(evento) {
    evento.preventDefault();   // impede o envio "nativo" do formulário
    const { idParcela, rotulo } = parcelaEmEdicao;
    executarAcao(el('botao-salvar-edicao'), `Parcela ${rotulo} atualizada.`, `/api/parcelas/${idParcela}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            valor: el('edicao-valor').value,                 // TEXTO, como no cadastro
            dataVencimento: el('edicao-vencimento').value,
        }),
    });
}

// ---------------------------------------------------------------------
// 8) Início: roda quando a página termina de carregar
// ---------------------------------------------------------------------
document.addEventListener('DOMContentLoaded', () => {
    el('data-hoje').textContent = formatarData(dataDaquiA(0));   // "Hoje: dd/mm/aaaa" no topo
    el('primeiro-vencimento').value = dataDaquiA(30);             // começa com hoje + 30 dias

    // US01: cadastro
    el('form-cobranca').addEventListener('submit', enviarCobranca);
    // O evento "input" de qualquer campo "sobe" até o form: um só ouvinte basta.
    el('form-cobranca').addEventListener('input', apagarErro);

    // US03: filtros e ordenação
    el('filtro-busca').addEventListener('input', agendarBusca);
    el('filtro-busca').addEventListener('keydown', buscarAoApertarEnter);
    for (const id of ['filtro-cliente', 'filtro-situacao', 'filtro-de', 'filtro-ate']) {
        el(id).addEventListener('change', carregarPendentes);
    }
    el('botao-limpar-filtros').addEventListener('click', limparFiltros);
    for (const botao of document.querySelectorAll('.botao-ordenar')) {
        botao.addEventListener('click', () => ordenarPor(botao.dataset.ordem));
    }

    // US02: painel de detalhe
    el('botao-fechar-detalhe').addEventListener('click', fecharDetalhe);
    el('dialogo-cobranca').addEventListener('cancel', aoApertarEsc);
    el('form-edicao').addEventListener('submit', salvarEdicao);
    el('form-edicao').addEventListener('input', () => escreverAviso('erro-detalhe', ''));
    el('botao-cancelar-edicao').addEventListener('click', cancelarEdicao);

    atualizarIndicadoresOrdem();
    carregarClientes();
    carregarPendentes();
});
