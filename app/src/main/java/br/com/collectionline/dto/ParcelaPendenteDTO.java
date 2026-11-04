package br.com.collectionline.dto;

import java.math.BigDecimal;
import java.time.LocalDate;

/** Uma linha da view vw_parcelas_pendentes. */
public record ParcelaPendenteDTO(String cpf, String nome, String telefone, int idCobranca,
                                 String parcela, BigDecimal valor, LocalDate dataVencimento,
                                 int diasParaVencer) {
}
