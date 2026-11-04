package br.com.collectionline;

import br.com.collectionline.dto.ClienteDTO;
import br.com.collectionline.dto.CobrancaCriadaResponse;
import br.com.collectionline.dto.CobrancaDetalheDTO;
import br.com.collectionline.dto.CobrancaResumoDTO;
import br.com.collectionline.dto.FiltroPendentes;
import br.com.collectionline.dto.ParcelaDTO;
import br.com.collectionline.dto.ParcelaDetalheDTO;
import br.com.collectionline.dto.ParcelaPendenteDTO;

import java.math.BigDecimal;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * Todo o SQL da aplicação. Sempre PreparedStatement com "?": o valor vai
 * separado do comando, o que impede SQL injection.
 * A regra de negócio NÃO está aqui: ela fica nas funções do banco.
 */
public class CobrancaRepository {

    /**
     * US03: colunas que podem ser usadas para ordenar a pesquisa.
     * O ORDER BY não aceita "?", então a coluna nunca vem do que o usuário
     * digitou: ela sai deste mapa fechado (nome na API -> coluna no SQL).
     */
    public static final Map<String, String> COLUNAS_ORDENAVEIS = Map.of(
            "vencimento", "data_vencimento",
            "valor", "valor",
            "cliente", "nome",
            "cobranca", "id_cobranca");

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

    // ---------------------------------------------------------------------
    // US01: cadastro
    // ---------------------------------------------------------------------

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

    // ---------------------------------------------------------------------
    // US03: pesquisa de pendentes
    // ---------------------------------------------------------------------

    /** Chama a função de pesquisa do banco e ordena pela coluna escolhida. */
    public List<ParcelaPendenteDTO> listarParcelasPendentes(FiltroPendentes filtro) throws SQLException {
        // Coluna e direção vêm do mapa fechado (o controller já recusou o resto).
        // (Map.of não aceita consultar chave nula, por isso o teste de null antes.)
        String coluna = filtro.ordem() == null
                ? "data_vencimento"
                : COLUNAS_ORDENAVEIS.getOrDefault(filtro.ordem(), "data_vencimento");
        String direcao = "desc".equals(filtro.direcao()) ? "DESC" : "ASC";

        // Os ::tipo dizem ao PostgreSQL o tipo de cada "?" (ele não deduz
        // sozinho quando o valor chega nulo). Depois da coluna escolhida, os
        // desempates deixam a ordem sempre igual.
        String sql = """
                SELECT cpf, nome, telefone, id_cobranca, parcela, valor,
                       data_vencimento, dias_para_vencer, situacao
                  FROM pesquisar_parcelas_pendentes(?::char(11), ?::text, ?::text, ?::date, ?::date)
                 ORDER BY %s %s, data_vencimento, cpf, id_cobranca, parcela""".formatted(coluna, direcao);

        List<ParcelaPendenteDTO> lista = new ArrayList<>();
        try (Connection conn = database.abrirConexao();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setString(1, filtro.cpf());
            ps.setString(2, filtro.busca());
            ps.setString(3, filtro.situacao());
            ps.setObject(4, filtro.de());
            ps.setObject(5, filtro.ate());
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
                            rs.getInt("dias_para_vencer"),
                            rs.getString("situacao")));
                }
            }
        }
        return lista;
    }

    /**
     * US05: uma linha por cobrança que aparece na pesquisa (mesmos filtros).
     * Os totais e a regra de quais cobranças entram vêm da função do banco.
     */
    public List<CobrancaResumoDTO> resumirCobrancas(FiltroPendentes filtro) throws SQLException {
        String sql = """
                SELECT id_cobranca, cpf, nome, telefone, data_emissao, data_vencimento, valor,
                       qtd_parcelas, parcelas_pagas, parcelas_pendentes, valor_pendente, status_pagamento
                  FROM resumir_cobrancas_pesquisadas(?::char(11), ?::text, ?::text, ?::date, ?::date)""";

        List<CobrancaResumoDTO> lista = new ArrayList<>();
        try (Connection conn = database.abrirConexao();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setString(1, filtro.cpf());
            ps.setString(2, filtro.busca());
            ps.setString(3, filtro.situacao());
            ps.setObject(4, filtro.de());
            ps.setObject(5, filtro.ate());
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    lista.add(new CobrancaResumoDTO(
                            rs.getInt("id_cobranca"),
                            rs.getString("cpf"),
                            rs.getString("nome"),
                            rs.getString("telefone"),
                            rs.getObject("data_emissao", LocalDate.class),
                            rs.getObject("data_vencimento", LocalDate.class),
                            rs.getBigDecimal("valor"),
                            rs.getInt("qtd_parcelas"),
                            rs.getInt("parcelas_pagas"),
                            rs.getInt("parcelas_pendentes"),
                            rs.getBigDecimal("valor_pendente"),
                            rs.getString("status_pagamento")));
                }
            }
        }
        return lista;
    }

    // ---------------------------------------------------------------------
    // US02: detalhe, edição e pagamento
    // ---------------------------------------------------------------------

    /** Detalhe da cobrança com todas as parcelas; null se não existir. */
    public CobrancaDetalheDTO buscarCobranca(int idCobranca) throws SQLException {
        try (Connection conn = database.abrirConexao()) {
            return lerDetalhe(conn, idCobranca);
        }
    }

    /** Edita valor e vencimento pela função do banco e devolve a cobrança atualizada. */
    public CobrancaDetalheDTO editarParcela(int idParcela, BigDecimal valor, LocalDate dataVencimento)
            throws SQLException {
        try (Connection conn = database.abrirConexao()) {
            conn.setAutoCommit(false);
            try {
                int idCobranca;
                try (PreparedStatement ps = conn.prepareStatement("SELECT editar_parcela(?, ?, ?)")) {
                    ps.setInt(1, idParcela);
                    ps.setBigDecimal(2, valor);
                    ps.setObject(3, dataVencimento);
                    idCobranca = lerInteiro(ps);
                }
                CobrancaDetalheDTO detalhe = lerDetalhe(conn, idCobranca);
                conn.commit();
                return detalhe;
            } catch (SQLException | RuntimeException e) {
                conn.rollback();
                throw e;
            }
        }
    }

    // ---------------------------------------------------------------------
    // US04: editar e excluir a cobrança
    // ---------------------------------------------------------------------

    /** Edita a cobrança inteira pela função do banco e devolve o detalhe atualizado. */
    public CobrancaDetalheDTO editarCobranca(int idCobranca, String cpf, BigDecimal valor, int qtdParcelas,
                                             LocalDate primeiroVencimento) throws SQLException {
        try (Connection conn = database.abrirConexao()) {
            conn.setAutoCommit(false);
            try {
                try (PreparedStatement ps = conn.prepareStatement("SELECT editar_cobranca(?, ?, ?, ?, ?)")) {
                    ps.setInt(1, idCobranca);
                    ps.setString(2, cpf);
                    ps.setBigDecimal(3, valor);
                    ps.setInt(4, qtdParcelas);
                    ps.setObject(5, primeiroVencimento);
                    lerInteiro(ps);
                }
                CobrancaDetalheDTO detalhe = lerDetalhe(conn, idCobranca);
                conn.commit();
                return detalhe;
            } catch (SQLException | RuntimeException e) {
                conn.rollback();
                throw e;
            }
        }
    }

    /** Exclui a cobrança pela função do banco (que recusa se houver parcela paga). */
    public void excluirCobranca(int idCobranca) throws SQLException {
        try (Connection conn = database.abrirConexao();
             PreparedStatement ps = conn.prepareStatement("SELECT excluir_cobranca(?)")) {
            ps.setInt(1, idCobranca);
            lerInteiro(ps);
        }
    }

    /** Marca a parcela como paga e devolve a cobrança atualizada. */
    public CobrancaDetalheDTO pagarParcela(int idParcela) throws SQLException {
        return executarAcaoNaParcela("SELECT pagar_parcela(?)", idParcela);
    }

    /** Desfaz o pagamento da parcela e devolve a cobrança atualizada. */
    public CobrancaDetalheDTO desfazerPagamento(int idParcela) throws SQLException {
        return executarAcaoNaParcela("SELECT desfazer_pagamento_parcela(?)", idParcela);
    }

    /**
     * Chama uma função do banco que recebe só o id da parcela e devolve o id
     * da cobrança; depois lê o detalhe atualizado. Tudo numa transação.
     */
    private CobrancaDetalheDTO executarAcaoNaParcela(String sqlFuncao, int idParcela) throws SQLException {
        try (Connection conn = database.abrirConexao()) {
            conn.setAutoCommit(false);
            try {
                int idCobranca;
                try (PreparedStatement ps = conn.prepareStatement(sqlFuncao)) {
                    ps.setInt(1, idParcela);
                    idCobranca = lerInteiro(ps);
                }
                CobrancaDetalheDTO detalhe = lerDetalhe(conn, idCobranca);
                conn.commit();
                return detalhe;
            } catch (SQLException | RuntimeException e) {
                conn.rollback();
                throw e;
            }
        }
    }

    /** Executa um SELECT que devolve um único número (o id da cobrança). */
    private static int lerInteiro(PreparedStatement ps) throws SQLException {
        try (ResultSet rs = ps.executeQuery()) {
            rs.next();
            return rs.getInt(1);
        }
    }

    /** Lê a cobrança e suas parcelas usando a conexão (e a transação) recebida. */
    private CobrancaDetalheDTO lerDetalhe(Connection conn, int idCobranca) throws SQLException {
        String sqlCobranca = """
                SELECT co.id, co.cpf_cliente, cl.nome, co.data_emissao, co.data_vencimento,
                       co.valor, co.status_pagamento
                  FROM cobranca co
                  JOIN cliente cl ON cl.cpf = co.cpf_cliente
                 WHERE co.id = ?""";
        String sqlParcelas = """
                SELECT id, numero_parcela, total_parcelas, valor, data_vencimento, status
                  FROM parcela
                 WHERE id_cobranca = ?
                 ORDER BY numero_parcela""";

        List<ParcelaDetalheDTO> parcelas = new ArrayList<>();
        try (PreparedStatement ps = conn.prepareStatement(sqlParcelas)) {
            ps.setInt(1, idCobranca);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    parcelas.add(new ParcelaDetalheDTO(
                            rs.getInt("id"),
                            rs.getInt("numero_parcela"),
                            rs.getInt("total_parcelas"),
                            rs.getBigDecimal("valor"),
                            rs.getObject("data_vencimento", LocalDate.class),
                            rs.getString("status")));
                }
            }
        }

        try (PreparedStatement ps = conn.prepareStatement(sqlCobranca)) {
            ps.setInt(1, idCobranca);
            try (ResultSet rs = ps.executeQuery()) {
                if (!rs.next()) {
                    return null;   // cobrança não existe
                }
                return new CobrancaDetalheDTO(
                        rs.getInt("id"),
                        rs.getString("cpf_cliente"),
                        rs.getString("nome"),
                        rs.getObject("data_emissao", LocalDate.class),
                        rs.getObject("data_vencimento", LocalDate.class),
                        rs.getBigDecimal("valor"),
                        rs.getString("status_pagamento"),
                        parcelas);
            }
        }
    }
}
