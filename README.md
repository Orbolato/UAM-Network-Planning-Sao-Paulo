# Data-driven framework for urban air mobility planning in São Paulo

Code and data for the article:

> Carvalho, L.O., Gomes, I.G., Rodrigues, J.F., Murça, M.C.R., Guterres, M.X., Pamplona, D.A. (2026).
> **Data-driven framework for urban air mobility planning: Integrating socioeconomic and operational
> factors for optimal network design in São Paulo, Brazil.** *Case Studies on Transport Policy*, 25, 101848.
> https://doi.org/10.1016/j.cstp.2026.101848

The framework plans an initial Urban Air Mobility (UAM) network for the São Paulo Metropolitan
Region (RMSP) in four steps:

1. **Vertiport location**: PAM (k-medoids) clustering of the ANAC-registered helipads located in
   high-income zones of the 2023 Metrô-SP Origin–Destination (OD) Survey. The medoids become the
   candidate vertiports.
2. **Route optimization**: Dijkstra shortest paths between vertiports and the airports SBSP
   (Congonhas), SBGR (Guarulhos) and SBMT (Campo de Marte) over the Helicopter Special Routes (REH)
   network. Vertiports and airports cannot be used as intermediate nodes.
3. **Demand estimation**: a daily UAM OD matrix for city-taxi, airport-shuttle and inter-airport
   services, built from the OD survey and airport passenger data.
4. **Network expansion**: three extra vertiports (SSUB, SIAV, SIBH) chosen from BIMTRA helicopter
   movement records, giving a 9-node network.

## Repository structure

```
.
├── run_all.R                       # runs the whole pipeline
├── install_packages.R              # installs the R packages
├── requirements.txt                # Python packages
├── scripts/
│   ├── preprocessing/              # data/raw  ->  data/processed
│   │   ├── 01_process_od2023.py
│   │   ├── 02_process_anac_helipads.py
│   │   ├── 03_extract_od_table30.py
│   │   ├── 04_prepare_data_en.R
│   │   └── 05_assign_heliports_to_zones.R
│   ├── 01_exploratory_data_analysis.R
│   ├── 02_helipad_income_threshold_maps.R
│   ├── 03_vertiport_clustering_baseline.R
│   ├── 04_uam_routes_baseline.R
│   ├── 05_bimtra_analysis.py
│   ├── 06_bimtra_od_map.R
│   ├── 07_vertiport_clustering_expanded.R
│   └── 08_uam_routes_expanded.R
├── data/
│   ├── raw/                        # original source files
│   └── processed/                  # analysis-ready inputs
│       └── bimtra/                 # aggregated helicopter movement tables
└── output/                         # created by the scripts
```

## Requirements

- R (≥ 4.3) with the packages listed in `install_packages.R`:
  `Rscript install_packages.R`
- Python (≥ 3.10) with the packages in `requirements.txt`:
  `pip install -r requirements.txt`

Tested with R 4.4.2 and Python 3.12 on Windows 10.

## How to run

Run all commands from the repository root.

```bash
Rscript run_all.R                 # analysis only, using data/processed/
Rscript run_all.R --preprocess    # first rebuilds data/processed/ from data/raw/
```

The full run with `--preprocess` takes about 20 minutes on a desktop computer.

The raw BIMTRA records are not included (see [Data](#data)), so `run_all.R` skips
`05_bimtra_analysis.py` and the BIMTRA map is drawn from the aggregated tables in
`data/processed/bimtra/`. If you obtain the raw records, save them as `data/raw/bimtra/BIMTRA.csv`
and script `05` will run as well.

If your Python interpreter is not called `python`, set it with the `PYTHON` environment variable
(e.g. `PYTHON=python3 Rscript run_all.R`).

On Windows, clone the repository to a short path (e.g. `C:\uam`). The interactive maps are saved
with deeply nested dependency folders, and saving them fails if the full path exceeds the
260-character Windows limit.

You can also run the scripts one at a time, in numerical order (e.g.
`Rscript scripts/03_vertiport_clustering_baseline.R`). Each route script reads the vertiports
written by the clustering script that ran just before it:

- run `03` then `04` for the **baseline** network (3 vertiports);
- run `07` then `08` for the **expanded** network (6 vertiports).

Both scenarios write files with the same names to `output/`. `run_all.R` therefore moves each
scenario's clustering and routing files to `output/baseline/` and `output/expanded/`.

## Scripts

| Script | What it does |
|---|---|
| `preprocessing/01_process_od2023.py` | Reads Tables 1 and 6 of the OD 2023 workbook: zone population, households, jobs, trips produced and attracted, and per capita income. |
| `preprocessing/02_process_anac_helipads.py` | Keeps the ANAC helipads located in the 39 RMSP municipalities (285 helipads). |
| `preprocessing/03_extract_od_table30.py` | Converts Table 30 of the OD 2023 workbook (zone-to-zone daily trips) to long format. |
| `preprocessing/04_prepare_data_en.R` | Translates column names to English and writes `data/processed/`. |
| `preprocessing/05_assign_heliports_to_zones.R` | Assigns each helipad to its OD zone by spatial join. |
| `01_exploratory_data_analysis.R` | Descriptive statistics, correlation matrix, histograms and helipad filtering by income (Section 4.2). |
| `02_helipad_income_threshold_maps.R` | Maps of the helipads in zones above R$ 2,500 and R$ 5,000 per capita income. |
| `03_vertiport_clustering_baseline.R` | Elbow and silhouette diagnostics for k = 2…8, PAM clustering with k = 3, reclustering of all helipads, cluster indicators and OD demand matrix (Sections 3.2, 3.4, 4.3, 4.5). |
| `04_uam_routes_baseline.R` | Builds the REH graph, links each vertiport and airport to its k = 2 nearest points, computes the constrained Dijkstra routes and draws the interactive map (Sections 3.3, 4.4). |
| `05_bimtra_analysis.py` | Filters BIMTRA helicopter movements with origin and destination in the RMSP and computes per-heliport and per-OD-pair statistics (Section 4.6). Needs the raw BIMTRA records, which are not included. |
| `06_bimtra_od_map.R` | Interactive map of helicopter operations by OD pair, from `data/processed/bimtra/`. |
| `07_vertiport_clustering_expanded.R` | Same as `03`, adding SSUB, SIAV and SIBH as vertiports 4–6 before reclustering (Section 4.6). |
| `08_uam_routes_expanded.R` | Routes for the expanded network. Refined version of `04`: vertiports are also linked to intermediate points of REH segments, link length is capped, and links that cross REH segments are rejected. |

Some comments and console messages, mainly in the preprocessing scripts, are in Portuguese.

## Where each figure and table comes from

The map figures in the article are screenshots of the interactive Leaflet maps (HTML files) made by
the scripts, with the named layers switched on. Fig. 1 is a diagram and is not produced by code.

| Article | Script | Output (after `run_all.R`) |
|---|---|---|
| Figs. 2–4 | `04` | `output/baseline/map_rmsp_uam.html`, layers *Population*, *Produced Trips*, *Per Capita Income* |
| Fig. 5 | `04` | `output/baseline/map_rmsp_uam.html`, layers *Per Capita Income* and *REH* |
| Table 3 | `01` | `output/eda_tables/01_descriptive_statistics.tex` |
| Fig. 6 | `01` | `output/eda_figures/06_correlation_matrix.pdf` |
| Fig. 7 | `03` | `output/baseline/elbow_plot_rmsp.pdf`, `k_selection_diagnostics_rmsp.csv` |
| Fig. 8 | `01` | `output/eda_figures/01_income_distribution.pdf`, `03_trips_produced_distribution.pdf` |
| Fig. 9 | `01` | `output/eda_figures/10_top_municipalities.pdf`, `11_helipads_by_income.pdf` |
| Fig. 10 | `01` | `output/eda_figures/13_helipads_income_threshold_comparison.pdf` |
| Fig. 11 | `02` | `output/map_helipads_threshold_2500.html`, `output/map_helipads_threshold_5000.html` |
| Fig. 12 | `03` | `output/baseline/map_clusters_vertiports_rmsp.html`, layers *Clustered Helipads* / *Reclustered Helipads* |
| Table 4 | `03` | `output/baseline/cluster_socioeconomics_indices_original.csv`; silhouettes in `vertiports_medoids_rmsp.csv` |
| Table 5 | `03` | `output/baseline/vertiports_medoids_rmsp.csv` |
| Fig. 13, Table 6 | `04` | `output/baseline/map_rmsp_uam.html`, `output/baseline/routes_uam_summary_rmsp.csv` |
| Table 7 | `03` | `output/baseline/expanded_od_matrix_vertiports_airports.csv` |
| Table 8 | `05` | `data/processed/bimtra/BIMTRA_RMSP_Only_heliport_statistics.csv` |
| Fig. 14 | `06` | `output/helicopter_analysis_bimtra_rmsp_only/leaflet_maps/BIMTRA_OD_RMSP_Only_All_Routes.html` |
| Fig. 15 | `08` | `output/expanded/map_rmsp_uam.html` |
| Table 9 | `07` | `output/expanded/vertiports_medoids_rmsp.csv` |
| Table 10 | `07` | `output/expanded/expanded_od_matrix_vertiports_airports.csv` |

In the output file names, *expanded_od_matrix_vertiports_airports* means the matrix of vertiports
**plus airports** (Tables 7 and 10). It does not refer to the expanded network.

## Main parameters

Parameters are set at the top of each script.

| Parameter | Value | Script |
|---|---|---|
| `INCOME_THRESHOLD` (minimum per capita income of a helipad's zone) | R$ 5,000 | `03`, `07` |
| `NUM_CLUSTERS` (k for PAM) | 3 | `03`, `07` |
| `ADDITIONAL_VERTIPORTS` (expanded network) | SSUB, SIAV, SIBH | `07` |
| Conversion factors (city taxi, airport shuttle, transfer) | 1% | `03`, `07` |
| `EVTOL_CAPACITY` | 4 passengers | `03`, `07` |
| Airport passengers per day, RMSP share and transfer volumes | see script header | `03`, `07` |
| `K_CONNECTIONS` (nearest points linked to each vertiport/airport) | 2 | `04` |
| `K_WAYPOINTS` / `K_GEOMETRIC_NODES` (nearest REH waypoints / intermediate REH points) | 2 / 1 | `08` |
| `MAX_CONNECTION_DISTANCE_NM`, `BLOCK_CONNECTIONS_CROSSING_REH` | 5 NM, TRUE | `08` |

## Data

### Raw data (`data/raw/`)

| File | Content | Source |
|---|---|---|
| `od2023/Tabelas_Site_OD2023_REV_190225.xlsx` | Tables of the 2023 OD Survey (Tab1 zone data, Tab6 income, Tab30 zone-to-zone trips) | Metrô-SP, [Pesquisa Origem e Destino 2023](https://www.metro.sp.gov.br/pesquisa-od), release of 19 Feb 2025 |
| `od2023/shapefile/Zonas_2023.*` | Boundaries of the 527 OD zones | Metrô-SP, OD 2023 maps |
| `anac/Helipontos.csv` | Registered civil helipads in Brazil (file dated 5 Dec 2025) | [ANAC, list of registered civil aerodromes](https://www.gov.br/anac/pt-br/assuntos/regulados/) |

The raw helicopter movement records from BIMTRA (Air Traffic Movement Information Database,
ANAC/DECEA; 58,440 records, mostly January 2025 – March 2026) cannot be redistributed. The
repository includes only the aggregated tables derived from them (see below).

### Processed data (`data/processed/`)

| File | Content | Produced by |
|---|---|---|
| `zones_data.csv` | 527 OD zones: population, households, jobs, trips produced and attracted | `preprocessing/01`, `04` |
| `income_per_capita.csv` | Income indicators per OD zone | `preprocessing/01`, `04` |
| `heliports.csv` | 285 ANAC helipads in the RMSP | `preprocessing/02`, `04` |
| `heliports_with_zones.csv` | Helipads with their OD zone | `preprocessing/05` |
| `od_matrix_30.csv` | Daily trips between OD zones (origin, destination, trips) | `preprocessing/03` |
| `reh_network_corrected.RData` | REH network: waypoints (`nodes`), route segments with altitudes (`edges`) and the control zone polygon (`obstacles_airports`) | Waypoints and routes from DECEA REH charts, manually corrected. Not rebuilt by the scripts. |
| `heliports_complete_with_coordinates.csv` | Coordinates of ANAC helipads, helidecks and public/private aerodromes, used by script `05` to locate BIMTRA origins and destinations | Compiled from ANAC registers. Not rebuilt by the scripts. |
| `bimtra/BIMTRA_RMSP_Only_heliport_statistics.csv` | Helicopter flights and distinct aircraft per heliport, departures and arrivals, with origin and destination in the RMSP (Table 8) | Script `05` |
| `bimtra/BIMTRA_RMSP_Only_od_mapping_data_complete.csv` | Helicopter flights and distinct aircraft per origin–destination pair, with coordinates (Fig. 14) | Script `05` |

`run_all.R --preprocess` rebuilds the first five processed files from `data/raw/`. It reproduces
`heliports.csv`, `heliports_with_zones.csv` and `od_matrix_30.csv` exactly. `zones_data.csv` and
`income_per_capita.csv` can differ in the last decimal digit because of floating-point differences
between library versions.

## Citation

If you use this code or data, please cite the article (see also `CITATION.cff`):

```bibtex
@article{Carvalho2026UAM,
  title   = {Data-driven framework for urban air mobility planning: Integrating socioeconomic and
             operational factors for optimal network design in S{\~a}o Paulo, Brazil},
  author  = {Carvalho, Lucas Orbolato and Gomes, Igor Galhano and Rodrigues, Jaqueline Fonseca and
             Mur{\c{c}}a, Mayara Cond{\'e} Rocha and Guterres, Marcelo Xavier and Pamplona, Daniel Alberto},
  journal = {Case Studies on Transport Policy},
  volume  = {25},
  pages   = {101848},
  year    = {2026},
  doi     = {10.1016/j.cstp.2026.101848}
}
```
