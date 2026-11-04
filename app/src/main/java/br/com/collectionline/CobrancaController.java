package br.com.collectionline;

import br.com.collectionline.dto.CobrancaDetalheDTO;
import br.com.collectionline.dto.EditarParcelaRequest;
import br.com.collectionline.dto.FiltroPendentes;
import br.com.collectionline.dto.NovaCobrancaRequest;
import com.google.gson.JsonParseException;
import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpHandler;
import org.postgresql.util.PSQLException;
import org.postgresql.util.ServerErrorMessage;

import java.io.IOException;
import java.io.InputStream;
import java.math.BigDecimal;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.sql.SQLException;
import java.time.LocalDate;
import java.time.format.DateTimeParseException;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Rotas /api/...: lê a requisição, confere só o FORMATO dos dados, chama o
 * repositório e devolve JSON. Regras de negócio ficam no banco.
 */
public class CobrancaController implements HttpHandler {

    /** Tamanho máximo do corpo da requisição: 10 KB sobram para um JSON pequeno. */
    private static final int TAMANHO_MAXIMO_CORPO = 10_000;

    // Formatos aceitos. É só FORMATO: valor mínimo, limites e datas
    // possíveis continuam sendo decididos pela função do banco.
    private static final Pattern CPF = Pattern.compile("\\d{11}");
    // aceita "100", "100.50" e também ".5" (o campo numérico do navegador pode mandar assim)
    private static final Pattern NUMERO_DECIMAL = Pattern.compile("-?(\\d+(\\.\\d+)?|\\.\\d+)");
    private static final Pattern NUMERO_INTEIRO = Pattern.compile("-?\\d{1,9}");
    private static final Pattern DATA_ISO = Pattern.compile("\\d{4}-\\d{2}-\\d{2}");

    // US02: rotas com id no caminho. \d{1,9} = só números (e cabem num int).
    private static final Pattern ROTA_COBRANCA = Pattern.compile("/api/cobrancas/(\\d{1,9})");
    private static final Pattern ROTA_PARCELA = Pattern.compile("/api/parcelas/(\\d{1,9})");
    private static final Pattern ROTA_PAGAMENTO = Pattern.compile("/api/parcelas/(\\d{1,9})/pagamento");

    /** US03: tamanho máximo do texto da busca. */
    private static final int TAMANHO_MAXIMO_BUSCA = 100;

    private final CobrancaRepository repository;

    public CobrancaController(CobrancaRepository repository) {
        this.repository = repository;
    }

    @Override
    public void handle(HttpExchange exchange) throws IOException {
        String metodo = exchange.getRequestMethod();
        String caminho = exchange.getRequestURI().getPath();

        try {
            Matcher m;
            if (caminho.equals("/api/clientes")) {
                if (!exigirMetodo(exchange, metodo, "GET")) return;
                JsonUtil.enviarJson(exchange, 200, repository.listarClientes());

            } else if (caminho.equals("/api/cobrancas")) {
                if (!exigirMetodo(exchange, metodo, "POST")) return;
                cadastrarCobranca(exchange);

            } else if (caminho.equals("/api/parcelas-pendentes")) {
                if (!exigirMetodo(exchange, metodo, "GET")) return;
                listarPendentes(exchange);

            } else if ((m = ROTA_COBRANCA.matcher(caminho)).matches()) {          // US02
                if (!exigirMetodo(exchange, metodo, "GET")) return;
                detalharCobranca(exchange, Integer.parseInt(m.group(1)));

            } else if ((m = ROTA_PARCELA.matcher(caminho)).matches()) {           // US02
                if (!exigirMetodo(exchange, metodo, "PUT")) return;
                editarParcela(exchange, Integer.parseInt(m.group(1)));

            } else if ((m = ROTA_PAGAMENTO.matcher(caminho)).matches()) {         // US02
                // POST cria o pagamento; DELETE remove (desfaz) o pagamento.
                int idParcela = Integer.parseInt(m.group(1));
                if (metodo.equals("POST")) {
                    JsonUtil.enviarJson(exchange, 200, repository.pagarParcela(idParcela));
                } else if (metodo.equals("DELETE")) {
                    JsonUtil.enviarJson(exchange, 200, repository.desfazerPagamento(idParcela));
                } else {
                    exigirMetodo(exchange, metodo, "POST, DELETE");
                }

            } else {
                JsonUtil.enviarErro(exchange, 404, "Rota não encontrada: " + caminho);
            }
        } catch (SQLException e) {
            traduzirErroDoBanco(exchange, e);
        } catch (RuntimeException e) {
            e.printStackTrace();
            JsonUtil.enviarErro(exchange, 500, "Erro interno no servidor");
        }
    }

    /** POST /api/cobrancas */
    private void cadastrarCobranca(HttpExchange exchange) throws IOException, SQLException {
        NovaCobrancaRequest req = lerCorpoJson(exchange, NovaCobrancaRequest.class);
        if (req == null) {
            return; // lerCorpoJson já respondeu com o erro
        }

        // --- Validação só de FORMATO (o resto é decidido pela função do banco) ---
        if (vazio(req.cpfCliente()) || vazio(req.valor()) || vazio(req.qtdParcelas())
                || vazio(req.primeiroVencimento())) {
            JsonUtil.enviarErro(exchange, 400,
                    "Campos obrigatórios: cpfCliente, valor, qtdParcelas e primeiroVencimento.");
            return;
        }

        String cpf = req.cpfCliente().trim();
        if (!CPF.matcher(cpf).matches()) {
            JsonUtil.enviarErro(exchange, 400, "O CPF deve ter exatamente 11 dígitos, sem pontos ou traço.");
            return;
        }

        BigDecimal valor = lerDecimal(req.valor());
        if (valor == null) {
            JsonUtil.enviarErro(exchange, 400, "Valor inválido: use números com ponto decimal, ex.: 100.00.");
            return;
        }

        Integer qtdParcelas = lerInteiro(req.qtdParcelas());
        if (qtdParcelas == null) {
            JsonUtil.enviarErro(exchange, 400, "A quantidade de parcelas deve ser um número inteiro.");
            return;
        }

        LocalDate primeiroVencimento = lerData(req.primeiroVencimento());
        if (primeiroVencimento == null) {
            JsonUtil.enviarErro(exchange, 400, "Data de vencimento inválida: use o formato aaaa-mm-dd.");
            return;
        }

        JsonUtil.enviarJson(exchange, 201,
                repository.cadastrarCobranca(cpf, valor, qtdParcelas, primeiroVencimento));
    }

    /**
     * GET /api/parcelas-pendentes — todos os filtros são opcionais:
     * cpf (US01), busca, situacao, de, ate, ordem e direcao (US03).
     */
    private void listarPendentes(HttpExchange exchange) throws IOException, SQLException {
        String query = exchange.getRequestURI().getRawQuery();

        String cpf = lerParametro(query, "cpf");
        if (cpf != null && !CPF.matcher(cpf).matches()) {
            JsonUtil.enviarErro(exchange, 400, "O filtro cpf deve ter exatamente 11 dígitos.");
            return;
        }

        String busca = lerParametro(query, "busca");
        if (busca != null && busca.length() > TAMANHO_MAXIMO_BUSCA) {
            JsonUtil.enviarErro(exchange, 400, "A busca pode ter no máximo " + TAMANHO_MAXIMO_BUSCA + " caracteres.");
            return;
        }

        // A situação é conferida pela função do banco (valor inválido -> 400).
        String situacao = lerParametro(query, "situacao");

        String textoDe = lerParametro(query, "de");
        String textoAte = lerParametro(query, "ate");
        LocalDate de = textoDe == null ? null : lerData(textoDe);
        LocalDate ate = textoAte == null ? null : lerData(textoAte);
        if ((textoDe != null && de == null) || (textoAte != null && ate == null)) {
            JsonUtil.enviarErro(exchange, 400, "Datas do período inválidas: use o formato aaaa-mm-dd.");
            return;
        }

        // Ordenação: só nomes da lista fechada (o ORDER BY não aceita "?").
        String ordem = lerParametro(query, "ordem");
        if (ordem != null && !CobrancaRepository.COLUNAS_ORDENAVEIS.containsKey(ordem)) {
            JsonUtil.enviarErro(exchange, 400,
                    "Ordem inválida: use vencimento, valor, cliente ou cobranca.");
            return;
        }
        String direcao = lerParametro(query, "direcao");
        if (direcao != null && !direcao.equals("asc") && !direcao.equals("desc")) {
            JsonUtil.enviarErro(exchange, 400, "Direção inválida: use asc ou desc.");
            return;
        }

        FiltroPendentes filtro = new FiltroPendentes(cpf, busca, situacao, de, ate, ordem, direcao);
        JsonUtil.enviarJson(exchange, 200, repository.listarParcelasPendentes(filtro));
    }

    /** US02 — GET /api/cobrancas/{id} */
    private void detalharCobranca(HttpExchange exchange, int idCobranca) throws IOException, SQLException {
        CobrancaDetalheDTO detalhe = repository.buscarCobranca(idCobranca);
        if (detalhe == null) {
            JsonUtil.enviarErro(exchange, 404, "Cobrança " + idCobranca + " não encontrada.");
            return;
        }
        JsonUtil.enviarJson(exchange, 200, detalhe);
    }

    /** US02 — PUT /api/parcelas/{id} com {valor, dataVencimento} */
    private void editarParcela(HttpExchange exchange, int idParcela) throws IOException, SQLException {
        EditarParcelaRequest req = lerCorpoJson(exchange, EditarParcelaRequest.class);
        if (req == null) {
            return; // lerCorpoJson já respondeu com o erro
        }
        if (vazio(req.valor()) || vazio(req.dataVencimento())) {
            JsonUtil.enviarErro(exchange, 400, "Campos obrigatórios: valor e dataVencimento.");
            return;
        }
        BigDecimal valor = lerDecimal(req.valor());
        if (valor == null) {
            JsonUtil.enviarErro(exchange, 400, "Valor inválido: use números com ponto decimal, ex.: 100.00.");
            return;
        }
        LocalDate dataVencimento = lerData(req.dataVencimento());
        if (dataVencimento == null) {
            JsonUtil.enviarErro(exchange, 400, "Data de vencimento inválida: use o formato aaaa-mm-dd.");
            return;
        }
        JsonUtil.enviarJson(exchange, 200, repository.editarParcela(idParcela, valor, dataVencimento));
    }

    // ---------------------------------------------------------------------
    // Leitura da requisição
    // ---------------------------------------------------------------------

    /**
     * Lê o corpo JSON da requisição e converte para o tipo pedido.
     * Se algo estiver errado, já responde com o erro e devolve null.
     */
    private <T> T lerCorpoJson(HttpExchange exchange, Class<T> tipo) throws IOException {
        // Só aceitamos JSON. Isso também protege contra outra página aberta no
        // navegador tentar criar cobranças aqui: para mandar JSON a outro site,
        // o navegador pede permissão antes (CORS), e este servidor não dá.
        String contentType = exchange.getRequestHeaders().getFirst("Content-Type");
        if (contentType == null || !contentType.toLowerCase().startsWith("application/json")) {
            JsonUtil.enviarErro(exchange, 415,
                    "Envie o corpo em JSON, com o cabeçalho Content-Type: application/json.");
            return null;
        }

        // Lê no máximo 10 KB (+1 byte, para saber se passou do limite).
        byte[] bytes;
        try (InputStream in = exchange.getRequestBody()) {
            bytes = in.readNBytes(TAMANHO_MAXIMO_CORPO + 1);
        }
        if (bytes.length > TAMANHO_MAXIMO_CORPO) {
            JsonUtil.enviarErro(exchange, 413, "O corpo da requisição é grande demais.");
            return null;
        }

        T objeto;
        try {
            objeto = JsonUtil.GSON.fromJson(new String(bytes, StandardCharsets.UTF_8), tipo);
        } catch (JsonParseException e) {
            JsonUtil.enviarErro(exchange, 400, "O corpo da requisição não é um JSON válido.");
            return null;
        }
        if (objeto == null) {
            JsonUtil.enviarErro(exchange, 400, "O corpo da requisição está vazio.");
        }
        return objeto;
    }

    /** "100.00" -> BigDecimal exato; formato inválido -> null. Nunca passa por double. */
    private static BigDecimal lerDecimal(String texto) {
        String t = texto.trim();
        return NUMERO_DECIMAL.matcher(t).matches() ? new BigDecimal(t) : null;
    }

    /** "3" -> 3; formato inválido -> null. */
    private static Integer lerInteiro(String texto) {
        String t = texto.trim();
        return NUMERO_INTEIRO.matcher(t).matches() ? Integer.valueOf(t) : null;
    }

    /** "2027-01-31" -> LocalDate; formato ou data impossível (ex.: 2027-02-30) -> null. */
    private static LocalDate lerData(String texto) {
        String t = texto.trim();
        if (!DATA_ISO.matcher(t).matches()) {
            return null; // barra também anos com mais de 4 dígitos, como +999999999-12-31
        }
        try {
            return LocalDate.parse(t);
        } catch (DateTimeParseException e) {
            return null;
        }
    }

    // ---------------------------------------------------------------------
    // Respostas de erro
    // ---------------------------------------------------------------------

    /**
     * Converte o erro do banco em status HTTP usando o SQLState
     * (o código de 5 caracteres que todo erro do PostgreSQL tem).
     */
    private void traduzirErroDoBanco(HttpExchange exchange, SQLException e) throws IOException {
        String sqlState = e.getSQLState() == null ? "" : e.getSQLState();
        int status;
        if (sqlState.equals("22023")) {          // invalid_parameter_value
            status = 400;
        } else if (sqlState.equals("P0002")) {   // no_data_found
            status = 404;
        } else if (sqlState.startsWith("23")) {  // classe 23: violação de restrição
            status = 409;
        } else if (sqlState.equals("55000")) {   // US02: parcela no estado errado (já paga / não paga)
            status = 409;
        } else {
            e.printStackTrace();                 // detalhe técnico só no console
            JsonUtil.enviarErro(exchange, 500, "Erro interno no servidor");
            return;
        }
        JsonUtil.enviarErro(exchange, status, mensagemDoBanco(e));
    }

    /** Mensagem do banco sem o prefixo "ERROR:" / "ERRO:". */
    private String mensagemDoBanco(SQLException e) {
        if (e instanceof PSQLException psql) {
            ServerErrorMessage msg = psql.getServerErrorMessage();
            if (msg != null && msg.getMessage() != null) {
                return msg.getMessage();
            }
        }
        return e.getMessage();
    }

    /** Responde 405 e devolve false se o método HTTP não for o esperado. */
    private boolean exigirMetodo(HttpExchange exchange, String metodo, String esperado) throws IOException {
        if (!esperado.equals(metodo)) {
            exchange.getResponseHeaders().set("Allow", esperado);
            JsonUtil.enviarErro(exchange, 405, "Método " + metodo + " não permitido nesta rota (use " + esperado + ").");
            return false;
        }
        return true;
    }

    private static boolean vazio(String s) {
        return s == null || s.isBlank();
    }

    /** Lê um parâmetro da query string (ex.: cpf em ?cpf=111). Vazio conta como ausente. */
    private static String lerParametro(String query, String nome) {
        if (query == null) return null;
        for (String par : query.split("&")) {
            int igual = par.indexOf('=');
            String chave = igual >= 0 ? par.substring(0, igual) : par;
            if (URLDecoder.decode(chave, StandardCharsets.UTF_8).equals(nome)) {
                String valor = igual >= 0 ? URLDecoder.decode(par.substring(igual + 1), StandardCharsets.UTF_8) : "";
                return valor.isBlank() ? null : valor.trim();
            }
        }
        return null;
    }
}
