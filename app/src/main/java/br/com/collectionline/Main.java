package br.com.collectionline;

import com.sun.net.httpserver.HttpServer;

import java.io.IOException;
import java.net.BindException;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.sql.Connection;
import java.sql.SQLException;
import java.util.concurrent.Executors;

/**
 * Ponto de entrada: lê a configuração, sobe o servidor HTTP do próprio JDK
 * e registra as rotas.
 */
public class Main {

    public static void main(String[] args) throws IOException {
        Config config = Config.carregar();
        Database database = new Database(config);

        // Confere logo na partida se o banco responde: um aviso claro aqui é
        // melhor do que "Erro interno no servidor" na primeira tela.
        try (Connection conn = database.abrirConexao()) {
            System.out.println("Banco conectado: " + conn.getMetaData().getDatabaseProductName()
                    + " " + conn.getMetaData().getDatabaseProductVersion());
        } catch (SQLException e) {
            System.err.println("Não foi possível conectar ao banco: " + e.getMessage());
            System.err.println("Confira db.url, db.user e db.password no app.properties e se o PostgreSQL está rodando.");
            System.exit(1);
        }

        CobrancaRepository repository = new CobrancaRepository(database);

        // Só no endereço de loopback: o servidor não fica acessível pela rede.
        InetSocketAddress endereco = new InetSocketAddress(InetAddress.getLoopbackAddress(), config.serverPort());
        HttpServer server;
        try {
            server = HttpServer.create(endereco, 0);
        } catch (BindException e) {
            System.err.println("A porta " + config.serverPort() + " já está em uso (o servidor já está aberto em outro terminal?).");
            System.err.println("Feche o outro servidor ou mude server.port no app.properties.");
            System.exit(1);
            return; // nunca chega aqui
        }

        // Rotas: tudo que começa com /api/ vai para o controller; o resto é arquivo estático.
        server.createContext("/api/", new CobrancaController(repository));
        server.createContext("/", new StaticFileHandler());

        // Até 4 requisições atendidas ao mesmo tempo.
        server.setExecutor(Executors.newFixedThreadPool(4));
        server.start();

        System.out.println("Servidor em http://localhost:" + config.serverPort());
    }
}
