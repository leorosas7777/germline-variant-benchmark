import csv
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import happy_strat_table as hst  # noqa: E402

HEADER = ["Type", "Subtype", "Subset", "Filter", "Genotype", "QQ",
          "METRIC.Recall", "METRIC.Precision",
          "TRUTH.TP", "TRUTH.FN", "QUERY.TP", "QUERY.FP"]


def write_fixture(rows):
    tmp = tempfile.NamedTemporaryFile("w", suffix=".csv", delete=False, newline="")
    w = csv.writer(tmp)
    w.writerow(HEADER)
    w.writerows(rows)
    tmp.close()
    return tmp.name


class TestWilson(unittest.TestCase):
    def test_empty(self):
        self.assertEqual(hst.wilson(0, 0), (None, None))

    def test_known_value(self):
        lo, hi = hst.wilson(9, 10)
        self.assertAlmostEqual(lo, 0.596, places=3)
        self.assertAlmostEqual(hi, 0.982, places=3)

    def test_bounds(self):
        lo, hi = hst.wilson(5, 5)
        self.assertLessEqual(hi, 1.0)
        self.assertGreater(lo, 0.0)


class TestParse(unittest.TestCase):
    def test_filters_and_metrics(self):
        path = write_fixture([
            ["SNP", "*", "*", "PASS", "*", "*", "0.9", "0.9", "9", "1", "9", "1"],
            ["SNP", "*", "*", "ALL", "*", "*", "0.9", "0.9", "9", "1", "9", "1"],    # not PASS
            ["SNP", "*", "*", "PASS", "*", "0.5", "0.9", "0.9", "9", "1", "9", "1"],  # ROC row
            ["SNP", "*", "TS_boundary", "PASS", "*", "*", "1.0", "1.0", "1", "0", "1", "0"],
            ["INDEL", "*", "gc85", "PASS", "*", "*", "0.0", "0.0", "0", "0", "0", "0"],
        ])
        rows = hst.parse_extended(path, "gatk")
        self.assertEqual([(r["type"], r["stratum"]) for r in rows],
                         [("SNP", "*"), ("INDEL", "gc85")])
        self.assertAlmostEqual(rows[0]["recall"], 0.9)
        self.assertAlmostEqual(rows[0]["f1"], 0.9)
        empty = rows[1]
        self.assertIsNone(empty["recall"])
        self.assertIsNone(empty["precision"])
        self.assertIsNone(empty["f1"])

    def test_mismatch_with_happy_fails(self):
        path = write_fixture([
            ["SNP", "*", "*", "PASS", "*", "*", "0.5", "0.9", "9", "1", "9", "1"],
        ])
        with self.assertRaises(ValueError):
            hst.parse_extended(path, "gatk")

    def test_no_rows_fails(self):
        path = write_fixture([])
        with self.assertRaises(ValueError):
            hst.parse_extended(path, "gatk")


if __name__ == "__main__":
    unittest.main()
