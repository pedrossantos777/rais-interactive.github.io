library(arrow)
library(tidyverse)

anos <- 2013:2023
resolucoes <- c(3, 5, 7, 9)

caminhos <- expand_grid(ano = anos, res = resolucoes) |>
  mutate(caminho = sprintf("dados/data/rais_h3_censurada/rais_cens_%d_h3_%02d.parquet", ano, res)) |>
  pull(caminho)

df_uni_cens <- map(caminhos, read_parquet) |> bind_rows()
write_parquet(df_uni_cens, "outputs_dados/df_uni_cens.parquet")

# preparar para o tile (geometria: 1 linha por hexágono, sem atributos)
df_uni_cens_prep_tile <- df_uni_cens |>
  select(h3_address, h3_res, code_muni) |>
  unique()

write_parquet(df_uni_cens_prep_tile, "outputs_dados/df_uni_cens_prep_tile.parquet")
