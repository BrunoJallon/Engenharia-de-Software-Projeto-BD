package br.com.collectionline.dto;

/** Formato único de erro da API: {"erro": "mensagem"}. */
public record ErroResponse(String erro) {
}
