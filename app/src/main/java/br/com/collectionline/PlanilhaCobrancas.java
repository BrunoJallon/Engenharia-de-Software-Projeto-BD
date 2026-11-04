package br.com.collectionline;

import br.com.collectionline.dto.CobrancaResumoDTO;
import br.com.collectionline.dto.ParcelaPendenteDTO;
import org.apache.poi.ss.usermodel.Cell;
import org.apache.poi.ss.usermodel.CellStyle;
import org.apache.poi.ss.usermodel.Font;
import org.apache.poi.ss.usermodel.Row;
import org.apache.poi.ss.usermodel.Sheet;
import org.apache.poi.ss.usermodel.Workbook;
import org.apache.poi.ss.util.CellRangeAddress;
import org.apache.poi.xssf.usermodel.XSSFWorkbook;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.List;

/**
 * US05: monta as planilhas a partir do que o banco devolveu.
 * - CSV: só o resumo (uma linha por cobrança), pensado para o Excel em português.
 * - XLSX: duas abas, "Cobranças" (resumo) e "Parcelas" (as parcelas pendentes).
 * Nenhuma regra de negócio aqui: só formatação.
 */
public final class PlanilhaCobrancas {

    private static final String[] COLUNAS_COBRANCAS = {
            "Cobrança", "CPF", "Cliente", "Telefone", "Emissão", "Último vencimento",
            "Valor total (R$)", "Parcelas", "Pagas", "Pendentes", "Valor pendente (R$)", "Status"};

    private static final String[] COLUNAS_PARCELAS = {
            "Id", "Cobrança", "Parcela", "CPF", "Cliente", "Telefone", "Valor (R$)", "Vencimento",
            "Dias para vencer", "Situação"};

    private static final DateTimeFormatter DATA_BR = DateTimeFormatter.ofPattern("dd/MM/yyyy");

    private PlanilhaCobrancas() {
        // classe utilitária: não deve ser instanciada
    }

    // ---------------------------------------------------------------------
    // CSV
    // ---------------------------------------------------------------------

    /**
     * CSV do resumo. Três cuidados para o Excel brasileiro abrir certo:
     * separador ";" (a vírgula é o decimal aqui), vírgula decimal nos valores
     * e o BOM no começo, que avisa ao Excel que o texto é UTF-8 (sem ele,
     * "Cobrança" aparece como "CobranÃ§a").
     */
    public static byte[] gerarCsv(List<CobrancaResumoDTO> cobrancas) {
        StringBuilder csv = new StringBuilder("﻿");
        adicionarLinhaCsv(csv, COLUNAS_COBRANCAS);
        for (CobrancaResumoDTO c : cobrancas) {
            adicionarLinhaCsv(csv,
                    String.valueOf(c.idCobranca()),
                    formatarCpf(c.cpf()),
                    protegerContraFormula(c.nome()),   // único texto livre, digitado no cadastro
                    formatarTelefone(c.telefone()),
                    c.dataEmissao().format(DATA_BR),
                    c.dataVencimento().format(DATA_BR),
                    formatarValorCsv(c.valor()),
                    String.valueOf(c.qtdParcelas()),
                    String.valueOf(c.parcelasPagas()),
                    String.valueOf(c.parcelasPendentes()),
                    formatarValorCsv(c.valorPendente()),
                    formatarStatus(c.statusPagamento()));
        }
        return csv.toString().getBytes(StandardCharsets.UTF_8);
    }

    /** Uma linha do CSV; termina com \r\n, o fim de linha que o Excel espera. */
    private static void adicionarLinhaCsv(StringBuilder csv, String... campos) {
        for (int i = 0; i < campos.length; i++) {
            if (i > 0) csv.append(';');
            csv.append(campoCsv(campos[i]));
        }
        csv.append("\r\n");
    }

    /**
     * Texto que começa com = + - @ ganha um apóstrofo na frente; senão o
     * Excel trata como fórmula (um nome de cliente "=HYPERLINK(...)" viraria
     * um link). Isso se chama "injeção de CSV". Só o nome precisa: os outros
     * campos são montados por nós a partir de números e datas.
     */
    private static String protegerContraFormula(String texto) {
        if (!texto.isEmpty() && "=+-@".indexOf(texto.charAt(0)) >= 0) {
            return "'" + texto;
        }
        return texto;
    }

    /**
     * Campo com ; aspas ou quebra de linha vai entre aspas, e as aspas de
     * dentro são dobradas ("" vale como uma aspa).
     */
    private static String campoCsv(String valor) {
        String v = valor == null ? "" : valor;
        if (v.contains(";") || v.contains("\"") || v.contains("\n") || v.contains("\r")) {
            v = "\"" + v.replace("\"", "\"\"") + "\"";
        }
        return v;
    }

    /** 1234.50 -> "1234,50" (sem separador de milhar, para o Excel ler como número). */
    private static String formatarValorCsv(BigDecimal valor) {
        return valor.toPlainString().replace('.', ',');
    }

    // ---------------------------------------------------------------------
    // XLSX
    // ---------------------------------------------------------------------

    /**
     * XLSX com as abas "Cobranças" e "Parcelas". Aqui datas e valores são
     * gravados como data e número de verdade (dá para somar e filtrar no
     * Excel); só o formato de exibição é escolhido por nós.
     */
    public static byte[] gerarXlsx(List<CobrancaResumoDTO> cobrancas, List<ParcelaPendenteDTO> parcelas)
            throws IOException {
        // try-with-resources: o Workbook é fechado mesmo se der erro no meio.
        try (Workbook planilha = new XSSFWorkbook();
             ByteArrayOutputStream saida = new ByteArrayOutputStream()) {
            Estilos estilos = new Estilos(planilha);

            Sheet abaCobrancas = criarAba(planilha, "Cobranças", COLUNAS_COBRANCAS, estilos);
            int numeroLinha = 1;
            for (CobrancaResumoDTO c : cobrancas) {
                Row linha = abaCobrancas.createRow(numeroLinha++);
                celulaNumero(linha, 0, c.idCobranca());
                celulaTexto(linha, 1, formatarCpf(c.cpf()));
                celulaTexto(linha, 2, c.nome());
                celulaTexto(linha, 3, formatarTelefone(c.telefone()));
                celulaData(linha, 4, c.dataEmissao(), estilos);
                celulaData(linha, 5, c.dataVencimento(), estilos);
                celulaDinheiro(linha, 6, c.valor(), estilos);
                celulaNumero(linha, 7, c.qtdParcelas());
                celulaNumero(linha, 8, c.parcelasPagas());
                celulaNumero(linha, 9, c.parcelasPendentes());
                celulaDinheiro(linha, 10, c.valorPendente(), estilos);
                celulaTexto(linha, 11, formatarStatus(c.statusPagamento()));
            }
            ajustarLarguras(abaCobrancas, 11, 16, 30, 20, 12, 18, 16, 10, 8, 11, 20, 11);

            Sheet abaParcelas = criarAba(planilha, "Parcelas", COLUNAS_PARCELAS, estilos);
            numeroLinha = 1;
            for (ParcelaPendenteDTO p : parcelas) {
                Row linha = abaParcelas.createRow(numeroLinha++);
                celulaNumero(linha, 0, p.idParcela());   // US06
                celulaNumero(linha, 1, p.idCobranca());
                celulaTexto(linha, 2, p.parcela());
                celulaTexto(linha, 3, formatarCpf(p.cpf()));
                celulaTexto(linha, 4, p.nome());
                celulaTexto(linha, 5, formatarTelefone(p.telefone()));
                celulaDinheiro(linha, 6, p.valor(), estilos);
                celulaData(linha, 7, p.dataVencimento(), estilos);
                celulaNumero(linha, 8, p.diasParaVencer());
                celulaTexto(linha, 9, formatarSituacao(p.situacao()));
            }
            ajustarLarguras(abaParcelas, 8, 11, 9, 16, 30, 20, 12, 12, 16, 12);

            planilha.write(saida);
            return saida.toByteArray();
        }
    }

    /** Estilos criados uma vez só (o Excel tem limite de estilos por arquivo). */
    private static final class Estilos {
        final CellStyle cabecalho;
        final CellStyle data;
        final CellStyle dinheiro;

        Estilos(Workbook planilha) {
            Font negrito = planilha.createFont();
            negrito.setBold(true);
            cabecalho = planilha.createCellStyle();
            cabecalho.setFont(negrito);

            data = planilha.createCellStyle();
            data.setDataFormat(planilha.createDataFormat().getFormat("dd/mm/yyyy"));

            // O Excel mostra com os separadores do computador (no Brasil: 1.234,50).
            dinheiro = planilha.createCellStyle();
            dinheiro.setDataFormat(planilha.createDataFormat().getFormat("#,##0.00"));
        }
    }

    /** Cria a aba com o cabeçalho em negrito, congelado e com filtro. */
    private static Sheet criarAba(Workbook planilha, String nome, String[] colunas, Estilos estilos) {
        Sheet aba = planilha.createSheet(nome);
        Row cabecalho = aba.createRow(0);
        for (int i = 0; i < colunas.length; i++) {
            Cell celula = cabecalho.createCell(i);
            celula.setCellValue(colunas[i]);
            celula.setCellStyle(estilos.cabecalho);
        }
        aba.createFreezePane(0, 1);  // o cabeçalho fica parado ao rolar
        aba.setAutoFilter(new CellRangeAddress(0, 0, 0, colunas.length - 1));
        return aba;
    }

    /** Largura de cada coluna, em caracteres (o POI conta em 1/256 de caractere). */
    private static void ajustarLarguras(Sheet aba, int... larguras) {
        for (int i = 0; i < larguras.length; i++) {
            aba.setColumnWidth(i, larguras[i] * 256);
        }
    }

    // setCellValue(String) grava sempre como texto, nunca como fórmula:
    // no XLSX não existe o risco de injeção que o CSV tem.
    private static void celulaTexto(Row linha, int coluna, String valor) {
        linha.createCell(coluna).setCellValue(valor);
    }

    private static void celulaNumero(Row linha, int coluna, int valor) {
        linha.createCell(coluna).setCellValue(valor);
    }

    private static void celulaData(Row linha, int coluna, LocalDate valor, Estilos estilos) {
        Cell celula = linha.createCell(coluna);
        celula.setCellValue(valor);
        celula.setCellStyle(estilos.data);
    }

    private static void celulaDinheiro(Row linha, int coluna, BigDecimal valor, Estilos estilos) {
        Cell celula = linha.createCell(coluna);
        // O Excel só guarda números como double; com 2 casas decimais e
        // valores até 99.999.999,99 (limite do banco) a conta fica exata na tela.
        celula.setCellValue(valor.doubleValue());
        celula.setCellStyle(estilos.dinheiro);
    }

    // ---------------------------------------------------------------------
    // Formatação (a mesma da tela)
    // ---------------------------------------------------------------------

    /** "12345678901" -> "123.456.789-01". Com pontos, o Excel não apaga zeros à esquerda. */
    static String formatarCpf(String cpf) {
        return cpf.substring(0, 3) + "." + cpf.substring(3, 6) + "." + cpf.substring(6, 9) + "-" + cpf.substring(9);
    }

    /**
     * "5583999990001" -> "+55 (83) 99999-0001". Sem formatar, o Excel leria
     * os 13 dígitos como número e mostraria 5,58E+12.
     * O banco aceita 10 a 13 dígitos: com 12 ou 13, os 2 primeiros são o DDI.
     */
    static String formatarTelefone(String tel) {
        String ddi = "";
        String resto = tel;
        if (tel.length() >= 12) {
            ddi = "+" + tel.substring(0, 2) + " ";
            resto = tel.substring(2);
        }
        String ddd = resto.substring(0, 2);
        String numero = resto.substring(2);           // 8 ou 9 dígitos
        int meio = numero.length() - 4;
        return ddi + "(" + ddd + ") " + numero.substring(0, meio) + "-" + numero.substring(meio);
    }

    /** "pendente" -> "Pendente" */
    private static String formatarStatus(String status) {
        return status.isEmpty() ? status : Character.toUpperCase(status.charAt(0)) + status.substring(1);
    }

    /** Situação que vem do banco -> texto da tela. */
    private static String formatarSituacao(String situacao) {
        return switch (situacao) {
            case "atrasada" -> "Atrasada";
            case "vence_hoje" -> "Vence hoje";
            case "a_vencer" -> "A vencer";
            default -> situacao;
        };
    }

    /** Nome do arquivo baixado: cobrancas-2026-11-04.csv / .xlsx */
    public static String nomeArquivo(String extensao) {
        return "cobrancas-" + LocalDate.now() + "." + extensao;
    }
}
