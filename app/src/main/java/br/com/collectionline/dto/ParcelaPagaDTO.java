package br.com.collectionline.dto;

import java.math.BigDecimal;
import java.time.LocalDate;

/**
 * US08: uma linha da aba "Pagas". diasAtrasoPagamento vem do banco
 * (0 = paga em dia; mais que 0 = quantos dias depois do vencimento).
 */
public record ParcelaPagaDTO(int idParcela, String cpf, String nome, String telefone, int idCobranca,
                             String parcela, BigDecimal valor, LocalDate dataVencimento,
                             LocalDate dataPagamento, int diasAtrasoPagamento) {
}
