package br.com.collectionline.dto;

/**
 * Corpo do POST /api/cobrancas. Tudo chega como texto e é convertido no
 * controller: assim conseguimos responder 400 com mensagem clara quando o
 * formato está errado (e o valor em dinheiro nunca passa por double).
 */
public record NovaCobrancaRequest(String cpfCliente, String valor, String qtdParcelas, String primeiroVencimento) {
}
