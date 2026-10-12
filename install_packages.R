# Installs the R packages used by the scripts (only those not yet installed)
pkgs <- c(
  "sf", "readr", "dplyr", "tidyr", "stringr", "cluster",
  "leaflet", "leaflet.extras", "htmlwidgets",
  "ggplot2", "gridExtra", "corrplot", "plotly", "knitr", "kableExtra"
)
missing <- setdiff(pkgs, rownames(installed.packages()))
if (length(missing) > 0) {
  install.packages(missing, repos = "https://cloud.r-project.org")
} else {
  cat("All required R packages are already installed.\n")
}
