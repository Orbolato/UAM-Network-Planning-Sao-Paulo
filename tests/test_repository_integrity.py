from __future__ import annotations

import csv
import hashlib
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def git_blob_sha1(path: Path) -> str:
    data = path.read_bytes()
    header = f"blob {len(data)}\0".encode("ascii")
    return hashlib.sha1(header + data).hexdigest()


def read_csv(path: Path):
    with path.open("r", encoding="utf-8-sig", newline="") as fh:
        reader = csv.DictReader(fh)
        rows = list(reader)
        return reader.fieldnames or [], rows


class ArtifactIntegrityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest_path = ROOT / "ARTIFACTS.json"
        cls.manifest = json.loads(cls.manifest_path.read_text(encoding="utf-8"))
        cls.entries = cls.manifest["artifacts"]

    def test_manifest_is_git_blob_manifest(self):
        self.assertEqual(self.manifest["schema_version"], 1)
        self.assertEqual(self.manifest["hash_type"], "git-blob-sha1")
        self.assertGreaterEqual(len(self.entries), 16)

    def test_all_manifest_artifacts_match_exact_bytes(self):
        for entry in self.entries:
            with self.subTest(path=entry["path"]):
                path = ROOT / entry["path"]
                self.assertTrue(path.is_file(), f"Missing artifact: {entry['path']}")
                self.assertEqual(path.stat().st_size, entry["bytes"])
                self.assertEqual(git_blob_sha1(path), entry["git_blob_sha1"])

    def test_manifest_covers_all_committed_data_artifacts(self):
        expected = {entry["path"] for entry in self.entries}
        present = {
            p.relative_to(ROOT).as_posix()
            for p in (ROOT / "data").rglob("*")
            if p.is_file() and p.name != "README.md"
        }
        self.assertEqual(present, expected)

    def test_restricted_bimtra_raw_records_are_absent(self):
        restricted_dir = ROOT / "data" / "raw" / "bimtra"
        if restricted_dir.exists():
            files = [p for p in restricted_dir.rglob("*") if p.is_file()]
            self.assertEqual(files, [], f"Restricted BIMTRA files present: {files}")


class DataContractTests(unittest.TestCase):
    def test_zone_and_income_tables(self):
        zone_header, zones = read_csv(ROOT / "data/processed/zones_data.csv")
        income_header, income = read_csv(ROOT / "data/processed/income_per_capita.csv")

        self.assertEqual(
            zone_header,
            [
                "zone_id", "zone_name", "population", "households", "families",
                "jobs", "enrollments", "automobiles", "trips_produced",
                "trips_attracted", "area_hectares",
            ],
        )
        self.assertEqual(
            income_header,
            [
                "zone_id", "total_income", "average_household_income",
                "income_per_capita", "median_household_income",
                "minimum_wage_ratio",
            ],
        )
        self.assertEqual(len(zones), 527)
        self.assertEqual(len(income), 527)
        self.assertEqual(
            {row["zone_id"] for row in zones},
            {row["zone_id"] for row in income},
        )

    def test_heliport_tables(self):
        heli_header, heliports = read_csv(ROOT / "data/processed/heliports.csv")
        zoned_header, zoned = read_csv(ROOT / "data/processed/heliports_with_zones.csv")

        self.assertEqual(
            heli_header,
            [
                "code", "heliport_name", "heliport_type", "latitude", "longitude",
                "operation_type", "municipality",
            ],
        )
        self.assertEqual(
            zoned_header,
            ["code", "name", "type", "operation_type", "municipality", "zone_id", "lat", "lon"],
        )
        self.assertEqual(len(heliports), 285)
        self.assertEqual(len(zoned), 285)
        self.assertEqual({row["code"] for row in heliports}, {row["code"] for row in zoned})
        self.assertTrue(all(row["zone_id"] for row in zoned))

    def test_od_matrix_contract(self):
        header, rows = read_csv(ROOT / "data/processed/od_matrix_30.csv")
        self.assertEqual(header, ["origin", "destination", "trips"])
        self.assertGreater(len(rows), 1000)
        self.assertTrue(all(row["origin"] and row["destination"] and row["trips"] for row in rows[:1000]))

    def test_bimtra_aggregates_are_aggregate_level(self):
        stats_header, stats = read_csv(
            ROOT / "data/processed/bimtra/BIMTRA_RMSP_Only_heliport_statistics.csv"
        )
        od_header, od_rows = read_csv(
            ROOT / "data/processed/bimtra/BIMTRA_RMSP_Only_od_mapping_data_complete.csv"
        )

        self.assertEqual(
            stats_header,
            [
                "Heliport", "Outbound_Flights", "Outbound_Aircraft", "Inbound_Flights",
                "Inbound_Aircraft", "Total_Flights", "Total_Aircraft", "Percentage_Total",
            ],
        )
        self.assertEqual(
            od_header,
            [
                "Origin", "Destination", "Unique_Aircraft", "Departures",
                "Origin_Lat", "Origin_Lon", "Origin_Name", "Dest_Lat", "Dest_Lon",
                "Dest_Name", "Percentage",
            ],
        )
        self.assertGreater(len(stats), 10)
        self.assertGreater(len(od_rows), 10)
        forbidden = {"matricula", "registration", "aircraft_registration", "dhmovreal"}
        self.assertTrue(forbidden.isdisjoint({h.lower() for h in stats_header}))
        self.assertTrue(forbidden.isdisjoint({h.lower() for h in od_header}))


class RepositoryContractTests(unittest.TestCase):
    def test_expected_pipeline_scripts_exist(self):
        expected = [
            "run_all.R",
            "scripts/01_exploratory_data_analysis.R",
            "scripts/02_helipad_income_threshold_maps.R",
            "scripts/03_vertiport_clustering_baseline.R",
            "scripts/04_uam_routes_baseline.R",
            "scripts/05_bimtra_analysis.py",
            "scripts/06_bimtra_od_map.R",
            "scripts/07_vertiport_clustering_expanded.R",
            "scripts/08_uam_routes_expanded.R",
            "scripts/preprocessing/01_process_od2023.py",
            "scripts/preprocessing/02_process_anac_helipads.py",
            "scripts/preprocessing/03_extract_od_table30.py",
            "scripts/preprocessing/04_prepare_data_en.R",
            "scripts/preprocessing/05_assign_heliports_to_zones.R",
        ]
        for rel in expected:
            with self.subTest(path=rel):
                self.assertTrue((ROOT / rel).is_file())

    def test_python_requirements_are_exactly_pinned(self):
        reqs = [
            line.strip()
            for line in (ROOT / "requirements.txt").read_text(encoding="utf-8").splitlines()
            if line.strip() and not line.lstrip().startswith("#")
        ]
        self.assertTrue(reqs)
        self.assertTrue(all("==" in req for req in reqs), reqs)

    def test_citation_metadata_points_to_article_and_repository(self):
        cff = (ROOT / "CITATION.cff").read_text(encoding="utf-8")
        self.assertIn("10.1016/j.cstp.2026.101848", cff)
        self.assertIn("https://github.com/Orbolato/UAM-Network-Planning-Sao-Paulo", cff)
        self.assertIn("https://orcid.org/0000-0002-8402-5832", cff)
        self.assertNotIn("license:", cff.lower())

    def test_no_repository_license_file_was_added(self):
        names = {p.name.lower() for p in ROOT.iterdir() if p.is_file()}
        self.assertFalse(any(name in names for name in {"license", "license.md", "license.txt", "copying"}))


if __name__ == "__main__":
    unittest.main()
