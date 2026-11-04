package br.com.collectionline;

import br.com.collectionline.dto.ClienteDTO;
import br.com.collectionline.dto.CobrancaCriadaResponse;
import br.com.collectionline.dto.ParcelaDTO;
import br.com.collectionline.dto.ParcelaPendenteDTO;

import java.math.BigDecimal;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;

/**
 * Todo o SQL da aplicação. Sempre PreparedStatement com "?": o valor vai
 * separado do comando, o que impede SQL injection.
 * A regra de negócio NÃO está aqui: ela fica na função do banco.
 */
public class CobrancaRepository {

    private final Database database;

    public CobrancaRepository(Database database) {
        this.database = database;
    }

    /** Lista clientes para o select da tela. */
    public List<ClienteDTO> listarClientes() throws SQLException {
        String sql = "SELECT cpf, nome FROM cliente ORDER BY nome";
        List<ClienteDTO> clientes = new ArrayList<>();
        try (Connection conn = database.abrirConexao();
             PreparedStatement ps = conn.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                clientes.add(new ClienteDTO(rs.getString("cpf"), rs.getString("nome")));
            }
        }
        return clientes;
    }

    /**
     * Chama a função do banco (que valida e calcula as parcelas) e depois
     * lê as parcelas criadas para devolver à tela.
     */
    public CobrancaCriadaResponse cadastrarCobranca(String cpf, BigDecimal valor, int qtdParcelas,
                                                    LocalDate primeiroVencimento) throws SQLException {
        String sqlFuncao = "SELECT cadastrar_cobranca_parcelada(?, ?, ?, ?)";
        String sqlParcelas = """
                SELECT numero_parcela, total_parcelas, valor, data_vencimento, status
                  FROM parcela
                 WHERE id_cobranca = ?
                 ORDER BY numero_parcela""";

        try (Connection conn = database.abrirConexao()) {
            // Cadastrar e ler as parcelas formam UMA transação: se a leitura
            // falhar, o cadastro também é desfeito, e a tela pode tentar de novo
            // sem criar uma cobrança duplicada.
            conn.setAutoCommit(false);
            try {
                int idCobranca;
                try (PreparedStatement ps = conn.prepareStatement(sqlFuncao)) {
                    ps.setString(1, cpf);
                    ps.setBigDecimal(2, valor);
                    ps.setInt(3, qtdParcelas);
                    ps.setObject(4, primeiroVencimento);
                    try (ResultSet rs = ps.executeQuery()) {
                        rs.next();
                        idCobranca = rs.getInt(1);
                    }
                }

                List<ParcelaDTO> parcelas = new ArrayList<>();
                try (PreparedStatement ps = conn.prepareStatement(sqlParcelas)) {
                    ps.setInt(1, idCobranca);
                    try (ResultSet rs = ps.executeQuery()) {
                        while (rs.next()) {
                            parcelas.add(new ParcelaDTO(
                                    rs.getInt("numero_parcela"),
                                    rs.getInt("total_parcelas"),
                                    rs.getBigDecimal("valor"),
                                    rs.getObject("data_vencimento", LocalDate.class),
                                    rs.getString("status")));
                        }
                    }
                }

                conn.commit();   // deu tudo certo: grava de vez
                return new CobrancaCriadaResponse(idCobranca, parcelas);
            } catch (SQLException | RuntimeException e) {
                conn.rollback(); // algo falhou: desfaz o que a função gravou
                throw e;
            }
        }
    }

    /** Lê a view de parcelas pendentes; cpf nulo significa "todos os clientes". */
    public List<ParcelaPendenteDTO> listarParcelasPendentes(String cpf) throws SQLException {
        // O mesmo CPF vai duas vezes: "(nulo OU igual)" faz o filtro ser opcional.
        // O ::char(11) é necessário porque o PostgreSQL não consegue deduzir
        // sozinho o tipo de um parâmetro que chega nulo.
        String sql = """
                SELECT cpf, nome, telefone, id_cobranca, parcela, valor, data_vencimento, dias_para_vencer
                  FROM vw_parcelas_pendentes
                 WHERE (?::char(11) IS NULL OR cpf = ?::char(11))
                 ORDER BY data_vencimento, cpf""";

        List<ParcelaPendenteDTO> lista = new ArrayList<>();
        try (Connection conn = database.abrirConexao();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setString(1, cpf);
            ps.setString(2, cpf);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    lista.add(new ParcelaPendenteDTO(
                            rs.getString("cpf"),
                            rs.getString("nome"),
                            rs.getString("telefone"),
                            rs.getInt("id_cobranca"),
                            rs.getString("parcela"),
                            rs.getBigDecimal("valor"),
                            rs.getObject("data_vencimento", LocalDate.class),
                            rs.getInt("dias_para_vencer")));
                }
            }
        }
        return lista;
    }
}
