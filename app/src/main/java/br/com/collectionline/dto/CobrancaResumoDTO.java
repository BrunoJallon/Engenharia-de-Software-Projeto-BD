package br.com.collectionline.dto;

import java.math.BigDecimal;
import java.time.LocalDate;

/**
 * US05: uma linha da aba "Cobranças" da planilha (uma por cobrança).
 * Vem da função resumir_cobrancas_pesquisadas do banco.
 */
public record CobrancaResumoDTO(int idCobranca, String cpf, String nome, String telefone,
                                LocalDate dataEmissao, LocalDate dataVencimento, BigDecimal valor,
                                int qtdParcelas, int parcelasPagas, int parcelasPendentes,
                                BigDecimal valorPendente, String statusPagamento) {
}
