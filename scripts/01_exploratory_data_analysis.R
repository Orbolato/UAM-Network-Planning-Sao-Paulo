# ============================================================================
# EXPLORATORY DATA ANALYSIS (EDA) - RMSP UAM PROJECT
# ============================================================================
# Script for exploratory analysis of data used in heliport clustering
# and UAM route visualization projects
# 
# Analyzes:
# 1. OD zone data 2023 (population, trips, income)
# 2. RMSP heliports
# 3. Geographic and socioeconomic distribution
# 4. Correlations between variables
# 5. Outliers and anomalies
# ============================================================================

library(sf)
library(readr)
library(dplyr)
library(tidyr)
library(ggplot2)
library(gridExtra)
library(corrplot)
library(kableExtra)
suppressWarnings(library(plotly))

rm(list = ls())

# ========== PARAMETRIC FILTERING OPTIONS ==========
PERCENTILE_TAIL <- 0  # Remove the given percentil from each tail (e.g., 0.2 = remove 20% lowest and 20% highest)
INCOME_THRESHOLD <- 2500    # Minimum income per capita (0 = no income filtering)

cat(paste(rep("=", 80), collapse=""), "\n")
cat("EXPLORATORY DATA ANALYSIS - RMSP UAM PROJECT\n")
cat(paste(rep("=", 80), collapse=""), "\n\n")

# ========== 1. LOADING DATA ==========
cat("1. LOADING DATA...\n")
cat(paste(rep("=", 50), collapse=""), "\n")

# Load shapefile of zones
zones_sf <- tryCatch({
  st_read("data/raw/od2023/shapefile/Zonas_2023.shp", quiet = TRUE)
}, error = function(e) {
  warning("Zone shapefile not found.")
  NULL
})

if (!is.null(zones_sf)) {
  zones_sf <- st_transform(zones_sf, crs = 4326)
  cat("✓ Zone shapefile loaded:", nrow(zones_sf), "zones\n")
}

# Load socioeconomic data (English translated)
zones_data <- tryCatch({
  read_csv("data/processed/zones_data.csv", show_col_types = FALSE, progress = FALSE)
}, error = function(e) {
  cat("⚠️ File data/processed/zones_data.csv not found\n")
  cat("   Please run: Rscript scripts/preprocessing/04_prepare_data_en.R\n")
  NULL
})

if (!is.null(zones_data)) {
  cat("✓ Zone data loaded:", nrow(zones_data), "records\n")
}

# Load income data (English translated)
income_data <- tryCatch({
  read_csv("data/processed/income_per_capita.csv", show_col_types = FALSE, progress = FALSE)
}, error = function(e) {
  cat("⚠️ File data/processed/income_per_capita.csv not found\n")
  cat("   Please run: Rscript scripts/preprocessing/04_prepare_data_en.R\n")
  NULL
})

if (!is.null(income_data)) {
  cat("✓ Per capita income loaded:", nrow(income_data), "records\n")
}

# Load heliports (English translated)
heliports <- tryCatch({
  read_csv("data/processed/heliports.csv", show_col_types = FALSE, progress = FALSE)
}, error = function(e) {
  cat("⚠️ File data/processed/heliports.csv not found\n")
  cat("   Please run: Rscript scripts/preprocessing/04_prepare_data_en.R\n")
  NULL
})

if (!is.null(heliports)) {
  heliports$latitude <- as.numeric(heliports$latitude)
  heliports$longitude <- as.numeric(heliports$longitude)
  heliports <- heliports[!is.na(heliports$latitude) & !is.na(heliports$longitude), ]
  cat("✓ Heliports loaded:", nrow(heliports), "records\n")
}

cat("\n")

# Merge data
if (!is.null(zones_data) && !is.null(income_data)) {
  complete_data <- zones_data %>%
    left_join(income_data[, c("zone_id", "income_per_capita")], by = "zone_id")
  cat("✓ Consolidated data:", nrow(complete_data), "zones\n")
  
  # Filter out zero income values for analysis
  complete_data <- complete_data %>%
    filter(income_per_capita > 0 | is.na(income_per_capita))
  
  cat("✓ After filtering zero income: ", nrow(complete_data), "zones\n")
  cat("  (Removed zones with zero income)\n\n")
} else {
  complete_data <- zones_data
  cat("⚠️ Some data is unavailable\n\n")
}

# ========== 2. DESCRIPTIVE STATISTICS ==========
cat("2. DESCRIPTIVE STATISTICS\n")
cat(paste(rep("=", 50), collapse=""), "\n")

if (!is.null(complete_data)) {
  cat("\nSUMMARY OF MAIN VARIABLES:\n")
  
  main_vars <- c("population", "trips_produced", "trips_attracted", 
                 "households", "jobs", "income_per_capita")
  
  for (var in main_vars) {
    if (var %in% names(complete_data)) {
      val <- complete_data[[var]]
      val <- val[!is.na(val)]
      
      var_label <- switch(var,
        "population" = "POPULATION",
        "trips_produced" = "TRIPS PRODUCED",
        "trips_attracted" = "TRIPS ATTRACTED",
        "households" = "HOUSEHOLDS",
        "jobs" = "JOBS",
        "income_per_capita" = "INCOME PER CAPITA",
        var)
      
      cat("\n", var_label, ":\n")
      cat("  Total:         ", format(sum(val, na.rm=TRUE), big.mark=","), "\n")
      cat("  Mean:          ", format(round(mean(val, na.rm=TRUE), 2), big.mark=","), "\n")
      cat("  Median:        ", format(round(median(val, na.rm=TRUE), 2), big.mark=","), "\n")
      cat("  Std Dev:       ", format(round(sd(val, na.rm=TRUE), 2), big.mark=","), "\n")
      cat("  Min:           ", format(min(val, na.rm=TRUE), big.mark=","), "\n")
      cat("  Max:           ", format(max(val, na.rm=TRUE), big.mark=","), "\n")
      cat("  Q1 (25%):      ", format(round(quantile(val, 0.25, na.rm=TRUE), 2), big.mark=","), "\n")
      cat("  Q3 (75%):      ", format(round(quantile(val, 0.75, na.rm=TRUE), 2), big.mark=","), "\n")
      cat("  P5:            ", format(round(quantile(val, 0.05, na.rm=TRUE), 2), big.mark=","), "\n")
      cat("  P95:           ", format(round(quantile(val, 0.95, na.rm=TRUE), 2), big.mark=","), "\n")
      cat("  NA Count:      ", sum(is.na(val)), "\n")
    }
  }
}

cat("\n")

# ========== 3. DATA QUALITY ANALYSIS ==========
cat("3. DATA QUALITY ANALYSIS\n")
cat(paste(rep("=", 50), collapse=""), "\n")

if (!is.null(complete_data)) {
  cat("\nCOVERAGE AND MISSING VALUES:\n")
  
  for (var in main_vars) {
    if (var %in% names(complete_data)) {
      total <- nrow(complete_data)
      na_count <- sum(is.na(complete_data[[var]]))
      coverage <- (total - na_count) / total * 100
      
      cat(sprintf("  %25s: %3.1f%% complete (%d missing)\n", 
                  var, coverage, na_count))
    }
  }
  
  # Check zero values
  cat("\nZERO VALUES (Potentially Valid Data):\n")
  
  for (var in c("population", "trips_produced", "trips_attracted", "jobs")) {
    if (var %in% names(complete_data)) {
      zero_count <- sum(complete_data[[var]] == 0, na.rm=TRUE)
      zero_pct <- zero_count / sum(!is.na(complete_data[[var]])) * 100
      
      cat(sprintf("  %25s: %d zones (%.1f%%)\n", 
                  var, zero_count, zero_pct))
    }
  }
}

cat("\n")

# ========== 4. PARAMETRIC PERCENTILE-INCOME FILTERING ==========
cat("4. PARAMETRIC FILTERING ANALYSIS\n")
cat(paste(rep("=", 50), collapse=""), "\n")

if (!is.null(complete_data)) {
  # Step 1: Validation (remove residencials with zero trips)
  valid_zones <- complete_data %>%
    filter(!is.na(income_per_capita), income_per_capita > 0,
           !is.na(trips_produced), trips_produced > 0)
  
  cat("\nZones after validation (excluding zero-trip residentials):\n")
  cat(sprintf("  Original: %d zones\n", nrow(complete_data)))
  cat(sprintf("  After validation: %d zones\n", nrow(valid_zones)))
  cat(sprintf("  Removed: %d zones (%.1f%%)\n\n", 
              nrow(complete_data) - nrow(valid_zones),
              (nrow(complete_data) - nrow(valid_zones)) / nrow(complete_data) * 100))
  
  # Step 2: Apply percentile filtering
  p_low <- PERCENTILE_TAIL
  p_high <- 1 - PERCENTILE_TAIL
  
  cat(sprintf("PERCENTILE_TAIL = %.2f (removing %.1f%% from each tail)\n", PERCENTILE_TAIL, PERCENTILE_TAIL*100))
  cat(sprintf("Filter range: P%.1f to P%.1f (keeping middle %.1f%% of data)\n\n", 
              p_low*100, p_high*100, (p_high-p_low)*100))
  
  income_p_low <- quantile(valid_zones$income_per_capita, p_low, na.rm = TRUE)
  income_p_high <- quantile(valid_zones$income_per_capita, p_high, na.rm = TRUE)
  trips_p_low <- quantile(valid_zones$trips_produced, p_low, na.rm = TRUE)
  trips_p_high <- quantile(valid_zones$trips_produced, p_high, na.rm = TRUE)
  pop_p_low <- quantile(valid_zones$population, p_low, na.rm = TRUE)
  pop_p_high <- quantile(valid_zones$population, p_high, na.rm = TRUE)
  
  percentile_zones <- valid_zones %>%
    filter(income_per_capita >= income_p_low, income_per_capita <= income_p_high,
           trips_produced >= trips_p_low, trips_produced <= trips_p_high,
           population >= pop_p_low, population <= pop_p_high)
  
  cat(sprintf("ACTUAL Percentile limits (P%.1f to P%.1f):\n", p_low*100, p_high*100))
  cat(sprintf("  Income: R$ %.2f - R$ %.2f\n", income_p_low, income_p_high))
  cat(sprintf("  Trips: %.0f - %.0f\n", trips_p_low, trips_p_high))
  cat(sprintf("  Population: %.0f - %.0f\n\n", pop_p_low, pop_p_high))
  
  # Step 3: Apply income threshold (if specified)
  if (INCOME_THRESHOLD > 0) {
    filtered_zones <- percentile_zones %>%
      filter(income_per_capita >= INCOME_THRESHOLD)
    
    cat(sprintf("Income threshold: R$ %.2f\n\n", INCOME_THRESHOLD))
  } else {
    filtered_zones <- percentile_zones
  }
  
  cat("Zones after filtering:\n")
  cat(sprintf("  Valid zones (before percentile filter): %d\n", nrow(valid_zones)))
  cat(sprintf("  After percentile filter: %d zones\n", nrow(percentile_zones)))
  cat(sprintf("  Percentile filter removed: %d zones (%.1f%%)\n", 
              nrow(valid_zones) - nrow(percentile_zones),
              (nrow(valid_zones) - nrow(percentile_zones)) / nrow(valid_zones) * 100))
  
  if (INCOME_THRESHOLD > 0) {
    cat(sprintf("  After income threshold (R$ %.2f): %d zones\n", INCOME_THRESHOLD, nrow(filtered_zones)))
    cat(sprintf("  Income threshold removed: %d zones (%.1f%%)\n", 
                nrow(percentile_zones) - nrow(filtered_zones),
                (nrow(percentile_zones) - nrow(filtered_zones)) / nrow(percentile_zones) * 100))
  }
  
  cat(sprintf("  FINAL RESULT: %d zones retained (%.1f%% of valid zones)\n", 
              nrow(filtered_zones),
              nrow(filtered_zones) / nrow(valid_zones) * 100))
}

cat("\n")

# ========== 5. CORRELATION ANALYSIS ==========
cat("5. CORRELATION ANALYSIS\n")
cat(paste(rep("=", 50), collapse=""), "\n")

if (!is.null(complete_data)) {
  # Select only numeric variables
  numeric_vars <- c("population", "trips_produced", "trips_attracted", 
                    "households", "jobs", "income_per_capita")
  
  cor_data <- complete_data %>%
    select(all_of(numeric_vars)) %>%
    filter(complete.cases(.))
  
  if (nrow(cor_data) > 0) {
    cor_matrix <- cor(cor_data, use = "complete.obs")
    
    cat("\nCORRELATION MATRIX (Pearson):\n")
    print(round(cor_matrix, 3))
    
    cat("\n\nCORRELATIONS WITH INCOME PER CAPITA:\n")
    if ("income_per_capita" %in% colnames(cor_matrix)) {
      income_cors <- cor_matrix["income_per_capita", ]
      income_cors <- sort(income_cors[income_cors != 1.000], decreasing = TRUE)
      
      for (var in names(income_cors)) {
        cor_val <- income_cors[var]
        strength <- ifelse(abs(cor_val) > 0.7, "Strong", 
                          ifelse(abs(cor_val) > 0.4, "Moderate", "Weak"))
        direction <- ifelse(cor_val > 0, "positive", "negative")
        
        cat(sprintf("  %25s: %7.3f (%s %s)\n", var, cor_val, strength, direction))
      }
    }
  }
}

cat("\n")

# ========== 6. HELIPORT DISTRIBUTION ==========
cat("6. HELIPORT ANALYSIS\n")
cat(paste(rep("=", 50), collapse=""), "\n")

if (!is.null(heliports)) {
  cat("\nHELIPORT DISTRIBUTION:\n")
  cat(sprintf("  Total heliports: %d\n", nrow(heliports)))
  
  if ("heliport_type" %in% names(heliports)) {
    cat("\n  By Type:\n")
    type_dist <- heliports %>%
      group_by(heliport_type) %>%
      summarise(count = n(), .groups = 'drop') %>%
      arrange(desc(count))
    
    for (i in 1:nrow(type_dist)) {
      pct <- type_dist$count[i] / nrow(heliports) * 100
      cat(sprintf("    %-30s: %3d (%.1f%%)\n", 
                  type_dist$heliport_type[i], type_dist$count[i], pct))
    }
  }
  
  if ("municipality" %in% names(heliports)) {
    cat("\n  Top 10 Municipalities with most heliports:\n")
    mun_dist <- heliports %>%
      group_by(municipality) %>%
      summarise(count = n(), .groups = 'drop') %>%
      arrange(desc(count)) %>%
      head(10)
    
    for (i in 1:nrow(mun_dist)) {
      pct <- mun_dist$count[i] / nrow(heliports) * 100
      cat(sprintf("    %-30s: %3d (%.1f%%)\n", 
                  mun_dist$municipality[i], mun_dist$count[i], pct))
    }
  }
  
  if ("operation_type" %in% names(heliports)) {
    cat("\n  By Operation Type:\n")
    op_dist <- heliports %>%
      group_by(operation_type) %>%
      summarise(count = n(), .groups = 'drop') %>%
      arrange(desc(count))
    
    for (i in 1:nrow(op_dist)) {
      pct <- op_dist$count[i] / nrow(heliports) * 100
      cat(sprintf("    %-30s: %3d (%.1f%%)\n", 
                  op_dist$operation_type[i], op_dist$count[i], pct))
    }
  }
}

cat("\n")

# ========== 7. GEOGRAPHIC ANALYSIS ==========
cat("7. GEOGRAPHIC ANALYSIS\n")
cat(paste(rep("=", 50), collapse=""), "\n")

if (!is.null(zones_sf) && !is.null(complete_data)) {
  cat("\nGEOGRAPHIC EXTENT:\n")
  
  # Calculate bounding box
  bbox <- st_bbox(zones_sf)
  cat(sprintf("  Latitude:  %.4f° to %.4f° (Δ %.4f°)\n", bbox["ymin"], bbox["ymax"], bbox["ymax"] - bbox["ymin"]))
  cat(sprintf("  Longitude: %.4f° to %.4f° (Δ %.4f°)\n", bbox["xmin"], bbox["xmax"], bbox["xmax"] - bbox["xmin"]))
  
  # Calculate total area
  zones_sf_utm <- st_transform(zones_sf, 31983)
  total_area <- sum(st_area(zones_sf_utm)) / 1e6  # Convert to km²
  cat(sprintf("  Total area: %.2f km²\n", total_area))
  
  # Calculate population density
  if ("population" %in% names(complete_data)) {
    total_pop <- sum(complete_data$population, na.rm=TRUE)
    density <- total_pop / total_area
    cat(sprintf("  Total population: %s\n", format(total_pop, big.mark=",", scientific=FALSE)))
    cat(sprintf("  Population density: %.1f inhab/km²\n", density))
  }
}

if (!is.null(heliports)) {
  cat("\nHELIPORT DISTRIBUTION:\n")
  
  # Bounding box of heliports
  lat_range <- range(heliports$latitude, na.rm=TRUE)
  lon_range <- range(heliports$longitude, na.rm=TRUE)
  
  cat(sprintf("  Latitude:  %.4f° to %.4f°\n", lat_range[1], lat_range[2]))
  cat(sprintf("  Longitude: %.4f° to %.4f°\n", lon_range[1], lon_range[2]))
}

cat("\n")

# ========== 8. TRAVEL DEMAND ANALYSIS ==========
cat("8. OD TRAVEL ANALYSIS\n")
cat(paste(rep("=", 50), collapse=""), "\n")

if (!is.null(complete_data)) {
  cat("\nTRAVEL DEMAND:\n")
  
  trips_prod_total <- sum(complete_data$trips_produced, na.rm=TRUE)
  trips_attr_total <- sum(complete_data$trips_attracted, na.rm=TRUE)
  
  cat(sprintf("  Trips Produced: %s/day\n", 
              format(round(trips_prod_total), big.mark=",", scientific=FALSE)))
  cat(sprintf("  Trips Attracted: %s/day\n", 
              format(round(trips_attr_total), big.mark=",", scientific=FALSE)))
  
  # Zones with highest demand
  cat("\n  Top 10 zones with highest demand (trips produced):\n")
  
  top_zones <- complete_data %>%
    arrange(desc(trips_produced)) %>%
    head(10)
  
  for (i in 1:nrow(top_zones)) {
    pct <- top_zones$trips_produced[i] / trips_prod_total * 100
    cat(sprintf("    Zone %3d: %7s trips (%.2f%%)\n", 
                top_zones$zone_id[i],
                format(round(top_zones$trips_produced[i]), big.mark=","),
                pct))
  }
  
  # Trip concentration
  top_pct <- top_zones %>%
    mutate(pct = trips_produced / trips_prod_total * 100) %>%
    slice(1:10) %>%
    summarise(total_pct = sum(pct)) %>%
    pull(total_pct)
  
  cat(sprintf("\n  Top 10 zones represent %.1f%% of total trips\n", top_pct))
}

cat("\n")

# ========== 9. ECONOMIC ANALYSIS ==========
cat("9. ECONOMIC ANALYSIS\n")
cat(paste(rep("=", 50), collapse=""), "\n")

if (!is.null(complete_data) && "income_per_capita" %in% names(complete_data)) {
  cat("\nINCOME PER CAPITA (Valid zones, zero values excluded):\n")
  
  valid_income <- complete_data$income_per_capita[!is.na(complete_data$income_per_capita) & 
                                                 complete_data$income_per_capita > 0]
  
  cat(sprintf("  Zones with valid income: %d (%.1f%%)\n", 
              length(valid_income), 
              length(valid_income) / nrow(complete_data) * 100))
  cat(sprintf("  Mean income: R$ %s\n", 
              format(round(mean(valid_income, na.rm=TRUE)), big.mark=",", decimal.mark=".")))
  cat(sprintf("  Median income: R$ %s\n", 
              format(round(median(valid_income, na.rm=TRUE)), big.mark=",", decimal.mark=".")))
  cat(sprintf("  Std Dev: R$ %s\n", 
              format(round(sd(valid_income, na.rm=TRUE)), big.mark=",", decimal.mark=".")))
  cat(sprintf("  Min income: R$ %s\n", 
              format(round(min(valid_income, na.rm=TRUE)), big.mark=",", decimal.mark=".")))
  cat(sprintf("  Max income: R$ %s\n", 
              format(round(max(valid_income, na.rm=TRUE)), big.mark=",", decimal.mark=".")))
  
  # Income inequality
  income_sorted <- sort(valid_income)
  income_top10 <- sum(income_sorted[(length(income_sorted)*0.9):length(income_sorted)]) / sum(valid_income) * 100
  income_bottom10 <- sum(income_sorted[1:(length(income_sorted)*0.1)]) / sum(valid_income) * 100
  
  cat(sprintf("  Top 10%% of zones: %.1f%% of total income\n", income_top10))
  cat(sprintf("  Bottom 10%% of zones: %.1f%% of total income\n", income_bottom10))
  cat(sprintf("  Top/Bottom ratio: %.1fx\n", income_top10 / income_bottom10))
  
  # By decile
  cat("\n  Distribution by income decile:\n")
  deciles <- quantile(valid_income, seq(0, 1, 0.1), na.rm=TRUE)
  
  for (i in 1:(length(deciles)-1)) {
    zones_decile <- sum(valid_income >= deciles[i] & valid_income < deciles[i+1])
    trips_decile <- sum(complete_data$trips_produced[
      valid_income >= deciles[i] & valid_income < deciles[i+1]], na.rm=TRUE)
    
    cat(sprintf("    Decile %d (R$ %.0f - R$ %.0f): %d zones, %.0f trips\n",
                i, deciles[i], deciles[i+1], zones_decile, trips_decile))
  }
}

cat("\n")

# ========== 10. EMPLOYMENT ANALYSIS ==========
cat("10. EMPLOYMENT ANALYSIS\n")
cat(paste(rep("=", 50), collapse=""), "\n")

if (!is.null(complete_data) && "jobs" %in% names(complete_data)) {
  cat("\nEMPLOYMENT:\n")
  
  valid_jobs <- complete_data$jobs[!is.na(complete_data$jobs) & 
                                       complete_data$jobs > 0]
  
  cat(sprintf("  Total jobs: %s\n", 
              format(sum(valid_jobs), big.mark=",", scientific=FALSE)))
  cat(sprintf("  Zones with jobs: %d (%.1f%%)\n",
              length(valid_jobs),
              length(valid_jobs) / nrow(complete_data) * 100))
  
  # Job concentration
  jobs_sorted <- sort(valid_jobs, decreasing=TRUE)
  jobs_top_10_pct <- sum(jobs_sorted[1:(length(jobs_sorted)*0.1)]) / sum(valid_jobs) * 100
  
  cat(sprintf("  Top 10%% of zones: %.1f%% of total jobs\n", jobs_top_10_pct))
}

cat("\n")

# ========== 11. EXECUTIVE SUMMARY ==========
cat("11. EXECUTIVE SUMMARY\n")
cat(paste(rep("=", 50), collapse=""), "\n")

if (!is.null(complete_data) && !is.null(heliports)) {
  cat("\nPROJECT CHARACTERISTICS:\n\n")
  
  cat("GEOGRAPHIC COVERAGE:\n")
  cat(sprintf("  - %d OD research zones (2023)\n", nrow(complete_data)))
  cat(sprintf("  - %d mapped heliports\n", nrow(heliports)))
  
  if (exists("total_area")) {
    heliport_density <- nrow(heliports) / (total_area / 100)
    cat(sprintf("  - Density: %.1f heliports per 100 km²\n", heliport_density))
  }
  
  cat("\nDEMAND:\n")
  if ("trips_produced" %in% names(complete_data)) {
    total_trips <- sum(complete_data$trips_produced, na.rm=TRUE)
    cat(sprintf("  - %s trips/day (2023 OD)\n", 
                format(round(total_trips), big.mark=",", scientific=FALSE)))
  }
  
  cat("\nDATA QUALITY:\n")
  
  # Calculate average quality
  vars_check <- c("population", "trips_produced", "trips_attracted", 
                  "income_per_capita", "jobs")
  
  coverage_scores <- c()
  for (var in vars_check) {
    if (var %in% names(complete_data)) {
      coverage <- sum(!is.na(complete_data[[var]])) / nrow(complete_data) * 100
      coverage_scores <- c(coverage_scores, coverage)
    }
  }
  
  avg_coverage <- mean(coverage_scores)
  cat(sprintf("  - Average data coverage: %.1f%%\n", avg_coverage))
  cat(sprintf("  - Variables analyzed: %d\n", length(coverage_scores)))
  
  cat("\n")
}

# ========== 12. RECOMMENDATIONS ==========
cat("12. RECOMMENDATIONS\n")
cat(paste(rep("=", 50), collapse=""), "\n")

cat("\n- Use P5-P95 filter to remove extreme outliers\n")
cat("- Validate income per capita data (35 zones with missing data)\n")
cat("- Consider imputation for residential zones with zero trips\n")
cat("- Heliports well distributed geographically\n")
cat("- Demand concentrated in high-income and employment zones\n")
cat("- K-medoids (PAM) appropriate for identifying vertiports\n")

cat("\n")
cat(paste(rep("=", 80), collapse=""), "\n")
cat("ANALYSIS COMPLETED SUCCESSFULLY!\n")
cat(paste(rep("=", 80), collapse=""), "\n\n")

# ========== 13. EXPORTING LATEX TABLES AND VISUALIZATIONS ==========
cat("13. GENERATING LATEX TABLES AND VISUALIZATIONS...\n")
cat(paste(rep("=", 50), collapse=""), "\n\n")

# Create output directories if they don't exist
if (!dir.exists("output/eda_tables")) {
  dir.create("output/eda_tables", recursive = TRUE)
}

if (!dir.exists("output/eda_figures")) {
  dir.create("output/eda_figures", recursive = TRUE)
}

# ===== TABLE 1: Descriptive Statistics =====
if (!is.null(complete_data)) {
  numeric_vars <- c("population", "trips_produced", "trips_attracted", 
                    "households", "jobs", "income_per_capita")
  
  stats_df <- data.frame()
  
  for (var in numeric_vars) {
    if (var %in% names(complete_data)) {
      val <- complete_data[[var]][!is.na(complete_data[[var]])]
      
      stats_df <- rbind(stats_df, data.frame(
        Variable = var,
        Mean = round(mean(val), 2),
        Median = round(median(val), 2),
        SD = round(sd(val), 2),
        Min = round(min(val), 2),
        Max = round(max(val), 2),
        Q1 = round(quantile(val, 0.25), 2),
        Q3 = round(quantile(val, 0.75), 2),
        P5 = round(quantile(val, 0.05), 2),
        P95 = round(quantile(val, 0.95), 2)
      ))
    }
  }
  
  # Save as LaTeX
  latex_table1 <- knitr::kable(stats_df, format = "latex", booktabs = TRUE,
                               caption = "Descriptive Statistics of Main Variables")
  writeLines(as.character(latex_table1), "output/eda_tables/01_descriptive_statistics.tex")
  cat("✓ Table 1 saved: output/eda_tables/01_descriptive_statistics.tex\n")
}

# ===== TABLE 2: Data Quality =====
if (!is.null(complete_data)) {
  quality_df <- data.frame()
  
  for (var in numeric_vars) {
    if (var %in% names(complete_data)) {
      total <- nrow(complete_data)
      na_count <- sum(is.na(complete_data[[var]]))
      coverage <- (total - na_count) / total * 100
      zero_count <- sum(complete_data[[var]] == 0, na.rm=TRUE)
      
      quality_df <- rbind(quality_df, data.frame(
        Variable = var,
        Total = total,
        Missing = na_count,
        Coverage_Pct = round(coverage, 1),
        Zero_Count = zero_count,
        Zero_Pct = round(zero_count / sum(!is.na(complete_data[[var]])) * 100, 1)
      ))
    }
  }
  
  latex_table2 <- knitr::kable(quality_df, format = "latex", booktabs = TRUE,
                               caption = "Data Quality Analysis")
  writeLines(as.character(latex_table2), "output/eda_tables/02_data_quality.tex")
  cat("✓ Table 2 saved: output/eda_tables/02_data_quality.tex\n")
}

# ===== TABLE 3: Filtering Impact =====
if (!is.null(complete_data)) {
  valid_zones <- complete_data %>%
    filter(!is.na(income_per_capita), income_per_capita > 0,
           !is.na(trips_produced), trips_produced > 0)
  
  income_p05 <- quantile(valid_zones$income_per_capita, 0.05, na.rm = TRUE)
  income_p95 <- quantile(valid_zones$income_per_capita, 0.95, na.rm = TRUE)
  trips_p05 <- quantile(valid_zones$trips_produced, 0.05, na.rm = TRUE)
  trips_p95 <- quantile(valid_zones$trips_produced, 0.95, na.rm = TRUE)
  # Use PERCENTILE_TAIL parameter instead of hardcoded 0.05
  p_low_table <- PERCENTILE_TAIL
  p_high_table <- 1 - PERCENTILE_TAIL
  
  income_p_low_table <- quantile(valid_zones$income_per_capita, p_low_table, na.rm = TRUE)
  income_p_high_table <- quantile(valid_zones$income_per_capita, p_high_table, na.rm = TRUE)
  trips_p_low_table <- quantile(valid_zones$trips_produced, p_low_table, na.rm = TRUE)
  trips_p_high_table <- quantile(valid_zones$trips_produced, p_high_table, na.rm = TRUE)
  pop_p_low_table <- quantile(valid_zones$population, p_low_table, na.rm = TRUE)
  pop_p_high_table <- quantile(valid_zones$population, p_high_table, na.rm = TRUE)
  
  percentile_filtered <- valid_zones %>%
    filter(income_per_capita >= income_p_low_table, income_per_capita <= income_p_high_table,
           trips_produced >= trips_p_low_table, trips_produced <= trips_p_high_table,
           population >= pop_p_low_table, population <= pop_p_high_table)
  
  # Apply income threshold if specified
  filtered_zones_final <- percentile_filtered
  if (INCOME_THRESHOLD > 0) {
    filtered_zones_final <- percentile_filtered %>%
      filter(income_per_capita >= INCOME_THRESHOLD)
  }
  
  filter_df <- data.frame(
    Stage = c("Original", "After Validation", "After Percentile Filter", "After Income Threshold"),
    Zones = c(nrow(complete_data), nrow(valid_zones), nrow(percentile_filtered), nrow(filtered_zones_final)),
    Removed = c(0, nrow(complete_data) - nrow(valid_zones), 
                nrow(valid_zones) - nrow(percentile_filtered),
                nrow(percentile_filtered) - nrow(filtered_zones_final)),
    Pct_Removed = c(0, 
                    round((nrow(complete_data) - nrow(valid_zones)) / nrow(complete_data) * 100, 1),
                    round((nrow(valid_zones) - nrow(percentile_filtered)) / nrow(valid_zones) * 100, 1),
                    round((nrow(percentile_filtered) - nrow(filtered_zones_final)) / nrow(percentile_filtered) * 100, 1))
  )
  
  latex_table3 <- knitr::kable(filter_df, format = "latex", booktabs = TRUE,
                               caption = "Impact of Validation Filtering")
  writeLines(as.character(latex_table3), "output/eda_tables/03_filtering_impact.tex")
  cat("✓ Table 3 saved: output/eda_tables/03_filtering_impact.tex\n")
}

# ===== TABLE 4: Top 10 Zones by Demand =====
if (!is.null(complete_data)) {
  top_10 <- complete_data %>%
    arrange(desc(trips_produced)) %>%
    head(10) %>%
    select(zone_id, population, trips_produced, trips_attracted, income_per_capita)
  
  colnames(top_10) <- c("Zone ID", "Population", "Trips Produced", "Trips Attracted", "Income Per Capita")
  
  latex_table4 <- knitr::kable(top_10, format = "latex", booktabs = TRUE,
                               caption = "Top 10 Zones with Highest Travel Demand")
  writeLines(as.character(latex_table4), "output/eda_tables/04_top_10_zones.tex")
  cat("✓ Table 4 saved: output/eda_tables/04_top_10_zones.tex\n")
}

# ===== TABLE 5: Heliport Distribution =====
if (!is.null(heliports)) {
  if ("heliport_type" %in% names(heliports)) {
    type_summary <- heliports %>%
      group_by(heliport_type) %>%
      summarise(Count = n(), .groups = 'drop') %>%
      mutate(Percentage = round(Count / sum(Count) * 100, 1)) %>%
      arrange(desc(Count))
    
    colnames(type_summary) <- c("Heliport Type", "Count", "Percentage")
    
    latex_table5 <- knitr::kable(type_summary, format = "latex", booktabs = TRUE,
                                 caption = "Heliport Distribution by Type")
    writeLines(as.character(latex_table5), "output/eda_tables/05_heliport_distribution.tex")
    cat("✓ Table 5 saved: output/eda_tables/05_heliport_distribution.tex\n")
  }
}

cat("\n")

# ========== 14. GENERATE VISUALIZATIONS ==========
cat("14. GENERATING GRAPHS...\n")
cat(paste(rep("=", 50), collapse=""), "\n")

if (!is.null(complete_data)) {
  
  # ===== GRAPH 1: Income Distribution =====
  p1 <- ggplot(complete_data, aes(x = income_per_capita)) +
    geom_histogram(bins = 30, fill = "#2E86AB", color = "white", alpha = 0.8) +
    labs(title = "Income Distribution per Capita",
         x = "Per Capita Income (R$)",
         y = "Number of Zones") +
    theme_minimal() +
    theme(plot.title = element_text(hjust = 0.5, face = "bold", size = 12))
  
  ggsave("output/eda_figures/01_income_distribution.pdf", p1, width = 8, height = 6)
  cat("✓ Graph 1 saved: output/eda_figures/01_income_distribution.pdf\n")
  
  # ===== GRAPH 2: Population Distribution =====
  data_pop <- complete_data %>% filter(population > 0)
  p2 <- ggplot(data_pop, aes(x = population)) +
    geom_histogram(bins = 30, fill = "#A23B72", color = "white", alpha = 0.8) +
    labs(title = "Population Distribution",
         x = "Population",
         y = "Number of Zones") +
    scale_x_log10() +
    theme_minimal() +
    theme(plot.title = element_text(hjust = 0.5, face = "bold", size = 12))
  
  ggsave("output/eda_figures/02_population_distribution.pdf", p2, width = 8, height = 6)
  cat("✓ Graph 2 saved: output/eda_figures/02_population_distribution.pdf\n")
  
  # ===== GRAPH 3: Trips Produced Distribution =====
  data_trips <- complete_data %>% filter(trips_produced > 0)
  p3 <- ggplot(data_trips, aes(x = trips_produced)) +
    geom_histogram(bins = 30, fill = "#F18F01", color = "white", alpha = 0.8) +
    labs(title = "Distribution of Trips Produced",
         x = "Trips Produced",
         y = "Number of Zones") +
    scale_x_log10() +
    theme_minimal() +
    theme(plot.title = element_text(hjust = 0.5, face = "bold", size = 12))
  
  ggsave("output/eda_figures/03_trips_produced_distribution.pdf", p3, width = 8, height = 6)
  cat("✓ Graph 3 saved: output/eda_figures/03_trips_produced_distribution.pdf\n")
  
  # ===== GRAPH 4: Income vs Trips Scatter =====
  data_scatter <- complete_data %>% filter(trips_produced > 0, !is.na(income_per_capita), income_per_capita > 0)
  p4 <- ggplot(data_scatter, aes(x = income_per_capita, y = trips_produced)) +
    geom_point(alpha = 0.5, color = "#2E86AB", size = 2) +
    geom_smooth(method = "lm", se = TRUE, color = "#F18F01", alpha = 0.2) +
    labs(title = "Relationship between Income and Trips Produced",
         x = "Per Capita Income (R$)",
         y = "Trips Produced") +
    scale_y_log10() +
    theme_minimal() +
    theme(plot.title = element_text(hjust = 0.5, face = "bold", size = 12))
  
  ggsave("output/eda_figures/04_income_vs_trips.pdf", p4, width = 8, height = 6)
  cat("✓ Graph 4 saved: output/eda_figures/04_income_vs_trips.pdf\n")
  
  # ===== GRAPH 5: Variable Comparison Box Plot =====
  data_for_scale <- complete_data %>%
    select(population, trips_produced, trips_attracted, jobs) %>%
    filter(complete.cases(.))
  
  data_scaled <- scale(data_for_scale) %>%
    as.data.frame()
  
  data_melted <- data_scaled %>%
    pivot_longer(everything(), names_to = "Variable", values_to = "Standardized_Value") %>%
    filter(!is.infinite(Standardized_Value), !is.na(Standardized_Value))
  
  p5 <- ggplot(data_melted, aes(x = Variable, y = Standardized_Value, fill = Variable)) +
    geom_boxplot(alpha = 0.7) +
    labs(title = "Variable Comparison (Standardized Values)",
         x = "Variable",
         y = "Standardized Value") +
    theme_minimal() +
    theme(plot.title = element_text(hjust = 0.5, face = "bold", size = 12),
          legend.position = "none",
          axis.text.x = element_text(angle = 45, hjust = 1))
  
  ggsave("output/eda_figures/05_boxplot_comparison.pdf", p5, width = 10, height = 6)
  cat("✓ Graph 5 saved: output/eda_figures/05_boxplot_comparison.pdf\n")
  
  # ===== GRAPH 6: Correlation Matrix =====
  vars_cor <- c("population", "trips_produced", "trips_attracted", 
                "households", "jobs", "income_per_capita")
  cor_data <- complete_data %>%
    select(all_of(vars_cor)) %>%
    filter(complete.cases(.))
  
  cor_matrix <- cor(cor_data)
  
  # Close any open graphics devices first
  tryCatch({
    if (!is.null(dev.list())) { dev.off() }
  }, error = function(e) { NULL })
  
  pdf("output/eda_figures/06_correlation_matrix.pdf", width = 10, height = 9)
  corrplot(cor_matrix, method = "circle", type = "upper", diag = TRUE,
           tl.col = "black", tl.srt = 45, addCoef.col = "black", number.cex = 0.8)
  dev.off()
  cat("✓ Graph 6 saved: output/eda_figures/06_correlation_matrix.pdf\n")
  
  # ===== GRAPH 7: Income Deciles =====
  valid_income <- complete_data$income_per_capita[!is.na(complete_data$income_per_capita) & 
                                                 complete_data$income_per_capita > 0]
  deciles <- quantile(valid_income, seq(0, 1, 0.1), na.rm=TRUE)
  
  decile_data <- data.frame()
  for (i in 1:(length(deciles)-1)) {
    zones_decile <- sum(valid_income >= deciles[i] & valid_income < deciles[i+1])
    trips_decile <- sum(complete_data$trips_produced[
      valid_income >= deciles[i] & valid_income < deciles[i+1]], na.rm=TRUE)
    
    decile_data <- rbind(decile_data, data.frame(
      Decile = paste0("D", i),
      Zones = zones_decile,
      Trips = trips_decile
    ))
  }
  
  p7 <- ggplot(decile_data, aes(x = Decile, y = Zones)) +
    geom_bar(stat = "identity", fill = "#2E86AB", alpha = 0.8) +
    geom_line(aes(y = Trips/50, group = 1), color = "#F18F01", linewidth = 1.2) +
    scale_y_continuous(
      name = "Number of Zones",
      sec.axis = sec_axis(~.*50, name = "Trips Produced")
    ) +
    labs(title = "Distribution by Income Decile",
         x = "Decile") +
    theme_minimal() +
    theme(plot.title = element_text(hjust = 0.5, face = "bold", size = 12))
  
  ggsave("output/eda_figures/07_income_deciles.pdf", p7, width = 10, height = 6)
  cat("✓ Graph 7 saved: output/eda_figures/07_income_deciles.pdf\n")
  
  # ===== GRAPH 8: Filter Impact =====
  if (INCOME_THRESHOLD > 0) {
    filter_data_graph <- data.frame(
      Stage = factor(c("Original", "After Validation", "After Percentile", "After Income Threshold"), 
                     levels = c("Original", "After Validation", "After Percentile", "After Income Threshold")),
      Zones = c(nrow(complete_data), nrow(valid_zones), nrow(percentile_filtered), nrow(filtered_zones_final))
    )
  } else {
    filter_data_graph <- data.frame(
      Stage = factor(c("Original", "After Validation", "After Percentile Filter"), 
                     levels = c("Original", "After Validation", "After Percentile Filter")),
      Zones = c(nrow(complete_data), nrow(valid_zones), nrow(percentile_filtered))
    )
  }
  
  p8 <- ggplot(filter_data_graph, aes(x = Stage, y = Zones, fill = Stage)) +
    geom_bar(stat = "identity", alpha = 0.8) +
    geom_text(aes(label = Zones), vjust = -0.5, size = 5, fontface = "bold") +
    labs(title = "Impact of Validation Filtering",
         x = "Filtering Stage",
         y = "Number of Zones") +
    theme_minimal() +
    theme(plot.title = element_text(hjust = 0.5, face = "bold", size = 12),
          legend.position = "none",
          axis.text.x = element_text(angle = 45, hjust = 1))
  
  ggsave("output/eda_figures/08_filtering_impact.pdf", p8, width = 8, height = 6)
  cat("✓ Graph 8 saved: output/eda_figures/08_filtering_impact.pdf\n")
}

# ===== GRAPH 9: Geographic Distribution of Heliports =====
if (!is.null(heliports)) {
  # Translate heliport types to English
  heliports_translated <- heliports %>%
    mutate(heliport_type_en = recode(heliport_type,
      "Público" = "Public",
      "Privado" = "Private",
      "Militar" = "Military",
      "No solo" = "Ground Level",
      "Elevado" = "Elevated",
      .default = heliport_type))
  
  p9 <- ggplot(heliports_translated, aes(x = longitude, y = latitude, color = heliport_type_en)) +
    geom_point(size = 3, alpha = 0.7) +
    labs(title = "Geographic Distribution of Heliports in RMSP",
         x = "Longitude",
         y = "Latitude",
         color = "Heliport Type") +
    theme_minimal() +
    theme(plot.title = element_text(hjust = 0.5, face = "bold", size = 12))
  
  ggsave("output/eda_figures/09_heliport_geographic_distribution.pdf", p9, width = 10, height = 8)
  cat("✓ Graph 9 saved: output/eda_figures/09_heliport_geographic_distribution.pdf\n")
}

# ===== GRAPH 10: Top Municipalities with Heliports =====
if (!is.null(heliports) && "municipality" %in% names(heliports)) {
  municipio_top <- heliports %>%
    group_by(municipality) %>%
    summarise(count = n(), .groups = 'drop') %>%
    arrange(desc(count)) %>%
    head(10)
  
  p10 <- ggplot(municipio_top, aes(x = reorder(municipality, count), y = count, fill = municipality)) +
    geom_bar(stat = "identity", alpha = 0.8) +
    geom_text(aes(label = count), hjust = -0.2, size = 4) +
    labs(title = "Top 10 Municipalities with Most Heliports",
         x = "Municipality",
         y = "Number of Heliports") +
    coord_flip() +
    theme_minimal() +
    theme(plot.title = element_text(hjust = 0.5, face = "bold", size = 12),
          legend.position = "none")
  
  ggsave("output/eda_figures/10_top_municipalities.pdf", p10, width = 10, height = 7)
  cat("✓ Graph 10 saved: output/eda_figures/10_top_municipalities.pdf\n")
}

# ===== GRAPH 11: Helipads by Per Capita Income =====
if (!is.null(heliports) && !is.null(complete_data)) {
  
  # Load heliports with actual zone assignments
  heliports_assigned <- read_csv("data/processed/heliports_with_zones.csv", show_col_types = FALSE)
  heliports_assigned$zone_id <- as.integer(heliports_assigned$zone_id)
  
  # Join with income data to get the income of each helipad's zone
  heliports_income <- heliports_assigned %>%
    left_join(complete_data[, c("zone_id", "income_per_capita")], by = "zone_id") %>%
    filter(!is.na(income_per_capita))
  
  if (nrow(heliports_income) > 0) {
    p11 <- ggplot(heliports_income, aes(x = income_per_capita)) +
      geom_histogram(bins = 20, fill = "#F18F01", color = "white", alpha = 0.8) +
      labs(title = "Distribution of Helipads by Per Capita Income of Zone",
           x = "Per Capita Income (R$)",
           y = "Number of Helipads") +
      theme_minimal() +
      theme(plot.title = element_text(hjust = 0.5, face = "bold", size = 12))
    
    ggsave("output/eda_figures/11_helipads_by_income.pdf", p11, width = 10, height = 6)
    cat("✓ Graph 11 saved: output/eda_figures/11_helipads_by_income.pdf\n")
    cat("   Distribution based on zone income levels (", nrow(heliports_income), " helipads with income data)\n")
  } else {
    cat("⚠️ Graph 11: Could not generate helipads income distribution\n")
  }
}

# ===== GRAPH 12: Filtering Impact on Helipads =====
if (!is.null(heliports) && !is.null(complete_data)) {
  
  # Load heliports with actual zone assignments (based on geographic location)
  heliports_assigned <- read_csv("data/processed/heliports_with_zones.csv", show_col_types = FALSE)
  
  # Ensure zone_id is properly formatted
  heliports_assigned$zone_id <- as.integer(heliports_assigned$zone_id)
  
  # Count helipads in each filtering stage
  heliports_valid <- heliports_assigned %>%
    filter(zone_id %in% valid_zones$zone_id)
  
  heliports_filtered <- heliports_assigned %>%
    filter(zone_id %in% filtered_zones_final$zone_id)
  
  # Create filtering impact data for helipads
  heliport_filter_data <- data.frame(
    Stage = factor(c("All Helipads", "In Valid Zones", "In Filtered Zones"),
                   levels = c("All Helipads", "In Valid Zones", "In Filtered Zones")),
    Helipads = c(nrow(heliports), nrow(heliports_valid), nrow(heliports_filtered))
  )
  
  p12 <- ggplot(heliport_filter_data, aes(x = Stage, y = Helipads, fill = Stage)) +
    geom_bar(stat = "identity", alpha = 0.8) +
    geom_text(aes(label = Helipads), vjust = -0.5, size = 5, fontface = "bold") +
    labs(title = "Impact of Zone Filtering on Helipad Availability",
         x = "Filtering Stage",
         y = "Number of Helipads") +
    theme_minimal() +
    theme(plot.title = element_text(hjust = 0.5, face = "bold", size = 12),
          legend.position = "none",
          axis.text.x = element_text(angle = 45, hjust = 1))
  
  ggsave("output/eda_figures/12_helipads_filtering_impact.pdf", p12, width = 10, height = 6)
  cat("✓ Graph 12 saved: output/eda_figures/12_helipads_filtering_impact.pdf\n")
  
  # Print summary
  cat("   Helipads in each filtering stage:\n")
  cat(sprintf("     All Helipads: %d\n", nrow(heliports)))
  cat(sprintf("     In Valid Zones: %d (%.1f%%)\n", nrow(heliports_valid), 
              nrow(heliports_valid) / nrow(heliports) * 100))
  cat(sprintf("     In Filtered Zones: %d (%.1f%%)\n", nrow(heliports_filtered),
              nrow(heliports_filtered) / nrow(heliports) * 100))
}

# ===== GRAPH 13: Helipad Availability by Income Threshold =====
if (!is.null(heliports) && !is.null(complete_data)) {
  
  # Create income threshold scenarios
  threshold_2500 <- complete_data %>%
    filter(income_per_capita >= 2500)
  
  threshold_5000 <- complete_data %>%
    filter(income_per_capita >= 5000)
  
  # Count helipads in each threshold scenario
  # heliports_assigned is already loaded from Graph 12
  heliports_threshold_2500 <- heliports_assigned %>%
    filter(zone_id %in% threshold_2500$zone_id)
  
  heliports_threshold_5000 <- heliports_assigned %>%
    filter(zone_id %in% threshold_5000$zone_id)
  
  # Create comparison data
  threshold_comparison <- data.frame(
    Scenario = factor(c("All Helipads", "Income >= R$ 2,500", "Income >= R$ 5,000"),
                      levels = c("All Helipads", "Income >= R$ 2,500", "Income >= R$ 5,000")),
    Helipads = c(nrow(heliports), nrow(heliports_threshold_2500), nrow(heliports_threshold_5000))
  )
  
  p13 <- ggplot(threshold_comparison, aes(x = Scenario, y = Helipads, fill = Scenario)) +
    geom_bar(stat = "identity", alpha = 0.8) +
    geom_text(aes(label = Helipads), vjust = -0.5, size = 5, fontface = "bold") +
    labs(title = "Helipad Availability by Income Threshold",
         x = "Income Threshold Scenario",
         y = "Number of Helipads") +
    theme_minimal() +
    theme(plot.title = element_text(hjust = 0.5, face = "bold", size = 12),
          legend.position = "none",
          axis.text.x = element_text(angle = 45, hjust = 1))
  
  ggsave("output/eda_figures/13_helipads_income_threshold_comparison.pdf", p13, width = 10, height = 6)
  cat("✓ Graph 13 saved: output/eda_figures/13_helipads_income_threshold_comparison.pdf\n")
  
  # Print summary
  cat("   Helipads by income threshold:\n")
  cat(sprintf("     All Helipads: %d\n", nrow(heliports)))
  cat(sprintf("     Income >= R$ 2,500: %d (%.1f%%)\n", nrow(heliports_threshold_2500),
              nrow(heliports_threshold_2500) / nrow(heliports) * 100))
  cat(sprintf("     Income >= R$ 5,000: %d (%.1f%%)\n", nrow(heliports_threshold_5000),
              nrow(heliports_threshold_5000) / nrow(heliports) * 100))
}

cat(paste(rep("=", 80), collapse=""), "\n")
cat("VISUALIZATIONS AND TABLES GENERATED SUCCESSFULLY!\n")
cat("LaTeX Tables: output/eda_tables/\n")
cat("Figures (PDF): output/eda_figures/\n")
cat("Interactive Maps: See visualizar_helipads_threshold_leaflet.R for Leaflet maps\n")
cat(paste(rep("=", 80), collapse=""), "\n\n")
