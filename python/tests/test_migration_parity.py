from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path

TESTS_DIR = Path(__file__).resolve().parent
if str(TESTS_DIR) not in sys.path:
    sys.path.insert(0, str(TESTS_DIR))

from migration_parity_harness import run_parity, summarize_python_scene


class MigrationParityTests(unittest.TestCase):
    def test_python_parity_summary_contract(self) -> None:
        report = summarize_python_scene(seed=42, width=512, height=512)
        self.assertEqual(report["engine"], "python")
        self.assertEqual(report["width"], 512)
        self.assertEqual(report["height"], 512)
        self.assertIn("by_kind", report)

        by_kind = report["by_kind"]
        for kind in ("circle", "triangle", "rectangle", "line"):
            self.assertIn(kind, by_kind)
            self.assertEqual(by_kind[kind]["count"], 20)

    @unittest.skipUnless(
        os.environ.get("GEOARTLAB_RUN_SWIFT_PARITY") == "1",
        "Set GEOARTLAB_RUN_SWIFT_PARITY=1 to run Swift-vs-Python parity harness",
    )
    def test_swift_vs_python_parity(self) -> None:
        result = run_parity(seed=42, width=512, height=512)
        self.assertTrue(result["strict_pass"], json_failure(result))
        self.assertTrue(result["statistical_pass"], json_failure(result))


def json_failure(result: dict) -> str:
    strict = result.get("strict_failures", [])
    statistical = result.get("statistical_failures", [])
    return f"strict_failures={strict}; statistical_failures={statistical}"


if __name__ == "__main__":
    unittest.main()
