package br.com.collectionline.dto;

/**
 * US02: corpo do PUT /api/parcelas/{id}. Como no cadastro, tudo chega como
 * texto e o controller confere o formato antes de chamar o banco.
 */
public record EditarParcelaRequest(String valor, String dataVencimento) {
}
