package br.com.collectionline;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpHandler;

import java.io.IOException;
import java.io.InputStream;
import java.util.Map;

/**
 * Serve os três arquivos da tela. Só nomes conhecidos são aceitos:
 * qualquer outro caminho dá 404, o que impede pedir arquivos fora da pasta
 * (ataque de "path traversal", como /../app.properties).
 */
public class StaticFileHandler implements HttpHandler {

    /** caminho pedido -> {arquivo em resources/public, Content-Type} */
    private static final Map<String, String[]> ARQUIVOS = Map.of(
            "/", new String[]{"index.html", "text/html; charset=utf-8"},
            "/index.html", new String[]{"index.html", "text/html; charset=utf-8"},
            "/style.css", new String[]{"style.css", "text/css; charset=utf-8"},
            "/app.js", new String[]{"app.js", "text/javascript; charset=utf-8"});

    @Override
    public void handle(HttpExchange exchange) throws IOException {
        String caminho = exchange.getRequestURI().getPath();
        String[] arquivo = ARQUIVOS.get(caminho);

        if (arquivo == null) {
            JsonUtil.enviarErro(exchange, 404, "Recurso não encontrado: " + caminho);
            return;
        }
        if (!"GET".equals(exchange.getRequestMethod())) {
            exchange.getResponseHeaders().set("Allow", "GET"); // o 405 deve dizer qual método vale
            JsonUtil.enviarErro(exchange, 405, "Método não permitido.");
            return;
        }

        try (InputStream in = getClass().getResourceAsStream("/public/" + arquivo[0])) {
            if (in == null) {
                JsonUtil.enviarErro(exchange, 404, "Arquivo não encontrado: " + arquivo[0]);
                return;
            }
            JsonUtil.enviarBytes(exchange, 200, arquivo[1], in.readAllBytes());
        }
    }
}
