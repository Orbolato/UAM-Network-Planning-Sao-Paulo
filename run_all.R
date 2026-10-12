# ============================================================================
# RUN ALL - orchestration for the public reproducibility package
# ============================================================================
# Usage:
#   Rscript run_all.R                 # analysis from committed processed inputs
#   Rscript run_all.R --preprocess    # rebuild public processed inputs first
#
# The raw BIMTRA movement records are not redistributed. When they are absent,
# script 05 is skipped and script 06 uses the committed aggregate BIMTRA tables.
# The Python interpreter can be selected with the PYTHON environment variable.
# ============================================================================

# Make execution independent of the caller's current working directory when
# invoked with Rscript.
full_args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", full_args, value = TRUE)
if (length(file_arg) > 0) {
  script_path <- sub("^--file=", "", file_arg[[1]])
  script_path <- normalizePath(script_path, winslash = "/", mustWork = TRUE)
  setwd(dirname(script_path))
}

args <- commandArgs(trailingOnly = TRUE)
allowed_args <- c("--preprocess")
unknown_args <- setdiff(args, allowed_args)
if (length(unknown_args) > 0) {
  stop(
    "Unknown argument(s): ", paste(unknown_args, collapse = ", "),
    ". Supported argument: --preprocess"
  )
}

PREPROCESS <- "--preprocess" %in% args
PYTHON <- Sys.getenv("PYTHON", unset = "")
if (!nzchar(PYTHON)) {
  candidates <- if (.Platform$OS.type == "windows") c("python", "py") else c("python3", "python")
  found <- candidates[nzchar(Sys.which(candidates))]
  if (length(found) == 0) stop("No Python interpreter found. Set the PYTHON environment variable.")
  PYTHON <- found[[1]]
}
if (!nzchar(Sys.which(PYTHON))) {
  stop("Python interpreter not found: ", PYTHON, ". Set the PYTHON environment variable.")
}

RSCRIPT <- file.path(R.home("bin"), "Rscript")
if (!file.exists(RSCRIPT)) stop("Rscript executable not found at: ", RSCRIPT)

# Avoid UnicodeEncodeError when Python prints check marks on some Windows consoles.
Sys.setenv(PYTHONIOENCODING = "utf-8")

cat("Repository root:", normalizePath(".", winslash = "/"), "\n")
cat("Rscript:", normalizePath(RSCRIPT, winslash = "/"), "\n")
cat("Python:", PYTHON, "\n")
cat("Preprocessing:", if (PREPROCESS) "enabled" else "disabled", "\n")

require_files <- function(paths, label) {
  missing <- paths[!file.exists(paths)]
  if (length(missing) > 0) {
    stop(
      label, " is incomplete. Missing:\n  - ",
      paste(missing, collapse = "\n  - ")
    )
  }
}

run <- function(script) {
  if (!file.exists(script)) stop("Script not found: ", script)
  cat("\n", paste(rep("#", 78), collapse = ""), "\n", sep = "")
  cat("# Running:", script, "\n")
  cat(paste(rep("#", 78), collapse = ""), "\n\n", sep = "")
  cmd <- if (grepl("\\.py$", script, ignore.case = TRUE)) PYTHON else RSCRIPT
  status <- system2(cmd, args = shQuote(script))
  if (!identical(status, 0L)) {
    stop("Script failed: ", script, " (exit status ", status, ")")
  }
}

# Files written to output/ by the clustering and routing scripts. Both the
# baseline and expanded scenarios use these names, so each set is archived in
# a scenario-specific subdirectory immediately after it is produced.
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
  unlink(dest, recursive = TRUE, force = TRUE)
  dir.create(dest, recursive = TRUE, showWarnings = FALSE)

  moved <- character(0)
  for (f in SCENARIO_OUTPUTS) {
    src <- file.path("output", f)
    if (file.exists(src)) {
      dst <- file.path(dest, f)
      ok <- file.rename(src, dst)
      if (!ok) stop("Could not move scenario output from ", src, " to ", dst)
      moved <- c(moved, f)
    }
  }
  if (length(moved) == 0) warning("No scenario outputs were found to move into ", dest)
  cat("\n>>> Scenario outputs moved to", dest, "(", length(moved), "items )\n")
}

PUBLIC_RAW_INPUTS <- c(
  "data/raw/od2023/Tabelas_Site_OD2023_REV_190225.xlsx",
  "data/raw/od2023/shapefile/Zonas_2023.shp",
  "data/raw/od2023/shapefile/Zonas_2023.shx",
  "data/raw/od2023/shapefile/Zonas_2023.dbf",
  "data/raw/od2023/shapefile/Zonas_2023.prj",
  "data/raw/anac/Helipontos.csv"
)

PROCESSED_INPUTS <- c(
  "data/processed/zones_data.csv",
  "data/processed/income_per_capita.csv",
  "data/processed/heliports.csv",
  "data/processed/heliports_with_zones.csv",
  "data/processed/od_matrix_30.csv",
  "data/processed/reh_network_corrected.RData",
  "data/processed/heliports_complete_with_coordinates.csv",
  "data/processed/bimtra/BIMTRA_RMSP_Only_heliport_statistics.csv",
  "data/processed/bimtra/BIMTRA_RMSP_Only_od_mapping_data_complete.csv"
)

if (PREPROCESS) {
  require_files(PUBLIC_RAW_INPUTS, "Public raw-data snapshot")
  run("scripts/preprocessing/01_process_od2023.py")
  run("scripts/preprocessing/02_process_anac_helipads.py")
  run("scripts/preprocessing/03_extract_od_table30.py")
  run("scripts/preprocessing/04_prepare_data_en.R")
  run("scripts/preprocessing/05_assign_heliports_to_zones.R")
}

require_files(PROCESSED_INPUTS, "Processed analysis inputs")
dir.create("output", showWarnings = FALSE)

# ---------- Exploratory data analysis (Section 4.2) ----------
run("scripts/01_exploratory_data_analysis.R")
run("scripts/02_helipad_income_threshold_maps.R")

# ---------- Baseline network: 3 PAM vertiports (Sections 4.3-4.5) ----------
run("scripts/03_vertiport_clustering_baseline.R")
run("scripts/04_uam_routes_baseline.R")
stash_scenario("baseline")

# ---------- Helicopter movements, BIMTRA (Section 4.6) ----------
# The raw BIMTRA records are not redistributed. Script 05 runs only when the
# authorized user has supplied data/raw/bimtra/BIMTRA.csv locally; otherwise
# script 06 uses the aggregate tables committed in data/processed/bimtra/.
if (file.exists("data/raw/bimtra/BIMTRA.csv")) {
  run("scripts/05_bimtra_analysis.py")
} else {
  cat("\n>>> Restricted BIMTRA raw file not present: skipping scripts/05_bimtra_analysis.py\n")
  cat(">>> Using committed aggregate BIMTRA tables for scripts/06_bimtra_od_map.R\n")
}
run("scripts/06_bimtra_od_map.R")

# ---------- Expanded network: 3 PAM + 3 BIMTRA vertiports (Section 4.6) ----------
run("scripts/07_vertiport_clustering_expanded.R")
run("scripts/08_uam_routes_expanded.R")
stash_scenario("expanded")

cat("\nAll requested steps completed. Results are in output/.\n")
