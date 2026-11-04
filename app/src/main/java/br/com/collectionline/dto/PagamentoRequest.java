package br.com.collectionline.dto;

/**
 * US06: corpo do POST e do PUT /api/parcelas/{id}/pagamento, com a data
 * em que o cliente pagou (aaaa-mm-dd). Chega como texto e o controller
 * confere o formato; "não pode ser no futuro" é regra do banco.
 */
public record PagamentoRequest(String dataPagamento) {
}
