library(sf)
library(leaflet)
library(readr)
library(dplyr)
library(htmlwidgets)
rm(list=ls())

# ========== CONFIGURABLE PARAMETERS ==========
HELIPADS_FILE <- "data/processed/heliports_with_zones.csv"
K_CONNECTIONS <- 2  # Number of REH waypoints each airport/vertiport connects to
ALLOW_DIRECT_ENDPOINT_CONNECTIONS <- TRUE  # If TRUE, allows direct connections between airports/vertiports
# =============================================

# ============================================================================
# VISUALIZATION REH - SÃO PAULO METROPOLITAN REGION (COMPLETE)
# ============================================================================
# Script for visualizing eVTOL routes, heliports, and socioeconomic data
# Based on the OD Survey 2023 - 527 research zones of the RMSP
# 
# LAYERS:
# 1. Population by zone
# 2. Trips produced by zone
# 3. Trips attracted by zone  
# 4. Income per capita by zone (Tab6 OD 2023)
# 5. UAM Routes
# 6. Heliports and Vertiports
# ============================================================================

cat(paste(rep("=", 70), collapse=""), "\n")
cat("VISUALIZATION REH - RMSP COMPLETE\n")
cat(paste(rep("=", 70), collapse=""), "\n\n")

# Load exported REH data (CORRECTED VERSION WITH WAYPOINT NAMES AND FILLED REH VALUES)
load(file = "data/processed/reh_network_corrected.RData")

# ========== DIAGNOSTIC: CHECK MISSING WAYPOINTS ==========
cat("\n========== WAYPOINTS DIAGNOSTIC ==========\n")
cat("Total waypoints in 'nodes':", nrow(nodes), "\n")
cat("Total edges in 'edges':", nrow(edges), "\n")

# CHECK GEOMETRIC POINTS IN EDGES (intermediate points of polylines)
cat("\nAnalyzing geometry of edges...\n")
total_geom_points <- 0
for (i in 1:nrow(edges)) {
  edge_coords <- st_coordinates(edges$geom[[i]])
  total_geom_points <- total_geom_points + nrow(edge_coords)
}
cat("Total geometric points in all edges:", total_geom_points, "\n")
cat("Average points per edge:", round(total_geom_points / nrow(edges), 1), "\n")
cat("\n⚠️ IMPORTANT: Edges are POLYLINES with multiple intermediate points!\n")
cat("   The 'sharp corners' you see are intermediate points of the geometry,\n")
cat("   NOT routing waypoints. Only the endpoints (from/to) are waypoints.\n\n")

# Check if edges have 'from' and 'to' columns
if ("from" %in% names(edges) && "to" %in% names(edges)) {
  cat("Edges have 'from' and 'to' columns (routing waypoints)\n")
  
  # Extract all waypoint IDs referenced in edges
  waypoints_from <- unique(edges$from)
  waypoints_to <- unique(edges$to)
  waypoints_in_edges <- unique(c(waypoints_from, waypoints_to))
  
  cat("Total unique routing waypoints in edges:", length(waypoints_in_edges), "\n")
  cat("Range of IDs in edges: [", min(waypoints_in_edges), ",", max(waypoints_in_edges), "]\n")
  
  # Check which waypoints are in edges but not in nodes
  waypoints_in_nodes <- nodes$id
  cat("Range of IDs in nodes: [", min(waypoints_in_nodes), ",", max(waypoints_in_nodes), "]\n")
  
  missing_waypoints <- setdiff(waypoints_in_edges, waypoints_in_nodes)
  
  if (length(missing_waypoints) > 0) {
    cat("\n⚠️ WARNING: ", length(missing_waypoints), " waypoints are in edges but NOT in nodes:\n")
    cat("Missing IDs:", paste(head(missing_waypoints, 20), collapse=", "))
    if (length(missing_waypoints) > 20) cat("...")
    cat("\n")
    
    # Try to extract waypoints from edge geometries
    cat("\nTrying to reconstruct missing waypoints from geometries...\n")
    
    missing_nodes_list <- list()
    for (wid in missing_waypoints) {
      # Find edges that contain this waypoint
      edges_with_wp <- which(edges$from == wid | edges$to == wid)
      
      if (length(edges_with_wp) > 0) {
        # Get first edge that contains this waypoint
        edge_idx <- edges_with_wp[1]
        edge_geom <- edges$geom[[edge_idx]]
        edge_coords <- st_coordinates(edge_geom)
        
        # Determine if it is from or to
        if (edges$from[edge_idx] == wid) {
          # It is the starting point
          wp_coords <- edge_coords[1, c("X", "Y")]
        } else {
          # It is the ending point
          wp_coords <- edge_coords[nrow(edge_coords), c("X", "Y")]
        }
        
        missing_nodes_list[[length(missing_nodes_list) + 1]] <- data.frame(
          id = wid,
          lon = wp_coords[1],
          lat = wp_coords[2]
        )
      }
    }
    
    if (length(missing_nodes_list) > 0) {
      missing_nodes_df <- do.call(rbind, missing_nodes_list)
      missing_nodes_sf <- st_as_sf(missing_nodes_df, coords = c("lon", "lat"), crs = 4326)
      missing_nodes_sf$id <- missing_nodes_df$id
      
      # Add to nodes
      cat("Adding", nrow(missing_nodes_sf), "reconstructed waypoints to 'nodes'\n")
      nodes <- rbind(nodes[, c("id", "geom")], missing_nodes_sf[, c("id", "geom")])
      nodes <- nodes[order(nodes$id), ]
      
      cat("✓ Missing waypoints added. Total nodes now:", nrow(nodes), "\n")
    }
  } else {
    cat("✓ All waypoints in edges exist in nodes\n")
  }
} else {
  cat("\nEdges do NOT have 'from'/'to' columns - waypoints will be inferred from geometry\n")
}
cat("=============================================\n\n")

# ========== LOAD OD ZONE DATA ==========
cat("1. Loading OD zone data 2023...\n")

# Load zone shapefile
zones_sf <- tryCatch({
  st_read("data/raw/od2023/shapefile/Zonas_2023.shp", quiet = TRUE)
}, error = function(e) {
  warning("Zone shapefile not found.")
  NULL
})

# Load socioeconomic data
zones_data <- tryCatch({
  read_csv("data/processed/zones_data.csv", show_col_types = FALSE, progress = FALSE)
}, error = function(e) {
  warning("File zones_data.csv not found.")
  data.frame(zone = integer(0), population = numeric(0))
})

# Load per capita income data
income_per_capita <- tryCatch({
  read_csv("data/processed/income_per_capita.csv", show_col_types = FALSE, progress = FALSE)
}, error = function(e) {
  warning(paste("Error loading income_per_capita.csv:", e$message))
  data.frame(zone = integer(0), income_per_capita = numeric(0))
})

# Join per capita income to zone data
if (nrow(income_per_capita) > 0 && nrow(zones_data) > 0) {
  zones_data <- zones_data %>%
    left_join(income_per_capita[, c("zone_id", "income_per_capita")], by = "zone_id")
  
  cat("   Total zones loaded:", nrow(zones_data), "\n")
  cat("   ✓ OD data 2023 loaded (without OD 2017 imputation)\n")
  
  # VALIDATION FILTER (non-residential zones should remain excluded)
  # This filter acts as a second layer of validation for visualizations
  zones_valid <- zones_data %>%
    filter(!is.na(income_per_capita), income_per_capita > 0,
           !is.na(trips_produced), trips_produced > 0)
  
  if (nrow(zones_data) - nrow(zones_valid) > 0) {
    cat("   ✓ Validation filter: excluding", nrow(zones_data) - nrow(zones_valid), "non-residential zones\n")
  }
  
  cat("   ✓ Valid zones:", nrow(zones_valid), "\n")
  zones_data <- zones_valid
}

# Juntar shapefile com dados
if (!is.null(zones_sf) && nrow(zones_data) > 0) {
  # Garantir que zonas_sf está em WGS84 para Leaflet
  zones_sf <- st_transform(zones_sf, crs = 4326)
  
  # Fix UTF-8 encoding issues BEFORE joining
  zones_sf$NomeZona <- iconv(zones_sf$NomeZona, to = "UTF-8", sub = "")
  zones_sf$NomeMunici <- iconv(zones_sf$NomeMunici, to = "UTF-8", sub = "")
  
  # Juntar dados pela coluna de zona
  zones_sf <- zones_sf %>%
    left_join(zones_data, by = c("NumeroZona" = "zone_id"))
  
  cat("   Total zones with geometry:", nrow(zones_sf), "\n")
  cat("   Total population:", format(sum(zones_sf$population, na.rm=TRUE), big.mark=","), "\n")
  cat("   Trips produced:", format(sum(zones_sf$trips_produced, na.rm=TRUE), big.mark=","), "\n")
  cat("   Trips attracted:", format(sum(zones_sf$trips_attracted, na.rm=TRUE), big.mark=","), "\n")
  cat("   Average per capita income: R$", format(mean(zones_sf$income_per_capita, na.rm=TRUE), digits=2), "\n\n")
} else if (nrow(zones_data) > 0) {
  cat("   Total zones (without geometry):", nrow(zones_data), "\n")
  cat("   Total population:", format(sum(zones_data$population, na.rm=TRUE), big.mark=","), "\n\n")
}

# ==========  UAM ROUTING SYSTEM ==========
# (Same functions as in visualize_reh_improved.r)

# Function to calculate geodesic distance (haversine) between two points in km
# Supports scalar or vector input
calc_dist <- function(lat1, lon1, lat2, lon2) {
  # If inputs are vectors, apply the function element-wise
  if (length(lat1) > 1 || length(lon1) > 1 || length(lat2) > 1 || length(lon2) > 1) {
    return(mapply(function(la1, lo1, la2, lo2) {
      p1 <- st_point(c(lo1, la1))
      p2 <- st_point(c(lo2, la2))
      p1_sf <- st_sfc(p1, crs = 4326)
      p2_sf <- st_sfc(p2, crs = 4326)
      as.numeric(st_distance(p1_sf, p2_sf)) / 1000
    }, lat1, lon1, lat2, lon2))
  }
  
  # For scalar input
  p1 <- st_point(c(lon1, lat1))
  p2 <- st_point(c(lon2, lat2))
  p1_sf <- st_sfc(p1, crs = 4326)
  p2_sf <- st_sfc(p2, crs = 4326)
  as.numeric(st_distance(p1_sf, p2_sf)) / 1000
}

find_nearest_node <- function(lat, lon, nodes_obj = nodes) {
  coords <- st_coordinates(nodes_obj$geom)
  distances <- calc_dist(lat, lon, coords[,"Y"], coords[,"X"])
  nodes_obj$id[which.min(distances)]
}

get_waypoint_name <- function(node_id, nodes_obj = nodes) {
  idx <- which(nodes_obj$id == node_id)
  if (length(idx) > 0) {
    name <- nodes_obj$waypoint_name[idx[1]]
    return(ifelse(is.na(name) || name == "Geometric node", paste("Node", node_id), name))
  }
  return(paste("Node", node_id))
}

build_uam_graph <- function(all_points_df, nodes_obj = nodes, edges_obj = edges, k_connections = 3, allow_direct = FALSE) {
  coords <- st_coordinates(nodes_obj$geom)
  node_coords <- data.frame(
    id = nodes_obj$id,
    lat = coords[,"Y"],
    lon = coords[,"X"],
    stringsAsFactors = FALSE
  )
  
  cat("Building REH graph:\n")
  cat("  Total REH waypoints:", nrow(node_coords), "\n")
  cat("  Total REH edges:", nrow(edges_obj), "\n")
  
  # Initialize graph (adjacencies, weights AND GEOMETRIES)
  adjacency <- list()
  edge_weights <- list()
  edge_geometries <- list()  # Initialize geometries storage
  
  edges_added <- 0
  
  for (i in 1:nrow(edges_obj)) {
    if ("from" %in% names(edges_obj) && "to" %in% names(edges_obj)) {
      start_node <- edges_obj$from[i]
      end_node <- edges_obj$to[i]
    } else {
      edge_geom <- edges_obj$geom[[i]]
      edge_coords <- st_coordinates(edge_geom)
      
      if (nrow(edge_coords) < 2) next
      
      start_coord <- edge_coords[1, c("X", "Y")]
      end_coord <- edge_coords[nrow(edge_coords), c("X", "Y")]
      
      start_node <- node_coords$id[which.min(calc_dist(start_coord[2], start_coord[1], 
                                                        node_coords$lat, node_coords$lon))]
      end_node <- node_coords$id[which.min(calc_dist(end_coord[2], end_coord[1], 
                                                      node_coords$lat, node_coords$lon))]
    }
    
    edge_geom <- edges_obj$geom[[i]]
    edge_coords <- st_coordinates(edge_geom)
    edge_length <- 0
    
    if (nrow(edge_coords) > 1) {
      for (j in 1:(nrow(edge_coords)-1)) {
        edge_length <- edge_length + calc_dist(
          edge_coords[j, "Y"], edge_coords[j, "X"],
          edge_coords[j+1, "Y"], edge_coords[j+1, "X"]
        )
      }
    }
    
    if (!(start_node %in% names(adjacency))) {
      adjacency[[as.character(start_node)]] <- c()
      edge_weights[[as.character(start_node)]] <- c()
      edge_geometries[[as.character(start_node)]] <- list()
    }
    if (!(end_node %in% names(adjacency))) {
      adjacency[[as.character(end_node)]] <- c()
      edge_weights[[as.character(end_node)]] <- c()
      edge_geometries[[as.character(end_node)]] <- list()
    }
    
    if (!(end_node %in% adjacency[[as.character(start_node)]])) {
      adjacency[[as.character(start_node)]] <- c(adjacency[[as.character(start_node)]], end_node)
      edge_weights[[as.character(start_node)]] <- c(edge_weights[[as.character(start_node)]], edge_length)
      edge_geometries[[as.character(start_node)]][[length(edge_geometries[[as.character(start_node)]]) + 1]] <- edge_coords
      edges_added <- edges_added + 1
    }
    
    if (!(start_node %in% adjacency[[as.character(end_node)]])) {
      adjacency[[as.character(end_node)]] <- c(adjacency[[as.character(end_node)]], start_node)
      edge_weights[[as.character(end_node)]] <- c(edge_weights[[as.character(end_node)]], edge_length)
      edge_geometries[[as.character(end_node)]][[length(edge_geometries[[as.character(end_node)]]) + 1]] <- edge_coords[nrow(edge_coords):1, ]
    }
  }
  
  cat("  REH edges added to graph:", edges_added, "\n")
  
  # Determine the set of points for nearest neighbor search
  if (allow_direct) {
    # Include REH waypoints AND other airports/vertiports
    search_coords <- rbind(
      node_coords[, c("id", "lat", "lon")],
      data.frame(
        id = all_points_df$id,
        lat = all_points_df$lat,
        lon = all_points_df$lon,
        stringsAsFactors = FALSE
      )
    )
    cat("  Connecting airports/vertiports to", k_connections, "nearest points (REH + other endpoints)\n")
  } else {
    # Use ONLY REH waypoints
    search_coords <- node_coords[, c("id", "lat", "lon")]
    cat("  Connecting airports/vertiports to", k_connections, "nearest REH waypoints\n")
  }
  
  for (i in 1:nrow(all_points_df)) {
    point_id <- all_points_df$id[i]
    point_lat <- all_points_df$lat[i]
    point_lon <- all_points_df$lon[i]
    
    # Calculate distances to all points in the search set
    distances_to_neighbors <- sapply(1:nrow(search_coords), function(j) {
      # Do not calculate distance to itself
      if (search_coords$id[j] == point_id) {
        return(Inf)
      }
      calc_dist(point_lat, point_lon, search_coords$lat[j], search_coords$lon[j])
    })
    
    # Find the K nearest points (excluding itself)
    k_nearest_indices <- order(distances_to_neighbors)[1:min(k_connections, sum(!is.infinite(distances_to_neighbors)))]
    
    if (!(point_id %in% names(adjacency))) {
      adjacency[[as.character(point_id)]] <- c()
      edge_weights[[as.character(point_id)]] <- c()
      edge_geometries[[as.character(point_id)]] <- list()
    }
    
    for (idx in k_nearest_indices) {
      nearest_node <- search_coords$id[idx]
      distance_to_neighbor <- distances_to_neighbors[idx]
      
      # Skip if distance is infinite (same point)
      if (is.infinite(distance_to_neighbor)) next
      
      # Connect directly to nearest_node (REH waypoint or other airport/vertiport)
      if (!(nearest_node %in% names(adjacency))) {
        adjacency[[as.character(nearest_node)]] <- c()
        edge_weights[[as.character(nearest_node)]] <- c()
        edge_geometries[[as.character(nearest_node)]] <- list()
      }
      
      # Bidirectional connection (Dijkstra will filter intermediate use)
      adjacency[[as.character(point_id)]] <- c(adjacency[[as.character(point_id)]], nearest_node)
      edge_weights[[as.character(point_id)]] <- c(edge_weights[[as.character(point_id)]], distance_to_neighbor)
      edge_geometries[[as.character(point_id)]][[length(edge_geometries[[as.character(point_id)]]) + 1]] <- NULL
      
      adjacency[[as.character(nearest_node)]] <- c(adjacency[[as.character(nearest_node)]], point_id)
      edge_weights[[as.character(nearest_node)]] <- c(edge_weights[[as.character(nearest_node)]], distance_to_neighbor)
      edge_geometries[[as.character(nearest_node)]][[length(edge_geometries[[as.character(nearest_node)]]) + 1]] <- NULL
    }
    
    cat("    ", point_id, "connected to points:", paste(search_coords$id[k_nearest_indices], collapse=", "), "\n")
  }
  
  return(list(adjacency = adjacency, weights = edge_weights, geometries = edge_geometries, node_coords = node_coords))
}

find_shortest_path_dijkstra <- function(start_id, end_id, graph, endpoint_ids = c()) {
  if (start_id == end_id) {
    return(list(path = c(start_id), edge_indices = c()))
  }
  
  adjacency <- graph$adjacency
  edge_weights <- graph$weights
  all_nodes <- names(adjacency)
  
  distances <- setNames(rep(Inf, length(all_nodes)), all_nodes)
  distances[as.character(start_id)] <- 0
  predecessors <- setNames(rep(NA, length(all_nodes)), all_nodes)
  edge_indices <- setNames(rep(NA, length(all_nodes)), all_nodes)
  unvisited <- all_nodes
  
  while (length(unvisited) > 0) {
    current_distances <- distances[unvisited]
    current_distances <- current_distances[!is.infinite(current_distances)]
    
    if (length(current_distances) == 0) break
    
    current <- names(current_distances)[which.min(current_distances)]
    
    if (current == as.character(end_id)) break
    
    unvisited <- setdiff(unvisited, current)
    
    neighbors <- adjacency[[current]]
    weights <- edge_weights[[current]]
    
    if (!is.null(neighbors) && length(neighbors) > 0) {
      for (i in 1:length(neighbors)) {
        neighbor <- as.character(neighbors[i])
        
        # Rule: Endpoints (airports/vertiports) can only be intermediates if the path is direct (no waypoints)
        # If the neighbor is an endpoint and not the final destination, only allow if:
        # - The neighbor is endpoint E
        # - The final destination is an endpoint E
        # - There are no waypoints in the path (only two endpoints connected directly)
        if (neighbor %in% endpoint_ids && neighbor != as.character(end_id)) {
          # Allow direct endpoint-to-endpoint connection only if destination is endpoint
          if (!(as.character(end_id) %in% endpoint_ids)) {
            # Destination is not endpoint, so do not allow passing through another endpoint
            next
          }
          # If reached here: neighbor is endpoint, destination is endpoint
          # But we need to avoid paths with intermediate waypoints
          # Check if there are waypoints between current and end_id
          # For now, only allow if current is also an endpoint (direct connection)
          if (!(current %in% endpoint_ids)) {
            # Current is a waypoint, neighbor is an endpoint
            # Do not allow passing through endpoint if coming from a waypoint
            next
          }
        }
        
        weight <- weights[i]
        alt_distance <- distances[current] + weight
        
        if (alt_distance < distances[neighbor]) {
          distances[neighbor] <- alt_distance
          predecessors[neighbor] <- current
          edge_indices[neighbor] <- i
        }
      }
    }
  }
  
  if (is.infinite(distances[as.character(end_id)])) {
    warning(paste("Path not found between", start_id, "and", end_id))
    return(list(path = c(start_id, end_id), edge_indices = c()))
  }
  
  path <- c()
  path_edges <- c()
  current <- as.character(end_id)
  
  while (!is.na(current)) {
    path <- c(current, path)
    if (!is.na(predecessors[current])) {
      path_edges <- c(edge_indices[current], path_edges)
    }
    current <- predecessors[current]
  }
  
  return(list(path = path, edge_indices = path_edges))
}

# ========== DEFINE ORIGIN/DESTINATION POINTS ==========
sbsp_lat <- -23.626111; sbsp_lon <- -46.656389
sbgr_lat <- -23.435556; sbgr_lon <- -46.473056
sbmt_lat <- -23.509000; sbmt_lon <- -46.633000

node_sbsp <- find_nearest_node(sbsp_lat, sbsp_lon)
node_sbgr <- find_nearest_node(sbgr_lat, sbgr_lon)
node_sbmt <- find_nearest_node(sbmt_lat, sbmt_lon)

cat("\n2. Nearest REH waypoints to airports:\n")
cat("  SBSP -> Node", node_sbsp, "\n")
cat("  SBGR -> Node", node_sbgr, "\n")
cat("  SBMT -> Node", node_sbmt, "\n\n")

# ========== LOAD VERTIPORTS ==========
if (file.exists("output/selected_vertiports_rmsp.rds")) {
  vertiports <- readRDS("output/selected_vertiports_rmsp.rds")
  cat("3. Vertiports loaded (RMSP): ", nrow(vertiports), "\n")
} else {
  stop("3. Vertiports not found.\n")
}

vertiports$node_reh <- sapply(1:nrow(vertiports), function(i) {
  find_nearest_node(vertiports$lat[i], vertiports$lon[i])
})

for (i in 1:nrow(vertiports)) {
  cat("  ", vertiports$id[i], "-> Node", vertiports$node_reh[i], "\n")
}

# ========== GENERATE UAM ROUTES ==========
cat("\n4. Generating UAM routes...\n")
all_points <- data.frame(
  id = c("SBSP", "SBGR", "SBMT", vertiports$id),
  name = c("SBSP", "SBGR", "SBMT", vertiports$id),
  lat = c(sbsp_lat, sbgr_lat, sbmt_lat, vertiports$lat),
  lon = c(sbsp_lon, sbgr_lon, sbmt_lon, vertiports$lon),
  node_reh = c(node_sbsp, node_sbgr, node_sbmt, vertiports$node_reh),
  tipo = c("Airport", "Airport", "Airport", rep("Vertiport", nrow(vertiports))),
  stringsAsFactors = FALSE
)

cat("\n========== BUILDING UAM GRAPH ==========\n")
uam_graph <- build_uam_graph(all_points, nodes, edges, k_connections = K_CONNECTIONS, allow_direct = ALLOW_DIRECT_ENDPOINT_CONNECTIONS)
cat("\nGraph built: ", length(uam_graph$adjacency), "total nodes\n")
cat("=========================================\n\n")

routes_list <- list()
route_counter <- 1

for (i in 1:(nrow(all_points)-1)) {
  for (j in (i+1):nrow(all_points)) {
    origin <- all_points[i,]
    destination <- all_points[j,]
    
    # Pass all airport/vertiport IDs to avoid using them as intermediaries
    dijkstra_result <- find_shortest_path_dijkstra(origin$id, destination$id, uam_graph, endpoint_ids = all_points$id)
    full_path <- dijkstra_result$path
    path_edge_indices <- dijkstra_result$edge_indices
    
    route_id <- paste(origin$id, destination$id, sep="-")
    
    path_coords <- list()
    path_names <- c()
    path_types <- c()
    path_node_ids <- c()  # Track node IDs to detect duplicates
    coord_counter <- 1
    
    for (k in 1:(length(full_path)-1)) {
      from_node <- full_path[k]
      to_node <- full_path[k+1]
      
      # Add from_node waypoint if it's the first node or if it hasn't been added yet
      if (k == 1 || (length(path_node_ids) == 0 || path_node_ids[length(path_node_ids)] != from_node)) {
        if (from_node %in% all_points$id) {
          idx <- which(all_points$id == from_node)
          path_coords[[coord_counter]] <- c(all_points$lon[idx], all_points$lat[idx])
          path_names[coord_counter] <- all_points$name[idx]
          path_types[coord_counter] <- all_points$tipo[idx]
          path_node_ids[coord_counter] <- from_node
        } else {
          node_id_num <- as.numeric(from_node)
          idx <- which(nodes$id == node_id_num)
          coords <- st_coordinates(nodes$geom[idx])
          path_coords[[coord_counter]] <- c(coords[1,"X"], coords[1,"Y"])
          path_names[coord_counter] <- get_waypoint_name(node_id_num)
          path_types[coord_counter] <- "Waypoint"
          path_node_ids[coord_counter] <- from_node
        }
        coord_counter <- coord_counter + 1
      }
      
      from_adjacency <- uam_graph$adjacency[[as.character(from_node)]]
      edge_idx_in_adj <- which(from_adjacency == to_node)
      
      if (length(edge_idx_in_adj) > 0) {
        from_geoms <- uam_graph$geometries[[as.character(from_node)]]
        
        if (!is.null(from_geoms) && length(from_geoms) >= edge_idx_in_adj[1]) {
          edge_geom <- from_geoms[[edge_idx_in_adj[1]]]
        } else {
          edge_geom <- NULL
        }
        
        if (!is.null(edge_geom) && nrow(edge_geom) > 2) {
          # Add intermediate corridor points (skip first and last which are endpoints)
          # IMPORTANT: Only add if there are MORE than 2 points (i.e., actual intermediate points)
          for (g in 2:(nrow(edge_geom)-1)) {
            path_coords[[coord_counter]] <- c(edge_geom[g, "X"], edge_geom[g, "Y"])
            path_names[coord_counter] <- paste("Corridor", from_node, "-", to_node)
            path_types[coord_counter] <- "Corridor"
            path_node_ids[coord_counter] <- NA  # Corridor points don't have node IDs
            coord_counter <- coord_counter + 1
          }
        }
      }
      
      # Add to_node waypoint
      if (to_node %in% all_points$id) {
        idx <- which(all_points$id == to_node)
        path_coords[[coord_counter]] <- c(all_points$lon[idx], all_points$lat[idx])
        path_names[coord_counter] <- all_points$name[idx]
        path_types[coord_counter] <- all_points$tipo[idx]
        path_node_ids[coord_counter] <- to_node
      } else {
        node_id_num <- as.numeric(to_node)
        idx <- which(nodes$id == node_id_num)
        coords <- st_coordinates(nodes$geom[idx])
        path_coords[[coord_counter]] <- c(coords[1,"X"], coords[1,"Y"])
        path_names[coord_counter] <- get_waypoint_name(node_id_num)
        path_types[coord_counter] <- "Waypoint"
        path_node_ids[coord_counter] <- to_node
      }
      coord_counter <- coord_counter + 1
    }
    
    if (length(path_coords) > 0) {
      coords_matrix <- do.call(rbind, path_coords)
      route_df <- data.frame(
        route = route_id,
        id = seq_len(nrow(coords_matrix)),
        name = path_names,
        lat = coords_matrix[,2],
        lon = coords_matrix[,1],
        type = path_types,
        stringsAsFactors = FALSE
      )
      
      routes_list[[route_counter]] <- route_df
      route_counter <- route_counter + 1
      
      num_waypoints <- sum(path_types == "Waypoint")
      cat("  Route", route_id, ":", num_waypoints, "waypoints REH\n")
    }
  }
}

wps <- do.call(rbind, routes_list)

cat("\nTotal routes UAM generated:", length(unique(wps$route)), "\n\n")

# ========== LOAD HELIPORTS ==========
cat("5. Loading RMSP heliports...\n")

helipads <- tryCatch({
  read_csv(HELIPADS_FILE, show_col_types = FALSE, progress = FALSE)
}, error = function(e) {
  warning(paste("File", HELIPADS_FILE, "not found."))
  data.frame(code = character(0), name = character(0), type = character(0),
            lat = numeric(0), lon = numeric(0), operation = character(0), municipality = character(0))
})

if (nrow(helipads) > 0) {
  helipads$lat <- as.numeric(helipads$lat)
  helipads$lon <- as.numeric(helipads$lon)
  helipads <- helipads[!is.na(helipads$lat) & !is.na(helipads$lon), ]
  cat("   Total RMSP heliports:", nrow(helipads), "\n")
  cat("   Municipalities:", length(unique(helipads$municipality)), "\n\n")
}

# ========== COLORS AND PALETTES ==========
color_routes_uam <- "#FF6B00"
color_vertiports <- "#FF00FF"
color_helipads <- "#FFD700"
color_waypoints <- "#A8DADC"

# Paletas para dados das zonas
if (!is.null(zones_sf) && nrow(zones_sf) > 0) {
  pal_population <- colorNumeric(
    palette = "YlOrRd",
    domain = c(0, max(zones_sf$population, na.rm=TRUE)),
    na.color = "transparent"
  )
  
  pal_trips_prod <- colorNumeric(
    palette = "Blues",
    domain = c(0, max(zones_sf$trips_produced, na.rm=TRUE)),
    na.color = "transparent"
  )
  
  pal_trips_attr <- colorNumeric(
    palette = "Greens",
    domain = c(0, max(zones_sf$trips_attracted, na.rm=TRUE)),
    na.color = "transparent"
  )
  
  pal_income <- colorNumeric(
    palette = "Purples",
    domain = c(min(zones_sf$income_per_capita, na.rm=TRUE), max(zones_sf$income_per_capita, na.rm=TRUE)),
    na.color = "transparent"
  )
}

# ========== INTERACTIVE MAP ==========
cat("6. Generating interactive map...\n\n")

map_rmsp <- leaflet() %>%
  addProviderTiles(provider = providers$CartoDB) %>%
  setView(-46.63, -23.55, 10) %>%
  
  # Layers of socioeconomic data of zones
  { if (!is.null(zones_sf) && nrow(zones_sf) > 0) {
    map_obj <- .
    
    # Layer: Population
    map_obj <- addPolygons(
      map_obj,
      data = zones_sf,
      fillColor = ~pal_population(population),
      fillOpacity = 0.7,
      color = "#444444",
      weight = 1,
      opacity = 0.5,
      group = "Population",
      popup = ~paste0(
        "<b>Zone ", NumeroZona, ": ", NomeZona, "</b><br>",
        "Municipality: ", NomeMunici, "<br>",
        "Population: ", format(population, big.mark=",", scientific=FALSE), "<br>",
        "Households: ", format(households, big.mark=",", scientific=FALSE)
      ),
      label = ~paste("Zone", NumeroZona, "-", NomeZona)
    )
    
    # Layer: Produced Trips
    map_obj <- addPolygons(
      map_obj,
      data = zones_sf,
      fillColor = ~pal_trips_prod(trips_produced),
      fillOpacity = 0.7,
      color = "#444444",
      weight = 1,
      opacity = 0.5,
      group = "Produced Trips",
      popup = ~paste0(
        "<b>Zone ", NumeroZona, ": ", NomeZona, "</b><br>",
        "Municipality: ", NomeMunici, "<br>",
        "Produced Trips: ", format(trips_produced, big.mark=",", scientific=FALSE), "<br>",
        "Population: ", format(population, big.mark=",", scientific=FALSE)
      ),
      label = ~paste("Zone", NumeroZona, "- Produced Trips:", format(trips_produced, big.mark=","))
    )
    
    # Layer: Attracted Trips
    map_obj <- addPolygons(
      map_obj,
      data = zones_sf,
      fillColor = ~pal_trips_attr(trips_attracted),
      fillOpacity = 0.7,
      color = "#444444",
      weight = 1,
      opacity = 0.5,
      group = "Attracted Trips",
      popup = ~paste0(
        "<b>Zone ", NumeroZona, ": ", NomeZona, "</b><br>",
        "Municipality: ", NomeMunici, "<br>",
        "Attracted Trips: ", format(trips_attracted, big.mark=",", scientific=FALSE), "<br>",
        "Jobs: ", format(jobs, big.mark=",", scientific=FALSE)
      ),
      label = ~paste("Zone", NumeroZona, "- Attracted Trips:", format(trips_attracted, big.mark=","))
    )
    
    # Layer: Per Capita Income
    map_obj <- addPolygons(
      map_obj,
      data = zones_sf,
      fillColor = ~pal_income(income_per_capita),
      fillOpacity = 0.7,
      color = "#444444",
      weight = 1,
      opacity = 0.5,
      group = "Per Capita Income",
      popup = ~paste0(
        "<b>Zone ", NumeroZona, ": ", NomeZona, "</b><br>",
        "Municipality: ", NomeMunici, "<br>",
        "Per Capita Income: R$ ", format(income_per_capita, big.mark=".", decimal.mark=",", scientific=FALSE), "<br>",
        "Population: ", format(population, big.mark=",", scientific=FALSE), "<br>",
        "Jobs: ", format(jobs, big.mark=",", scientific=FALSE)
      ),
      label = ~paste("Zone", NumeroZona, "- Per Capita Income: R$", format(income_per_capita, big.mark=".", decimal.mark=","))
    )
    
    map_obj
  } else . } %>%
  
  # Layer control
  addLayersControl(
    baseGroups = c("None", "Population", "Produced Trips", "Attracted Trips", "Per Capita Income"),
    overlayGroups = c("UAM Routes", "Airports", "Vertiports", "Helipads",
                      "REH", "CTR", "Waypoints"),
    options = layersControlOptions(collapsed = FALSE),
    position = "topleft"
  ) %>%
  
  hideGroup(c("Waypoints", "REH", "CTR", "Population", "Produced Trips", 
              "Attracted Trips", "Per Capita Income")) %>%
  
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
        console.log('Updating legends for group:', selectedGroup);
        
        legends.forEach(function(legend) {
          // Extract only the title from the first div with the strong class
          var titleElem = legend.querySelector('div strong');
          if (titleElem) {
            // Use innerHTML to keep <br>, then remove the tags
            var title = titleElem.innerHTML.toLowerCase();
            console.log('Raw HTML:', JSON.stringify(title));
            // Replace <br> with space and remove tags
            title = title.replace(/<br\\s*\\/?>/gi, ' ').replace(/<[^>]+>/g, '').trim().replace(/  +/g, ' ');
            console.log('Cleaned title:', JSON.stringify(title));
            var selectedClean = selectedGroup.toLowerCase();
            console.log('Selected group:', JSON.stringify(selectedClean));
            
            // If None is selected, hide all legends
            if (!selectedGroup || selectedGroup === 'None') {
              legend.classList.add('legend-hidden');
              console.log('Hidden (None selected)');
            } else if (title === selectedClean || title.includes(selectedClean)) {
              // Exact match or contains the text
              legend.classList.remove('legend-hidden');
              console.log('Shown (match found)');
            } else {
              legend.classList.add('legend-hidden');
              console.log('Hidden (no match)');
            }
          }
        });
      }
      
      map.on('baselayerchange', function(event) {
        updateLegendVisibility(event.name);
      });
      
      // Wait for legends to render initially
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
  ") %>%
  
  # Legends (leaflet 2.2.2 syntax)
  { if (!is.null(zones_sf)) {
      addLegend(
        .,
        "topright",
        pal = pal_population,
        values = zones_sf$population,
        title = "Population",
        group = "Population",
        opacity = 0.7,
        layerId = "leg_pop"
      ) %>%
      addLegend(
        "topright",
        pal = pal_trips_prod,
        values = zones_sf$trips_produced,
        title = "Produced<br>Trips",
        group = "Produced Trips",
        opacity = 0.7,
        layerId = "leg_tprod"
      ) %>%
      addLegend(
        "topright",
        pal = pal_trips_attr,
        values = zones_sf$trips_attracted,
        title = "Attracted<br>Trips",
        group = "Attracted Trips",
        opacity = 0.7,
        layerId = "leg_tattra"
      ) %>%
      addLegend(
        "topright",
        pal = pal_income,
        values = zones_sf$income_per_capita,
        title = "Per Capita Income<br>(R$)",
        group = "Per Capita Income",
        opacity = 0.7,
        labFormat = labelFormat(prefix = "R$ ", big.mark = ",", digits = 0),
        layerId = "leg_income"
      )
    } else . } %>%
  
  # Layer: REH
  addProviderTiles(providers$CartoDB.Positron, group = "REH") %>%
  addPolygons(data = obstacles_airports$geometry, color = 'orange', group = "CTR") %>%
  addPolylines(data = edges$geom, color=edges$col,
               popup = paste0("REH: ", edges$REH, "<br>", edges$edge_info),
               opacity=1, group = "REH") %>%
  { 
    # Add waypoint markers
    map_obj <- .
    nodes_coords <- st_coordinates(nodes$geom)
    nodes_with_coords <- nodes %>%
      st_drop_geometry() %>%
      mutate(
        lng = nodes_coords[,"X"],
        lat = nodes_coords[,"Y"]
      )
    
    for (i in 1:nrow(nodes_with_coords)) {
      map_obj <- addMarkers(
        map_obj,
        lng = nodes_with_coords$lng[i],
        lat = nodes_with_coords$lat[i],
        popup = paste0("<b>", nodes_with_coords$waypoint_name[i], "</b><br>Type: ", nodes_with_coords$node_type[i]),
        label = nodes_with_coords$waypoint_name[i],
        group = 'Waypoints'
      )
    }
    map_obj
  } %>%
  
  # Layer: UAM Routes
  {
    map_obj <- .
    for (route_id in unique(wps$route)) {
      route_data <- wps[wps$route == route_id, ]
      map_obj <- addPolylines(
        map_obj,
        data = route_data,
        lng = ~lon, lat = ~lat,
        color = color_routes_uam,
        weight = 5,
        opacity = 0.8,
        dashArray = "8, 6",
        group = "UAM Routes",
        popup = paste0("UAM Route: ", route_id),
        label = route_id
      )
    }
    map_obj
  } %>%
  
  # Layer: Airports
  { if (exists("all_points")) addAwesomeMarkers(
    .,
    data = all_points[all_points$tipo == "Airport",],
    lng = ~lon, lat = ~lat,
    icon = awesomeIcons(icon = "plane", library = "fa", markerColor = "red", iconColor = "white"),
    popup = ~paste("<b>✈️ Airport:", name, "</b><br>",
                   "Waypoint REH: Node", node_reh),
    label = ~paste("✈️", name),
    group = "Airports"
  ) else . } %>%
  
  # Layer: Vertiports
  { if (exists("vertiports") && nrow(vertiports) > 0) addAwesomeMarkers(
    .,
    data = vertiports,
    lng = ~lon, lat = ~lat,
    icon = awesomeIcons(icon = "star", library = "fa", markerColor = "purple", iconColor = "yellow"),
    popup = ~paste("<b>⭐ Vertiport:", id, "</b><br>",
                   "Location: ", name, "<br>",
                   "Code: ", code, "<br>",
                   "Waypoint REH: Node", node_reh),
    label = ~paste("⭐", id),
    group = "Vertiports"
  ) else . } %>%
  
  # Layer: Helipads
  { if (nrow(helipads) > 0) addCircleMarkers(
    .,
    data = helipads,
    lng = ~lon, lat = ~lat,
    radius = 5,
    color = "#000000",
    fillColor = color_helipads,
    fillOpacity = 0.7,
    stroke = TRUE,
    weight = 1,
    popup = ~paste("<b>🚁 ", name, "</b><br>",
                   "Code: ", code, "<br>",
                   "Type: ", type, "<br>",
                   "Municipality: ", municipality),
    label = ~paste("🚁", name),
    group = "Helipads"
  ) else . }

# Make sure the object is created
cat("   ✓ Map generated successfully\n\n")

# ========== EXPORT ROUTES ==========
cat("7. Exporting routes...\n")
routes_export <- wps[, c("route", "id", "name", "lat", "lon", "type")]

routes_summary <- data.frame()
for (route_id in unique(wps$route)) {
  route_data <- wps[wps$route == route_id, ]
  
  # Calculate distance only between WAYPOINTS (skip corridor intermediate points)
  waypoints_only <- route_data[route_data$type %in% c("Waypoint", "Airport", "Vertiport"), ]
  
  dist_total <- 0
  if (nrow(waypoints_only) > 1) {
    for (i in 1:(nrow(waypoints_only)-1)) {
      dist_total <- dist_total + calc_dist(
        waypoints_only$lat[i], waypoints_only$lon[i],
        waypoints_only$lat[i+1], waypoints_only$lon[i+1]
      )
    }
  }
  
  # dist_total already in km from calc_dist() (geodesic distance)
  dist_km <- dist_total
  
  routes_summary <- rbind(routes_summary, data.frame(
    route = route_id,
    origin = route_data$name[1],
    destination = route_data$name[nrow(route_data)],
    num_waypoints = sum(route_data$type == "Waypoint"),
    num_total_points = nrow(route_data),
    distance_km = round(dist_km, 2),
    stringsAsFactors = FALSE
  ))
}

write.csv(routes_export, "output/routes_uam_detailed_rmsp.csv", row.names = FALSE)
write.csv(routes_summary, "output/routes_uam_summary_rmsp.csv", row.names = FALSE)
saveRDS(list(routes_detailed = routes_export, routes_summary = routes_summary,
            all_points = all_points, graph = uam_graph), "output/routes_uam_complete_rmsp.rds")

cat("   ✓ Routes exported\n")

# Save map as HTML
library(htmlwidgets)
saveWidget(map_rmsp, "output/map_rmsp_uam.html", selfcontained = FALSE)
cat("   ✓ Map saved to: output/map_rmsp_uam.html\n")
cat("   (Open the HTML file in a browser to view)\n\n")
cat(paste(rep("=", 70), collapse=""), "\n")
cat("VISUALIZAÇÃO CONCLUÍDA\n")
cat(paste(rep("=", 70), collapse=""), "\n\n")

# Display map in R Viewer
#print(map_rmsp)
