# ======================================================================
# _targets.R
#
# Pipeline que gera, a partir do parquet bruto da RAIS (agregado em
# H3, multi-resolução, multi-ano):
#   - geometria.pmtiles          (geometria dos hexágonos, 1 camada por
#                                  resolução, gerada 1x — não repete por ano)
#   - dados/hex_rXX_ANO.parquet  (atributos por resolução x ano)
#   - uf_lookup.parquet          (h3_address -> uf, para filtro no dashboard)
#
# As funções usadas aqui vêm de funcoes_principais/funcoes_targets_parquet_tile.R.
# ======================================================================

library(targets)

tar_option_set(
  packages = c("arrow", "dplyr", "sf", "h3jsr", "purrr", "freestiler")
)

tar_source("funcoes_principais/funcoes_targets_parquet_tile.R")

list(
  # --------------------------------------------------------------
  # Inputs do pipeline
  # --------------------------------------------------------------

  # Parquet bruto da RAIS (agregado em H3). format = "file" faz o
  # pipeline reexecutar os targets a jusante se o arquivo mudar.
  tar_target(
    arquivo_rais_bruto,
    "dados/rais_test_20260727.parquet",
    format = "file"
  ),

  # Resoluções H3 a incluir no geometria.pmtiles e nos parquets de
  # atributos. Mudar este vetor é o único passo necessário para
  # adicionar/remover uma resolução do pipeline.
  tar_target(resolucoes_alvo, c(4, 6, 8)),

  # Colunas de atributo da RAIS a agregar por hexágono (ver
  # preparar_atributos()). Vive aqui — não hardcoded na função — para
  # que novas variáveis do parquet de entrada só exijam editar este
  # vetor.
  tar_target(colunas_atributos, c("n_firmas", "qt_vinc_ativos")),

  # --------------------------------------------------------------
  # Carga
  # --------------------------------------------------------------

  tar_target(df_rais, carregar_rais(arquivo_rais_bruto)),

  tar_target(anos_disponiveis, sort(unique(df_rais$ano))),

  # --------------------------------------------------------------
  # Geometria -> geometria.pmtiles (1 camada por resolução)
  # --------------------------------------------------------------

  tar_target(
    geometria_por_resolucao,
    preparar_geometria(df_rais, resolucoes_alvo),
    pattern = map(resolucoes_alvo),
    iteration = "list"
  ),

  tar_target(
    geometrias_nomeadas,
    nomear_geometrias(geometria_por_resolucao, resolucoes_alvo)
  ),

  tar_target(
    caminho_pmtiles,
    gerar_pmtiles(geometrias_nomeadas, "geometria.pmtiles"),
    format = "file"
  ),

  # --------------------------------------------------------------
  # uf_lookup.parquet (h3_address -> uf, todas as resoluções)
  # --------------------------------------------------------------

  tar_target(
    uf_parcial_por_resolucao,
    preparar_uf_lookup_parcial(df_rais, resolucoes_alvo),
    pattern = map(resolucoes_alvo),
    iteration = "list"
  ),

  tar_target(
    caminho_uf_lookup,
    gerar_uf_lookup(uf_parcial_por_resolucao, "uf_lookup.parquet"),
    format = "file"
  ),

  # --------------------------------------------------------------
  # dados/hex_rXX_ANO.parquet (atributos: resolução x ano)
  # --------------------------------------------------------------

  tar_target(
    caminho_atributos_parquet,
    exportar_atributos_parquet(
      df_rais,
      resolucoes_alvo,
      anos_disponiveis,
      colunas_atributos,
      diretorio_saida = "dados"
    ),
    pattern = cross(resolucoes_alvo, anos_disponiveis),
    format = "file"
  )
)
