package br.com.collectionline.dto;

/** US04: resposta simples de sucesso, ex.: {"mensagem": "Cobrança nº 7 excluída."}. */
public record MensagemResponse(String mensagem) {
}
