# ======================================================================
# _targets.R
#
# Dois pipelines, lado a lado, compartilhando as mesmas 3 famílias de
# target (ver funcoes_principais/funcoes_targets_parquet_tile.R):
#
#   1) geometria -> pmtiles  (1 camada MVT por resolução)
#   2) uf_lookup.parquet     (h3_address -> uf, pra filtro no dashboard)
#   3) hex_rXX(_ANO).parquet (atributos por hexágono)
#
# Pipeline "rais": parquet bruto da RAIS (dados/rais_test_20260727.parquet),
#   multi-ano, resoluções 4/6/8.
# Pipeline "cens": parquet já censurado por fora (ver
#   transformacao_parquets.R, que gera os 2 parquets de entrada abaixo
#   a partir de dados/rais_cens_2019_h3_0{5,7,9}.parquet), ano único
#   (2019), resoluções 5/7/9.
# ======================================================================

library(targets)

tar_option_set(
  packages = c("arrow", "dplyr", "sf", "h3jsr", "purrr", "freestiler")
)

tar_source("funcoes_principais/funcoes_targets_parquet_tile.R")

list(
  # ================================================================
  # Pipeline "rais": RAIS bruta, multi-ano, resoluções 4/6/8
  # ================================================================

  # tar_target(
  #   arquivo_rais_bruto,
  #   "dados/rais_test_20260727.parquet",
  #   format = "file"
  # ),
  # 
  # tar_target(df_rais, carregar_rais(arquivo_rais_bruto)),
  # 
  # tar_target(resolucoes_rais, c(4, 6, 8)),
  # 
  # tar_target(anos_rais, sort(unique(df_rais$ano))),
  # 
  # tar_target(colunas_atributos_rais, c("n_firmas", "qt_vinc_ativos")),
  # 
  # # Janela de zoom em que cada resolução é exibida no mapa (mesma
  # # ideia do array RESOLUCOES em index.html). Cada camada do pmtiles
  # # usa a SUA PRÓPRIA janela — ver gerar_geometria_pmtiles() pra
  # # entender por que isso é obrigatório, não cosmético.
  # tar_target(janelas_zoom_rais, list(
  #   h3_r04 = list(resolucao = 4, min_zoom = 0,  max_zoom = 7),
  #   h3_r06 = list(resolucao = 6, min_zoom = 7,  max_zoom = 10),
  #   h3_r08 = list(resolucao = 8, min_zoom = 10, max_zoom = 14)
  # )),
  # 
  # # --- Target 1: geometria -> geometria.pmtiles ------------------
  # 
  # tar_target(
  #   caminho_pmtiles,
  #   gerar_geometria_pmtiles(df_rais, janelas_zoom_rais, "geometria.pmtiles"),
  #   format = "file"
  # ),
  # 
  # # --- Target 2: uf_lookup.parquet --------------------------------
  # 
  # tar_target(
  #   caminho_uf_lookup,
  #   gerar_uf_lookup(df_rais, resolucoes_rais, "uf_lookup.parquet"),
  #   format = "file"
  # ),
  # 
  # # --- Target 3: dados/hex_rXX_ANO.parquet ------------------------
  # 
  # tar_target(
  #   caminho_atributos_parquet,
  #   exportar_atributos_parquet(
  #     df_rais,
  #     resolucoes_rais,
  #     anos_rais,
  #     colunas_atributos_rais,
  #     diretorio_saida = "dados"
  #   ),
  #   pattern = cross(resolucoes_rais, anos_rais),
  #   format = "file"
  # ),

  # ================================================================
  # Pipeline "cens": RAIS 2019 já censurada, resoluções 5/7/9
  # ================================================================

  tar_target(
    arquivo_cens_prep_tile,
    "outputs_dados/df_uni_cens_prep_tile.parquet",
    format = "file"
  ),

  tar_target(
    arquivo_cens,
    "outputs_dados/df_uni_cens.parquet",
    format = "file"
  ),

  tar_target(df_cens_prep_tile, carregar_cens_prep_tile(arquivo_cens_prep_tile)),

  tar_target(df_cens, carregar_cens(arquivo_cens)),

  tar_target(resolucoes_cens, c(5, 7, 9)),

  tar_target(colunas_atributos_cens, c("n_firmas", "qt_vinc_ativos")),

  tar_target(janelas_zoom_cens, list(
    h3_r05 = list(resolucao = 5, min_zoom = 0,  max_zoom = 7),
    h3_r07 = list(resolucao = 7, min_zoom = 7,  max_zoom = 10),
    h3_r09 = list(resolucao = 9, min_zoom = 10, max_zoom = 14)
  )),

  # --- Target 1: geometria -> geometria_cens.pmtiles --------------

  tar_target(
    caminho_pmtiles_cens,
    gerar_geometria_pmtiles(df_cens_prep_tile, janelas_zoom_cens, "outputs_dados/geometria_cens.pmtiles"),
    format = "file"
  ),

  # --- Target 2: uf_lookup_cens.parquet ----------------------------

  tar_target(
    caminho_uf_lookup_cens,
    gerar_uf_lookup(df_cens, resolucoes_cens, "outputs_dados/uf_lookup_cens.parquet"),
    format = "file"
  ),

  # --- Target 3: outputs_dados/hex_rXX_cens.parquet ----------------

  tar_target(
    caminho_hex_cens,
    exportar_hex_cens(df_cens, resolucoes_cens, colunas_atributos_cens, diretorio_saida = "outputs_dados"),
    pattern = map(resolucoes_cens),
    format = "file"
  )
)
