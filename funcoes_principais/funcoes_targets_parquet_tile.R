# ======================================================================
# funcoes_principais/funcoes_targets_parquet_tile.R
#
# Funções usadas pelo _targets.R. Dois pipelines compartilham estas
# funções:
#   - "rais"  : parquet bruto da RAIS, multi-ano, resoluções 4/6/8
#   - "cens"  : parquet já censurado (ver transformacao_parquets.R),
#               ano único, resoluções 5/7/9
#
# Cada pipeline gera 3 saídas pelas MESMAS 3 famílias de função:
#   1) gerar_geometria_pmtiles() -> geometria.pmtiles
#   2) gerar_uf_lookup()         -> uf_lookup.parquet
#   3) exportar_*()              -> hex_rXX(_ANO).parquet (atributos)
#
# Carregadas via tar_source() no _targets.R.
# ======================================================================

# ----------------------------------------------------------------------
# 1. Carga
# ----------------------------------------------------------------------

#' Lê o parquet bruto da RAIS (já agregado em H3, multi-resolução,
#' multi-ano) e coleta em memória.
carregar_rais <- function(caminho_parquet) {
  arrow::open_dataset(caminho_parquet) |>
    dplyr::collect()
}

#' Lê o parquet de geometria do pipeline "cens" (h3_address/h3_res/
#' code_muni, 1 linha por hexágono, sem colunas de atributo).
carregar_cens_prep_tile <- function(caminho_parquet) {
  arrow::read_parquet(caminho_parquet)
}

#' Lê o parquet de atributos já censurado e renomeia pros nomes que o
#' resto do pipeline usa (ano, n_firmas, qt_vinc_ativos, uf) — a origem
#' usa year/F001/T001/abbrev_state (nomenclatura do processo de
#' censura, ver legado/censura_rapida.R).
carregar_cens <- function(caminho_parquet) {
  arrow::read_parquet(caminho_parquet) |>
    dplyr::rename(ano = year, n_firmas = F001, qt_vinc_ativos = T001, uf = abbrev_state)
}

# 2. Geometria -> pmtiles (compartilhada pelos dois pipelines)
# ----------------------------------------------------------------------

#' Gera um pmtiles com 1 camada MVT por resolução, cada camada com a
#' SUA PRÓPRIA janela de zoom (min_zoom/max_zoom).
#'
#' `janelas_zoom` é uma lista nomeada no formato:
#'   list(h3_r04 = list(resolucao = 4, min_zoom = 0, max_zoom = 7), ...)
#' — o nome de cada item é o nome da camada MVT (o dashboard espera
#' sourceLayer: "h3_r04", etc.) e também a janela de zoom em que essa
#' resolução é exibida no mapa (mesma ideia do array RESOLUCOES em
#' index.html).
#'
#' Isso é OBRIGATÓRIO, não cosmético: o freestile() usa `base_zoom` pra
#' decidir a curva de drop_rate (quantos hexágonos sobrevivem em cada
#' zoom), e por padrão `base_zoom` é o `max_zoom` da própria camada. Se
#' todas as camadas usassem o mesmo max_zoom global (14), uma resolução
#' exibida só até o zoom 7 (ex.: h3_r04) teria quase TODOS os hexágonos
#' descartados nos zooms em que ela de fato aparece no mapa — foi
#' exatamente isso que fazia o pmtiles gerado não mostrar hexágono
#' nenhum (a camada existia no arquivo, mas ficava praticamente vazia
#' nos zooms onde o dashboard a desenha).
#'
#' coalesce = FALSE é igualmente obrigatório: TRUE fundiria hexágonos
#' adjacentes com atributos iguais, destruindo a identidade individual
#' de h3_address que o feature-state no navegador precisa para colar o
#' valor certo no hexágono certo.
gerar_geometria_pmtiles <- function(df, janelas_zoom, caminho_saida) {
  camadas <- purrr::imap(janelas_zoom, function(janela, nome_camada) {
    poligonos <- df |>
      dplyr::filter(h3_res == janela$resolucao) |>
      dplyr::distinct(h3_address) |>
      dplyr::mutate(geometry = h3jsr::cell_to_polygon(h3_address)) |>
      sf::st_as_sf(crs = 4326)

    freestiler::freestile_layer(poligonos, min_zoom = janela$min_zoom, max_zoom = janela$max_zoom)
  })

  if (file.exists(caminho_saida)) file.remove(caminho_saida)

  freestiler::freestile(camadas, caminho_saida, drop_rate = 2.5, coalesce = FALSE)

  caminho_saida
}

# ----------------------------------------------------------------------
# 3. uf_lookup.parquet (compartilhada pelos dois pipelines)
# ----------------------------------------------------------------------

#' Gera o lookup h3_address -> uf de todas as resoluções de uma vez,
#' direto do df de atributos (não da geometria — a geometria não leva
#' uf: um hexágono pode tocar mais de uma UF, e colocar uf na geometria
#' duplicaria a linha de desenho desse hexágono no pmtiles). `uf` pode
#' chegar como string simples (pipeline "cens") ou como list-column
#' (pipeline "rais", 1 string por elemento) — `purrr::map_chr(uf, 1)`
#' funciona para os dois casos.
#'
#' Pode conter mais de uma linha por h3_address — isso é esperado
#' (hexágono de fronteira entre UFs) e é responsabilidade do consumidor
#' (dashboard) lidar com isso via subquery de existência, não JOIN
#' direto, para não duplicar o hexágono na hora de usar.
gerar_uf_lookup <- function(df, resolucoes_alvo, caminho_saida) {
  uf_lookup <- df |>
    dplyr::filter(h3_res %in% resolucoes_alvo) |>
    dplyr::mutate(uf = purrr::map_chr(uf, 1)) |>
    dplyr::distinct(h3_address, uf)

  arrow::write_parquet(uf_lookup, caminho_saida)
  caminho_saida
}

# ----------------------------------------------------------------------
# 4a. Atributos do pipeline "rais" (multi-ano, precisa agregar)
# ----------------------------------------------------------------------

#' Agrega as colunas de atributo (ex.: n_firmas/qt_vinc_ativos) por
#' hexágono, para UMA combinação resolução x ano. O "ano" não vira
#' coluna no arquivo final — vira parte do nome do arquivo (ver
#' exportar_atributos_parquet()).
preparar_atributos <- function(df, resolucao, ano_alvo, colunas_atributos) {
  df |>
    dplyr::filter(h3_res == resolucao, ano == ano_alvo) |>
    dplyr::group_by(h3_address) |>
    dplyr::summarise(
      dplyr::across(dplyr::all_of(colunas_atributos), ~ sum(.x, na.rm = TRUE)),
      .groups = "drop"
    )
}

#' Agrega e grava o parquet de UMA combinação resolução x ano em
#' dados/hex_rXX_ANO.parquet.
exportar_atributos_parquet <- function(df, resolucao, ano_alvo, colunas_atributos, diretorio_saida = "dados") {
  if (!dir.exists(diretorio_saida)) dir.create(diretorio_saida, recursive = TRUE)

  atributos <- preparar_atributos(df, resolucao, ano_alvo, colunas_atributos)

  if (nrow(atributos) == 0) {
    warning(sprintf("Resolução %d, ano %d: 0 linhas — nada para exportar.", resolucao, ano_alvo))
    return(NA_character_)
  }

  caminho <- file.path(diretorio_saida, sprintf("hex_r%02d_%d.parquet", resolucao, ano_alvo))
  arrow::write_parquet(atributos, caminho)
  caminho
}

# ----------------------------------------------------------------------
# 4b. Atributos do pipeline "cens" (ano único, já vem 1 linha/hexágono
#     — não precisa agregar, só selecionar e gravar)
# ----------------------------------------------------------------------

#' Grava o parquet de atributos de UMA resolução em
#' hex_rXX_cens.parquet. `ano` fica como COLUNA dentro do arquivo (não
#' no nome) para o dashboard filtrar por ano em SQL, como já faz com os
#' outros parquets hex_resX_*.parquet.
exportar_hex_cens <- function(df, resolucao, colunas_atributos, diretorio_saida = "outputs_dados") {
  if (!dir.exists(diretorio_saida)) dir.create(diretorio_saida, recursive = TRUE)

  atributos <- df |>
    dplyr::filter(h3_res == resolucao) |>
    dplyr::select(h3_address, ano, dplyr::all_of(colunas_atributos))

  caminho <- file.path(diretorio_saida, sprintf("hex_r%02d_cens.parquet", resolucao))
  arrow::write_parquet(atributos, caminho)
  caminho
}
