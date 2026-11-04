package br.com.collectionline;

import com.sun.net.httpserver.HttpServer;

import java.io.IOException;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.util.concurrent.Executors;

/**
 * Ponto de entrada: lê a configuração, sobe o servidor HTTP do próprio JDK
 * e registra as rotas.
 */
public class Main {

    public static void main(String[] args) throws IOException {
        Config config = Config.carregar();
        Database database = new Database(config);
        CobrancaRepository repository = new CobrancaRepository(database);

        // Só no endereço de loopback: o servidor não fica acessível pela rede.
        InetSocketAddress endereco = new InetSocketAddress(InetAddress.getLoopbackAddress(), config.serverPort());
        HttpServer server = HttpServer.create(endereco, 0);

        // Rotas: tudo que começa com /api/ vai para o controller; o resto é arquivo estático.
        server.createContext("/api/", new CobrancaController(repository));
        server.createContext("/", new StaticFileHandler());

        // Até 4 requisições atendidas ao mesmo tempo.
        server.setExecutor(Executors.newFixedThreadPool(4));
        server.start();

        System.out.println("Servidor em http://localhost:" + config.serverPort());
    }
}
