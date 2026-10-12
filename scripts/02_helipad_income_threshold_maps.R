# ============================================================================
# VISUALIZAR HELIPADS POR THRESHOLD DE RENDA - LEAFLET MAPS
# ============================================================================
# Script para criar mapas interativos Leaflet mostrando distribuição de
# helipads em dois cenários de threshold de renda (R$ 2500 e R$ 5000)
# ============================================================================

library(sf)
library(readr)
library(dplyr)
library(leaflet)
library(leaflet.extras)
library(htmlwidgets)

# Disable s2 geometry to avoid issues with invalid geometries
sf::sf_use_s2(FALSE)

rm(list = ls())

cat(paste(rep("=", 80), collapse=""), "\n")
cat("VISUALIZAÇÃO DE HELIPADS POR THRESHOLD DE RENDA - LEAFLET\n")
cat(paste(rep("=", 80), collapse=""), "\n\n")

# ========== CARREGAR DADOS ==========
cat("1. Carregando dados...\n")

# Carregar shapefile das zonas RMSP
zones_sf <- tryCatch({
  st_read("data/raw/od2023/shapefile/Zonas_2023.shp", quiet = TRUE)
}, error = function(e) {
  warning("Zone shapefile not found.")
  NULL
})

if (!is.null(zones_sf)) {
  zones_sf <- st_make_valid(zones_sf)
  # Cast to POLYGON if there are GEOMETRYCOLLECTION types
  if (any(st_geometry_type(zones_sf) == "GEOMETRYCOLLECTION")) {
    zones_sf <- st_collection_extract(zones_sf, "POLYGON")
  }
  zones_sf <- st_transform(zones_sf, crs = 4326)
  cat("✓ Zone shapefile loaded:", nrow(zones_sf), "zones\n")
}

# Carregar dados de zonas com renda
zones_data <- tryCatch({
  read_csv("data/processed/zones_data.csv", show_col_types = FALSE, progress = FALSE)
}, error = function(e) {
  cat("⚠️ File data/processed/zones_data.csv not found\n")
  NULL
})

# Carregar dados de renda per capita
income_data <- tryCatch({
  read_csv("data/processed/income_per_capita.csv", show_col_types = FALSE, progress = FALSE)
}, error = function(e) {
  cat("⚠️ File data/processed/income_per_capita.csv not found\n")
  NULL
})

# Carregar heliports
heliports <- tryCatch({
  read_csv("data/processed/heliports.csv", show_col_types = FALSE, progress = FALSE)
}, error = function(e) {
  cat("⚠️ File data/processed/heliports.csv not found\n")
  NULL
})

if (!is.null(heliports)) {
  heliports$latitude <- as.numeric(heliports$latitude)
  heliports$longitude <- as.numeric(heliports$longitude)
  heliports <- heliports[!is.na(heliports$latitude) & !is.na(heliports$longitude), ]
  cat("✓ Heliports loaded:", nrow(heliports), "records\n")
}

# Juntar dados de renda com dados de zonas
if (!is.null(zones_data) && !is.null(income_data)) {
  complete_data <- zones_data %>%
    left_join(income_data[, c("zone_id", "income_per_capita")], by = "zone_id")
  
  # Filtrar zero incomes
  complete_data <- complete_data %>%
    filter(income_per_capita > 0 | is.na(income_per_capita))
  
  cat("✓ Data consolidated:", nrow(complete_data), "zones\n\n")
}

# ========== DEFINIR THRESHOLDS ==========
THRESHOLD_1 <- 2500
THRESHOLD_2 <- 5000

# Criar dados para cada threshold
zones_threshold_1 <- complete_data %>%
  filter(income_per_capita >= THRESHOLD_1)

zones_threshold_2 <- complete_data %>%
  filter(income_per_capita >= THRESHOLD_2)

cat("2. Zones by threshold:\n")
cat("   Income >=", THRESHOLD_1, ":", nrow(zones_threshold_1), "zones\n")
cat("   Income >=", THRESHOLD_2, ":", nrow(zones_threshold_2), "zones\n\n")

# ========== FILTRAR HELIPORTS POR THRESHOLD ==========
cat("3. Filtrando helipads por threshold...\n")

# Load heliports with actual zone assignments (based on geographic location)
heliports_assigned <- read_csv("data/processed/heliports_with_zones.csv", show_col_types = FALSE)
heliports_assigned$zone_id <- as.integer(heliports_assigned$zone_id)

# Need latitude/longitude for mapping - rejoin with original heliports
heliports_with_coords <- heliports %>%
  select(code, latitude, longitude) %>%
  left_join(heliports_assigned %>%
              select(code, heliport_name = name, heliport_type = type,
                     operation_type, municipality, zone_id),
            by = "code")

# Filter by threshold
heliports_threshold_1 <- heliports_with_coords %>%
  filter(zone_id %in% zones_threshold_1$zone_id)

heliports_threshold_2 <- heliports_with_coords %>%
  filter(zone_id %in% zones_threshold_2$zone_id)

cat("   Helipads (Income >=", THRESHOLD_1, "):", nrow(heliports_threshold_1), "\n")
cat("   Helipads (Income >=", THRESHOLD_2, "):", nrow(heliports_threshold_2), "\n\n")

# ========== CRIAR MAPAS LEAFLET ==========
cat("4. Criando mapas Leaflet...\n")

# Definir cores para os helipads
cor_threshold_1 <- "#2E86AB"  # Azul
cor_threshold_2 <- "#F18F01"  # Laranja

# Calcular centroid da RMSP para centralizar o mapa
center_lat <- -23.55
center_lon <- -46.63

# ===== MAPA 1: THRESHOLD R$ 2500 =====
map_threshold_1 <- leaflet() %>%
  addProviderTiles("CartoDB.Positron",
                   options = providerTileOptions(noWrap = TRUE)) %>%
  setView(lng = center_lon, lat = center_lat, zoom = 10) %>%
  
  # Adicionar boundaries das zonas RMSP
  addPolygons(data = zones_sf,
              color = "#999999",
              weight = 1,
              opacity = 0.6,
              fillColor = "#E8E8E8",
              fillOpacity = 0.2,
              popup = ~paste("Zone:", NumeroZona)) %>%
  
  # Adicionar helipads do threshold 1
  addCircleMarkers(data = heliports_threshold_1,
                   lng = ~longitude,
                   lat = ~latitude,
                   radius = 4,
                   color = cor_threshold_1,
                   fillColor = cor_threshold_1,
                   fillOpacity = 0.7,
                   weight = 1,
                   opacity = 0.8,
                   popup = ~paste("<b>", heliport_name, "</b><br>",
                                  "Type:", heliport_type, "<br>",
                                  "Municipality:", municipality)) %>%
  
  # Adicionar título e informações
  addControl(
    html = paste("<div style='background-color: white; padding: 10px; border-radius: 5px; font-size: 14px;'>",
                 "<b>Helipads Distribution</b><br>",
                 "Income Threshold: ≥ R$ 2,500<br>",
                 "Total Helipads:", nrow(heliports_threshold_1), "<br>",
                 "Coverage:", round(nrow(heliports_threshold_1) / nrow(heliports) * 100, 1), "%",
                 "</div>"),
    position = "topright"
  )

# ===== MAPA 2: THRESHOLD R$ 5000 =====
map_threshold_2 <- leaflet() %>%
  addProviderTiles("CartoDB.Positron",
                   options = providerTileOptions(noWrap = TRUE)) %>%
  setView(lng = center_lon, lat = center_lat, zoom = 10) %>%
  
  # Adicionar boundaries das zonas RMSP
  addPolygons(data = zones_sf,
              color = "#999999",
              weight = 1,
              opacity = 0.6,
              fillColor = "#E8E8E8",
              fillOpacity = 0.2,
              popup = ~paste("Zone:", NumeroZona)) %>%
  
  # Adicionar helipads do threshold 2
  addCircleMarkers(data = heliports_threshold_2,
                   lng = ~longitude,
                   lat = ~latitude,
                   radius = 4,
                   color = cor_threshold_2,
                   fillColor = cor_threshold_2,
                   fillOpacity = 0.7,
                   weight = 1,
                   opacity = 0.8,
                   popup = ~paste("<b>", heliport_name, "</b><br>",
                                  "Type:", heliport_type, "<br>",
                                  "Municipality:", municipality)) %>%
  
  # Adicionar título e informações
  addControl(
    html = paste("<div style='background-color: white; padding: 10px; border-radius: 5px; font-size: 14px;'>",
                 "<b>Helipads Distribution</b><br>",
                 "Income Threshold: ≥ R$ 5,000<br>",
                 "Total Helipads:", nrow(heliports_threshold_2), "<br>",
                 "Coverage:", round(nrow(heliports_threshold_2) / nrow(heliports) * 100, 1), "%",
                 "</div>"),
    position = "topright"
  )

cat("   ✓ Maps created\n\n")

# ========== SALVAR MAPAS ==========
cat("5. Saving maps as HTML files...\n")

if (!dir.exists("output")) {
  dir.create("output", recursive = TRUE)
}

# Salvar mapa 1
saveWidget(map_threshold_1, 
           file = "output/map_helipads_threshold_2500.html",
           selfcontained = FALSE)
cat("   ✓ Saved: output/map_helipads_threshold_2500.html\n")

# Salvar mapa 2
saveWidget(map_threshold_2,
           file = "output/map_helipads_threshold_5000.html",
           selfcontained = FALSE)
cat("   ✓ Saved: output/map_helipads_threshold_5000.html\n\n")

# ========== CRIAR MAPA COMPARATIVO (SIDE-BY-SIDE) =====
cat("6. Creating comparison map (side-by-side view)...\n")

# Criar HTML com dois mapas lado a lado
html_comparison <- paste('
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8" />
  <title>Helipads Distribution Comparison - Income Thresholds</title>
  <style>
    body { margin: 0; padding: 0; font-family: Arial, sans-serif; }
    .container { display: flex; height: 100vh; }
    .map-container { flex: 1; position: relative; }
    .map-title { 
      position: absolute; 
      top: 10px; 
      left: 10px; 
      background: white; 
      padding: 10px 15px; 
      border-radius: 5px; 
      z-index: 400;
      font-weight: bold;
      box-shadow: 0 2px 4px rgba(0,0,0,0.2);
    }
    .map-stats {
      position: absolute;
      top: 70px;
      left: 10px;
      background: white;
      padding: 10px 15px;
      border-radius: 5px;
      z-index: 400;
      font-size: 12px;
      box-shadow: 0 2px 4px rgba(0,0,0,0.2);
    }
    .divider { width: 2px; background-color: #ddd; }
  </style>
</head>
<body>
  <div class="container">
    <div class="map-container" id="map1">
      <div class="map-title">Income ≥ R$ 2,500</div>
      <div class="map-stats">
        Helipads: ', nrow(heliports_threshold_1), '<br>
        Coverage: ', round(nrow(heliports_threshold_1) / nrow(heliports) * 100, 1), '%
      </div>
    </div>
    <div class="divider"></div>
    <div class="map-container" id="map2">
      <div class="map-title">Income ≥ R$ 5,000</div>
      <div class="map-stats">
        Helipads: ', nrow(heliports_threshold_2), '<br>
        Coverage: ', round(nrow(heliports_threshold_2) / nrow(heliports) * 100, 1), '%
      </div>
    </div>
  </div>
  <script src="https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.min.js"></script>
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.min.css" />
  <script>
    // Initialize map 1
    var map1 = L.map("map1").setView([', center_lat, ', ', center_lon, '], 10);
    L.tileLayer("https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png", {
      attribution: "© CartoDB"
    }).addTo(map1);
    
    // Initialize map 2
    var map2 = L.map("map2").setView([', center_lat, ', ', center_lon, '], 10);
    L.tileLayer("https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png", {
      attribution: "© CartoDB"
    }).addTo(map2);
    
    // Sync maps when one is dragged or zoomed
    map1.on("move", function() {
      map2.setView(map1.getCenter(), map1.getZoom());
    });
    
    map2.on("move", function() {
      map1.setView(map2.getCenter(), map2.getZoom());
    });
  </script>
</body>
</html>
')

writeLines(html_comparison, "output/map_helipads_comparison_side_by_side.html")
cat("   ✓ Saved: output/map_helipads_comparison_side_by_side.html\n\n")

cat(paste(rep("=", 80), collapse=""), "\n")
cat("LEAFLET MAPS GENERATED SUCCESSFULLY!\n")
cat("Output files:\n")
cat("  1. output/map_helipads_threshold_2500.html\n")
cat("  2. output/map_helipads_threshold_5000.html\n")
cat("  3. output/map_helipads_comparison_side_by_side.html (synchronized side-by-side)\n")
cat(paste(rep("=", 80), collapse=""), "\n\n")
