package br.com.collectionline.dto;

import java.math.BigDecimal;
import java.time.LocalDate;

/**
 * US02: uma parcela no detalhe da cobrança (com o id, para editar e pagar).
 * US06: dataPagamento e diasAtrasoPagamento (0 = paga em dia) ficam null
 * enquanto a parcela não está paga. O atraso é calculado pelo banco.
 */
public record ParcelaDetalheDTO(int idParcela, int numeroParcela, int totalParcelas, BigDecimal valor,
                                LocalDate dataVencimento, String status,
                                LocalDate dataPagamento, Integer diasAtrasoPagamento) {
}
