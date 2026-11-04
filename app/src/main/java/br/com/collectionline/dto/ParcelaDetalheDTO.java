package br.com.collectionline.dto;

import java.math.BigDecimal;
import java.time.LocalDate;

/** US02: uma parcela no detalhe da cobrança (com o id, para editar e pagar). */
public record ParcelaDetalheDTO(int idParcela, int numeroParcela, int totalParcelas, BigDecimal valor,
                                LocalDate dataVencimento, String status) {
}
