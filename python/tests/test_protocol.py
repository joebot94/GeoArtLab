from __future__ import annotations

import concurrent.futures
import json
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "python" / "worker" / "main.py"


class ProtocolTests(unittest.TestCase):
    def setUp(self) -> None:
        self.proc = subprocess.Popen(
            [sys.executable, str(SCRIPT)],
            cwd=str(ROOT),
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
        )

    def tearDown(self) -> None:
        if self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                self.proc.kill()
        if self.proc.stdin:
            self.proc.stdin.close()
        if self.proc.stdout:
            self.proc.stdout.close()
        if self.proc.stderr:
            self.proc.stderr.close()

    def send_line(self, line: str) -> None:
        assert self.proc.stdin is not None
        self.proc.stdin.write(line + "\n")
        self.proc.stdin.flush()

    def send_json(self, payload: dict) -> None:
        self.send_line(json.dumps(payload, separators=(",", ":")))

    def read_message(self, timeout: float = 5.0, fail_on_timeout: bool = True) -> dict | None:
        assert self.proc.stdout is not None
        with concurrent.futures.ThreadPoolExecutor(max_workers=1) as executor:
            future = executor.submit(self.proc.stdout.readline)
            try:
                raw = future.result(timeout=timeout)
            except concurrent.futures.TimeoutError:
                if fail_on_timeout:
                    self.fail("Timed out waiting for worker response")
                return None

        if raw is None:
            if fail_on_timeout:
                self.fail("Timed out waiting for worker response")
            return None
        raw = raw.strip()
        self.assertTrue(raw, "Worker returned empty output")
        return json.loads(raw)

    def test_malformed_and_unsupported_requests_return_error(self) -> None:
        self.send_line("not-json")
        malformed = self.read_message()
        self.assertEqual(malformed["type"], "error")
        self.assertFalse(malformed["ok"])

        self.send_json({"request_id": "x1", "type": "unknown_op", "payload": {}})
        unknown = self.read_message()
        self.assertEqual(unknown["request_id"], "x1")
        self.assertEqual(unknown["type"], "error")
        self.assertFalse(unknown["ok"])

    def test_hello_contains_new_capabilities(self) -> None:
        self.send_json({"request_id": "hello-1", "type": "hello", "payload": {}})
        ready = self.read_message()
        self.assertEqual(ready["request_id"], "hello-1")
        self.assertEqual(ready["type"], "ready")
        self.assertTrue(ready["ok"])
        capabilities = ready["payload"].get("capabilities", [])
        self.assertIn("render_preview", capabilities)
        self.assertIn("export_batch", capabilities)
        self.assertIn("render_animation_preview", capabilities)
        self.assertIn("export_animation", capabilities)

    def test_hello_and_export_batch_contract(self) -> None:
        self.send_json({"request_id": "hello-1", "type": "hello", "payload": {}})
        ready = self.read_message()
        self.assertEqual(ready["request_id"], "hello-1")
        self.assertEqual(ready["type"], "ready")
        self.assertTrue(ready["ok"])

        with tempfile.TemporaryDirectory() as td:
            self.send_json(
                {
                    "request_id": "exp-1",
                    "type": "export_batch",
                    "payload": {
                        "base_seed": 42,
                        "repeats": 2,
                        "output_root": td,
                        "canvas": {"width": 256, "height": 256},
                        "render": {
                            "style_id": "clean_geometric",
                            "shape_family": "mixed",
                            "shape_count": 20,
                            "symmetry": 4,
                            "rotation": 10,
                            "scale_range": 0.4,
                            "stroke_width": 2,
                            "fill_ratio": 0.6,
                            "palette_id": "synthwave",
                            "palette_colors": ["#2D1E2F", "#D7263D", "#F46036", "#2E294E", "#1B998B"],
                            "background_style": "paper",
                        },
                    },
                }
            )

            messages = []
            complete = None
            deadline = time.time() + 20.0
            while time.time() < deadline:
                message = self.read_message(timeout=1.0, fail_on_timeout=False)
                if message is None:
                    continue
                messages.append(message)
                if message["type"] == "export_complete":
                    complete = message
                    break

            progress_messages = [m for m in messages if m["type"] == "export_progress"]
            self.assertGreaterEqual(len(progress_messages), 1)
            self.assertIsNotNone(complete)
            assert complete is not None
            self.assertEqual(complete["request_id"], "exp-1")
            self.assertTrue(complete["ok"])
            self.assertEqual(complete["payload"]["total"], 2)
            self.assertEqual(len(complete["payload"]["items"]), 2)

    def test_export_batch_accepts_new_shape_payload(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            self.send_json(
                {
                    "request_id": "exp-new",
                    "type": "export_batch",
                    "payload": {
                        "base_seed": 42,
                        "repeats": 1,
                        "output_root": td,
                        "canvas": {"width": 256, "height": 256},
                        "render": {
                            "style_id": "clean_geometric",
                            "shape_family": "mixed",
                            "shape_counts": {"circle": 4, "triangle": 3, "rectangle": 2, "line": 1},
                            "total_shapes": 10,
                            "symmetry": 1,
                            "symmetry_mode": "none",
                            "rotation": 10,
                            "scale_range": 0.4,
                            "stroke_width": 2,
                            "fill_ratio": 0.6,
                            "fill_ratios": {"circle": 1.0, "triangle": 0.5, "rectangle": 0.2, "line": 0.0},
                            "palette_id": "synthwave",
                            "palette_colors": ["#2D1E2F", "#D7263D", "#F46036", "#2E294E", "#1B998B"],
                            "background_style": "creme",
                            "color_mode": "palette_lock",
                            "angle_ranges_deg": {
                                "circle": {"min": 0, "max": 10},
                                "triangle": {"min": 15, "max": 30},
                                "rectangle": {"min": 45, "max": 90},
                                "line": {"min": 120, "max": 160},
                            },
                            "placement_regions": {
                                "circle": {"x_min": 0.0, "x_max": 0.5, "y_min": 0.0, "y_max": 0.5},
                                "triangle": {"x_min": 0.2, "x_max": 0.7, "y_min": 0.2, "y_max": 0.7},
                                "rectangle": {"x_min": 0.4, "x_max": 0.9, "y_min": 0.4, "y_max": 0.9},
                                "line": {"x_min": 0.6, "x_max": 1.0, "y_min": 0.6, "y_max": 1.0},
                            },
                            "canvas_meta": {
                                "lock_ratio": True,
                                "ratio_preset": "1:1",
                                "long_edge_px": 1024,
                                "resolution_preset": "1080p",
                                "preview_max_dim": 4096,
                                "export_max_dim": 16384,
                            },
                        },
                    },
                }
            )

            complete = None
            deadline = time.time() + 20.0
            while time.time() < deadline:
                message = self.read_message(timeout=1.0, fail_on_timeout=False)
                if message is None:
                    continue
                if message["type"] == "export_complete":
                    complete = message
                    break

            self.assertIsNotNone(complete)
            assert complete is not None
            self.assertEqual(complete["request_id"], "exp-new")
            self.assertTrue(complete["ok"])
            self.assertEqual(complete["payload"]["total"], 1)

    def test_animation_preview_and_export_contract(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            render = {
                "style_id": "clean_geometric",
                "shape_family": "mixed",
                "shape_counts": {"circle": 4, "triangle": 3, "rectangle": 2, "line": 1},
                "symmetry": 2,
                "symmetry_mode": "radial",
                "rotation": 5,
                "scale_range": 0.4,
                "stroke_width": 2,
                "fill_ratio": 0.6,
                "palette_id": "synthwave",
                "palette_colors": ["#2D1E2F", "#D7263D", "#F46036", "#2E294E", "#1B998B"],
                "background_style": "pure_black",
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
            timeline = {
                "fps": 8,
                "frame_count": 4,
                "tracks": [
                    {
                        "parameter_id": "rotation",
                        "keyframes": [
                            {"frame": 0, "value": 0, "interpolation": "linear"},
                            {"frame": 3, "value": 180, "interpolation": "linear"},
                        ],
                    }
                ],
            }

            self.send_json(
                {
                    "request_id": "anim-prev-1",
                    "type": "render_animation_preview",
                    "payload": {
                        "output_root": td,
                        "canvas": {"width": 256, "height": 256},
                        "params": render,
                        "timeline": timeline,
                        "frame": 2,
                    },
                }
            )
            preview = self.read_message()
            self.assertEqual(preview["request_id"], "anim-prev-1")
            self.assertEqual(preview["type"], "animation_preview_ready")
            self.assertTrue(preview["ok"])

            self.send_json(
                {
                    "request_id": "anim-exp-1",
                    "type": "export_animation",
                    "payload": {
                        "output_root": td,
                        "canvas": {"width": 256, "height": 256},
                        "render": render,
                        "timeline": timeline,
                        "animation_name": "proto-test",
                    },
                }
            )

            messages = []
            complete = None
            deadline = time.time() + 30.0
            while time.time() < deadline:
                message = self.read_message(timeout=1.0, fail_on_timeout=False)
                if message is None:
                    continue
                messages.append(message)
                if message["type"] == "animation_export_complete":
                    complete = message
                    break

            progress_messages = [m for m in messages if m["type"] == "animation_export_progress"]
            self.assertGreaterEqual(len(progress_messages), 1)
            self.assertIsNotNone(complete)
            assert complete is not None
            self.assertEqual(complete["request_id"], "anim-exp-1")
            self.assertTrue(complete["ok"])
            self.assertEqual(complete["payload"]["frame_count"], 4)


if __name__ == "__main__":
    unittest.main()
