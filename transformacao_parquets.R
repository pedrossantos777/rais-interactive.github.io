library(arrow)
library(tidyverse)
df5 <- read_parquet("dados/rais_cens_2019_h3_05.parquet")
df7 <- read_parquet("dados/rais_cens_2019_h3_07.parquet")
df9 <- read_parquet("dados/rais_cens_2019_h3_09.parquet")

df_uni_cens <- bind_rows(df5, df7, df9)
write_parquet(df_uni_cens, "outputs_dados/df_uni_cens.parquet")

# preparar para o tile (geometria: 1 linha por hexágono, sem atributos)
df_uni_cens_prep_tile <- df_uni_cens |>
  select(h3_address, h3_res, code_muni) |>
  unique()

write_parquet(df_uni_cens_prep_tile, "outputs_dados/df_uni_cens_prep_tile.parquet")