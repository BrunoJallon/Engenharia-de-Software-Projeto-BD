package br.com.collectionline.dto;

import java.util.List;

/**
 * US07: corpo do POST /api/pagamentos — os ids das parcelas que o cliente
 * pagou e a data do pagamento (aaaa-mm-dd), igual para todas.
 */
public record PagarParcelasRequest(List<Integer> idsParcelas, String dataPagamento) {
}
