package br.com.collectionline.dto;

import java.math.BigDecimal;
import java.time.LocalDate;

/** Uma parcela recém-criada, devolvida na resposta do cadastro. */
public record ParcelaDTO(int numeroParcela, int totalParcelas, BigDecimal valor,
                         LocalDate dataVencimento, String status) {
}
