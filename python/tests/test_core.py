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
            "symmetry_mode": "radial",
            "rotation": 0,
            "scale_range": 0.4,
            "stroke_width": 2,
            "fill_ratio": 0.65,
            "fill_ratios": {"circle": 1.0, "triangle": 0.8, "rectangle": 0.4, "line": 0.0},
            "palette_id": "synthwave",
            "palette_colors": ["#2D1E2F", "#D7263D", "#F46036", "#2E294E", "#1B998B"],
            "background_style": "paper",
            "color_mode": "seed_derived_index",
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
            "canvas_meta": {
                "lock_ratio": True,
                "ratio_preset": "1:1",
                "long_edge_px": 1024,
                "resolution_preset": "1080p",
                "preview_max_dim": 4096,
                "export_max_dim": 16384,
            },
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

    def test_total_shapes_legacy_mapping(self) -> None:
        mixed = core.normalize_render_params({"shape_family": "mixed", "total_shapes": 11})
        self.assertEqual(mixed["shape_count"], 11)
        self.assertEqual(mixed["shape_counts"], {"circle": 3, "triangle": 3, "rectangle": 3, "line": 2})

    def test_per_shape_counts_match_with_symmetry_one(self) -> None:
        scene = core.build_scene(self.render, self.canvas)
        counts = Counter(shape["kind"] for shape in scene["shapes"])
        self.assertEqual(counts["circle"], 12)
        self.assertEqual(counts["triangle"], 8)
        self.assertEqual(counts["rectangle"], 6)
        self.assertEqual(counts["line"], 4)

    def test_none_symmetry_mode_uses_random_non_radial_placement(self) -> None:
        params = dict(self.render)
        params["symmetry"] = 6
        params["symmetry_mode"] = "none"
        scene = core.build_scene(params, self.canvas)
        counts = Counter(shape["kind"] for shape in scene["shapes"])
        self.assertEqual(counts["circle"], 12)
        self.assertEqual(counts["triangle"], 8)
        self.assertEqual(counts["rectangle"], 6)
        self.assertEqual(counts["line"], 4)
        self.assertEqual(scene["params"]["symmetry_mode"], "none")

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

    def test_per_shape_fill_ratios_enforced(self) -> None:
        scene = core.build_scene(self.render, self.canvas)
        for shape in scene["shapes"]:
            if shape["kind"] == "circle":
                self.assertTrue(shape["filled"])
            if shape["kind"] == "line":
                self.assertFalse(shape["filled"])

    def test_new_color_modes_and_backgrounds(self) -> None:
        palette = self.render["palette_colors"]
        for color_mode in ["palette_lock", "palette_rotate_per_ring", "seed_derived_index"]:
            params = dict(self.render)
            params["color_mode"] = color_mode
            params["background_style"] = "pure_black"
            scene = core.build_scene(params, self.canvas)
            self.assertEqual(scene["background"], "#000000")
            self.assertTrue(scene["shapes"])
            for shape in scene["shapes"][:20]:
                self.assertIn(shape["color"], palette)

    def test_canvas_meta_policy(self) -> None:
        params = core.normalize_render_params(
            {
                "canvas_meta": {
                    "preview_max_dim": 50000,
                    "export_max_dim": 50000,
                }
            }
        )
        self.assertEqual(params["canvas_meta"]["preview_max_dim"], 4096)
        self.assertEqual(params["canvas_meta"]["export_max_dim"], 16384)

        preview_canvas = core.normalize_canvas({"width": 9000, "height": 7000}, max_dimension=4096)
        self.assertEqual(preview_canvas["width"], 4096)
        self.assertEqual(preview_canvas["height"], 4096)

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
                self.assertEqual(jbt["payload"].get("render_engine"), "python")
                self.assertIn("shape_counts", jbt["payload"]["parameters"])
                self.assertIn("symmetry_mode", jbt["payload"]["parameters"])
                self.assertIn("fill_ratios", jbt["payload"]["parameters"])
                self.assertIn("angle_ranges_deg", jbt["payload"]["parameters"])
                self.assertIn("placement_regions", jbt["payload"]["parameters"])

            index_path = Path(td) / "index.jbtl"
            self.assertTrue(index_path.exists())
            lines = [line for line in index_path.read_text(encoding="utf-8").splitlines() if line.strip()]
            self.assertEqual(len(lines), 3)
            index_records = [json.loads(line) for line in lines]
            self.assertTrue(all(record.get("render_engine") == "python" for record in index_records))

    def test_timeline_interpolation_and_export_animation(self) -> None:
        timeline = {
            "fps": 10,
            "frame_count": 5,
            "tracks": [
                {
                    "parameter_id": "rotation",
                    "keyframes": [
                        {"frame": 0, "value": 0, "interpolation": "linear"},
                        {"frame": 4, "value": 180, "interpolation": "linear"},
                    ],
                },
                {
                    "parameter_id": "shape_counts.circle",
                    "keyframes": [
                        {"frame": 0, "value": 4, "interpolation": "hold"},
                        {"frame": 4, "value": 8, "interpolation": "hold"},
                    ],
                },
            ],
        }
        timeline_norm = core.normalize_timeline(timeline)
        value_mid = core.sample_track_value(timeline_norm["tracks"][0], 2)
        self.assertAlmostEqual(value_mid, 90.0, delta=0.001)

        with tempfile.TemporaryDirectory() as td:
            result = core.export_animation(
                output_root=td,
                render_params=self.render,
                canvas=self.canvas,
                timeline=timeline,
                animation_name="test-anim",
            )
            self.assertEqual(result["frame_count"], 5)
            self.assertTrue(Path(result["animation_jbt_path"]).exists())
            frames = sorted(Path(result["frames_dir"]).glob("frame_*.png"))
            self.assertEqual(len(frames), 5)
            animation_jbt = json.loads(Path(result["animation_jbt_path"]).read_text(encoding="utf-8"))
            self.assertEqual(animation_jbt["payload"].get("render_engine"), "python")

            animations_index = Path(td) / "animations" / "index.jbtl"
            self.assertTrue(animations_index.exists())
            lines = [line for line in animations_index.read_text(encoding="utf-8").splitlines() if line.strip()]
            self.assertEqual(len(lines), 1)
            self.assertEqual(json.loads(lines[0]).get("render_engine"), "python")


if __name__ == "__main__":
    unittest.main()
