# ============================================================================
# ASSIGN HELIPORTS TO ZONES - SPATIAL JOIN
# ============================================================================
# Properly assigns each helipad to its actual zone using spatial operations
# based on geographic coordinates (lat/lon intersection with zone boundaries)
# ============================================================================

library(sf)
library(readr)
library(dplyr)

rm(list = ls())

cat("HELIPORT-TO-ZONE SPATIAL ASSIGNMENT\n")
cat(paste(rep("=", 80), collapse=""), "\n\n")

# 1. Load zone shapefile
cat("1. Loading RMSP zone boundaries...\n")
zones_sf <- st_read("data/raw/od2023/shapefile/Zonas_2023.shp", quiet = TRUE)
zones_sf <- st_make_valid(zones_sf)
if (any(st_geometry_type(zones_sf) == "GEOMETRYCOLLECTION")) {
  zones_sf <- st_collection_extract(zones_sf, "POLYGON")
}
zones_sf <- st_transform(zones_sf, crs = 4326)
cat(sprintf("   ✓ Loaded %d zones\n\n", nrow(zones_sf)))

# 2. Load heliports with coordinates
cat("2. Loading heliports...\n")
heliports <- read_csv("data/processed/heliports.csv", show_col_types = FALSE)
heliports_sf <- heliports %>%
  filter(!is.na(latitude) & !is.na(longitude)) %>%
  st_as_sf(coords = c("longitude", "latitude"), crs = 4326)
cat(sprintf("   ✓ Loaded %d heliports with valid coordinates\n\n", nrow(heliports_sf)))

# 3. Spatial join: Find which zone each heliport falls into
cat("3. Performing spatial join (heliports to zones)...\n")
heliports_with_zone <- st_join(heliports_sf, zones_sf[, "NumeroZona"], left = TRUE)

# Extract zone_id and convert back to data frame
heliports_assigned <- heliports_with_zone %>%
  st_drop_geometry() %>%
  rename(zone_id = NumeroZona) %>%
  as.data.frame()

# Check how many helipads were successfully assigned to a zone
assigned_count <- sum(!is.na(heliports_assigned$zone_id))
unassigned_count <- sum(is.na(heliports_assigned$zone_id))

cat(sprintf("   ✓ Successfully assigned: %d heliports (%.1f%%)\n", 
            assigned_count, assigned_count / nrow(heliports_assigned) * 100))
if (unassigned_count > 0) {
  cat(sprintf("   ⚠️  Unassigned: %d heliports (outside RMSP zones)\n", unassigned_count))
}

# For unassigned helipads, find the nearest zone
if (unassigned_count > 0) {
  cat("\n4. Finding nearest zones for unassigned helipads...\n")
  
  unassigned_idx <- which(is.na(heliports_assigned$zone_id))
  
  for (i in unassigned_idx) {
    heliport_point <- heliports_sf[i, ]
    
    # Find nearest zone
    distances <- st_distance(heliport_point, zones_sf)
    nearest_zone_idx <- which.min(distances)
    heliports_assigned$zone_id[i] <- zones_sf$NumeroZona[nearest_zone_idx]
  }
  
  cat(sprintf("   ✓ All %d helipads now assigned to zones\n", nrow(heliports_assigned)))
}

cat("\n")

# 4. Summary statistics
cat("5. Summary Statistics:\n")
cat("   Heliports by zone:\n")
zone_summary <- heliports_assigned %>%
  filter(!is.na(zone_id)) %>%
  group_by(zone_id) %>%
  summarise(count = n(), .groups = 'drop') %>%
  arrange(desc(count))

cat(sprintf("     - Zones with helipads: %d\n", nrow(zone_summary)))
cat(sprintf("     - Max helipads in single zone: %d\n", max(zone_summary$count)))
cat(sprintf("     - Min helipads in single zone: %d\n", min(zone_summary$count)))
cat(sprintf("     - Average helipads per zone: %.2f\n\n", mean(zone_summary$count)))

# Show top 10 zones by helipad count
cat("   Top 10 zones by helipad count:\n")
print(head(zone_summary, 10))
cat("\n")

# 5. Save the assigned heliports to CSV
cat("6. Saving results...\n")

# Keep all original columns, add zone_id and coordinates, using the column
# names expected by the analysis scripts (code, name, type, ..., lat, lon)
heliports_assigned_output <- heliports_assigned %>%
  left_join(heliports %>% select(code, latitude, longitude), by = "code") %>%
  select(code, name = heliport_name, type = heliport_type, operation_type,
         municipality, zone_id, lat = latitude, lon = longitude)

write_csv(heliports_assigned_output, "data/processed/heliports_with_zones.csv")
cat("   ✓ Saved: data/processed/heliports_with_zones.csv\n\n")

cat(paste(rep("=", 80), collapse=""), "\n")
cat("SPATIAL ASSIGNMENT COMPLETED SUCCESSFULLY!\n")
cat(paste(rep("=", 80), collapse=""), "\n")
