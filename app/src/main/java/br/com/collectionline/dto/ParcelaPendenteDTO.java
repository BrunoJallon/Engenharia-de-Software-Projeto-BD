package br.com.collectionline.dto;

import java.math.BigDecimal;
import java.time.LocalDate;

/**
 * Uma linha da pesquisa de parcelas pendentes. situacao (US03) vem do banco:
 * "atrasada", "vence_hoje" ou "a_vencer". idParcela (US06) é o id da
 * parcela no banco, mostrado na primeira coluna da lista.
 */
public record ParcelaPendenteDTO(int idParcela, String cpf, String nome, String telefone, int idCobranca,
                                 String parcela, BigDecimal valor, LocalDate dataVencimento,
                                 int diasParaVencer, String situacao) {
}
