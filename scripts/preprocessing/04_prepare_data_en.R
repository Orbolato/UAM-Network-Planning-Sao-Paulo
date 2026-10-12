# ============================================================================
# DATA PREPARATION SCRIPT - PORTUGUESE TO ENGLISH
# ============================================================================
# This script translates Portuguese CSV column names to English
# Reads the intermediate files in data/interim/ and writes clean,
# English-labeled inputs to data/processed/
# ============================================================================

library(readr)
library(dplyr)

cat("\n")
cat(paste(rep("=", 80), collapse=""), "\n")
cat("DATA PREPARATION: PORTUGUESE TO ENGLISH\n")
cat(paste(rep("=", 80), collapse=""), "\n\n")

# Create output directory
if (!dir.exists("data/processed")) {
  dir.create("data/processed", recursive = TRUE)
  cat("✓ Created directory: data/processed/\n\n")
} else {
  cat("✓ Directory already exists: data/processed/\n\n")
}

# ========== 1. TRANSLATE: dados_zonas_rmsp.csv ==========
cat("1. Translating zone data (dados_zonas_rmsp.csv)...\n")

zones_data <- read_csv("data/interim/dados_zonas_rmsp.csv", show_col_types = FALSE, progress = FALSE)

zones_data_en <- zones_data %>%
  rename(
    zone_id = zona,
    zone_name = nome_zona,
    population = populacao,
    households = domicilios,
    families = familias,
    jobs = empregos,
    enrollments = matriculas,
    automobiles = automoveis,
    trips_produced = viagens_produzidas,
    trips_attracted = viagens_atraidas,
    area_hectares = area_ha
  )

write_csv(zones_data_en, "data/processed/zones_data.csv")
cat("   ✓ Saved: data/processed/zones_data.csv\n")
cat(sprintf("   Columns: %s\n", paste(names(zones_data_en), collapse = ", ")))
cat(sprintf("   Records: %d\n\n", nrow(zones_data_en)))

# ========== 2. TRANSLATE: renda_per_capita_rmsp.csv ==========
cat("2. Translating income data (renda_per_capita_rmsp.csv)...\n")

income_data <- read_csv("data/interim/renda_per_capita_rmsp.csv", show_col_types = FALSE, progress = FALSE)

income_data_en <- income_data %>%
  rename(
    zone_id = zona,
    total_income = renda_total,
    average_household_income = renda_familiar_media,
    income_per_capita = renda_per_capita,
    median_household_income = renda_familiar_mediana,
    minimum_wage_ratio = renda_sm
  )

write_csv(income_data_en, "data/processed/income_per_capita.csv")
cat("   ✓ Saved: data/processed/income_per_capita.csv\n")
cat(sprintf("   Columns: %s\n", paste(names(income_data_en), collapse = ", ")))
cat(sprintf("   Records: %d\n\n", nrow(income_data_en)))

# ========== 3. TRANSLATE: helipontos_rmsp_anac.csv ==========
cat("3. Translating heliports data (helipontos_rmsp_anac.csv)...\n")

heliports_data <- read_csv("data/interim/helipontos_rmsp_anac.csv", show_col_types = FALSE, progress = FALSE)

heliports_data_en <- heliports_data %>%
  rename(
    code = codigo,
    heliport_name = name,
    heliport_type = tipo,
    latitude = lat,
    longitude = lon,
    operation_type = operacao,
    municipality = municipio
  )

write_csv(heliports_data_en, "data/processed/heliports.csv")
cat("   ✓ Saved: data/processed/heliports.csv\n")
cat(sprintf("   Columns: %s\n", paste(names(heliports_data_en), collapse = ", ")))
cat(sprintf("   Records: %d\n\n", nrow(heliports_data_en)))

cat("\n")
cat(paste(rep("=", 80), collapse=""), "\n")
cat("DATA PREPARATION COMPLETED SUCCESSFULLY!\n")
cat(paste(rep("=", 80), collapse=""), "\n\n")

cat("SUMMARY OF TRANSLATED FILES:\n")
cat("  • zones_data.csv: OD zones with socioeconomic indicators\n")
cat("  • income_per_capita.csv: Income by zone\n")
cat("  • heliports.csv: RMSP heliports locations and types\n")
cat("\nCOLUMN TRANSLATIONS:\n")
cat("  Portuguese → English\n")
cat("  ─────────────────────────────────────────────────────────────\n")
cat("  zona → zone_id\n")
cat("  nome_zona → zone_name\n")
cat("  populacao → population\n")
cat("  domicilios → households\n")
cat("  familias → families\n")
cat("  empregos → jobs\n")
cat("  matriculas → enrollments\n")
cat("  automoveis → automobiles\n")
cat("  viagens_produzidas → trips_produced\n")
cat("  viagens_atraidas → trips_attracted\n")
cat("  area_ha → area_hectares\n")
cat("  renda_total → total_income\n")
cat("  renda_familiar_media → average_household_income\n")
cat("  renda_per_capita → income_per_capita\n")
cat("  renda_familiar_mediana → median_household_income\n")
cat("  renda_sm → minimum_wage_ratio\n")
cat("  codigo → code\n")
cat("  name → heliport_name\n")
cat("  tipo → heliport_type\n")
cat("  lat → latitude\n")
cat("  lon → longitude\n")
cat("  operacao → operation_type\n")
cat("  municipio → municipality\n")
cat("\nNEXT STEPS:\n")
cat("  Run: Rscript scripts/preprocessing/05_assign_heliports_to_zones.R\n")
cat("\n")
