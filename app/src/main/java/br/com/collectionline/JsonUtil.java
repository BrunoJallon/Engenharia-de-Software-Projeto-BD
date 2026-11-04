package br.com.collectionline;

import br.com.collectionline.dto.ErroResponse;
import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.Strictness;
import com.google.gson.TypeAdapter;
import com.google.gson.stream.JsonReader;
import com.google.gson.stream.JsonToken;
import com.google.gson.stream.JsonWriter;
import com.sun.net.httpserver.HttpExchange;

import java.io.IOException;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.time.LocalDate;

/**
 * Tudo que envolve JSON e o envio de respostas HTTP.
 */
public final class JsonUtil {

    /**
     * Instância única do Gson, compartilhada por toda a aplicação.
     * STRICT: só aceita JSON de verdade (nada de nomes sem aspas ou comentários).
     */
    public static final Gson GSON = new GsonBuilder()
            .registerTypeAdapter(LocalDate.class, new LocalDateAdapter())
            .setStrictness(Strictness.STRICT)
            .create();

    private JsonUtil() {
        // classe utilitária: não deve ser instanciada
    }

    /** Converte o objeto em JSON e envia com o status informado. */
    public static void enviarJson(HttpExchange exchange, int status, Object corpo) throws IOException {
        byte[] bytes = GSON.toJson(corpo).getBytes(StandardCharsets.UTF_8);
        enviarBytes(exchange, status, "application/json; charset=utf-8", bytes);
    }

    /** Atalho para a resposta de erro padrão {"erro": "..."}. */
    public static void enviarErro(HttpExchange exchange, int status, String mensagem) throws IOException {
        enviarJson(exchange, status, new ErroResponse(mensagem));
    }

    /**
     * Envia bytes já prontos. O tamanho informado é o do array de bytes em
     * UTF-8, não o String.length(): "ç" e "ã" ocupam 2 bytes cada, e um
     * tamanho errado faria a resposta chegar cortada.
     * Também imprime a linha de log da requisição.
     */
    public static void enviarBytes(HttpExchange exchange, int status, String contentType, byte[] bytes)
            throws IOException {
        // Log: método, caminho e status. Só o caminho (getPath), sem a query
        // string, que pode ter dados pessoais como o CPF.
        System.out.println(exchange.getRequestMethod() + " " + exchange.getRequestURI().getPath() + " -> " + status);

        exchange.getResponseHeaders().set("Content-Type", contentType);
        exchange.sendResponseHeaders(status, bytes.length);
        try (OutputStream out = exchange.getResponseBody()) {
            out.write(bytes);
        }
    }

    /**
     * Gson não sabe converter LocalDate sozinho: usamos o texto ISO aaaa-mm-dd.
     * Nas respostas, o write() é usado em toda data. O read() hoje não é usado:
     * as datas das requisições chegam como texto nos DTOs e são convertidas no
     * controller, que assim consegue responder 400 com uma mensagem clara.
     */
    private static final class LocalDateAdapter extends TypeAdapter<LocalDate> {
        @Override
        public void write(JsonWriter out, LocalDate data) throws IOException {
            if (data == null) {
                out.nullValue();
            } else {
                out.value(data.toString());
            }
        }

        @Override
        public LocalDate read(JsonReader in) throws IOException {
            if (in.peek() == JsonToken.NULL) {
                in.nextNull();
                return null;
            }
            return LocalDate.parse(in.nextString());
        }
    }
}
