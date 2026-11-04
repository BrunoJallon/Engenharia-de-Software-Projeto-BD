package br.com.collectionline;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;

/**
 * Abre conexões com o PostgreSQL. Uma conexão por requisição, sem pool:
 * simples de entender e suficiente para uma demonstração.
 * Quem chama deve fechar a conexão com try-with-resources.
 */
public class Database {

    private final Config config;

    public Database(Config config) {
        this.config = config;
        try {
            // Registra o driver do PostgreSQL de forma explícita. Normalmente o
            // Java encontra o driver sozinho, mas o "mvn exec:java" roda o programa
            // num carregador de classes separado, e sem esta linha o DriverManager
            // responde "No suitable driver found".
            Class.forName("org.postgresql.Driver");
        } catch (ClassNotFoundException e) {
            throw new IllegalStateException("Driver do PostgreSQL não encontrado. Rode pelo Maven: mvn -q compile exec:java", e);
        }
    }

    public Connection abrirConexao() throws SQLException {
        return DriverManager.getConnection(config.dbUrl(), config.dbUser(), config.dbPassword());
    }
}
