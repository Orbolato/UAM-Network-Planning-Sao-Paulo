#!/usr/bin/env Rscript
# ============================================================================
# BIMTRA HELICOPTER OD PAIRS - LEAFLET MAP VISUALIZATION (RMSP ONLY)
# Shows only routes where BOTH origin AND destination are in RMSP
# ============================================================================

cat("\n========== BIMTRA OD PAIRS LEAFLET VISUALIZATION (RMSP ONLY) ==========\n\n")

# ============================================================================
# 1. FIND THE CORRECT WORKING DIRECTORY
# ============================================================================
cat("Step 0: Locating data files...\n")

script_dir <- getwd()
output_dir <- "output/helicopter_analysis_bimtra_rmsp_only"

if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
}

# Aggregated OD pairs (written by scripts/05_bimtra_analysis.py and shipped in
# data/processed/bimtra/, since the raw BIMTRA records are not redistributed)
od_data_file <- "data/processed/bimtra/BIMTRA_RMSP_Only_od_mapping_data_complete.csv"
if (!file.exists(od_data_file)) {
  cat("  ✗ ERROR: OD mapping file not found:", od_data_file, "\n\n")
  stop("RMSP-only OD mapping file not found")
}

cat("  ✓ Found data at:", normalizePath(od_data_file), "\n\n")

# ============================================================================
# 2. LOAD PACKAGES
# ============================================================================
cat("Step 1: Loading required packages...\n")

required_packages <- c("leaflet", "dplyr", "readr", "htmlwidgets", "sf")
new_packages <- required_packages[!(required_packages %in% installed.packages()[, "Package"])]

if (length(new_packages) > 0) {
  cat("  Installing missing packages:", paste(new_packages, collapse=", "), "\n")
  install.packages(new_packages, quiet = TRUE)
}

suppressPackageStartupMessages({
  library(leaflet, quietly = TRUE)
  library(dplyr, quietly = TRUE)
  library(readr, quietly = TRUE)
  library(htmlwidgets, quietly = TRUE)
  library(sf, quietly = TRUE)
})

cat("  All packages loaded successfully\n\n")

# ============================================================================
# 2B. LOAD HELIPORTS DATA
# ============================================================================
cat("Step 2B: Loading heliports database...\n")

heliports_data <- NULL
rmsp_zones <- NULL

tryCatch({
  heliports_file <- "data/processed/heliports.csv"
  if (file.exists(heliports_file)) {
    heliports_data <- read_csv(heliports_file, show_col_types = FALSE)
    cat("  Loaded", nrow(heliports_data), "heliports\n")
  } else {
    cat("  Warning: heliports.csv not found\n")
  }
}, error = function(e) {
  cat("  Warning: Could not load heliports -", conditionMessage(e), "\n")
})

# Load RMSP zone boundary
tryCatch({
  zones_file <- "data/raw/od2023/shapefile/Zonas_2023.shp"
  if (file.exists(zones_file)) {
    rmsp_zones <- sf::st_read(zones_file, quiet = TRUE)
    rmsp_zones <- sf::st_transform(rmsp_zones, crs = 4326)
    cat("  Loaded RMSP zones\n\n")
  } else {
    cat("  WARNING: Zones shapefile not found at", zones_file, "\n\n")
    rmsp_zones <- NULL
  }
}, error = function(e) {
  cat("  Info: Could not load RMSP boundary -", conditionMessage(e), "\n\n")
})

# ============================================================================
# 3. LOAD DATA
# ============================================================================
cat("Step 3: Loading OD mapping data...\n")

tryCatch({
  od_data <- read_csv(od_data_file, show_col_types = FALSE)
  cat("  Loaded", nrow(od_data), "RMSP-only routes with coordinates\n\n")
}, error = function(e) {
  cat("  ERROR:", conditionMessage(e), "\n")
  stop("Could not load OD data")
})

# ============================================================================
# 4. PREPARE RMSP-ONLY OD DATA FOR VISUALIZATION
# ============================================================================
cat("Step 4: Preparing RMSP-only OD data for visualization...\n")
cat("  (Data already filtered by RMSP-only analysis script)\n\n")

# Parameter: Minimum number of occurrences to display a route
min_occurrences <- 1
cat("  Filter: Minimum", min_occurrences, "occurrences per route\n")

visualization_dir <- file.path(output_dir, "leaflet_maps")
if (!dir.exists(visualization_dir)) {
  dir.create(visualization_dir, recursive = TRUE)
  cat("  Created output directory\n")
}

# Use RMSP-only data directly (already filtered and with correct percentages)
od_rmsp_only <- od_data %>%
  filter(!is.na(Origin_Lat), !is.na(Origin_Lon), !is.na(Dest_Lat), !is.na(Dest_Lon)) %>%
  filter(Departures >= min_occurrences)

cat("  Total routes with both endpoints in RMSP:", nrow(od_rmsp_only), "\n")
cat("  Total departures on RMSP-only routes:", sum(od_rmsp_only$Departures), "\n")

# Calculate filtering statistics
od_rmsp_with_coords <- od_data %>%
  filter(!is.na(Origin_Lat), !is.na(Origin_Lon), !is.na(Dest_Lat), !is.na(Dest_Lon))

routes_removed <- nrow(od_rmsp_with_coords) - nrow(od_rmsp_only)
departures_before <- sum(od_rmsp_with_coords$Departures, na.rm = TRUE)
departures_after <- sum(od_rmsp_only$Departures, na.rm = TRUE)
departures_removed <- departures_before - departures_after

cat("\n  FILTERING STATISTICS (min_occurrences =", min_occurrences, "):\n")
cat("    Routes before filter:", nrow(od_rmsp_with_coords), "\n")
cat("    Routes after filter:", nrow(od_rmsp_only), "\n")
cat("    Routes removed:", routes_removed, "(", round(100 * routes_removed / nrow(od_rmsp_with_coords), 1), "%)\n")
cat("\n    Departures before filter:", departures_before, "\n")
cat("    Departures after filter:", departures_after, "\n")
cat("    Departures removed:", departures_removed, "(", round(100 * departures_removed / departures_before, 1), "%)\n\n")

if (nrow(od_rmsp_only) == 0) {
  cat("  ⚠ WARNING: No RMSP-only routes found meeting the criteria\n")
  cat("  Try reducing min_occurrences parameter\n\n")
  stop("No valid RMSP-only routes found")
}

# Calculate visualization properties
min_dep <- min(od_rmsp_only$Departures)
max_dep <- max(od_rmsp_only$Departures)

od_rmsp_only <- od_rmsp_only %>%
  mutate(
    LineWidth = 1 + 9 * (Departures - min_dep) / (max_dep - min_dep),
    LineColor = case_when(
      Percentage <= 0.5 ~ "#1f77b4",
      Percentage <= 1.0 ~ "#2ca02c",
      Percentage <= 2.0 ~ "#ff7f0e",
      Percentage <= 5.0 ~ "#d62728",
      TRUE ~ "#8b0000"
    ),
    Label = paste0("<b>", Origin, " → ", Destination, "</b><br>",
                   "Departures: ", Departures, "<br>",
                   "Share: ", round(Percentage, 2), "%<br>",
                   "Aircraft: ", Unique_Aircraft)
  )

center_lat <- mean(c(od_rmsp_only$Origin_Lat, od_rmsp_only$Dest_Lat), na.rm = TRUE)
center_lon <- mean(c(od_rmsp_only$Origin_Lon, od_rmsp_only$Dest_Lon), na.rm = TRUE)

cat("  Map center:", round(center_lat, 4), ",", round(center_lon, 4), "\n\n")

# ============================================================================
# 5. CREATE MAP - ALL RMSP ROUTES
# ============================================================================
cat("Step 5: Creating Leaflet maps...\n")

# Map 1: All RMSP-only routes
m_all_rmsp <- leaflet() %>%
  addProviderTiles("CartoDB.Positron") %>%
  setView(lng = center_lon, lat = center_lat, zoom = 10)

for (i in 1:nrow(od_rmsp_only)) {
  route <- od_rmsp_only[i, ]
  m_all_rmsp <- m_all_rmsp %>%
    addPolylines(
      lng = c(route$Origin_Lon, route$Dest_Lon),
      lat = c(route$Origin_Lat, route$Dest_Lat),
      weight = route$LineWidth,
      color = route$LineColor,
      opacity = 0.6,
      popup = route$Label,
      group = "Routes"
    )
}

# Add origin and destination markers
origins_rmsp <- od_rmsp_only %>%
  select(Origin, Origin_Lat, Origin_Lon, Origin_Name) %>%
  rename(Code = Origin, Lat = Origin_Lat, Lon = Origin_Lon, Name = Origin_Name) %>%
  distinct()

destinations_rmsp <- od_rmsp_only %>%
  select(Destination, Dest_Lat, Dest_Lon, Dest_Name) %>%
  rename(Code = Destination, Lat = Dest_Lat, Lon = Dest_Lon, Name = Dest_Name) %>%
  distinct()

m_all_rmsp <- m_all_rmsp %>%
  addCircleMarkers(
    data = origins_rmsp, lng = ~Lon, lat = ~Lat, radius = 6,
    color = "#1f77b4", fillColor = "#1f77b4", fillOpacity = 0.8, weight = 2,
    popup = ~paste0("<b>ORIGIN: ", Code, "</b><br>", Name),
    label = ~Code, group = "Origins"
  ) %>%
  addCircleMarkers(
    data = destinations_rmsp, lng = ~Lon, lat = ~Lat, radius = 6,
    color = "#d62728", fillColor = "#d62728", fillOpacity = 0.8, weight = 2,
    popup = ~paste0("<b>DESTINATION: ", Code, "</b><br>", Name),
    label = ~Code, group = "Destinations"
  )

# Add heliports layer
if (!is.null(heliports_data) && nrow(heliports_data) > 0) {
  tryCatch({
    heliports_colored <- heliports_data %>%
      mutate(
        color = case_when(
          heliport_type == "Elevado" ~ "#FF6B35",
          TRUE ~ "#4CAF50"
        )
      )
    
    m_all_rmsp <- m_all_rmsp %>%
      addCircleMarkers(
        data = heliports_colored,
        lng = ~longitude,
        lat = ~latitude,
        radius = 4,
        color = ~color,
        fillColor = ~color,
        fillOpacity = 0.7,
        weight = 1.5,
        popup = ~paste0("<b>", code, "</b><br>", heliport_name, "<br>", heliport_type),
        label = ~code,
        group = "Heliports"
      )
  }, error = function(e) { NULL })
}

# Add RMSP boundary
if (!is.null(rmsp_zones)) {
  tryCatch({
    m_all_rmsp <- m_all_rmsp %>%
      addPolygons(
        data = rmsp_zones,
        fillColor = "transparent",
        fillOpacity = 0,
        weight = 2.5,
        color = "#000000",
        dashArray = "5,5",
        popup = "RMSP Boundary",
        label = "São Paulo Metropolitan Region",
        group = "RMSP Boundary"
      )
  }, error = function(e) { NULL })
}

m_all_rmsp <- m_all_rmsp %>%
  addLayersControl(
    overlayGroups = c("Routes", "Origins", "Destinations", "Heliports", "RMSP Boundary"),
    options = layersControlOptions(collapsed = FALSE)
  ) %>%
  hideGroup("Heliports") %>%
  addScaleBar(position = "bottomleft") %>%
  addLegend(
    position = "topright",
    colors = c("#1f77b4", "#2ca02c", "#ff7f0e", "#d62728", "#8b0000"),
    labels = c("≤ 0.5%", "0.5%-1.0%", "1.0%-2.0%", "2.0%-5.0%", "> 5.0%"),
    title = "Traffic Share %",
    opacity = 0.9
  )

cat("  ✓ Created map with all RMSP-only routes\n")

# ============================================================================
# 6. CREATE MAP - TOP RMSP ROUTES ONLY
# ============================================================================
top_n <- 50
od_top_rmsp <- od_rmsp_only %>% slice_head(n = top_n)

m_top_rmsp <- leaflet() %>%
  addProviderTiles("CartoDB.Positron") %>%
  setView(lng = center_lon, lat = center_lat, zoom = 10)

for (i in 1:nrow(od_top_rmsp)) {
  route <- od_top_rmsp[i, ]
  m_top_rmsp <- m_top_rmsp %>%
    addPolylines(
      lng = c(route$Origin_Lon, route$Dest_Lon),
      lat = c(route$Origin_Lat, route$Dest_Lat),
      weight = route$LineWidth,
      color = route$LineColor,
      opacity = 0.7,
      popup = route$Label,
      group = "Routes"
    )
}

origins_top_rmsp <- od_top_rmsp %>%
  select(Origin, Origin_Lat, Origin_Lon, Origin_Name) %>%
  rename(Code = Origin, Lat = Origin_Lat, Lon = Origin_Lon, Name = Origin_Name) %>%
  distinct()

destinations_top_rmsp <- od_top_rmsp %>%
  select(Destination, Dest_Lat, Dest_Lon, Dest_Name) %>%
  rename(Code = Destination, Lat = Dest_Lat, Lon = Dest_Lon, Name = Dest_Name) %>%
  distinct()

m_top_rmsp <- m_top_rmsp %>%
  addCircleMarkers(
    data = origins_top_rmsp, lng = ~Lon, lat = ~Lat, radius = 7,
    color = "#1f77b4", fillColor = "#1f77b4", fillOpacity = 0.8, weight = 2,
    popup = ~paste0("<b>ORIGIN: ", Code, "</b><br>", Name),
    label = ~Code, group = "Origins"
  ) %>%
  addCircleMarkers(
    data = destinations_top_rmsp, lng = ~Lon, lat = ~Lat, radius = 7,
    color = "#d62728", fillColor = "#d62728", fillOpacity = 0.8, weight = 2,
    popup = ~paste0("<b>DESTINATION: ", Code, "</b><br>", Name),
    label = ~Code, group = "Destinations"
  )

# Add heliports layer
if (!is.null(heliports_data) && nrow(heliports_data) > 0) {
  tryCatch({
    heliports_colored <- heliports_data %>%
      mutate(
        color = case_when(
          heliport_type == "Elevado" ~ "#FF6B35",
          TRUE ~ "#4CAF50"
        )
      )
    
    m_top_rmsp <- m_top_rmsp %>%
      addCircleMarkers(
        data = heliports_colored,
        lng = ~longitude,
        lat = ~latitude,
        radius = 4,
        color = ~color,
        fillColor = ~color,
        fillOpacity = 0.7,
        weight = 1.5,
        popup = ~paste0("<b>", code, "</b><br>", heliport_name, "<br>", heliport_type),
        label = ~code,
        group = "Heliports"
      )
  }, error = function(e) { NULL })
}

# Add RMSP boundary
if (!is.null(rmsp_zones)) {
  tryCatch({
    m_top_rmsp <- m_top_rmsp %>%
      addPolygons(
        data = rmsp_zones,
        fillColor = "transparent",
        fillOpacity = 0,
        weight = 2.5,
        color = "#000000",
        dashArray = "5,5",
        popup = "RMSP Boundary",
        label = "São Paulo Metropolitan Region",
        group = "RMSP Boundary"
      )
  }, error = function(e) { NULL })
}

m_top_rmsp <- m_top_rmsp %>%
  addLayersControl(
    overlayGroups = c("Routes", "Origins", "Destinations", "Heliports", "RMSP Boundary"),
    options = layersControlOptions(collapsed = FALSE)
  ) %>%
  hideGroup("Heliports") %>%
  addScaleBar(position = "bottomleft") %>%
  addLegend(
    position = "topright",
    colors = c("#1f77b4", "#2ca02c", "#ff7f0e", "#d62728", "#8b0000"),
    labels = c("≤ 0.5%", "0.5%-1.0%", "1.0%-2.0%", "2.0%-5.0%", "> 5.0%"),
    title = "Traffic Share %",
    opacity = 0.9
  )

cat("  ✓ Created map with top", top_n, "RMSP-only routes\n\n")

# ============================================================================
# 7. SAVE MAPS
# ============================================================================
cat("Step 6: Saving maps...\n")

tryCatch({
  map_all_file <- file.path(visualization_dir, "BIMTRA_OD_RMSP_Only_All_Routes.html")
  saveWidget(m_all_rmsp, file = map_all_file, selfcontained = TRUE)
  cat("  ✓ BIMTRA_OD_RMSP_Only_All_Routes.html\n")
}, error = function(e) {
  cat("  Warning:", conditionMessage(e), "\n")
})

tryCatch({
  map_top_file <- file.path(visualization_dir, "BIMTRA_OD_RMSP_Only_Top_Routes.html")
  saveWidget(m_top_rmsp, file = map_top_file, selfcontained = TRUE)
  cat("  ✓ BIMTRA_OD_RMSP_Only_Top_Routes.html\n")
}, error = function(e) {
  cat("  Warning:", conditionMessage(e), "\n")
})

# ============================================================================
# 8. SAVE SUMMARY STATISTICS
# ============================================================================
cat("\nStep 7: Saving summary statistics...\n")

tryCatch({
  summary_file <- file.path(visualization_dir, "RMSP_Only_Statistics.txt")
  summary_text <- paste(
    "BIMTRA RMSP-ONLY LEAFLET MAP SUMMARY",
    "====================================\n",
    "Total RMSP-only routes with coordinates:", nrow(od_rmsp_only),
    "Total departures on RMSP-only routes:", sum(od_rmsp_only$Departures),
    "Unique origins (RMSP):", n_distinct(od_rmsp_only$Origin),
    "Unique destinations (RMSP):", n_distinct(od_rmsp_only$Destination),
    "Top route:", paste0(od_rmsp_only$Origin[1], " → ", od_rmsp_only$Destination[1], 
                         " (", od_rmsp_only$Departures[1], " departures)"),
    "\nTop 10 RMSP-only routes by departures:\n",
    sep = "\n"
  )
  
  capture.output(
    print(od_rmsp_only %>% head(10) %>% select(Origin, Destination, Departures, Percentage)),
    file = summary_file, append = TRUE
  )
  
  cat("  ✓ RMSP_Only_Statistics.txt\n")
}, error = function(e) {
  cat("  Warning:", conditionMessage(e), "\n")
})

cat("\n")
cat("========== SUCCESS ==========\n")
cat("Output files saved to:\n")
cat(normalizePath(visualization_dir), "\n\n")
cat("RMSP-only maps created:\n")
cat("  - BIMTRA_OD_RMSP_Only_All_Routes.html (all RMSP-only routes)\n")
cat("  - BIMTRA_OD_RMSP_Only_Top_Routes.html (top", top_n, "RMSP-only routes)\n\n")
