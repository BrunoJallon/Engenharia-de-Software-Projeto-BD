package br.com.collectionline;

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

    private final CobrancaRepository repository;

    public CobrancaController(CobrancaRepository repository) {
        this.repository = repository;
    }

    @Override
    public void handle(HttpExchange exchange) throws IOException {
        String metodo = exchange.getRequestMethod();
        String caminho = exchange.getRequestURI().getPath();

        try {
            switch (caminho) {
                case "/api/clientes" -> {
                    if (!exigirMetodo(exchange, metodo, "GET")) return;
                    JsonUtil.enviarJson(exchange, 200, repository.listarClientes());
                }
                case "/api/cobrancas" -> {
                    if (!exigirMetodo(exchange, metodo, "POST")) return;
                    cadastrarCobranca(exchange);
                }
                case "/api/parcelas-pendentes" -> {
                    if (!exigirMetodo(exchange, metodo, "GET")) return;
                    listarPendentes(exchange);
                }
                default -> JsonUtil.enviarErro(exchange, 404, "Rota não encontrada: " + caminho);
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

    /** GET /api/parcelas-pendentes?cpf=... (filtro opcional) */
    private void listarPendentes(HttpExchange exchange) throws IOException, SQLException {
        String cpf = lerParametro(exchange.getRequestURI().getRawQuery(), "cpf");
        if (cpf != null && !CPF.matcher(cpf).matches()) {
            JsonUtil.enviarErro(exchange, 400, "O filtro cpf deve ter exatamente 11 dígitos.");
            return;
        }
        JsonUtil.enviarJson(exchange, 200, repository.listarParcelasPendentes(cpf));
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
