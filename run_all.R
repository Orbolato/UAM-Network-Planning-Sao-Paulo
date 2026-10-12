# ============================================================================
# RUN ALL - reproduces the results of the paper
# ============================================================================
# Run from the repository root:
#   Rscript run_all.R                 # analysis only (uses data/processed/)
#   Rscript run_all.R --preprocess    # also rebuilds data/processed/ from data/raw/
#
# The Python interpreter can be set with the PYTHON environment variable
# (default: "python").
#
# The baseline (3 vertiports) and expanded (6 vertiports) scenarios write
# files with the same names to output/, so after each scenario the clustering
# and routing outputs are moved to output/baseline/ and output/expanded/.
# ============================================================================

args <- commandArgs(trailingOnly = TRUE)
PREPROCESS <- "--preprocess" %in% args
PYTHON <- Sys.getenv("PYTHON", "python")
RSCRIPT <- file.path(R.home("bin"), "Rscript")

# Avoid UnicodeEncodeError when Python prints check marks on Windows consoles
Sys.setenv(PYTHONIOENCODING = "utf-8")

run <- function(script) {
  cat("\n", paste(rep("#", 78), collapse = ""), "\n", sep = "")
  cat("# Running:", script, "\n")
  cat(paste(rep("#", 78), collapse = ""), "\n\n", sep = "")
  cmd <- if (grepl("\\.py$", script)) PYTHON else RSCRIPT
  status <- system2(cmd, shQuote(script))
  if (status != 0) stop("Script failed: ", script, " (exit status ", status, ")")
}

# Files written to output/ by the clustering and routing scripts
SCENARIO_OUTPUTS <- c(
  "k_selection_diagnostics_rmsp.csv", "elbow_plot_rmsp.pdf",
  "clustered_helipads_rmsp.csv", "vertiports_medoids_rmsp.csv",
  "selected_vertiports_rmsp.rds", "clustering_metadata_rmsp.rds",
  "cluster_socioeconomics_indices_original.csv", "cluster_socioeconomics_indices.csv",
  "demand_od_pairs_vertiports.csv", "matrix_od_vertiports.csv",
  "expanded_od_matrix_vertiports_airports.csv", "expanded_set_vertiports_airports.csv",
  "expanded_od_demand_all_pairs.csv",
  "map_clusters_vertiports_rmsp.html", "map_clusters_vertiports_rmsp_files",
  "routes_uam_detailed_rmsp.csv", "routes_uam_summary_rmsp.csv",
  "routes_uam_complete_rmsp.rds",
  "map_rmsp_uam.html", "map_rmsp_uam_files"
)

stash_scenario <- function(scenario) {
  dest <- file.path("output", scenario)
  unlink(dest, recursive = TRUE)
  dir.create(dest, recursive = TRUE)
  for (f in SCENARIO_OUTPUTS) {
    src <- file.path("output", f)
    if (file.exists(src)) file.rename(src, file.path(dest, f))
  }
  cat("\n>>> Scenario outputs moved to", dest, "\n")
}

# ---------- Preprocessing (optional) ----------
if (PREPROCESS) {
  run("scripts/preprocessing/01_process_od2023.py")
  run("scripts/preprocessing/02_process_anac_helipads.py")
  run("scripts/preprocessing/03_extract_od_table30.py")
  run("scripts/preprocessing/04_prepare_data_en.R")
  run("scripts/preprocessing/05_assign_heliports_to_zones.R")
}

dir.create("output", showWarnings = FALSE)

# ---------- Exploratory data analysis (Section 4.2) ----------
run("scripts/01_exploratory_data_analysis.R")
run("scripts/02_helipad_income_threshold_maps.R")

# ---------- Baseline network: 3 PAM vertiports (Sections 4.3-4.5) ----------
run("scripts/03_vertiport_clustering_baseline.R")
run("scripts/04_uam_routes_baseline.R")
stash_scenario("baseline")

# ---------- Helicopter movements, BIMTRA (Section 4.6) ----------
# The raw BIMTRA records are not redistributed. Script 05 runs only if you
# have placed them in data/raw/bimtra/BIMTRA.csv; otherwise script 06 uses the
# aggregated tables shipped in data/processed/bimtra/.
if (file.exists("data/raw/bimtra/BIMTRA.csv")) {
  run("scripts/05_bimtra_analysis.py")
} else {
  cat("\n>>> data/raw/bimtra/BIMTRA.csv not found: skipping scripts/05_bimtra_analysis.py\n")
}
run("scripts/06_bimtra_od_map.R")

# ---------- Expanded network: 3 PAM + 3 BIMTRA vertiports (Section 4.6) ----------
run("scripts/07_vertiport_clustering_expanded.R")
run("scripts/08_uam_routes_expanded.R")
stash_scenario("expanded")

cat("\nAll steps completed. Results are in output/.\n")
