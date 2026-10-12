# Data guide

This directory contains a mixture of public source snapshots, processed study inputs, manually curated aeronautical-network inputs, and aggregate outputs derived from restricted BIMTRA movement records. See [`../PROVENANCE.md`](../PROVENANCE.md) for the reproducibility boundaries and [`../ARTIFACTS.json`](../ARTIFACTS.json) for exact-byte artifact anchors.

## `raw/`

### `raw/od2023/`

Public source material from the 2023 São Paulo Metropolitan Region Origin-Destination Survey (Metrô-SP):

- `Tabelas_Site_OD2023_REV_190225.xlsx` — workbook release dated 19 February 2025.
- `shapefile/Zonas_2023.*` — geometry and attributes for the 527 OD zones.

The study uses zone socioeconomic indicators and the Table 30 zone-to-zone demand matrix. `scripts/preprocessing/01_process_od2023.py` also creates a historical Table-25 interim extract, but that extract is not the demand matrix used by the final network pipeline.

### `raw/anac/`

- `Helipontos.csv` — ANAC civil-heliport register snapshot dated 5 December 2025, used to identify registered heliports in the 39 RMSP municipalities.

### `raw/bimtra/`

Intentionally absent from the public repository. Flight-level BIMTRA movement records are not redistributed. If an authorized user supplies `data/raw/bimtra/BIMTRA.csv` locally, `scripts/05_bimtra_analysis.py` can rebuild the aggregate BIMTRA tables.

## `processed/`

| File | Role | Public reconstruction path |
|---|---|---|
| `zones_data.csv` | 527 OD zones with population, jobs, trips and other socioeconomic indicators | `preprocessing/01` → `preprocessing/04` |
| `income_per_capita.csv` | Zone-level income indicators | `preprocessing/01` → `preprocessing/04` |
| `heliports.csv` | ANAC heliports filtered to the RMSP | `preprocessing/02` → `preprocessing/04` |
| `heliports_with_zones.csv` | RMSP heliports assigned to OD zones | `preprocessing/05` |
| `od_matrix_30.csv` | Long-form Table 30 daily zone-to-zone trip matrix | `preprocessing/03` |
| `reh_network_corrected.RData` | Curated REH graph and control-zone obstacle data used for routing | archived input; not rebuilt automatically |
| `heliports_complete_with_coordinates.csv` | Coordinate reference used by BIMTRA processing | archived compiled input; not rebuilt automatically |
| `bimtra/BIMTRA_RMSP_Only_heliport_statistics.csv` | Heliport-level aggregate helicopter activity | requires restricted BIMTRA source to rebuild |
| `bimtra/BIMTRA_RMSP_Only_od_mapping_data_complete.csv` | OD-pair aggregate helicopter activity and coordinates | requires restricted BIMTRA source to rebuild |

The public preprocessing chain is invoked with:

```bash
Rscript run_all.R --preprocess
```

The first five processed datasets above are regenerated before the analysis starts. The remaining archived/curated inputs are preserved as committed artifacts.

## Reproducibility notes

- `heliports.csv`, `heliports_with_zones.csv`, and `od_matrix_30.csv` are expected to reproduce exactly from the committed source snapshots under the tested environment.
- `zones_data.csv` and `income_per_capita.csv` can exhibit last-decimal floating-point differences across dependency/platform versions.
- The BIMTRA aggregate tables are sufficient for the public map and network-expansion workflow, but the flight-level restricted records are required to recreate those aggregates from first principles.
- The article's interactive maps depend on Leaflet/htmlwidgets rendering and final paper figures were produced as screenshots from those interactive maps; the repository does not claim pixel-identical screenshot reproduction.

## Source terms

No separate data license is granted by this repository. Source-provider terms continue to apply to the source snapshots and to material derived from them. The repository's inclusion of a file should not be interpreted as a relicensing of third-party data.
