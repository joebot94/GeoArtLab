from __future__ import annotations

import hashlib
import json
import sys
import tempfile
import unittest
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORKER_DIR = ROOT / "python" / "worker"
if str(WORKER_DIR) not in sys.path:
    sys.path.insert(0, str(WORKER_DIR))

import core  # noqa: E402


class CoreTests(unittest.TestCase):
    def setUp(self) -> None:
        self.render = {
            "style_id": "clean_geometric",
            "shape_family": "mixed",
            "shape_counts": {"circle": 12, "triangle": 8, "rectangle": 6, "line": 4},
            "symmetry": 1,
            "rotation": 0,
            "scale_range": 0.4,
            "stroke_width": 2,
            "fill_ratio": 0.65,
            "palette_id": "synthwave",
            "palette_colors": ["#2D1E2F", "#D7263D", "#F46036", "#2E294E", "#1B998B"],
            "background_style": "paper",
            "angle_ranges_deg": {
                "circle": {"min": 0, "max": 0},
                "triangle": {"min": 20, "max": 40},
                "rectangle": {"min": 120, "max": 120},
                "line": {"min": 260, "max": 280},
            },
            "placement_regions": {
                "circle": {"x_min": 0.0, "x_max": 0.25, "y_min": 0.0, "y_max": 0.25},
                "triangle": {"x_min": 0.25, "x_max": 0.5, "y_min": 0.25, "y_max": 0.5},
                "rectangle": {"x_min": 0.5, "x_max": 0.75, "y_min": 0.5, "y_max": 0.75},
                "line": {"x_min": 0.75, "x_max": 1.0, "y_min": 0.75, "y_max": 1.0},
            },
            "canvas_meta": {"lock_ratio": True, "ratio_preset": "1:1", "long_edge_px": 1024},
            "seed": 42,
        }
        self.canvas = {"width": 512, "height": 512}

    def test_scene_signature_is_deterministic(self) -> None:
        scene_a = core.build_scene(self.render, self.canvas)
        scene_b = core.build_scene(self.render, self.canvas)
        self.assertEqual(core.scene_signature(scene_a), core.scene_signature(scene_b))

    def test_png_render_is_deterministic_for_same_scene(self) -> None:
        scene = core.build_scene(self.render, self.canvas)
        with tempfile.TemporaryDirectory() as td:
            p1 = Path(td) / "a.png"
            p2 = Path(td) / "b.png"
            core.render_scene_png(scene, p1)
            core.render_scene_png(scene, p2)
            h1 = hashlib.sha256(p1.read_bytes()).hexdigest()
            h2 = hashlib.sha256(p2.read_bytes()).hexdigest()
            self.assertEqual(h1, h2)

    def test_seed_sequence(self) -> None:
        self.assertEqual(core.generate_seed_sequence(42, 5), [42, 43, 44, 45, 46])

    def test_legacy_shape_count_mapping(self) -> None:
        circles = core.normalize_render_params({"shape_family": "circles", "shape_count": 9})["shape_counts"]
        self.assertEqual(circles["circle"], 9)
        self.assertEqual(circles["triangle"], 0)
        self.assertEqual(circles["rectangle"], 0)
        self.assertEqual(circles["line"], 0)

        mixed = core.normalize_render_params({"shape_family": "mixed", "shape_count": 10})["shape_counts"]
        self.assertEqual(mixed, {"circle": 3, "triangle": 3, "rectangle": 2, "line": 2})

    def test_per_shape_counts_match_with_symmetry_one(self) -> None:
        scene = core.build_scene(self.render, self.canvas)
        counts = Counter(shape["kind"] for shape in scene["shapes"])
        self.assertEqual(counts["circle"], 12)
        self.assertEqual(counts["triangle"], 8)
        self.assertEqual(counts["rectangle"], 6)
        self.assertEqual(counts["line"], 4)

    def test_region_and_angle_constraints(self) -> None:
        scene = core.build_scene(self.render, self.canvas)
        width = self.canvas["width"]
        height = self.canvas["height"]

        regions = self.render["placement_regions"]
        angles = self.render["angle_ranges_deg"]

        for shape in scene["shapes"]:
            kind = shape["kind"]
            x = shape["x"]
            y = shape["y"]
            angle_deg = (shape["angle"] * 180.0 / 3.141592653589793) % 360.0

            region = regions[kind]
            self.assertGreaterEqual(x, region["x_min"] * width - 1e-6)
            self.assertLessEqual(x, region["x_max"] * width + 1e-6)
            self.assertGreaterEqual(y, region["y_min"] * height - 1e-6)
            self.assertLessEqual(y, region["y_max"] * height + 1e-6)

            angle = angles[kind]
            self.assertGreaterEqual(angle_deg, angle["min"] - 1e-3)
            self.assertLessEqual(angle_deg, angle["max"] + 1e-3)

    def test_export_batch_writes_png_svg_jbt_and_index(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            items = core.export_batch(
                output_root=td,
                render_params=self.render,
                canvas=self.canvas,
                base_seed=42,
                repeats=3,
            )
            self.assertEqual(len(items), 3)

            for item in items:
                png_path = Path(item["png_path"])
                svg_path = Path(item["svg_path"])
                jbt_path = Path(item["jbt_path"])

                self.assertTrue(png_path.exists())
                self.assertTrue(svg_path.exists())
                self.assertTrue(jbt_path.exists())

                jbt = json.loads(jbt_path.read_text(encoding="utf-8"))
                self.assertEqual(jbt["jbt_type"], "geo_art_piece")
                self.assertEqual(jbt["version"], "1.0")
                self.assertIn("payload", jbt)
                self.assertIn("shape_counts", jbt["payload"]["parameters"])
                self.assertIn("angle_ranges_deg", jbt["payload"]["parameters"])
                self.assertIn("placement_regions", jbt["payload"]["parameters"])

            index_path = Path(td) / "index.jbtl"
            self.assertTrue(index_path.exists())
            lines = [line for line in index_path.read_text(encoding="utf-8").splitlines() if line.strip()]
            self.assertEqual(len(lines), 3)


if __name__ == "__main__":
    unittest.main()
