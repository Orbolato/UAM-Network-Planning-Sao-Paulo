# Provenance and reproducibility scope

This repository accompanies the 2026 *Case Studies on Transport Policy* article:

> Lucas Orbolato Carvalho, Igor Galhano Gomes, Jaqueline Fonseca Rodrigues, Mayara Condé Rocha Murça, Marcelo Xavier Guterres, and Daniel Alberto Pamplona. **Data-driven framework for urban air mobility planning: Integrating socioeconomic and operational factors for optimal network design in São Paulo, Brazil.** *Case Studies on Transport Policy* 25, 101848. https://doi.org/10.1016/j.cstp.2026.101848

The public package intentionally separates (1) source snapshots that may be redistributed, (2) processed/curated inputs, (3) restricted source records that are not redistributed, and (4) generated analysis outputs.

## Reproducibility levels

### 1. Public artifact integrity

`ARTIFACTS.json` records the exact Git blob identity and byte size of every committed research-data artifact. `tests/test_repository_integrity.py` recomputes those identities in CI. This verifies that the repository contains the same public data snapshots and processed artifacts that were packaged for this release.

A Git blob SHA-1 is a content identity calculated over `blob <size>\0<bytes>`; it is used here as an exact-byte anchor for Git content, not as a security guarantee.

### 2. Public raw-to-processed preprocessing

The public raw inputs under `data/raw/` support the following preprocessing chain:

1. `scripts/preprocessing/01_process_od2023.py`
2. `scripts/preprocessing/02_process_anac_helipads.py`
3. `scripts/preprocessing/03_extract_od_table30.py`
4. `scripts/preprocessing/04_prepare_data_en.R`
5. `scripts/preprocessing/05_assign_heliports_to_zones.R`

This chain rebuilds the analysis tables derived from the Metrô-SP OD 2023 survey and the ANAC heliport register. The packaged `heliports.csv`, `heliports_with_zones.csv`, and `od_matrix_30.csv` are intended to reproduce exactly from the committed public raw snapshots. The zone and income tables may differ in the final floating-point decimal digits across library/platform versions; such differences should not be interpreted as a change in the study methodology.

The preprocessing script `01_process_od2023.py` also creates an interim Table-25 OD extract. That historical intermediate is not the OD matrix used by the network-demand pipeline; the study pipeline uses Table 30 as extracted by `03_extract_od_table30.py`.

### 3. Analysis rerun from committed processed inputs

`Rscript run_all.R` runs the analysis from the committed files in `data/processed/`. The orchestration executes the exploratory analysis, baseline PAM/route-design case, BIMTRA aggregate map, and expanded network case. Baseline and expanded outputs are moved into separate subdirectories under `output/` to prevent one scenario from overwriting the other.

The numbered scientific-analysis scripts are retained as the study implementation. The public hardening pass changes orchestration, documentation, environment pinning, and integrity checks; it does not intentionally change the study's scientific parameters or optimization logic.

### 4. Restricted BIMTRA branch

The flight-level BIMTRA movement records used for the helicopter-movement analysis are **not redistributed**. They are expected locally at:

`data/raw/bimtra/BIMTRA.csv`

If that file is absent, `run_all.R` skips `scripts/05_bimtra_analysis.py` and uses the committed aggregate tables under `data/processed/bimtra/` for the map and network-expansion inputs. The public repository therefore supports the published aggregate BIMTRA-dependent analysis, but it does **not** independently reconstruct those aggregate tables from the restricted source records.

The committed BIMTRA aggregates contain heliport- and OD-pair-level counts/coordinates; the public package does not include the underlying flight-level records or aircraft-registration observations.

### 5. Curated aeronautical network inputs

Two processed inputs are not rebuilt by the public preprocessing chain:

- `data/processed/reh_network_corrected.RData`: REH waypoints, route segments/altitudes, and the control-zone obstacle representation, manually curated from DECEA helicopter-route charts.
- `data/processed/heliports_complete_with_coordinates.csv`: a compiled coordinate reference used to locate BIMTRA origins and destinations.

These are archived analysis inputs. Their presence and exact bytes are verified by CI, but the repository does not claim an automated raw-to-processed reconstruction for them.

## Source snapshots included in the repository

| Source | Repository snapshot | Role |
|---|---|---|
| Metrô-SP, Pesquisa Origem e Destino 2023 | `data/raw/od2023/Tabelas_Site_OD2023_REV_190225.xlsx` | Zone socioeconomic data and OD demand tables |
| Metrô-SP, OD 2023 zone geography | `data/raw/od2023/shapefile/Zonas_2023.*` | Boundaries of the 527 OD zones |
| ANAC civil heliport register | `data/raw/anac/Helipontos.csv` | Registered heliports used for RMSP filtering and candidate-site analysis |
| DECEA REH information | archived as `data/processed/reh_network_corrected.RData` | Route-network representation used by the routing scripts |
| BIMTRA movement records | **not included** | Helicopter operational evidence used for network expansion |

The README records the source pages and snapshot dates used in the study package.

## Maps and paper figures

Several article maps are screenshots of interactive Leaflet HTML products rather than static figures generated byte-for-byte by CI. The repository maps each paper figure/table to its generating script/output in `README.md`. CI validates source syntax, data identities, schemas, and package structure; it does not claim pixel-identical regeneration of screenshots from interactive maps.

## Software environments

The public package was tested with R 4.4.2 and Python 3.12. Python package versions are pinned in `requirements.txt`. R dependencies are listed in `install_packages.R`; the original analysis was not archived with a complete lockfile, so the repository does not claim byte-identical R package restoration.

## Licensing and source terms

No software or data license is granted by this repository. Source-provider terms continue to apply to source data, and inclusion of a public source snapshot or a derived artifact here does not relicense third-party material. Users should consult the relevant data providers before redistributing source data or derived products beyond uses permitted by those providers.
