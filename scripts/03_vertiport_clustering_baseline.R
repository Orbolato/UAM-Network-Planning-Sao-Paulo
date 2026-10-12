# ============================================================================
# CLUSTERING OF HELIPADS TO VERTIPORTS - RMSP
# ============================================================================
# Script to identify optimal locations for vertiports in the entire RMSP
# Based on OD zones 2023 and ANAC helipads
# ============================================================================

library(sf)
library(readr)
library(dplyr)
library(stringr)
library(cluster)  # For k-medoids (PAM)
library(leaflet)
library(htmlwidgets)

sf_use_s2(FALSE)  # Disable S2 geometry to avoid issues with centroids
rm(list = ls())

# ========== CONFIGURABLE PARAMETERS ==========
NUM_CLUSTERS <- 3                                    # Number of vertiports to identify
INCOME_THRESHOLD <- 5000                                # Minimum per capita income in R$ (after percentile)
HELIPADS_FILE <- "data/processed/heliports_with_zones.csv"  # Helipads of the entire RMSP
CITY_TAXI_CONVERSION_FACTOR <- 0.01               # 1% for VP-VP operations (city taxi)
AIRPORT_SHUTTLE_CONVERSION_FACTOR <- 0.01          # 1% for operations with airports
TRANSFER_CONVERSION_FACTOR <- 0.01                     # 1% for airport transfers
EVTOL_CAPACITY <- 4                             # Passengers per eVTOL (typical: 4-6)

# ========== ANAC AIRPORT PASSENGER DATA ==========
# Source: ANAC - Statistical Yearbook 2023
# Daily passenger volume at major airports
AIRPORT_PASSENGER_DATA <- list(
  SBGR = list(name = "Guarulhos", pax_day = 120000),
  SBSP = list(name = "Congonhas", pax_day = 60000),
  SBMT = list(name = "Campo de Marte", pax_day = 2000)
)

# RMSP capture rates: proportion of airport passengers originating/destined to RMSP
AIRPORT_RMSP_CAPTURE_RATE <- list(
  SBGR = 0.60,   # 60% of SBGR passengers from/to RMSP
  SBSP = 0.75,   # 75% of SBSP passengers from/to RMSP
  SBMT = 0.85    # 85% of SBMT passengers from/to RMSP (mostly local)
)

# Estimated demand for transfers between airports (passengers/day)
# Source: ANAC - Statistical Yearbook 2019 (pre-pandemic)
# % in connection: SBGR ~15-20% | SBSP ~5-8% | SBMT minimal
TRANSFERS_AP_AP_PAX <- list(
  SBGR_SBSP = 3000,  # Guarulhos → Congonhas: Internacional → Doméstico (~2.5% of SBGR)
  SBSP_SBGR = 6000,   # Congonhas → Guarulhos: Doméstico → Internacional (~1.5% of SBSP)
  SBSP_SBMT = 30,    # Congonhas ↔ Campo de Marte (executive aviation)
  SBMT_SBSP = 30,
  SBGR_SBMT = 60,    # Guarulhos ↔ Campo de Marte (executive aviation)
  SBMT_SBGR = 60
)

# =============================================

cat("======================================================\n")
cat("CLUSTERING OF HELIPADS TO VERTIPORTS - RMSP\n")
cat("======================================================\n")
cat("PARAMETERS:\n")
cat("  - Number of clusters:", NUM_CLUSTERS, "\n")
cat("  - Minimum income threshold: > R$", INCOME_THRESHOLD, "\n")
cat("  - City Taxi conversion factor (VP-VP):", CITY_TAXI_CONVERSION_FACTOR * 100, "%\n")
cat("  - Airport Shuttle conversion factor:", AIRPORT_SHUTTLE_CONVERSION_FACTOR * 100, "%\n")
cat("  - Transfer conversion factor:", TRANSFER_CONVERSION_FACTOR * 100, "%\n")
cat("  - eVTOL capacity:", EVTOL_CAPACITY, "passengers\n")
cat("  - Estimated transfers (ANAC 2019): SBGR→SBSP:", TRANSFERS_AP_AP_PAX$SBGR_SBSP, "pax/day\n")
cat("  - Helipads file:", HELIPADS_FILE, "\n")
cat("\nANAC AIRPORT DATA:\n")
cat("  - SBGR (Guarulhos):", AIRPORT_PASSENGER_DATA$SBGR$pax_day, "pax/day, RMSP capture:", AIRPORT_RMSP_CAPTURE_RATE$SBGR * 100, "%\n")
cat("  - SBSP (Congonhas):", AIRPORT_PASSENGER_DATA$SBSP$pax_day, "pax/day, RMSP capture:", AIRPORT_RMSP_CAPTURE_RATE$SBSP * 100, "%\n")
cat("  - SBMT (Campo de Marte):", AIRPORT_PASSENGER_DATA$SBMT$pax_day, "pax/day, RMSP capture:", AIRPORT_RMSP_CAPTURE_RATE$SBMT * 100, "%\n")
cat("======================================================\n\n")

# ========== LOADING OD ZONE DATA ==========
cat("1. Loading OD zone data 2023...\n")
# Load shapefile of zones
zones_sf <- tryCatch({
  st_read("data/raw/od2023/shapefile/Zonas_2023.shp", quiet = TRUE)
}, error = function(e) {
  warning("Shapefile of zones not found.")
  NULL
})

# Load socioeconomic data
zones_data <- tryCatch({
  read_csv("data/processed/zones_data.csv", show_col_types = FALSE, progress = FALSE)
}, error = function(e) {
  stop("File zones_data.csv not found.")
})

# Load per capita income data
income_per_capita <- tryCatch({
  read_csv("data/processed/income_per_capita.csv", show_col_types = FALSE, progress = FALSE)
}, error = function(e) {
  warning(paste("Error loading income_per_capita.csv:", e$message))
  data.frame(zone_id = integer(0), income_per_capita = numeric(0))
})

# Join per capita income to zone data
if (nrow(income_per_capita) > 0 && nrow(zones_data) > 0) {
  zones_data <- zones_data %>%
    left_join(income_per_capita[, c("zone_id", "income_per_capita")], by = "zone_id")
}

cat("   Total zones in 2023 OD Survey:", nrow(zones_data), "\n")
cat("   ✓ Data validated in 2023 OD Survey\n")

# VALIDATION FILTER (non-residential zones should remain excluded)
# This filter acts as a second layer of validation
basic_zones <- zones_data %>%
  filter(!is.na(income_per_capita), income_per_capita > 0)

if (nrow(zones_data) - nrow(basic_zones) > 0) {
  cat("   ✓ Validation filter: excluding", nrow(zones_data) - nrow(basic_zones), "non-residential zones\n")
  cat("     (Parks, airports, universities with zero population)\n")
}

cat("   ✓ Valid zones for analysis:", nrow(basic_zones), "\n")

# basic_zones_ids: ALL zones with income>0 and trips>0 (NO filter)
# Used for helipads_complete (reclustering uses ALL helipads in these zones)
basic_zones_ids <- basic_zones$zone_id

# Keep basic_zones_data with ALL zones for index calculations
# (includes zones that were filtered out)
basic_zones_data <- basic_zones

# Join shapefile with BASIC data (all zones)
if (!is.null(zones_sf) && nrow(basic_zones_data) > 0) {
  zones_sf <- st_transform(zones_sf, crs = 4326)
  # Drop previous data if they exist
  cols_to_keep <- c("geometry", "NumeroZona", "NomeZona", "NomeMunici")
  for (col in setdiff(colnames(zones_sf), cols_to_keep)) {
    if (col != "geometry") {
      zones_sf[[col]] <- NULL
    }
  }
  # Join with basic_zone_data
  zones_sf <- zones_sf %>%
    left_join(basic_zones_data, by = c("NumeroZona" = "zone_id"))
}

cat("   Total population:", format(sum(basic_zones_data$population, na.rm=TRUE), big.mark=","), "\n")
cat("   Trips produced:", format(sum(basic_zones_data$trips_produced, na.rm=TRUE), big.mark=","), "\n")
cat("   Average per capita income: R$", format(mean(basic_zones_data$income_per_capita, na.rm=TRUE), digits=2), "\n\n")

# ========== LOAD HELIPADS ==========
cat("2. Loading helipads from ANAC...\n")
cat("   File:", HELIPADS_FILE, "\n")

helipads <- tryCatch({
  read_csv(HELIPADS_FILE, show_col_types = FALSE, progress = FALSE)
}, error = function(e) {
  stop(paste("File", HELIPADS_FILE, "not found."))
})

# Convert coordinates to numeric
helipads$lat <- as.numeric(helipads$lat)
helipads$lon <- as.numeric(helipads$lon)

# Remove helipads without valid coordinates
helipads <- helipads[!is.na(helipads$lat) & !is.na(helipads$lon), ]

cat("   Total helipads in RMSP:", nrow(helipads), "\n")
cat("   Municipalities represented:", length(unique(helipads$municipality)), "\n")

# ========== ENSURE ALL HELIPADS HAVE ZONE_ID ==========
cat("2.1 Assigning zones to all helipads by spatial join...\n")

# Make sure ALL helipads have zone_id column before filtering
if (is.null(helipads$zone_id) || !("zone_id" %in% colnames(helipads))) {
  helipads$zone_id <- NA_integer_
}

# Contar quantos já têm zone_id
assigned_count <- sum(!is.na(helipads$zone_id))
unassigned_count <- sum(is.na(helipads$zone_id))

cat("    Helipads already with zone_id:", assigned_count, "\n")
cat("    Helipads needing zone_id:", unassigned_count, "\n")

# Assign zones to ALL helipads that do not have zone_id (via spatial join/proximity)
if (unassigned_count > 0 && !is.null(zones_sf) && nrow(zones_sf) > 0) {
  cat("    Assigning zones by spatial join/proximity...\n")
  
  # Use spatial join for all helipads without zone_id
  unassigned_idx <- which(is.na(helipads$zone_id))
  helipads_sf_unassigned <- st_as_sf(helipads[unassigned_idx, ], coords = c("lon", "lat"), crs = 4326)
  
  # Try spatial join (st_within) first
  helipads_sf_utm <- st_transform(helipads_sf_unassigned, 31983)
  zones_sf_utm <- st_transform(zones_sf, 31983)
  
  zone_join <- suppressWarnings(st_join(helipads_sf_utm, zones_sf_utm[, "NumeroZona"], join = st_within))
  
  # For those that did not fall into any zone (st_within returns NA), use proximity
  for (i in seq_along(unassigned_idx)) {
    if (is.na(zone_join$NumeroZona[i])) {
      # Use proximity (find nearest zone)
      heli_pt <- helipads_sf_utm[i, ]
      dist_to_zones <- as.numeric(st_distance(heli_pt, zones_sf_utm))
      nearest_zone_idx <- which.min(dist_to_zones)
      helipads$zone_id[unassigned_idx[i]] <- zones_sf$NumeroZona[nearest_zone_idx]
    } else {
      helipads$zone_id[unassigned_idx[i]] <- zone_join$NumeroZona[i]
    }
  }
  
  cat("    ✓ All zones assigned\n")
}

cat("\n")

# ========== CREATE COMPLETE VALID SET OF HELIPADS ==========
cat("2.2 Creating complete valid set of helipads...\n")

# DIAGNOSTIC: Check how many heliports we start with
cat("   Total original helipads:", nrow(helipads), "\n")
cat("   Helipads with valid lat/lon:", sum(!is.na(helipads$lat) & !is.na(helipads$lon)), "\n")
cat("   Helipads with valid zone_id:", sum(!is.na(helipads$zone_id)), "\n")
cat("   Total basic_zones_ids (without percentile):", length(basic_zones_ids), "\n")
cat("   Helipads in basic zones:", sum(!is.na(helipads$zone_id) & helipads$zone_id %in% basic_zones_ids), "\n")

# helipads_complete = ALL helipads in basic zones (WITHOUT filter)
# Use basic_zones_ids to include ALL valid helipads
helipads_complete <- helipads[!is.na(helipads$lat) & !is.na(helipads$lon) & 
                                    !is.na(helipads$zone_id) & 
                                    helipads$zone_id %in% basic_zones_ids, ]

cat("    Helipads in COMPLETE set:", nrow(helipads_complete), "\n")

cat("\n")

# ========== FILTER HELIPADS BY INCOME ==========
cat("3. Filtering helipads by zones with minimum income...\n")
cat("   Income threshold: > R$", INCOME_THRESHOLD, "\n")

# Filter zones that meet BOTH criteria
qualified_zones <- basic_zones_data %>%
  filter(!is.na(income_per_capita), income_per_capita > INCOME_THRESHOLD)

cat("   Qualified zones (income):", nrow(qualified_zones), "\n")

# Filter helipads_complete for only qualified zones (for clustering)
# This will be helipads_filtered
helipads_filtered <- helipads_complete[helipads_complete$zone_id %in% qualified_zones$zone_id, ]

cat("   Helipads in FILTERED set (for clustering):", nrow(helipads_filtered), "\n")
cat("   Difference (complete - filtered):", nrow(helipads_complete) - nrow(helipads_filtered), "helipads removed\n\n")

# ========== ELBOW ANALYSIS FOR CHOOSING K ========== 
evaluate_k_candidates <- function(helipads_df, k_values) {
  cat("\n--- Evaluating candidate k values ---\n")

  coords_matrix <- cbind(helipads_df$lon, helipads_df$lat)
  all_points <- st_as_sf(data.frame(
    id = 1:nrow(coords_matrix),
    lon = coords_matrix[, 1],
    lat = coords_matrix[, 2]
  ), coords = c("lon", "lat"), crs = 4326)

  dist_matrix_m <- st_distance(all_points)
  dist_matrix <- matrix(as.numeric(dist_matrix_m), nrow = nrow(all_points), ncol = nrow(all_points)) / 1000

  results <- data.frame(
    k = integer(0),
    total_dissimilarity = numeric(0),
    average_silhouette = numeric(0),
    stringsAsFactors = FALSE
  )

  for (k in k_values) {
    cat("  Evaluating k =", k, "...\n")
    set.seed(42)
    pam_result <- pam(dist_matrix, k = k, diss = TRUE)

    medoid_indices <- pam_result$id.med[pam_result$clustering]
    total_dissimilarity <- sum(dist_matrix[cbind(seq_len(nrow(dist_matrix)), medoid_indices)], na.rm = TRUE)
    average_silhouette <- mean(pam_result$silinfo$widths[, "sil_width"], na.rm = TRUE)

    results <- rbind(results, data.frame(
      k = k,
      total_dissimilarity = total_dissimilarity,
      average_silhouette = average_silhouette,
      stringsAsFactors = FALSE
    ))

    cat("    Total dissimilarity:", round(total_dissimilarity, 3), "\n")
    cat("    Average silhouette:", round(average_silhouette, 3), "\n")
  }

  return(results)
}

# ========== ELBOW ANALYSIS ==========
cat("3.1 Evaluating clustering candidates with elbow and silhouette diagnostics...\n")
max_k <- min(8, nrow(helipads_filtered) - 1)
if (max_k < 2) {
  stop("Not enough helipads to evaluate cluster candidates.")
}

candidate_k <- 2:max_k
elbow_results <- evaluate_k_candidates(helipads_filtered, candidate_k)
write_csv(elbow_results, "output/k_selection_diagnostics_rmsp.csv")
cat("   Saved: output/k_selection_diagnostics_rmsp.csv\n")

pdf("output/elbow_plot_rmsp.pdf", width = 18, height = 8)#, res = 200)
par(mfrow = c(1, 2), mar = c(5, 5, 3, 1))

plot(elbow_results$k, elbow_results$total_dissimilarity,
  type = "b", pch = 19, col = "#1f77b4",
  xlab = "Number of clusters (k)",
  ylab = "Total within-cluster dissimilarity",
  main = "Elbow analysis")

plot(elbow_results$k, elbow_results$average_silhouette,
  type = "b", pch = 19, col = "#d62728",
  xlab = "Number of clusters (k)",
  ylab = "Average silhouette width",
  main = "Silhouette check")

dev.off()
cat("   Saved: output/elbow_plot_rmsp.pdf\n\n")

# Convert helipads to sf object (use helipads_filtered for clustering)
helipads_sf <- st_as_sf(helipads_filtered, coords = c("lon", "lat"), crs = 4326)

# Fix UTF-8 encoding issues
if (!is.null(zones_sf)) {
  zones_sf$NomeZona <- iconv(zones_sf$NomeZona, to = "UTF-8", sub = "")
  zones_sf$NomeMunici <- iconv(zones_sf$NomeMunici, to = "UTF-8", sub = "")
}

# Extract coordinates
coords_filtered <- st_coordinates(helipads_sf)
helipads_filtered$lon <- coords_filtered[, "X"]
helipads_filtered$lat <- coords_filtered[, "Y"]

# ========== PARAMETRIC CLUSTERING FUNCTION ==========

execute_clustering <- function(helipads_df, num_clusters, zones_data = NULL) {
  cat("\n--- Clustering by geodesic distance (haversine) ---\n")
  
  # Prepare base coordinate matrix
  coords_matrix <- cbind(helipads_df$lon, helipads_df$lat)
  # Traditional clustering by geographic distance
  all_points <- st_as_sf(data.frame(
    id = 1:nrow(coords_matrix),
    lon = coords_matrix[, 1],
    lat = coords_matrix[, 2]
  ), coords = c("lon", "lat"), crs = 4326)
  dist_matrix_m <- st_distance(all_points)
  # Convert to numeric matrix (st_distance returns matrix with units in meters)
  dist_matrix <- matrix(as.numeric(dist_matrix_m), nrow = nrow(all_points), ncol = nrow(all_points)) / 1000
  # st_distance already returns symmetric matrix, diagonal is zero
  # No further action needed  
  
  # Execute PAM
  cat("  Executing K-medoids (PAM) with k =", num_clusters, "...\n")
  set.seed(42)
  pam_result <- pam(dist_matrix, k = num_clusters, diss = TRUE)
  
  # Add results to dataframe
  helipads_df$cluster <- pam_result$clustering
  
  # Statistics
  silhouette_avg <- mean(pam_result$silinfo$widths[, "sil_width"])
  cat("  Average silhouette:", round(silhouette_avg, 3), "\n")
  
  for (i in 1:num_clusters) {
    cat("    Cluster", i, ":", sum(pam_result$clustering == i), "helipads\n")
  }
  
  return(list(
    helipads = helipads_df,
    pam_result = pam_result,
    silhouette = silhouette_avg
  ))
}

# ========== FUNCTION: CALCULATE CLUSTER INDICES ==========
calculate_cluster_indices <- function(helipads_cluster, zones_data, type = "cluster") {
  if (is.null(zones_data) || nrow(zones_data) == 0) {
    return(list(mean_income = NA, total_demand = NA, total_trips_attracted = NA, 
                combined = NA, total_population = NA, coverage_population = NA, n_zones = 0, zones_ids = c()))
  }
  
  # Find ALL zones that have at least one helipad in cluster
  # Transform to metric CRS before calculating centroids (more accurate for geodesic distances)
  zones_data_utm <- st_transform(zones_data, 31983)
  zones_centroids <- st_centroid(st_geometry(zones_data_utm))
  zones_coords <- st_coordinates(zones_centroids)
  
  # Create helipads in UTM for geodesic distance calculation
  helipads_sf_temp <- st_as_sf(helipads_cluster, coords = c("lon", "lat"), crs = 4326)
  helipads_utm_temp <- st_transform(helipads_sf_temp, 31983)
  helipads_coords_utm <- st_coordinates(helipads_utm_temp)
  
  zones_in_cluster <- c()
  
  for (i in 1:nrow(helipads_cluster)) {
    # Find nearest zone for each helipad using geodesic distance
    # (using st_distance which returns distance in meters in metric CRS)
    heli_pt <- helipads_utm_temp[i, ]
    dist_to_zones <- as.numeric(st_distance(heli_pt, zones_data_utm)) / 1000  # converter para km
    zone_idx <- which.min(dist_to_zones)
    zones_in_cluster <- c(zones_in_cluster, zone_idx)
  }
  
  # Unique zones covered by the cluster
  zones_unique <- unique(zones_in_cluster)
  zones_cluster_data <- zones_data[zones_unique, ]
  
  # Calculate aggregates of ALL covered zones
  total_income <- sum(zones_cluster_data$income_per_capita * zones_cluster_data$population, na.rm = TRUE)
  total_population <- sum(zones_cluster_data$population, na.rm = TRUE)
  total_demand <- sum(zones_cluster_data$trips_produced, na.rm = TRUE)
  total_trips_attracted <- sum(zones_cluster_data$trips_attracted, na.rm = TRUE)
  
  # Validate that we have valid data
  if (is.na(total_demand) || total_demand == 0) {
    stop("Error calculating total demand for cluster/point. ",
         "Zones found: ", length(zones_unique),
         ", Zones with trips > 0: ", sum(zones_cluster_data$trips_produced > 0, na.rm = TRUE),
         ", Sum of trips: ", sum(zones_cluster_data$trips_produced, na.rm = TRUE))
  }
  
  # Mean income weighted by population
  mean_income <- ifelse(total_population > 0, total_income / total_population, 0)
  
  # Cluster total demand
  cluster_demand <- total_demand
  
  # Combined index using PRODUCT (income × demand)
  # Product prioritizes clusters with BOTH high income AND high demand
  income_max <- max(zones_data$income_per_capita, na.rm = TRUE)
  trips_max_total <- sum(zones_data$trips_produced, na.rm = TRUE)
  
  income_norm <- mean_income / income_max
  demand_norm <- cluster_demand / (trips_max_total / NUM_CLUSTERS)  # Compare with 1/NUM_CLUSTERS of total
  # demand_norm <- min(demand_norm, 1.0)  # Limit to 1.0
  
  # Normalized product (square root to maintain 0-1 scale)
  combined <- sqrt(income_norm * demand_norm)
  
  return(list(
    mean_income = mean_income,
    total_demand = cluster_demand,
    total_trips_attracted = total_trips_attracted,
    combined = combined,
    total_population = total_population,
    coverage_population = total_population,
    n_zones = length(zones_unique),
    zones_ids = zones_cluster_data$NumeroZona
  ))
}

# ========== K-MEDOIDS (PAM) CLUSTERING ==========
cat("4. Executing K-medoids/PAM clustering (k=", NUM_CLUSTERS, ")...\n", sep="")
cat("   (K-medoids ensures centers are actual helipads)\n")

# Final result
final_result <- execute_clustering(
  helipads_df = helipads_filtered,
  num_clusters = NUM_CLUSTERS,
  zones_data = zones_sf
)
helipads_filtered <- final_result$helipads
pam_result <- final_result$pam_result

cat("\n")

# ========== IDENTIFYING MEDOIDS AS VERTIPORTS ==========
cat("5. Identifying medoids (central helipads) as vertiports...\n")

# Medoids are indices of helipads selected as centers
vertiports <- data.frame()
# Ensure helipads_filtered is a data.frame (not sf)
if ("sf" %in% class(helipads_filtered)) {
  helipads_df <- st_drop_geometry(helipads_filtered)
  helipads_df$lon <- helipads_filtered$lon
  helipads_df$lat <- helipads_filtered$lat
} else {
  helipads_df <- helipads_filtered
}

# Rebuild coords_matrix to ensure consistency
coords_matrix <- cbind(helipads_df$lon, helipads_df$lat)

for (i in 1:NUM_CLUSTERS) {
  # Index of the medoid in the filtered set
  medoid_idx <- pam_result$id.med[i]
  
  # Helipad selected as medoid (vertiport)
  helipad_selected <- helipads_df[medoid_idx, ]
  
  # Coordinates of the medoid
  medoid_coords <- coords_matrix[medoid_idx, ]
  
  # Silhouette of the medoid
  medoid_silhouette <- pam_result$silinfo$widths[medoid_idx, "sil_width"]
  
  # Create vertiport record
  vertiport <- data.frame(
    id = paste0("VP-", sprintf("%03d", i)),
    helipad_code = helipad_selected$code,
    helipad_name = helipad_selected$name,
    municipality = helipad_selected$municipality,
    helipad_type = helipad_selected$type,
    lat = medoid_coords[2],
    lon = medoid_coords[1],
    cluster = i,
    helipads_cluster = sum(pam_result$clustering == i),
    silhouette = medoid_silhouette,
    silhouette_reclustered = NA_real_,  # Will be calculated after reclustering
    stringsAsFactors = FALSE
  )
  
  vertiports <- rbind(vertiports, vertiport)
  
  cat("   Vertiport", i, ":\n")
  cat("     Helipad (medoid):", helipad_selected$code, "-", helipad_selected$name, "\n")
  cat("     Municipality:", helipad_selected$municipality, "\n")
  cat("     Type:", helipad_selected$type, "\n")
  cat("     Coordinates: (", round(medoid_coords[2], 6), ",", round(medoid_coords[1], 6), ")\n")
  cat("     Helipads in cluster:", vertiport$helipads_cluster, "\n")
  cat("     Silhouette:", round(vertiport$silhouette, 3), "\n\n")
}

# Add zone_od to vertiports (needed for VP-VP distance calculation)
cat("   Assigning OD zones to vertiports...\n")
vertiports_sf <- st_as_sf(vertiports, coords = c("lon", "lat"), crs = 4326)
# Transform to metric CRS (SIRGAS 2000 UTM 23S) for precise spatial operations
vertiports_sf_utm <- st_transform(vertiports_sf, 31983)
zones_sf_utm <- st_transform(zones_sf, 31983)
vertiports_with_zone <- suppressWarnings(st_join(vertiports_sf_utm, zones_sf_utm, join = st_within))
vertiports$zone_od <- vertiports_with_zone$NumeroZona
cat("   OD zones assigned:", paste(vertiports$zone_od, collapse = ", "), "\n\n")

# ========== ORIGINAL CLUSTER METRICS (FILTERED HELIPADS) ==========
cat("5.1 Calculating metrics for original clusters (filtered helipads with threshold)...\n\n")

# Calculate indices for original clusters based on helipads_filtered (PAM input set)
original_cluster_indices <- data.frame()

for (i in 1:NUM_CLUSTERS) {
  # IMPORTANT: Use helipads_filtered (original set used for PAM), not helipads_complete
  helis_original_cluster <- helipads_filtered[helipads_filtered$cluster == i, ]
  cat("   Original Cluster", i, ":", nrow(helis_original_cluster), "helipads (with threshold)\n")
  indices <- calculate_cluster_indices(helis_original_cluster, zones_sf)
  
  original_cluster_indices <- rbind(original_cluster_indices, data.frame(
    cluster = i,
    vertiport_id = paste0("VP-", sprintf("%03d", i)),
    n_helipads = nrow(helis_original_cluster),
    n_zones = indices$n_zones,
    mean_income = round(indices$mean_income, 2),
    total_population = round(indices$total_population, 0),
    total_demand = round(indices$total_demand, 0),
    total_trips_attracted = round(indices$total_trips_attracted, 0),
    combined_index = round(indices$combined, 3),
    coverage_population = round(indices$coverage_population, 0),
    stringsAsFactors = FALSE
  ))
  
  cat("     Covered zones:", indices$n_zones, "\n")
  cat("     Per capita income (weighted): R$", round(indices$mean_income, 2), "\n")
  cat("     Total population:", format(round(indices$total_population, 0), big.mark=","), "inhabitants\n")
  cat("     Trips Produced (demand):", format(round(indices$total_demand, 0), big.mark=","), "trips/day\n")
  cat("     Trips Attracted:", format(round(indices$total_trips_attracted, 0), big.mark=","), "trips/day\n")
  cat("     Combined index:", round(indices$combined, 3), "\n\n")
}

# ========== RECLUSTERING: REASSIGNING HELIPORTS TO THE NEAREST MEDOID ==========" 
cat("5.2 Executing reclustering by distance to medoids...\n")
cat("    (Reassigning ALL heliports in valid zones to the nearest medoid)\n\n")
# Reclustering strategy:
# 1. helipads_filtered (274): Set with threshold → USED TO FIND MEDOIDS ✓
# 2. helipads_complete: All heliports in valid zones (without applying filter) → FOR RECLUSTERING
#    Valid zones = zones with income > 0 and trips > 0 (already defined in basic_zones_ids)
#    This set is LARGER than helipads_filtered because it does not apply INCOME_THRESHOLD

cat("    Heliports in the COMPLETE set (all valid zones):", nrow(helipads_complete), "\n")
cat("    Heliports in the FILTERED set (with threshold):", nrow(helipads_filtered), "\n")
cat("    Medoids found:", nrow(vertiports), "\n")
cat("    Expected expansion:", nrow(helipads_complete) - nrow(helipads_filtered), "additional heliports\n\n")

# Convert to SF
helipads_complete_sf <- st_as_sf(helipads_complete, coords = c("lon", "lat"), crs = 4326)
helipads_complete_sf_utm <- st_transform(helipads_complete_sf, 31983)
# Coordinates of medoids in UTM
medoids_coords_utm <- st_transform(vertiports_sf, 31983)

# For each heliport in the complete set, find the nearest medoid
cat("    Calculating distances and reassigning heliports...\n")

# IMPORTANT: Initialize cluster column on the SF OBJECT
# This ensures all cluster assignments will use consistent indexing
helipads_complete_sf$cluster <- NA_integer_

# Validate number of medoids
if (nrow(medoids_coords_utm) != NUM_CLUSTERS) {
  cat("    ⚠️ WARNING: Number of medoids (", nrow(medoids_coords_utm), ") does not match NUM_CLUSTERS (", NUM_CLUSTERS, ")\n", sep="")
}

for (h in 1:nrow(helipads_complete_sf_utm)) {
  heli_pt <- helipads_complete_sf_utm[h, ]
  
  # Calculate distance to each medoid
  distances_to_medoids <- as.numeric(st_distance(heli_pt, medoids_coords_utm))
  
  # Validate distances - if they fail, something is very wrong
  if (length(distances_to_medoids) != NUM_CLUSTERS || all(is.na(distances_to_medoids))) {
    cat("    ⚠️ ERROR: Heliport", h, "has invalid distances (length:", 
        length(distances_to_medoids), ", all NA:", all(is.na(distances_to_medoids)), ")\n")
    next
  }
  
  # Assign to nearest medoid
  # which.min() returns the index (1 to NUM_CLUSTERS)
  nearest_cluster <- which.min(distances_to_medoids)
  
  # IMPORTANT: which.min() ALWAYS returns a valid index if distances has values
  # So we should ALWAYS assign here - no additional validation needed
  if (nearest_cluster >= 1 && nearest_cluster <= NUM_CLUSTERS) {
    helipads_complete_sf$cluster[h] <- nearest_cluster
  } else {
    cat("    ⚠️ CRITICAL ERROR: which.min() returned invalid value:", nearest_cluster, 
        "for heliport", h, "\n")
  }
  
  if (h %% 50 == 0) {
    cat("      Processed", h, "heliports\n")
  }
}

cat("    ✓ Reclustering completed\n")
cat("    Distribution of heliports in clusters:\n")
for (i in 1:NUM_CLUSTERS) {
  count <- sum(helipads_complete_sf$cluster == i, na.rm = TRUE)
  cat("      Cluster", i, ":", count, "heliports\n")
}
cat("\n")

# CRITICAL FIX: Propagate cluster values from sf object back to dataframe
# This ensures helipads_complete$cluster values are synchronized with the assignments
helipads_complete$cluster <- helipads_complete_sf$cluster

# Update helipads_filtered with new clustering (to maintain downstream compatibility)
# IMPORTANT: From this point on, helipads_filtered contains ALL reclustered helipads
# (not just the originally filtered ones), since reclustering reassigns all helipads in valid zones
helipads_clustered <- helipads_filtered  # PRESERVE the original filtered set for map visualization
helipads_filtered <- helipads_complete
# Recalculate necessary data structures for OD demand calculation
# (helipads_per_zone, total_helipads_per_zone, total_helipads_cluster)

cat("    Recalculating data structures with new clustering...\n")

# Diagnostic: Check cluster distribution
cat("    Distribution after reclustering:\n")
for (i in 1:NUM_CLUSTERS) {
  count <- sum(helipads_complete$cluster == i, na.rm = TRUE)
  cat("      Cluster", i, ":", count, "heliports\n")
}
na_count <- sum(is.na(helipads_complete$cluster))
if (na_count > 0) {
  cat("    ⚠️ WARNING: ", na_count, " heliports with NA cluster! (should be 0)\n", sep="")
  # Show which heliports were not assigned
  unassigned_indices <- which(is.na(helipads_complete$cluster))
  cat("      Heliports not assigned:", paste(head(unassigned_indices, 20), collapse=", "))
  if (length(unassigned_indices) > 20) {
    cat(", ... and ", length(unassigned_indices) - 20, " more\n", sep="")
  } else {
    cat("\n")
  }
}
cat("\n")

# ========== RECALCULATE SILHOUETTE FOR RECLUSTERED CLUSTERS ==========
cat("    Calculating silhouette for reclustered clusters...\n")
# Create distance matrix for reclustered helipads
coords_matrix_reclustered <- cbind(helipads_complete$lon, helipads_complete$lat)

# Convert to SF for distance calculation (in meters using UTM)
helipads_reclustered_sf <- st_as_sf(helipads_complete, coords = c("lon", "lat"), crs = 4326)
helipads_reclustered_utm <- st_transform(helipads_reclustered_sf, 31983)

# Calculate distance matrix in UTM coordinates
dist_matrix_reclustered <- as.matrix(st_distance(helipads_reclustered_utm))

# Calculate silhouette using cluster::silhouette()
# This function requires a distance matrix and cluster assignments
silhouette_reclustered <- silhouette(helipads_complete$cluster, dist_matrix_reclustered)

# Extract mean silhouette for each cluster
mean_silhouette_per_cluster <- aggregate(silhouette_reclustered[, "sil_width"], 
                                         by = list(cluster = silhouette_reclustered[, "cluster"]), 
                                         FUN = mean)

# Update vertiports with new silhouette values (use the cluster mean, not the medoid silhouette)
for (i in 1:NUM_CLUSTERS) {
  new_sil <- mean_silhouette_per_cluster$x[mean_silhouette_per_cluster$cluster == i]
  vertiports$silhouette_reclustered[i] <- ifelse(length(new_sil) > 0, new_sil, NA)
}

# Print comparison
cat("    Silhouette comparison (original vs reclustered):\n")
for (i in 1:NUM_CLUSTERS) {
  original_sil <- vertiports$silhouette[i]
  reclustered_sil <- vertiports$silhouette_reclustered[i]
  cat("      Cluster", i, "- Original (filtered helipads):", round(original_sil, 3), 
      "| Reclustered (all helipads):", round(reclustered_sil, 3), "\n")
}
cat("\n")

# Reinitialize structures with robust initialization
helipads_per_zone <- list()
total_helipads_per_zone <- list()
total_helipads_cluster <- as.integer(rep(0, NUM_CLUSTERS))
zones_per_cluster <- list()
# Initialize each cluster correctly
for (i in 1:NUM_CLUSTERS) {
  helipads_per_zone[[i]] <- list()
  zones_per_cluster[[i]] <- integer(0)  # empty integer vector
}

total_helipads_per_zone_temp <- list()

# Iterate over helipads and build structures
cat("    Starting recalculation loop. NUM_CLUSTERS =", NUM_CLUSTERS, "\n")
cat("    Size of helipads_complete:", nrow(helipads_complete), "\n\n")

for (h in 1:nrow(helipads_complete)) {
  cluster <- as.integer(helipads_complete$cluster[h])
  
  # Validate cluster
  if (is.na(cluster) || cluster < 1 || cluster > NUM_CLUSTERS) {
    next
  }
  
  zone <- helipads_complete$zone_id[h]
  
  # If there is no zone_id, try to obtain it via spatial join with zones
  if (is.na(zone) || is.null(zone)) {
    if (!is.null(zones_sf) && nrow(zones_sf) > 0) {
      heli_pt <- st_as_sf(helipads_complete[h, ], coords = c("lon", "lat"), crs = 4326)
      zone_match <- suppressWarnings(st_join(st_transform(heli_pt, 31983), 
                                             st_transform(zones_sf[, c("NumeroZona")], 31983), 
                                             join = st_within))
      zone <- zone_match$NumeroZona[1]
    }
  }
  
  # Only continue if we have a valid zone
  if (!is.na(zone) && is.numeric(zone)) {
    zone_char <- as.character(as.integer(zone))
    
    # Ensure the cluster has an element for this zone
    if (!(zone_char %in% names(helipads_per_zone[[cluster]]))) {
      helipads_per_zone[[cluster]][[zone_char]] <- 0
    }
    
    # Increment counters
    helipads_per_zone[[cluster]][[zone_char]] <- helipads_per_zone[[cluster]][[zone_char]] + 1
    
    # Total helipads by zone (all clusters)
    if (!(zone_char %in% names(total_helipads_per_zone_temp))) {
      total_helipads_per_zone_temp[[zone_char]] <- 0
    }
    total_helipads_per_zone_temp[[zone_char]] <- total_helipads_per_zone_temp[[zone_char]] + 1
    
    # Add zone to cluster (avoid duplicates)
    if (!(zone %in% zones_per_cluster[[cluster]])) {
      zones_per_cluster[[cluster]] <- c(zones_per_cluster[[cluster]], zone)
    }
  }
  
  # Count helipads per cluster
  total_helipads_cluster[cluster] <- total_helipads_cluster[cluster] + 1
}

# Copy to final structure
total_helipads_per_zone <- total_helipads_per_zone_temp

cat("    ✓ Data structures recalculated\n")
cat("    Zones with helipads:", length(total_helipads_per_zone), "\n")

# DIAGNOSTIC: Detailed check of data structures
cat("\n    === COMPLETE DIAGNOSTIC OF OD STRUCTURES ===\n")
total_helis_per_cluster <- sum(total_helipads_cluster)
cat("    Total helipads in clusters:", total_helis_per_cluster, "(expected:", nrow(helipads_complete), ")\n")

cat("    Distribution by cluster:\n")
for (i in 1:NUM_CLUSTERS) {
  cat("      Cluster", i, ":", total_helipads_cluster[i], "helipads\n")
}

total_helis_per_zone <- sum(unlist(total_helipads_per_zone))
cat("    Total helipads in total_helipads_per_zone:", total_helis_per_zone, "\n")
cat("    Number of zones with helipads:", length(total_helipads_per_zone), "\n")

# Sample some zones
cat("    Sample of zones (first 10):\n")
zones_sample <- names(total_helipads_per_zone)[1:min(10, length(total_helipads_per_zone))]
for (z in zones_sample) {
  cat("      Zone", z, ":", total_helipads_per_zone[[z]], "helipads total\n")
}
if (length(total_helipads_per_zone) > 10) {
  cat("      ... and", length(total_helipads_per_zone) - 10, "additional zones\n")
}

# Check helipads per zone per cluster (first 3 clusters)
cat("    Helipads per ZONE and CLUSTER (Cluster 1, first 5 zones):\n")
if (length(helipads_per_zone[[1]]) > 0) {
  zones_c1 <- names(helipads_per_zone[[1]])[1:min(5, length(helipads_per_zone[[1]]))]
  for (z in zones_c1) {
    cat("      Cluster 1, Zone", z, ":", helipads_per_zone[[1]][[z]], "helipads\n")
  }
}

cat("    === END OF DIAGNOSTIC ===\n\n")

# Add zone_od to vertiports (necessary for calculating VP-VP distances)
cat("   Assigning OD zones to vertiports...\n")
vertiports_sf <- st_as_sf(vertiports, coords = c("lon", "lat"), crs = 4326)
# Transform to metric CRS (SIRGAS 2000 UTM 23S) for precise spatial operations
vertiports_sf_utm <- st_transform(vertiports_sf, 31983)
zones_sf_utm <- st_transform(zones_sf, 31983)
vertiports_with_zone <- suppressWarnings(st_join(vertiports_sf_utm, zones_sf_utm, join = st_within))
vertiports$zone_od <- vertiports_with_zone$NumeroZona
cat("   OD zones assigned:", paste(vertiports$zone_od, collapse = ", "), "\n\n")

# ========== SAVING RESULTS ==========
cat("6. Saving results...\n")

# Save filtered and clustered helipads
helipads_output <- helipads_filtered %>%
  st_drop_geometry()

# Add conditional columns
if ("zone_od" %in% names(helipads_output)) {
  helipads_output <- helipads_output %>%
    select(code, name, type, lat, lon, municipality, cluster, zone_od, socio_economic_weight)
} else {
  helipads_output <- helipads_output %>%
    select(code, name, type, lat, lon, municipality, cluster)
}

write_csv(helipads_output, "output/clustered_helipads_rmsp.csv")
cat("   Saved: output/clustered_helipads_rmsp.csv (", nrow(helipads_output), " helipads)\n")

# Save identified vertiports (medoids)
write_csv(vertiports, "output/vertiports_medoids_rmsp.csv")
cat("   Saved: output/vertiports_medoids_rmsp.csv (", nrow(vertiports), " vertiports)\n")

# Create data frame in format compatible with 04_uam_routes_baseline.R
vertiports_export <- data.frame(
  id = vertiports$id,
  name = paste0(vertiports$id, " (", vertiports$helipad_name, ")"),
  code = vertiports$helipad_code,
  helipad_base = vertiports$helipad_code,
  tipo = "Vertiporto",
  lat = vertiports$lat,
  lon = vertiports$lon,
  stringsAsFactors = FALSE
)

# Save in RDS format for easy loading in the other script
saveRDS(vertiports_export, "output/selected_vertiports_rmsp.rds")
cat("   Saved: output/selected_vertiports_rmsp.rds (format for 04_uam_routes_baseline.R)\n")

# Save also clustering metadata
metadata <- list(
  num_clusters = NUM_CLUSTERS,
  silhouette = mean(pam_result$silinfo$widths[, "sil_width"]),
  INCOME_THRESHOLD = INCOME_THRESHOLD,
  data_geracao = Sys.time()
)
saveRDS(metadata, "output/clustering_metadata_rmsp.rds")
cat("   Saved: output/clustering_metadata_rmsp.rds\n\n")

# ========== CALCULATE INFLUENCE REGIONS ==========
cat("7. Calculating influence regions for each cluster...\n")

# Associate each helipad to the nearest vertiport
helipads_sf_all <- st_as_sf(helipads, coords = c("lon", "lat"), crs = 4326)

# For each helipad, find the nearest vertiport
helipads_influence <- helipads_sf_all
helipads_influence$cluster_influence <- NA
helipads_influence$vertiport_distance <- NA

for (i in 1:nrow(helipads_influence)) {
  heli_pt <- helipads_influence[i,]
  
  # Calculate geodesic distance to each vertiport
  vertiports_sf <- st_as_sf(vertiports, coords = c("lon", "lat"), crs = 4326)
  distances_m <- st_distance(heli_pt, vertiports_sf)
  distances_km <- as.numeric(distances_m) / 1000
  
  # Assign to the cluster of the nearest vertiport
  nearest_cluster <- which.min(distances_km)
  helipads_influence$cluster_influence[i] <- nearest_cluster
  helipads_influence$vertiport_distance[i] <- distances_km[nearest_cluster]
}

# Extract coordinates
coords_influence <- st_coordinates(helipads_influence)
helipads_influence$lon <- coords_influence[, "X"]
helipads_influence$lat <- coords_influence[, "Y"]

# Calculate influence radius for each cluster (95th percentile of distances)
radii_influence <- sapply(1:NUM_CLUSTERS, function(i) {
  helis_cluster <- helipads_influence[helipads_influence$cluster_influence == i, ]
  if (nrow(helis_cluster) == 0) {
    stop("Cluster ", i, " has no helipad to calculate the influence radius.")
  }
  quantile(helis_cluster$vertiport_distance, 0.95, na.rm = TRUE)
})

vertiports$influence_radius_km <- radii_influence

cat("   Helipads assigned to influence regions\n")
cat("   Influence radii (95% coverage):\n")
for (i in 1:NUM_CLUSTERS) {
  cat("     VP-", sprintf("%03d", i), ": ", round(radii_influence[i], 2), " km\n", sep="")
}
cat("\n")

# ========== CALCULATE SOCIOECONOMIC INDICES BY CLUSTER ==========
cat("8. Calculating socioeconomic quality indices by cluster...\n")
cat("   IMPORTANT: Using ALL helipads from the complete set after reclustering\n")
cat("   (Not just the filtered helipads used to find medoids)\n\n")

# Use ALL basic zones to validate the calculations, because 
# all helipads in basic zones must be considered
if (!is.null(zones_sf) && nrow(zones_sf) > 0) {
  # Use basic_zones_ids (WITHOUT filter) which includes ALL zones with income > 0
  # this corresponds to the helipads_complete set
  qualified_zones_sf_calculation <- zones_sf %>%
    filter(NumeroZona %in% basic_zones_ids)
  cat("   Using", nrow(qualified_zones_sf_calculation), "valid basic zones (without percentile filter)\n")
  cat("   Helipads dataset: helipads_complete (all after reclustering, n=", nrow(helipads_complete), ")\n\n", sep="")
} else {
  qualified_zones_sf_calculation <- zones_sf
  cat("   WARNING: Using all zones in calculations\n")
}

# CRITICAL: Calculate indices using ALL helipads from the complete set after reclustering
# (not just the helipads from the influence region, but all reclustered helipads)
cat("   Calculating indices based on ALL reclustered helipads...\n")
clusters_indices <- data.frame()
zones_per_cluster <- list()

for (i in 1:NUM_CLUSTERS) {
  # IMPORTANT: use helipads_complete (after reclustering), not helipads_influence
  helis_cluster <- helipads_complete[helipads_complete$cluster == i, ]
  cat("   Cluster", i, ":", nrow(helis_cluster), "helipads reclustered\n")
  indices <- calculate_cluster_indices(helis_cluster, qualified_zones_sf_calculation)
  
  # Store zones of each cluster for later OD calculation
  zones_per_cluster[[i]] <- indices$zones_ids
  
  clusters_indices <- rbind(clusters_indices, data.frame(
    cluster = i,
    vertiport_id = paste0("VP-", sprintf("%03d", i)),
    n_helipads = nrow(helis_cluster),
    n_zones = indices$n_zones,
    mean_income = round(indices$mean_income, 2),
    total_population = round(indices$total_population, 0),
    total_demand = round(indices$total_demand, 0),
    total_trips_attracted = round(indices$total_trips_attracted, 0),
    combined_index = round(indices$combined, 3),
    coverage_population = round(indices$coverage_population, 0),
    influence_radius_km = round(vertiports$influence_radius_km[i], 2),
    silhouette_original = round(vertiports$silhouette[i], 3),
    silhouette_reclustered = round(vertiports$silhouette_reclustered[i], 3),
    stringsAsFactors = FALSE
  ))
  
  cat("   Cluster", i, "(", paste0("VP-", sprintf("%03d", i)), "):\n", sep="")
  cat("     Covered zones:", indices$n_zones, "\n")
  cat("     Per capita income (weighted): R$", round(indices$mean_income, 2), "\n")
  cat("     Total population:", format(round(indices$total_population, 0), big.mark=","), "inhabitants\n")
  cat("     Trips Produced (demand):", format(round(indices$total_demand, 0), big.mark=","), "trips/day\n")
  cat("     Trips Attracted:", format(round(indices$total_trips_attracted, 0), big.mark=","), "trips/day\n")
  cat("     Combined index:", round(indices$combined, 3), "\n")
  cat("     Coverage population:", format(round(indices$coverage_population, 0), big.mark=","), "\n")
  cat("     Silhouette (original):", round(vertiports$silhouette[i], 3), "\n")
  cat("     Silhouette (reclustered):", round(vertiports$silhouette_reclustered[i], 3), "\n\n")
}

# Save indices
write.csv(original_cluster_indices, "output/cluster_socioeconomics_indices_original.csv", row.names = FALSE)
cat("✓ Original cluster indices saved to: output/cluster_socioeconomics_indices_original.csv\n")
write.csv(clusters_indices, "output/cluster_socioeconomics_indices.csv", row.names = FALSE)
cat("✓ Reclustered indices saved to: output/cluster_socioeconomics_indices.csv\n\n")

# ========== LOAD ENTIRE OD MATRIX ==========
cat("Loading entire OD matrix from 2023 OD Survey...\n")

od_matrix_complete <- tryCatch({
  # Load processed CSV (format: origin, destination, trips)
  df_od <- read_csv("data/processed/od_matrix_30.csv", show_col_types = FALSE, progress = FALSE)
  
  # Get all unique zones
  all_zones <- sort(unique(c(df_od$origin, df_od$destination)))
  n_zones <- length(all_zones)
  
  # Create empty matrix
  matrix <- matrix(0, nrow = n_zones, ncol = n_zones)
  rownames(matrix) <- as.character(all_zones)
  colnames(matrix) <- as.character(all_zones)
  
  # Fill matrix with values
  for (i in 1:nrow(df_od)) {
    orig <- as.character(df_od$origin[i])
    dest <- as.character(df_od$destination[i])
    trips <- df_od$trips[i]
    
    if (orig %in% rownames(matrix) && dest %in% colnames(matrix)) {
      matrix[orig, dest] <- trips
    }
  }
  
  cat("   ✓ OD matrix loaded:", nrow(matrix), "x", ncol(matrix), "zones\n")
  cat("   ✓ Total trips:", format(sum(matrix, na.rm = TRUE), big.mark = ","), "\n\n")
  
  matrix
}, error = function(e) {
  cat("   ⚠ OD matrix not found...\n")
  cat("   Error:", e$message, "\n\n")
  NULL
})

# ========== CREATE AIRPORT-BASED DEMAND MATRIX ==========
cat("Creating airport-based demand matrix using ANAC passenger data...\n\n")

# Function to create airport-based OD matrix
create_airport_demand_matrix <- function(airport_code, pax_day, rmsp_capture_rate, helipads_per_zone_arg) {
  # Calculate RMSP-bound passengers for this airport
  rmsp_pax <- pax_day * rmsp_capture_rate
  
  # Create demand vector distributed by helipad density across zones
  airport_demand <- numeric(0)
  names(airport_demand) <- character(0)
  
  # Flatten the nested list: helipads_per_zone[[cluster]][[zone]] to get all zones
  total_helis <- 0
  zone_helis_list <- list()
  
  for (cluster_idx in seq_along(helipads_per_zone_arg)) {
    cluster_data <- helipads_per_zone_arg[[cluster_idx]]
    if (is.list(cluster_data)) {
      for (zone_char in names(cluster_data)) {
        zone_helis <- cluster_data[[zone_char]]
        if (is.numeric(zone_helis) && zone_helis > 0) {
          if (!(zone_char %in% names(zone_helis_list))) {
            zone_helis_list[[zone_char]] <- 0
          }
          zone_helis_list[[zone_char]] <- zone_helis_list[[zone_char]] + zone_helis
          total_helis <- total_helis + zone_helis
        }
      }
    }
  }
  
  # Distribute demand proportional to helipad count in each zone
  if (total_helis > 0) {
    for (zone_char in names(zone_helis_list)) {
      zone_helis <- zone_helis_list[[zone_char]]
      zone_demand <- rmsp_pax * (zone_helis / total_helis)
      airport_demand[zone_char] <- zone_demand
    }
    
    cat("   ", airport_code, "- RMSP passengers:", format(round(rmsp_pax, 0), big.mark = ","), "pax/day\n")
    cat("        Total helipads across all zones:", format(total_helis, big.mark = ","), "\n")
    cat("        Distribution by helipad density across", length(zone_helis_list), "zones\n\n")
    return(airport_demand)
  }
  
  cat("   Warning: No helipad data found for airport", airport_code, "\n\n")
  return(NULL)
}

# Create demand matrices for each airport
airport_demand_matrices <- list()

cat("Processing airport shuttle demand:\n")
airport_demand_matrices$SBGR <- create_airport_demand_matrix(
  "SBGR", 
  AIRPORT_PASSENGER_DATA$SBGR$pax_day,
  AIRPORT_RMSP_CAPTURE_RATE$SBGR,
  helipads_per_zone
)

airport_demand_matrices$SBSP <- create_airport_demand_matrix(
  "SBSP", 
  AIRPORT_PASSENGER_DATA$SBSP$pax_day,
  AIRPORT_RMSP_CAPTURE_RATE$SBSP,
  helipads_per_zone
)

airport_demand_matrices$SBMT <- create_airport_demand_matrix(
  "SBMT", 
  AIRPORT_PASSENGER_DATA$SBMT$pax_day,
  AIRPORT_RMSP_CAPTURE_RATE$SBMT,
  helipads_per_zone
)

# ========== CALCULATE OD DEMAND BETWEEN PAIRS OF VERTIPORTS ==========
cat("Calculating OD demand between pairs of vertiports (with aggregation by cluster)...\n")

# DIAGNOSTIC: Show what we're using for OD calculation
cat("\n=== FINAL PRE-OD DIAGNOSTIC ===\n")
cat("Total helipads in total_helipads_cluster:", sum(total_helipads_cluster), "\n")
cat("Total helipads in total_helipads_per_zone:", sum(unlist(total_helipads_per_zone)), "\n")
cat("Zones being used for OD:", length(total_helipads_per_zone), "\n")
cat("Clusters:", NUM_CLUSTERS, "\n\n")

# Auxiliary function to calculate distance between zones
calculate_zones_distance <- function(zone1, zone2) {
  if (is.null(zones_sf)) return(NA)
  if (length(zone1) == 0 || length(zone2) == 0) return(NA)
  if (any(is.na(zone1)) || any(is.na(zone2))) return(NA)
  
  z1 <- zones_sf[zones_sf$NumeroZona == zone1[1], ]
  z2 <- zones_sf[zones_sf$NumeroZona == zone2[1], ]
  
  if (nrow(z1) == 0 || nrow(z2) == 0) return(NA)
  
  # Transform to metric CRS to calculate centroids (more precise)
  z1_utm <- st_transform(z1, 31983)
  z2_utm <- st_transform(z2, 31983)
  
  centroid1 <- st_centroid(st_geometry(z1_utm))
  centroid2 <- st_centroid(st_geometry(z2_utm))
  
  # Calculate geodesic distance between centroids (in km)
  dist_m <- as.numeric(st_distance(centroid1, centroid2))
  dist_km <- dist_m / 1000  # Convert meters to km
  
  return(dist_km)
}

# Create dataframe of OD demand between pairs
demand_od_pairs <- data.frame()

for (i in 1:(NUM_CLUSTERS-1)) {
  for (j in (i+1):NUM_CLUSTERS) {
    zone_vp_origin <- vertiports$zone_od[i]
    zone_vp_destination <- vertiports$zone_od[j]
    cluster_origin <- i
    cluster_destination <- j
    
    # Get zones of clusters
    zones_cluster_origin <- zones_per_cluster[[cluster_origin]]
    zones_cluster_destination <- zones_per_cluster[[cluster_destination]]
    
    # Calculate distance VP origin -> VP destination
    dist_vp_vp <- calculate_zones_distance(zone_vp_origin, zone_vp_destination)
    
    demand_ij <- 0
    demand_ji <- 0
    
    if (!is.null(od_matrix_complete) && length(zones_cluster_origin) > 0 && 
        length(zones_cluster_destination) > 0 && !is.na(dist_vp_vp)) {
      
      # Aggregate demand only from zones WITH helipads
      zones_with_helis_origin <- names(helipads_per_zone[[cluster_origin]])
      zones_with_helis_destination <- names(helipads_per_zone[[cluster_destination]])
      
      for (zone_o_char in zones_with_helis_origin) {
        for (zone_d_char in zones_with_helis_destination) {
          zone_o <- as.numeric(zone_o_char)
          zone_d <- as.numeric(zone_d_char)
          
          # Check if zones exist in the matrix
          if (zone_o_char %in% rownames(od_matrix_complete) && 
              zone_d_char %in% colnames(od_matrix_complete)) {
            
            # OD matrix gross demand
            gross_demand <- od_matrix_complete[zone_o_char, zone_d_char]
            
            if (!is.na(gross_demand) && gross_demand > 0) {
              # Calculate direct distance zone_o -> zone_d
              dist_direct <- calculate_zones_distance(zone_o, zone_d)
              
              if (!is.na(dist_direct) && dist_direct > 0) {
                # Calculate distance via vertiports: zone_o -> VP_o + VP_o -> VP_d + VP_d -> zone_d
                dist_zo_vpo <- calculate_zones_distance(zone_o, zone_vp_origin)
                dist_vpd_zd <- calculate_zones_distance(zone_vp_destination, zone_d)
                
                # Distances cannot be NA
                if (is.na(dist_zo_vpo)) {
                  stop("Distance zone_o (", zone_o, ") -> vertiport_origin cannot be calculated")
                }
                if (is.na(dist_vpd_zd)) {
                  stop("Distance vertiport_destination -> zone_d (", zone_d, ") cannot be calculated")
                }
                
                dist_via_vp <- dist_zo_vpo + dist_vp_vp + dist_vpd_zd
                
                # Distance factor: the smaller the detour, the higher the weight
                # If dist_direct = dist_via_vp (no detour), factor   = 1
                # If dist_via_vp > dist_direct (detour), factor < 1
                factor_dist <- dist_direct / dist_via_vp
                
                # Obtain number of helipads in the zones
                helis_zone_o <- helipads_per_zone[[cluster_origin]][[zone_o_char]]
                helis_zone_d <- helipads_per_zone[[cluster_destination]][[zone_d_char]]
                
                # Share factor (proportion of helipads of the cluster in the zone)
                # If zone has helipads from multiple clusters, divide proportionally
                total_helis_zone_o <- total_helipads_per_zone[[zone_o_char]]
                total_helis_zone_d <- total_helipads_per_zone[[zone_d_char]]
                factor_share_o <- helis_zone_o / total_helis_zone_o
                factor_share_d <- helis_zone_d / total_helis_zone_d
                
                # Fator de helipads (proporção do cluster)
                factor_helis_o <- helis_zone_o / total_helipads_cluster[cluster_origin]
                factor_helis_d <- helis_zone_d / total_helipads_cluster[cluster_destination]
                
                # Geometric mean of helipads factors
                factor_helis_geom <- sqrt(factor_helis_o * factor_helis_d)
                
                # Geometric mean of share factors
                factor_share_geom <- sqrt(factor_share_o * factor_share_d)
                
                # Final weight: geometric mean of helipads × geometric mean of share × distance factor
                weight <- factor_helis_geom * factor_share_geom * factor_dist
                
                # Aggregate weighted demand
                demand_ij <- demand_ij + (gross_demand * weight)
              }
            }
          }
          
          # Inverse direction (zone_d -> zone_o)
          if (zone_d_char %in% rownames(od_matrix_complete) && 
              zone_o_char %in% colnames(od_matrix_complete)) {
            
            gross_demand_inv <- od_matrix_complete[zone_d_char, zone_o_char]
            
            if (!is.na(gross_demand_inv) && gross_demand_inv > 0) {
              # Inverse direction: zone_d -> zone_o
              dist_direct <- calculate_zones_distance(zone_d, zone_o)
              
              if (!is.na(dist_direct) && dist_direct > 0) {
                # Distance via vertiports: zone_d -> VP_d + VP_d -> VP_o + VP_o -> zone_o
                dist_zd_vpd <- calculate_zones_distance(zone_d, zone_vp_destination)
                dist_vpo_zo <- calculate_zones_distance(zone_vp_origin, zone_o)
                
                if (is.na(dist_zd_vpd)) {
                  stop("It was not possible to calculate the distance from zone_d (", zone_d, ") to vertiport_destination")
                }
                if (is.na(dist_vpo_zo)) {
                  stop("It was not possible to calculate the distance from vertiport_origin to zone_o (", zone_o, ")")
                }
                
                dist_via_vp <- dist_zd_vpd + dist_vp_vp + dist_vpo_zo
                
                factor_dist <- dist_direct / dist_via_vp
                
                # Helipads already obtained above
                helis_zone_o <- helipads_per_zone[[cluster_origin]][[zone_o_char]]
                helis_zone_d <- helipads_per_zone[[cluster_destination]][[zone_d_char]]
                
                # Share factor (proportion of cluster helipads in the zone)
                total_helis_zone_o <- total_helipads_per_zone[[zone_o_char]]
                total_helis_zone_d <- total_helipads_per_zone[[zone_d_char]]
                factor_share_o <- helis_zone_o / total_helis_zone_o
                factor_share_d <- helis_zone_d / total_helis_zone_d
                
                factor_helis_o <- helis_zone_o / total_helipads_cluster[cluster_origin]
                factor_helis_d <- helis_zone_d / total_helipads_cluster[cluster_destination]
                factor_helis_geom <- sqrt(factor_helis_o * factor_helis_d)
                
                # Geometric mean of share factors
                factor_share_geom <- sqrt(factor_share_o * factor_share_d)
                
                weight <- factor_helis_geom * factor_share_geom * factor_dist
                demand_ji <- demand_ji + (gross_demand_inv * weight)
              }
            }
          }
        }
      }
      
      # Apply City Taxi conversion factor
      if (demand_ij > 0) {
        demand_ij <- ceiling(demand_ij * CITY_TAXI_CONVERSION_FACTOR)
      }
      if (demand_ji > 0) {
        demand_ji <- ceiling(demand_ji * CITY_TAXI_CONVERSION_FACTOR)
      }
    } else {
      # There are not enough data to calculate OD between clusters
      stop("It was not possible to calculate demand between clusters ", i, " and ", j, ". ",
           "Check: od_matrix_complete=", !is.null(od_matrix_complete), 
           ", zones_origin=", length(zones_cluster_origin),
           ", zones_destination=", length(zones_cluster_destination),
           ", dist_vp_vp=", !is.na(dist_vp_vp))
    }
    
    demand_total_pair <- demand_ij + demand_ji
    
    demand_od_pairs <- rbind(demand_od_pairs, data.frame(
      pair = paste0("VP-", sprintf("%03d", i), " <-> VP-", sprintf("%03d", j)),
      vp_origin = paste0("VP-", sprintf("%03d", i)),
      vp_destination = paste0("VP-", sprintf("%03d", j)),
      demand_ij = round(demand_ij, 0),
      demand_ji = round(demand_ji, 0),
      demand_total = round(demand_total_pair, 0),
      n_zones_i = length(zones_cluster_origin),
      n_zones_j = length(zones_cluster_destination),
      stringsAsFactors = FALSE
    ))
    
    cat("  ", paste0("VP-", sprintf("%03d", i)), "<->", paste0("VP-", sprintf("%03d", j)), ":",
        format(round(demand_total_pair, 0), big.mark=","), "trips/day\n")
  }
}

# Calculate total demand between all pairs
demand_od_total <- sum(demand_od_pairs$demand_total, na.rm = TRUE)
cat("\n  Total OD demand between all vertiport pairs:",
    format(round(demand_od_total, 0), big.mark=","), "trips/day\n")

# Save total OD demand between pairs
write.csv(demand_od_pairs, "output/demand_od_pairs_vertiports.csv", row.names = FALSE)
cat("✓ Total OD demand between pairs saved in: output/demand_od_pairs_vertiports.csv\n")

# Create complete OD matrix (matrix format) for vertiports
cat("Generating complete OD matrix for vertiports...\n")
matrix_od_vertiports <- matrix(0, nrow = NUM_CLUSTERS, ncol = NUM_CLUSTERS)
rownames(matrix_od_vertiports) <- paste0("VP-", sprintf("%03d", 1:NUM_CLUSTERS))
colnames(matrix_od_vertiports) <- paste0("VP-", sprintf("%03d", 1:NUM_CLUSTERS))

for (k in 1:nrow(demand_od_pairs)) {
  pair_info <- demand_od_pairs[k, ]
  i <- as.numeric(gsub("VP-", "", pair_info$vp_origin))
  j <- as.numeric(gsub("VP-", "", pair_info$vp_destination))
  
  matrix_od_vertiports[i, j] <- pair_info$demand_ij
  matrix_od_vertiports[j, i] <- pair_info$demand_ji
}

# Save complete OD matrix
write.csv(matrix_od_vertiports, "output/matrix_od_vertiports.csv", row.names = TRUE)
cat("✓ Complete OD matrix saved in: output/matrix_od_vertiports.csv\n\n")

# ========== ANALYSIS WITH AIRPORTS INCLUDED ==========
cat("========== EXTENDED ANALYSIS: VERTIPORTS + AIRPORTS ==========\n")
cat("Including airports SBSP, SBGR, and SBMT in the analysis...\n\n")

# Define airport locations
airports <- data.frame(
  id = c("SBSP", "SBGR", "SBMT"),
  name = c("Congonhas (SBSP)", "Guarulhos (SBGR)", "Campo de Marte (SBMT)"),
  code = c("SBSP", "SBGR", "SBMT"),
  type = "Airport",
  lat = c(-23.626111, -23.435556, -23.509000),
  lon = c(-46.656389, -46.473056, -46.633000),
  stringsAsFactors = FALSE
)

# Convert airports to sf
airports_sf <- st_as_sf(airports, coords = c("lon", "lat"), crs = 4326)
coords_airports <- st_coordinates(airports_sf)
airports$lon <- coords_airports[, "X"]
airports$lat <- coords_airports[, "Y"]

# Calculate indices for each airport
cat("Calculating socioeconomic indices for airports...\n")
indices_airports <- data.frame()
for (i in 1:nrow(airports)) {
  # Create "pseudo-cluster" with a single point (the airport)
  airport_point <- airports[i, ]
  indices_airport <- calculate_cluster_indices(airport_point, qualified_zones_sf_calculation)
  
  indices_airports <- rbind(indices_airports, data.frame(
    point = airports$id[i],
    point_id = airports$id[i],
    type = "Airport",
    n_zones = indices_airport$n_zones,
    mean_income = round(indices_airport$mean_income, 2),
    total_demand = round(indices_airport$total_demand, 0),
    total_trips_attracted= round(indices_airport$total_trips_attracted, 0),
    combined_index = round(indices_airport$combined, 3),
    coverage_population = round(indices_airport$coverage_population, 0),
    stringsAsFactors = FALSE
  ))
  
  # Store zones for OD calculation
  zones_per_cluster[[NUM_CLUSTERS + i]] <- indices_airport$zones_ids
  
  cat("  ", airports$id[i], ":", indices_airport$n_zones, "zones,",
      format(round(indices_airport$total_demand, 0), big.mark=","), "trips produced/day\n")
}

cat("\n")

# Create expanded set (vertiports + airports)
expanded_set <- data.frame(
  point_id = c(paste0("VP-", sprintf("%03d", 1:NUM_CLUSTERS)), airports$id),
  type = c(rep("Vertiport", NUM_CLUSTERS), rep("Airport", nrow(airports))),
  n_zones = c(clusters_indices$n_zones, indices_airports$n_zones),
  mean_income = c(clusters_indices$mean_income, indices_airports$mean_income),
  total_demand = c(clusters_indices$total_demand, indices_airports$total_demand),
  total_trips_attracted = c(clusters_indices$total_trips_attracted, indices_airports$total_trips_attracted),
  combined_index = c(clusters_indices$combined_index, indices_airports$combined_index),
  coverage_population = c(clusters_indices$coverage_population, indices_airports$coverage_population),
  stringsAsFactors = FALSE
)

# Identify zones of airports
cat("Identifying zones of airports...\n")
airports_sf_zones <- st_as_sf(airports, coords = c("lon", "lat"), crs = 4326)
airports_with_zone <- suppressWarnings(st_join(airports_sf_zones, zones_sf, join = st_within))
airports$zone_od <- airports_with_zone$NumeroZona

for (i in 1:nrow(airports)) {
  if (!is.na(airports$zone_od[i])) {
    cat("   ", airports$id[i], "-> Zone", airports$zone_od[i], "\n")
  }
}
cat("\n")

# Calculate OD demand between all pairs (vertiports + airports)
cat("Calculating OD demand between all pairs (vertiports + airports)...\n")
n_total <- NUM_CLUSTERS + nrow(airports)

# Start with existing vertiport-vertiport demand
demand_od_expanded <- demand_od_pairs %>%
  mutate(
    origin_point = vp_origin,
    destination_point = vp_destination,
    origin_type = "Vertiport",
    destination_type = "Vertiport"
  ) %>%
  select(pair, origin_point, destination_point, origin_type, destination_type, 
         demand_ij, demand_ji, demand_total)

# Create expanded matrix to store values
expanded_od_matrix <- matrix(0, nrow = n_total, ncol = n_total)
expanded_zones <- c(vertiports$zone_od, airports$zone_od)
expanded_ids <- c(paste0("VP-", sprintf("%03d", 1:NUM_CLUSTERS)), airports$id)
expanded_clusters <- c(1:NUM_CLUSTERS, rep(NA, nrow(airports)))

rownames(expanded_od_matrix) <- expanded_ids
colnames(expanded_od_matrix) <- expanded_ids

# Fill matrix with already calculated VP-VP values
for (k in 1:nrow(demand_od_pairs)) {
  pair_info <- demand_od_pairs[k, ]
  i <- as.numeric(gsub("VP-", "", pair_info$vp_origin))
  j <- as.numeric(gsub("VP-", "", pair_info$vp_destination))
  
  expanded_od_matrix[i, j] <- pair_info$demand_ij
  expanded_od_matrix[j, i] <- pair_info$demand_ji
}

# Now calculate only pairs involving airports (VP-Airport and Airport-Airport)
for (i in 1:n_total) {
  for (j in 1:n_total) {
    if (i >= j) next  # Skip diagonal and lower half
    
    cluster_origin <- expanded_clusters[i]
    cluster_destination <- expanded_clusters[j]
    
    # Skip VP-VP pairs (already calculated)
    if (!is.na(cluster_origin) && !is.na(cluster_destination)) next
    
    zone_origin <- expanded_zones[i]
    zone_destination <- expanded_zones[j]
    
    demand_ij <- 0
    demand_ji <- 0
    
    # CASE 4: Airport → Airport (TRANSFERS)
    if (is.na(cluster_origin) && is.na(cluster_destination)) {
      id_origin <- expanded_ids[i]
      id_destination <- expanded_ids[j]
      transfer_key_ij <- paste0(id_origin, "_", id_destination)
      transfer_key_ji <- paste0(id_destination, "_", id_origin)
      
      # Direction i -> j
      if (transfer_key_ij %in% names(TRANSFERS_AP_AP_PAX)) {
        pax_transfer <- TRANSFERS_AP_AP_PAX[[transfer_key_ij]]
        pax_uam <- pax_transfer * TRANSFER_CONVERSION_FACTOR
        viagens_uam <- pax_uam / EVTOL_CAPACITY
        demand_ij <- ceiling(viagens_uam)
      }
      
      # Direction j -> i
      if (transfer_key_ji %in% names(TRANSFERS_AP_AP_PAX)) {
        pax_transfer <- TRANSFERS_AP_AP_PAX[[transfer_key_ji]]
        pax_uam <- pax_transfer * TRANSFER_CONVERSION_FACTOR
        trips_uam <- pax_uam / EVTOL_CAPACITY
        demand_ji <- ceiling(trips_uam)
      }
    }
    # CASE 2: VP → Airport (using airport-based demand with helipad aggregation)
    if (!is.na(cluster_origin) && is.na(cluster_destination)) {
      
      # Determine which airport this is
      airport_id <- expanded_ids[j]
      airport_demand_vector <- NULL
      
      if (airport_id == "SBGR" && !is.null(airport_demand_matrices$SBGR)) {
        airport_demand_vector <- airport_demand_matrices$SBGR
      } else if (airport_id == "SBSP" && !is.null(airport_demand_matrices$SBSP)) {
        airport_demand_vector <- airport_demand_matrices$SBSP
      } else if (airport_id == "SBMT" && !is.null(airport_demand_matrices$SBMT)) {
        airport_demand_vector <- airport_demand_matrices$SBMT
      }
      
      # If we have airport demand data, aggregate it using helipad factors
      if (!is.null(airport_demand_vector)) {
        # Filter only zones that have helipads in this cluster
        zones_cluster_origin <- intersect(
          zones_per_cluster[[cluster_origin]],
          as.numeric(names(helipads_per_zone[[cluster_origin]]))
        )
        zone_vp_origin <- vertiports$zone_od[cluster_origin]
        
        for (zone_o in zones_cluster_origin) {
          zone_orig_char <- as.character(zone_o)
          
          # Get demand from airport demand vector (outbound from zone to airport)
          if (zone_orig_char %in% names(airport_demand_vector)) {
            gross_demand <- airport_demand_vector[[zone_orig_char]]
            
            if (!is.na(gross_demand) && gross_demand > 0) {
              # Calculate factors on the vertiport side (origin)
              helis_zone_o <- ifelse(as.character(zone_o) %in% names(helipads_per_zone[[cluster_origin]]),
                                     helipads_per_zone[[cluster_origin]][[as.character(zone_o)]], 0)
              total_helis_zone_o <- total_helipads_per_zone[[zone_orig_char]]
              
              # Factor of helipads
              factor_helis_o <- helis_zone_o / total_helipads_cluster[[cluster_origin]]
              
              # Share factor (cluster dominance in the zone)
              factor_share_o <- helis_zone_o / total_helis_zone_o
              
              # Distance factor (zone to VP to airport vs direct)
              dist_direct <- calculate_zones_distance(zone_o, zone_destination)
              dist_zo_vpo <- calculate_zones_distance(zone_o, zone_vp_origin)
              dist_vpo_ap <- calculate_zones_distance(zone_vp_origin, zone_destination)
              
              if (!is.na(dist_zo_vpo) && !is.na(dist_vpo_ap)) {
                dist_via_vp <- dist_zo_vpo + dist_vpo_ap
                
                if (!is.na(dist_direct) && dist_direct > 0 && dist_via_vp > 0) {
                  factor_dist <- dist_direct / dist_via_vp
                } else {
                  factor_dist <- 1.0
                }
              } else {
                factor_dist <- 1.0
              }
              
              # Final weight: product of factors
              weight <- factor_helis_o * factor_share_o * factor_dist
              
              demand_ij <- demand_ij + (gross_demand * weight)
            }
          }
          
          # Reverse direction (Airport → VP using same demand vector)
          if (zone_orig_char %in% names(airport_demand_vector)) {
            gross_demand_inv <- airport_demand_vector[[zone_orig_char]]
            
            if (!is.na(gross_demand_inv) && gross_demand_inv > 0) {
              helis_zone_o <- ifelse(as.character(zone_o) %in% names(helipads_per_zone[[cluster_origin]]),
                                     helipads_per_zone[[cluster_origin]][[as.character(zone_o)]], 0)
              total_helis_zone_o <- total_helipads_per_zone[[zone_orig_char]]
              
              factor_helis_o <- helis_zone_o / total_helipads_cluster[[cluster_origin]]
              factor_share_o <- helis_zone_o / total_helis_zone_o
              
              dist_direct <- calculate_zones_distance(zone_destination, zone_o)
              dist_ap_zo <- calculate_zones_distance(zone_destination, zone_o)
              dist_zo_vpo <- calculate_zones_distance(zone_o, zone_vp_origin)
              
              if (!is.na(dist_ap_zo) && !is.na(dist_zo_vpo)) {
                dist_via_vp <- dist_ap_zo + dist_zo_vpo
                
                if (!is.na(dist_direct) && dist_direct > 0 && dist_via_vp > 0) {
                  factor_dist <- dist_direct / dist_via_vp
                } else {
                  factor_dist <- 1.0
                }
              } else {
                factor_dist <- 1.0
              }
              
              factor <- factor_helis_o * factor_share_o * factor_dist
              demand_ji <- demand_ji + (gross_demand_inv * factor)
            }
          }
        }
      }
      
      # Apply conversion factor to convert passengers to UAM trips
      demand_ij <- ceiling((demand_ij / EVTOL_CAPACITY) * AIRPORT_SHUTTLE_CONVERSION_FACTOR)
      demand_ji <- ceiling((demand_ji / EVTOL_CAPACITY) * AIRPORT_SHUTTLE_CONVERSION_FACTOR)
    }
    
    # CASE 3: Airport → VP (using airport-based demand with helipad aggregation)
    if (is.na(cluster_origin) && !is.na(cluster_destination)) {
      
      # Determine which airport this is
      airport_id <- expanded_ids[i]
      airport_demand_vector <- NULL
      
      if (airport_id == "SBGR" && !is.null(airport_demand_matrices$SBGR)) {
        airport_demand_vector <- airport_demand_matrices$SBGR
      } else if (airport_id == "SBSP" && !is.null(airport_demand_matrices$SBSP)) {
        airport_demand_vector <- airport_demand_matrices$SBSP
      } else if (airport_id == "SBMT" && !is.null(airport_demand_matrices$SBMT)) {
        airport_demand_vector <- airport_demand_matrices$SBMT
      }
      
      # If we have airport demand data, aggregate it using helipad factors
      if (!is.null(airport_demand_vector)) {
        # Filter only zones that have helipads in this cluster
        zones_cluster_destination <- intersect(
          zones_per_cluster[[cluster_destination]],
          as.numeric(names(helipads_per_zone[[cluster_destination]]))
        )
        zone_vp_destination <- vertiports$zone_od[cluster_destination]
        
        for (zone_d in zones_cluster_destination) {
          zone_dest_char <- as.character(zone_d)
          
          # Get demand to this zone from airport demand vector (inbound from airport)
          if (zone_dest_char %in% names(airport_demand_vector)) {
            gross_demand <- airport_demand_vector[[zone_dest_char]]
            
            if (!is.na(gross_demand) && gross_demand > 0) {
              # Calculate factors on the vertiport side (destination)
              helis_zone_d <- ifelse(as.character(zone_d) %in% names(helipads_per_zone[[cluster_destination]]),
                                     helipads_per_zone[[cluster_destination]][[as.character(zone_d)]], 0)
              total_helis_zone_d <- total_helipads_per_zone[[zone_dest_char]]
              
              # Helipad factor
              factor_helis_d <- helis_zone_d / total_helipads_cluster[cluster_destination]
              
              # Share factor (cluster dominance in the zone)
              factor_share_d <- helis_zone_d / total_helis_zone_d
              
              # Distance factor
              dist_direct <- calculate_zones_distance(zone_origin, zone_d)
              dist_ap_vpd <- calculate_zones_distance(zone_origin, zone_vp_destination)
              dist_vpd_zd <- calculate_zones_distance(zone_vp_destination, zone_d)
              
              if (!is.na(dist_ap_vpd) && !is.na(dist_vpd_zd)) {
                dist_via_vp <- dist_ap_vpd + dist_vpd_zd
                
                if (!is.na(dist_direct) && dist_direct > 0 && dist_via_vp > 0) {
                  factor_dist <- dist_direct / dist_via_vp
                } else {
                  factor_dist <- 1.0
                }
              } else {
                factor_dist <- 1.0
              }
              
              # Final weight (product of the 3 factors)
              weight <- factor_helis_d * factor_share_d * factor_dist
              
              demand_ij <- demand_ij + (gross_demand * weight)
            }
          }
          
          # Reverse direction (VP → Airport using same demand vector)
          if (zone_dest_char %in% names(airport_demand_vector)) {
            gross_demand_inv <- airport_demand_vector[[zone_dest_char]]
            
            if (!is.na(gross_demand_inv) && gross_demand_inv > 0) {
              helis_zone_d <- ifelse(as.character(zone_d) %in% names(helipads_per_zone[[cluster_destination]]),
                                     helipads_per_zone[[cluster_destination]][[as.character(zone_d)]], 0)
              total_helis_zone_d <- total_helipads_per_zone[[zone_dest_char]]
              
              factor_helis_d <- helis_zone_d / total_helipads_cluster[cluster_destination]
              factor_share_d <- helis_zone_d / total_helis_zone_d
              
              dist_direct <- calculate_zones_distance(zone_d, zone_origin)
              dist_zd_vpd <- calculate_zones_distance(zone_d, zone_vp_destination)
              dist_vpd_ap <- calculate_zones_distance(zone_vp_destination, zone_origin)
              
              if (!is.na(dist_zd_vpd) && !is.na(dist_vpd_ap)) {
                dist_via_vp <- dist_zd_vpd + dist_vpd_ap
                
                if (!is.na(dist_direct) && dist_direct > 0 && dist_via_vp > 0) {
                  factor_dist <- dist_direct / dist_via_vp
                } else {
                  factor_dist <- 1.0
                }
              } else {
                factor_dist <- 1.0
              }
              
              weight <- factor_helis_d * factor_share_d * factor_dist
              
              demand_ji <- demand_ji + (gross_demand_inv * weight)
            }
          }
        }
      }
      
      # Apply conversion factor to convert passengers to UAM trips
      demand_ij <- ceiling((demand_ij / EVTOL_CAPACITY) * AIRPORT_SHUTTLE_CONVERSION_FACTOR)
      demand_ji <- ceiling((demand_ji / EVTOL_CAPACITY) * AIRPORT_SHUTTLE_CONVERSION_FACTOR)
    }
    
    # Preencher matriz expandida
    expanded_od_matrix[i, j] <- demand_ij
    expanded_od_matrix[j, i] <- demand_ji
    
    demand_total_pair <- demand_ij + demand_ji
    
    id_i <- expanded_ids[i]
    id_j <- expanded_ids[j]
    type_i <- if (is.na(cluster_origin)) "Airport" else "Vertiport"
    type_j <- if (is.na(cluster_destination)) "Airport" else "Vertiport"
    
    demand_od_expanded <- rbind(demand_od_expanded, data.frame(
      pair = paste0(id_i, " <-> ", id_j),
      origin_point = id_i,
      destination_point = id_j,
      origin_type = type_i,
      destination_type = type_j,
      demand_ij = round(demand_ij, 0),
      demand_ji = round(demand_ji, 0),
      demand_total = round(demand_total_pair, 0),
      stringsAsFactors = FALSE
    ))
  }
}

# Calculate total demand of the expanded set
demand_od_expanded_total <- sum(demand_od_expanded$demand_total, na.rm = TRUE)

cat("  Total OD demand (vertiports + airports):",
    format(round(demand_od_expanded_total, 0), big.mark=","), "trips/day\n")
cat("  Increase compared to isolated vertiports:",
    format(round((demand_od_expanded_total - demand_od_total) / demand_od_total * 100, 1)),
    "%\n\n")

# Identify pairs with highest demand
demand_od_expanded_ordered <- demand_od_expanded[order(-demand_od_expanded$demand_total), ]
cat("Top 10 pairs with highest OD demand:\n")
for (k in 1:min(10, nrow(demand_od_expanded_ordered))) {
  pair_info <- demand_od_expanded_ordered[k, ]
  cat("  ", k, ".", pair_info$pair, ":", 
      format(pair_info$demand_total, big.mark=","), "trips/day",
      "(", pair_info$origin_type, "-", pair_info$destination_type, ")\n")
}
cat("\n")

# Save expanded matrix
write.csv(expanded_od_matrix, "output/expanded_od_matrix_vertiports_airports.csv", row.names = TRUE)

# Save expanded results
write.csv(expanded_set, "output/expanded_set_vertiports_airports.csv", row.names = FALSE)
write.csv(demand_od_expanded, "output/expanded_od_demand_all_pairs.csv", row.names = FALSE)
cat("✓ Expanded analysis saved in:\n")
cat("  - output/expanded_set_vertiports_airports.csv\n")
cat("  - output/expanded_od_demand_all_pairs.csv\n")
cat("  - output/expanded_od_matrix_vertiports_airports.csv\n\n")

cat("   SUMMARY OF OD MATRICES:\n")
if (!is.null(od_matrix_complete)) {
  cat("   Source of ground demand: OD Survey Matrix 2023 (Table 25)\n")
  cat("   Source of AP-AP transfer demand: ANAC 2019 (passengers/day)\n")
  cat("   City Taxi Factor (VP-VP):", CITY_TAXI_CONVERSION_FACTOR * 100, "%\n")
  cat("   Airport Shuttle Factor (with airports):", AIRPORT_SHUTTLE_CONVERSION_FACTOR * 100, "%\n")
  cat("   Transfer Conversion Factor:", TRANSFER_CONVERSION_FACTOR * 100, "%\n")
  cat("   eVTOL Capacity:", EVTOL_CAPACITY, "passengers\n")
} else {
  cat("   Couldn't find complete OD matrix data.\n")
}
cat("   - Total trips (VP only):", format(round(demand_od_total, 0), big.mark=","), "trips/day\n")
cat("   - Total trips (VP + Airports):", format(round(demand_od_expanded_total, 0), big.mark=","), "trips/day\n")
cat("   - Increase with airports:", format(round((demand_od_expanded_total - demand_od_total) / demand_od_total * 100, 1), nsmall=1), "%\n\n")

# Create complete OD matrix (matrix format) for expanded set
# (Expanded OD matrix has already been created and saved above)

# Compare connectivity: vertiports only vs vertiports + airports
cat("========== CONNECTIVITY COMPARISON ==========\n")
cat("Vertiports Only (", NUM_CLUSTERS, " points):\n", sep="")
cat("  - Possible pairs:", NUM_CLUSTERS * (NUM_CLUSTERS - 1) / 2, "\n")
cat("  - Total OD demand:", format(round(demand_od_total, 0), big.mark=","), "trips/day\n")
cat("  - Average demand per pair:", format(round(demand_od_total / nrow(demand_od_pairs), 0), big.mark=","), "trips/day\n\n")

cat("Vertiports + Airports (", n_total, " points):\n", sep="")
cat("  - Possible pairs:", n_total * (n_total - 1) / 2, "\n")
cat("  - Total OD demand:", format(round(demand_od_expanded_total, 0), big.mark=","), "trips/day\n")
cat("  - Average demand per pair:", format(round(demand_od_expanded_total / nrow(demand_od_expanded), 0), big.mark=","), "trips/day\n\n")

# Analysis of airport contribution
demand_with_airports <- demand_od_expanded %>%
  filter(origin_type == "Airport" | destination_type == "Airport")
demand_airports_total <- sum(demand_with_airports$demand_total, na.rm = TRUE)

cat("Airport Contribution:\n")
cat("  - Pairs involving airports:", nrow(demand_with_airports), "\n")
cat("  - OD demand with airports:", format(round(demand_airports_total, 0), big.mark=","), "trips/day\n")
cat("  - Proportion of total demand:", round(demand_airports_total / demand_od_expanded_total * 100, 1), "%\n\n")

cat("========== END OF EXPANDED ANALYSIS ==========\n\n")

# ========== GENERATE VISUALIZATION ==========
cat("9. Generating interactive visualization...\n")

# Define color palettes for socioeconomic layers
pal_population <- colorNumeric(
  palette = "YlOrRd",
  domain = zones_sf$population,
  na.color = "transparent"
)

pal_trips_produced <- colorNumeric(
  palette = "Blues",
  domain = zones_sf$trips_produced,
  na.color = "transparent"
)

pal_trips_attracted <- colorNumeric(
  palette = "Greens",
  domain = zones_sf$trips_attracted,
  na.color = "transparent"
)

pal_income <- colorNumeric(
  palette = "Purples",
  domain = zones_sf$income_per_capita,
  na.color = "transparent"
)

# Color palette for clusters
cluster_colors <- c("#e41a1c", "#377eb8", "#4daf4a", "#984ea3", "#ff7f00",
                    "#ffff33", "#a65628", "#f781bf", "#999999", "#66c2a5")

# Create base map
map <- leaflet() %>%
  addProviderTiles(provider = providers$CartoDB)

# Add base layers with socioeconomic data
map <- map %>%
  # Layer 1: Population
  { if (!is.null(zones_sf) && nrow(zones_sf) > 0) {
      map_obj <- .
      map_obj <- addPolygons(map_obj,
        data = zones_sf,
        fillColor = ~pal_population(population),
        fillOpacity = 0.6,
        color = "white",
        weight = 1,
        opacity = 0.5,
        group = "Population",
        popup = ~paste0(
          "<b>Zone ", NumeroZona, " - ", NomeZona, "</b><br>",
          "Municipality: ", NomeMunici, "<br>",
          "Population: ", format(population, big.mark=",", scientific=FALSE), "<br>",
          "Households: ", format(households, big.mark=",", scientific=FALSE)
        ),
        label = ~paste("Zone", NumeroZona, "-", NomeZona)
      )
      map_obj
    } else . 
  } %>%
  # Layer 2: Produced Trips
  { if (!is.null(zones_sf) && nrow(zones_sf) > 0) {
      map_obj <- .
      map_obj <- addPolygons(map_obj,
        data = zones_sf,
        fillColor = ~pal_trips_produced(trips_produced),
        fillOpacity = 0.6,
        color = "white",
        weight = 1,
        opacity = 0.5,
        group = "Produced Trips",
        popup = ~paste0(
          "<b>Zone ", NumeroZona, " - ", NomeZona, "</b><br>",
          "Municipality: ", NomeMunici, "<br>",
          "Produced Trips: ", format(trips_produced, big.mark=",", scientific=FALSE), "<br>",
          "Population: ", format(population, big.mark=",", scientific=FALSE)
        ),
        label = ~paste("Zone", NumeroZona, "-", NomeZona)
      )
      map_obj
    } else . 
  } %>%
  # Layer 3: Attracted Trips
  { if (!is.null(zones_sf) && nrow(zones_sf) > 0) {
      map_obj <- .
      map_obj <- addPolygons(map_obj,
        data = zones_sf,
        fillColor = ~pal_trips_attracted(trips_attracted),
        fillOpacity = 0.6,
        color = "white",
        weight = 1,
        opacity = 0.5,
        group = "Attracted Trips",
        popup = ~paste0(
          "<b>Zone ", NumeroZona, " - ", NomeZona, "</b><br>",
          "Municipality: ", NomeMunici, "<br>",
          "Attracted Trips: ", format(trips_attracted, big.mark=",", scientific=FALSE), "<br>",
          "Jobs: ", format(jobs, big.mark=",", scientific=FALSE)
        ),
        label = ~paste("Zone", NumeroZona, "-", NomeZona)
      )
      map_obj
    } else . 
  } %>%
  # Layer 4: Per Capita Income
  { if (!is.null(zones_sf) && nrow(zones_sf) > 0) {
      map_obj <- .
      map_obj <- addPolygons(map_obj,
        data = zones_sf,
        fillColor = ~pal_income(income_per_capita),
        fillOpacity = 0.6,
        color = "white",
        weight = 1,
        opacity = 0.5,
        group = "Per Capita Income",
        popup = ~paste0(
          "<b>Zone ", NumeroZona, " - ", NomeZona, "</b><br>",
          "Municipality: ", NomeMunici, "<br>",
          "Per Capita Income: $ ", format(round(income_per_capita, 2), big.mark=",", nsmall=2)
        ),
        label = ~paste("Zone", NumeroZona, "-", NomeZona)
      )
      map_obj
    } else . 
  }

# Add legends (leaflet syntax 2.2.2)
if (!is.null(zones_sf) && nrow(zones_sf) > 0) {
  map <- map %>%
    addLegend("bottomright", pal = pal_population, values = zones_sf$population, 
              title = "Population", opacity = 0.7, group = "Population", layerId = "leg_pop") %>%
    addLegend("bottomright", pal = pal_trips_produced, values = zones_sf$trips_produced, 
              title = "Produced Trips", opacity = 0.7, group = "Produced Trips", layerId = "leg_vprod") %>%
    addLegend("bottomright", pal = pal_trips_attracted, values = zones_sf$trips_attracted, 
              title = "Attracted Trips", opacity = 0.7, group = "Attracted Trips", layerId = "leg_vatra") %>%
    addLegend("bottomright", pal = pal_income, values = zones_sf$income_per_capita, 
              title = "Per Capita Income ($)", opacity = 0.7, group = "Per Capita Income", layerId = "leg_renda")
}

# Add clustered helipads as overlay
map <- map %>%
  addCircleMarkers(
    data = helipads_clustered,
    lng = ~lon,
    lat = ~lat,
    radius = 4,
    color = ~cluster_colors[cluster],
    fillColor = ~cluster_colors[cluster],
    fillOpacity = 0.6,
    weight = 1,
    group = "Clustered Helipads",
    popup = ~paste0(
      "<b>", name, "</b><br>",
      "Code: ", code, "<br>",
      "Type: ", type, "<br>",
      "Municipality: ", municipality, "<br>",
      "Cluster: ", cluster
    ),
    label = ~paste(code, "-", name)
  )

# Add reclustered helipads as overlay (all helipads in valid zones after reclustering)
map <- map %>%
  addCircleMarkers(
    data = helipads_complete,
    lng = ~lon,
    lat = ~lat,
    radius = 3,
    color = ~cluster_colors[cluster],
    fillColor = ~cluster_colors[cluster],
    fillOpacity = 0.3,
    weight = 0.5,
    group = "Reclustered Helipads",
    popup = ~paste0(
      "<b>", name, "</b><br>",
      "Code: ", code, "<br>",
      "Type: ", type, "<br>",
      "Municipality: ", municipality, "<br>",
      "Cluster: ", cluster
    ),
    label = ~paste(code, "-", name)
  )

# Add vertiports (medoids) as overlay
map <- map %>%
  addAwesomeMarkers(
    data = vertiports,
    lng = ~lon,
    lat = ~lat,
    icon = awesomeIcons(
      icon = "star",
      iconColor = "white",
      library = "fa",
      markerColor = "red"
    ),
    group = "Vertiports",
    popup = ~paste0(
      "<b>", id, "</b><br>",
      "<b>Base Heliport: ", helipad_name, "</b><br>",
      "Code: ", helipad_code, "<br>",
      "Municipality: ", municipality, "<br>",
      "Cluster: ", cluster, "<br>",
      "Helipads in cluster: ", helipads_cluster, "<br>",
      "Influence radius: ", round(influence_radius_km, 2), " km<br>",
      "<hr>",
      "<b>Socioeconomic Indices:</b><br>",
      "Covered zones: ", clusters_indices$n_zones[cluster], "<br>",
      "Average income: R$ ", format(clusters_indices$mean_income[cluster], big.mark=","), "<br>",
      "Total demand: ", format(clusters_indices$total_demand[cluster], big.mark=","), " trips/day<br>",
      "Combined index: ", round(clusters_indices$combined_index[cluster], 3), "<br>",
      "Covered population: ", format(clusters_indices$coverage_population[cluster], big.mark=","), "<br>",
      "Silhouette: ", round(silhouette, 3)
    ),
    label = ~paste(id, "-", helipad_name)
  )

# Add influence circles around vertiports
for (i in 1:NUM_CLUSTERS) {
  vp <- vertiports[i, ]
  radius_meters <- vp$influence_radius_km * 1000
  
  # Create circle (approximation with 64 points)
  n_points <- 64
  angles <- seq(0, 2*pi, length.out = n_points)
  
  # Approximate conversion from meters to degrees (1 degree lat ≈ 111km)
  radius_lat <- vp$influence_radius_km / 111
  radius_lon <- vp$influence_radius_km / (111 * cos(vp$lat * pi/180))
  
  circle_lat <- vp$lat + radius_lat * sin(angles)
  circle_lon <- vp$lon + radius_lon * cos(angles)
  
  map <- map %>%
    addPolygons(
      lng = circle_lon,
      lat = circle_lat,
      color = cluster_colors[i],
      fillColor = cluster_colors[i],
      fillOpacity = 0.1,
      weight = 2,
      opacity = 0.6,
      dashArray = "5, 5",
      group = paste0("Region VP-", sprintf("%03d", i)),
      popup = paste0(
        "<b>Influence Region VP-", sprintf("%03d", i), "</b><br>",
        "Radius: ", round(vp$influence_radius_km, 2), " km<br>",
        "Heliports covered: ", clusters_indices$n_helipads[i], "<br>",
        "Covered zones: ", clusters_indices$n_zones[i], "<br>",
        "Population: ", format(clusters_indices$coverage_population[i], big.mark=","), "<br>",
        "Average income: R$ ", format(clusters_indices$mean_income[i], big.mark=","), "<br>",
        "Total demand: ", format(clusters_indices$total_demand[i], big.mark=","), " trips/day"
      ),
      label = paste0("Region VP-", sprintf("%03d", i))
    )
}

# Add helipads by influence region
for (i in 1:NUM_CLUSTERS) {
  helis_cluster <- helipads_influence[helipads_influence$cluster_influence == i, ]
  
  map <- map %>%
    addCircleMarkers(
      data = helis_cluster,
      lng = ~lon,
      lat = ~lat,
      radius = 3,
      color = cluster_colors[i],
      fillColor = cluster_colors[i],
      fillOpacity = 0.4,
      weight = 1,
      group = paste0("Region VP-", sprintf("%03d", i)),
      popup = ~paste0(
        "<b>", name, "</b><br>",
        "Code: ", code, "<br>",
        "Municipality: ", municipality, "<br>",
        "Nearest Vertiport: VP-", sprintf("%03d", i), "<br>",
        "Distance: ", round(vertiport_distance, 2), " km"
      ),
      label = ~name
    )
}

# Add layer control
map <- map %>%
  addLayersControl(
    baseGroups = c("None", "Population", "Produced Trips", "Attracted Trips", "Per Capita Income"),
    overlayGroups = c(
      "Clustered Helipads",
      "Reclustered Helipads",
      "Vertiports",
      paste0("Region VP-", sprintf("%03d", 1:NUM_CLUSTERS))
    ),
    options = layersControlOptions(collapsed = FALSE),
    position = "topleft"
  ) %>%
  hideGroup(c(
    "Produced Trips", 
    "Attracted Trips", 
    "Per Capita Income",
    "Reclustered Helipads",
    paste0("Region VP-", sprintf("%03d", 2:NUM_CLUSTERS))
  )) %>%
  # Script to control dynamic visibility of legends
  onRender("
    function(x, data) {
      var map = this;
      
      // Add CSS to control legends visibility
      if (!document.getElementById('legend-style')) {
        var style = document.createElement('style');
        style.id = 'legend-style';
        style.textContent = '.legend-hidden { display: none !important; }';
        document.head.appendChild(style);
      }
      
      function updateLegendVisibility(selectedGroup) {
        var legends = document.querySelectorAll('.leaflet-control.info');
        
        legends.forEach(function(legend) {
          // Extract only the title from the first div with the strong class
          var titleElem = legend.querySelector('div strong');
          if (titleElem) {
            var title = (titleElem.textContent || titleElem.innerText).trim().toLowerCase();
            var selectedClean = selectedGroup.toLowerCase();
            
            // If None is selected, hide all
            if (!selectedGroup || selectedGroup === 'None') {
              legend.classList.add('legend-hidden');
            } else if (title === selectedClean || title.includes(selectedClean)) {
              // Exact match or contains the text
              legend.classList.remove('legend-hidden');
            } else {
              legend.classList.add('legend-hidden');
            }
          }
        });
      }
      
      map.on('baselayerchange', function(event) {
        updateLegendVisibility(event.name);
      });
      
      // Wait for legends to render
      setTimeout(function() {
        var activeLayer = document.querySelector('.leaflet-control-layers input[type=\"radio\"]:checked');
        if (activeLayer && activeLayer.nextSibling) {
          var label = activeLayer.nextSibling.textContent.trim();
          updateLegendVisibility(label);
        } else {
          updateLegendVisibility('None');
        }
      }, 1000);
    }
  ")

# Save map
saveWidget(map, "output/map_clusters_vertiports_rmsp.html", selfcontained = FALSE)
cat("   ✓ Map generated successfully!\n")
cat("   Saved: output/map_clusters_vertiports_rmsp.html\n\n")

# Show map in R Viewer
# print(map)

# ========== FINAL STATISTICS ==========
cat("======================================================\n")
cat("FINAL CLUSTERING SUMMARY\n")
cat("======================================================\n")
cat("Helipoints analyzed:", nrow(helipads_filtered), "\n")
cat("Vertiports identified (medoids):", nrow(vertiports), "\n")
cat("Average Silhouette:", round(mean(pam_result$silinfo$widths[, "sil_width"]), 3), "\n")
cat("\n")

cat("DISTRIBUTION AND INDICES BY CLUSTER:\n")
for (i in 1:NUM_CLUSTERS) {
  n_cluster <- sum(helipads_filtered$cluster == i)
  n_influencia <- sum(helipads_influence$cluster_influence == i)
  vertiport_info <- vertiports[vertiports$cluster == i, ]
  indices_info <- clusters_indices[i, ]
  
  cat("  Cluster", i, "(VP-", sprintf("%03d", i), "):\n", sep="")
  cat("    Vertiporto:", vertiport_info$helipad_name, "(", vertiport_info$helipad_code, ")\n")
  cat("    Municipality:", vertiport_info$municipality, "\n")
  cat("    Helipoints in cluster:", n_cluster, "\n")
  cat("    Helipoints in influence region:", n_influencia, "\n")
  cat("    Influence radius:", round(vertiport_info$influence_radius_km, 2), "km\n")
  cat("    ------ Socioeconomic Indices ------\n")
  cat("    Covered zones:", indices_info$n_zones, "\n")
  cat("    Average income (weighted): R$", format(indices_info$mean_income, big.mark=","), "\n")
  cat("    Produced Trips (demand):", format(indices_info$total_demand, big.mark=","), "trips/day\n")
  cat("    Attracted Trips:", format(indices_info$total_trips_attracted, big.mark=","), "trips/day\n")
  cat("    Combined index:", indices_info$combined_index, "\n")
  cat("    Covered Population:", format(indices_info$coverage_population, big.mark=","), "\n")
  cat("    Silhouette:", indices_info$silhouette, "\n\n")
}

cat("OD DEMAND BETWEEN PAIRS OF VERTIPORTS:\n")
if (exists("demand_od_pairs") && nrow(demand_od_pairs) > 0) {
  for (k in 1:nrow(demand_od_pairs)) {
    cat("  ", demand_od_pairs$par[k], ":",
        format(demand_od_pairs$demand_total[k], big.mark=","), "trips/day",
        "(", demand_od_pairs$n_zones_i[k], "x", demand_od_pairs$n_zones_j[k], "zones )\n")
  }
  cat("\n  TOTAL:", format(round(demand_od_total, 0), big.mark=","), "trips/day\n")
}
cat("\n")

if (exists("expanded_od_demand") && nrow(expanded_od_demand) > 0) {
  cat("======================================================\n")
  cat("EXPANDED ANALYSIS: VERTIPORTS + AIRPORTS\n")
  cat("======================================================\n\n")
  
  cat("AIRPORT INDICES:\n")
  if (exists("indices_airports") && nrow(indices_airports) > 0) {
    for (i in 1:nrow(indices_airports)) {
      air_info <- indices_airports[i, ]
      cat("  ", air_info$ponto_id, ":\n")
      cat("    Covered zones:", air_info$n_zones, "\n")
      cat("    Average income: R$", format(air_info$mean_income, big.mark=","), "\n")
      cat("    Produced Trips:", format(air_info$total_demand, big.mark=","), "trips/day\n")
      cat("    Attracted Trips:", format(air_info$total_trips_attracted, big.mark=","), "trips/day\n")
      cat("    Combined index:", air_info$combined_index, "\n")
      cat("    Covered Population:", format(air_info$coverage_population, big.mark=","), "\n\n")
    }
  }
  
  cat("TOTAL CONNECTIVITY:\n")
  cat("  - Only Vertiports: ", format(round(demand_od_total, 0), big.mark=","), " trips/day\n")
  cat("  - Vertiports + Airports: ", format(round(demand_od_expanded_total, 0), big.mark=","), " trips/day\n")
  cat("  - Increase: ", format(round((demand_od_expanded_total - demand_od_total) / demand_od_total * 100, 1)), "%\n\n")
  
  cat("TOP 5 PAIRS WITH AIRPORTS:\n")
  airport_pairs <- expanded_od_demand %>%
    filter(tipo_origem == "Airport" | tipo_destino == "Airport") %>%
    arrange(desc(demand_total)) %>%
    head(5)
  
  for (k in 1:nrow(airport_pairs)) {
    pair_info <- airport_pairs[k, ]
    cat("  ", k, ".", pair_info$par, ":",
        format(pair_info$demand_total, big.mark=","), "trips/day\n")
  }
  cat("\n")
}

cat("======================================================\n")
cat("PROCESS SUCCESFULLY CONCLUDED!\n")
cat("======================================================\n")
