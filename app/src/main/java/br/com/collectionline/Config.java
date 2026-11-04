package br.com.collectionline;

import java.io.IOException;
import java.io.Reader;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Properties;

/**
 * Configuração lida do arquivo app.properties da pasta app/.
 * A senha do banco fica só nesse arquivo, que não vai para o git.
 */
public record Config(String dbUrl, String dbUser, String dbPassword, int serverPort) {

    private static final Path ARQUIVO = Path.of("app.properties");

    public static Config carregar() {
        if (!Files.exists(ARQUIVO)) {
            System.err.println("Arquivo app.properties não encontrado em " + ARQUIVO.toAbsolutePath() + ".");
            System.err.println("Copie app.properties.example para app.properties e preencha a senha do banco.");
            System.exit(1);
        }

        Properties props = new Properties();
        try (Reader reader = Files.newBufferedReader(ARQUIVO, StandardCharsets.UTF_8)) {
            props.load(reader);
        } catch (IOException e) {
            System.err.println("Não foi possível ler o app.properties: " + e.getMessage());
            System.exit(1);
        }

        String porta = props.getProperty("server.port", "8080").trim();
        try {
            return new Config(
                    props.getProperty("db.url", "jdbc:postgresql://localhost:5432/collectionline_xp").trim(),
                    props.getProperty("db.user", "postgres").trim(),
                    props.getProperty("db.password", ""),
                    Integer.parseInt(porta));
        } catch (NumberFormatException e) {
            System.err.println("server.port inválido no app.properties: " + porta);
            System.exit(1);
            return null; // nunca chega aqui
        }
    }
}
