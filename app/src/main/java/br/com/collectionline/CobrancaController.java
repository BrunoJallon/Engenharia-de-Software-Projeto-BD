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

/**
 * Rotas /api/...: lê a requisição, confere só o FORMATO dos dados, chama o
 * repositório e devolve JSON. Regras de negócio ficam no banco.
 */
public class CobrancaController implements HttpHandler {

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
        NovaCobrancaRequest req;
        try (InputStream in = exchange.getRequestBody()) {
            String corpo = new String(in.readAllBytes(), StandardCharsets.UTF_8);
            req = JsonUtil.GSON.fromJson(corpo, NovaCobrancaRequest.class);
        } catch (JsonParseException e) {
            JsonUtil.enviarErro(exchange, 400, "O corpo da requisição não é um JSON válido.");
            return;
        }
        if (req == null) {
            JsonUtil.enviarErro(exchange, 400, "O corpo da requisição está vazio.");
            return;
        }

        // --- Validação só de FORMATO (o resto é decidido pela função do banco) ---
        if (vazio(req.cpfCliente()) || vazio(req.valor()) || vazio(req.qtdParcelas())
                || vazio(req.primeiroVencimento())) {
            JsonUtil.enviarErro(exchange, 400,
                    "Campos obrigatórios: cpfCliente, valor, qtdParcelas e primeiroVencimento.");
            return;
        }

        String cpf = req.cpfCliente().trim();
        if (!cpf.matches("\\d{11}")) {
            JsonUtil.enviarErro(exchange, 400, "O CPF deve ter exatamente 11 dígitos, sem pontos ou traço.");
            return;
        }

        BigDecimal valor;
        try {
            // BigDecimal guarda o valor decimal exato; double erraria centavos.
            valor = new BigDecimal(req.valor().trim());
        } catch (NumberFormatException e) {
            JsonUtil.enviarErro(exchange, 400, "Valor inválido: use números com ponto decimal, ex.: 100.00.");
            return;
        }

        int qtdParcelas;
        try {
            qtdParcelas = Integer.parseInt(req.qtdParcelas().trim());
        } catch (NumberFormatException e) {
            JsonUtil.enviarErro(exchange, 400, "A quantidade de parcelas deve ser um número inteiro.");
            return;
        }

        LocalDate primeiroVencimento;
        try {
            primeiroVencimento = LocalDate.parse(req.primeiroVencimento().trim());
        } catch (DateTimeParseException e) {
            JsonUtil.enviarErro(exchange, 400, "Data de vencimento inválida: use o formato aaaa-mm-dd.");
            return;
        }

        JsonUtil.enviarJson(exchange, 201,
                repository.cadastrarCobranca(cpf, valor, qtdParcelas, primeiroVencimento));
    }

    /** GET /api/parcelas-pendentes?cpf=... (filtro opcional) */
    private void listarPendentes(HttpExchange exchange) throws IOException, SQLException {
        String cpf = lerParametro(exchange.getRequestURI().getRawQuery(), "cpf");
        if (cpf != null && !cpf.matches("\\d{11}")) {
            JsonUtil.enviarErro(exchange, 400, "O filtro cpf deve ter exatamente 11 dígitos.");
            return;
        }
        JsonUtil.enviarJson(exchange, 200, repository.listarParcelasPendentes(cpf));
    }

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
