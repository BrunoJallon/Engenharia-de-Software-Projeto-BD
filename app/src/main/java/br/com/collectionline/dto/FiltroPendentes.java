package br.com.collectionline.dto;

import java.time.LocalDate;

/**
 * US03: filtros da pesquisa de parcelas pendentes. Campo nulo = não filtra.
 * ordem e direcao já chegam conferidos pelo controller (lista fechada).
 */
public record FiltroPendentes(String cpf, String busca, String situacao, LocalDate de, LocalDate ate,
                              String ordem, String direcao) {
}
