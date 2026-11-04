package br.com.collectionline.dto;

import java.util.List;

/** Resposta do POST /api/cobrancas: id da cobrança e suas parcelas. */
public record CobrancaCriadaResponse(int idCobranca, List<ParcelaDTO> parcelas) {
}
