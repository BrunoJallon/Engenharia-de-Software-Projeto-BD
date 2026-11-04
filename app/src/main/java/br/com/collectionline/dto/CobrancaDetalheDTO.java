package br.com.collectionline.dto;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;

/** US02: uma cobrança com todas as suas parcelas (pendentes e pagas). */
public record CobrancaDetalheDTO(int idCobranca, String cpfCliente, String nomeCliente,
                                 LocalDate dataEmissao, LocalDate dataVencimento, BigDecimal valor,
                                 String statusPagamento, List<ParcelaDetalheDTO> parcelas) {
}
