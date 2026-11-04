package br.com.collectionline.dto;

import java.math.BigDecimal;
import java.time.LocalDate;

/**
 * Uma linha da pesquisa de parcelas pendentes. situacao (US03) vem do banco:
 * "atrasada", "vence_hoje" ou "a_vencer".
 */
public record ParcelaPendenteDTO(String cpf, String nome, String telefone, int idCobranca,
                                 String parcela, BigDecimal valor, LocalDate dataVencimento,
                                 int diasParaVencer, String situacao) {
}
