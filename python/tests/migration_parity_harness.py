from __future__ import annotations

import argparse
import json
import math
import os
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
WORKER_DIR = ROOT / "python" / "worker"
if str(WORKER_DIR) not in sys.path:
    sys.path.insert(0, str(WORKER_DIR))

import core  # noqa: E402

SHAPE_ORDER = ("circle", "triangle", "rectangle", "line")
SENTINEL = "GEOARTLAB_PARITY_JSON_START"
_SWIFT_BINARY_CACHE: str | None = None


@dataclass
class ParityThresholds:
    mean_position_norm_delta_max: float = 0.22
    mean_size_norm_delta_max: float = 0.08
    fill_ratio_delta_max: float = 0.35
    mean_angle_delta_max: float = 120.0


def baseline_render_params(seed: int) -> dict[str, Any]:
    return {
        "style_id": "clean_geometric",
        "shape_family": "mixed",
        "shape_counts": {"circle": 20, "triangle": 20, "rectangle": 20, "line": 20},
        "total_shapes": 80,
        "symmetry": 1,
        "symmetry_mode": "radial",
        "rotation": 0,
        "scale_range": 0.45,
        "stroke_width": 2,
        "fill_ratio": 0.65,
        "fill_ratios": {"circle": 0.65, "triangle": 0.65, "rectangle": 0.65, "line": 0.65},
        "palette_id": "synthwave",
        "palette_colors": ["#2D1E2F", "#D7263D", "#F46036", "#2E294E", "#1B998B"],
        "background_style": "paper",
        "color_mode": "random_per_shape",
        "angle_ranges_deg": {
            "circle": {"min": 0, "max": 360},
            "triangle": {"min": 0, "max": 360},
            "rectangle": {"min": 0, "max": 360},
            "line": {"min": 0, "max": 360},
        },
        "placement_regions": {
            "circle": {"x_min": 0.0, "x_max": 1.0, "y_min": 0.0, "y_max": 1.0},
            "triangle": {"x_min": 0.0, "x_max": 1.0, "y_min": 0.0, "y_max": 1.0},
            "rectangle": {"x_min": 0.0, "x_max": 1.0, "y_min": 0.0, "y_max": 1.0},
            "line": {"x_min": 0.0, "x_max": 1.0, "y_min": 0.0, "y_max": 1.0},
        },
        "canvas_meta": {
            "lock_ratio": False,
            "ratio_preset": "1:1",
            "long_edge_px": max(512, seed % 4096),
            "resolution_preset": "custom",
            "preview_max_dim": 4096,
            "export_max_dim": 16384,
        },
        "seed": seed,
    }


def _mean(values: list[float]) -> float:
    if not values:
        return 0.0
    return sum(values) / float(len(values))


def _wrap_angle_deg(angle: float) -> float:
    wrapped = angle % 360.0
    return wrapped if wrapped >= 0 else wrapped + 360.0


def summarize_python_scene(seed: int, width: int, height: int) -> dict[str, Any]:
    render_params = baseline_render_params(seed)
    scene = core.build_scene(render_params, {"width": width, "height": height})

    min_dimension = float(max(1, min(width, height)))

    by_kind: dict[str, dict[str, float | int]] = {}
    for kind in SHAPE_ORDER:
        kind_shapes = [shape for shape in scene["shapes"] if shape.get("kind") == kind]
        count = len(kind_shapes)
        if count == 0:
            by_kind[kind] = {
                "count": 0,
                "mean_x_norm": 0.0,
                "mean_y_norm": 0.0,
                "mean_size_norm": 0.0,
                "mean_angle_deg": 0.0,
                "fill_ratio": 0.0,
            }
            continue

        x_mean = _mean([float(shape["x"]) for shape in kind_shapes])
        y_mean = _mean([float(shape["y"]) for shape in kind_shapes])
        size_mean = _mean([float(shape["size"]) for shape in kind_shapes])
        angle_mean = _mean([_wrap_angle_deg(math.degrees(float(shape["angle"]))) for shape in kind_shapes])
        fill_ratio = sum(1 for shape in kind_shapes if bool(shape.get("filled"))) / float(count)

        by_kind[kind] = {
            "count": count,
            "mean_x_norm": x_mean / float(max(width, 1)),
            "mean_y_norm": y_mean / float(max(height, 1)),
            "mean_size_norm": size_mean / min_dimension,
            "mean_angle_deg": angle_mean,
            "fill_ratio": fill_ratio,
        }

    return {
        "engine": "python",
        "seed": seed,
        "width": width,
        "height": height,
        "sample_count": len(scene["shapes"]),
        "by_kind": by_kind,
    }


def run_swift_sample(seed: int, width: int, height: int) -> dict[str, Any]:
    cmd = [
        resolve_swift_binary(),
        "--migration-parity-sample",
        "--seed",
        str(seed),
        "--width",
        str(width),
        "--height",
        str(height),
    ]

    proc = subprocess.run(
        cmd,
        cwd=str(ROOT),
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(
            "Swift parity sample failed with code "
            f"{proc.returncode}\nstdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
        )

    lines = proc.stdout.splitlines()
    if SENTINEL not in lines:
        raise RuntimeError(
            "Swift parity output sentinel missing."
            f"\nstdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
        )

    idx = lines.index(SENTINEL)
    if idx + 1 >= len(lines):
        raise RuntimeError("Swift parity sentinel found but JSON line missing")

    try:
        return json.loads(lines[idx + 1])
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"Failed to decode Swift parity JSON: {exc}") from exc


def resolve_swift_binary() -> str:
    global _SWIFT_BINARY_CACHE
    if _SWIFT_BINARY_CACHE:
        return _SWIFT_BINARY_CACHE

    env_override = os.environ.get("GEOARTLAB_SWIFT_BINARY", "").strip()
    if env_override:
        _SWIFT_BINARY_CACHE = env_override
        return _SWIFT_BINARY_CACHE

    show_bin = subprocess.run(
        ["swift", "build", "--show-bin-path"],
        cwd=str(ROOT),
        capture_output=True,
        text=True,
        check=False,
    )
    if show_bin.returncode != 0:
        raise RuntimeError(
            "Failed to resolve Swift binary path."
            f"\nstdout:\n{show_bin.stdout}\nstderr:\n{show_bin.stderr}"
        )

    bin_dir = show_bin.stdout.strip()
    if not bin_dir:
        raise RuntimeError("Swift --show-bin-path returned empty output")

    binary_path = Path(bin_dir) / "GeoArtLab"
    if not binary_path.exists():
        build_proc = subprocess.run(
            ["swift", "build"],
            cwd=str(ROOT),
            capture_output=True,
            text=True,
            check=False,
        )
        if build_proc.returncode != 0:
            raise RuntimeError(
                "swift build failed while preparing migration parity binary."
                f"\nstdout:\n{build_proc.stdout}\nstderr:\n{build_proc.stderr}"
            )
    if not binary_path.exists():
        raise RuntimeError(f"Swift parity binary not found at {binary_path}")

    _SWIFT_BINARY_CACHE = str(binary_path)
    return _SWIFT_BINARY_CACHE


def _angle_delta_deg(a: float, b: float) -> float:
    delta = abs((a % 360.0) - (b % 360.0))
    return min(delta, 360.0 - delta)


def compare_reports(
    swift_report: dict[str, Any],
    python_report: dict[str, Any],
    thresholds: ParityThresholds | None = None,
) -> dict[str, Any]:
    thresholds = thresholds or ParityThresholds()

    strict_failures: list[str] = []
    statistical_failures: list[str] = []
    metrics: dict[str, dict[str, float]] = {}

    if swift_report.get("width") != python_report.get("width"):
        strict_failures.append("width mismatch")
    if swift_report.get("height") != python_report.get("height"):
        strict_failures.append("height mismatch")

    swift_by_kind = swift_report.get("by_kind", {})
    python_by_kind = python_report.get("by_kind", {})

    for kind in SHAPE_ORDER:
        swift_kind = swift_by_kind.get(kind, {})
        python_kind = python_by_kind.get(kind, {})

        swift_count = int(swift_kind.get("count", 0))
        python_count = int(python_kind.get("count", 0))
        if swift_count != python_count:
            strict_failures.append(f"count mismatch for {kind}: swift={swift_count}, python={python_count}")

        position_delta_x = abs(float(swift_kind.get("mean_x_norm", 0.0)) - float(python_kind.get("mean_x_norm", 0.0)))
        position_delta_y = abs(float(swift_kind.get("mean_y_norm", 0.0)) - float(python_kind.get("mean_y_norm", 0.0)))
        size_delta = abs(float(swift_kind.get("mean_size_norm", 0.0)) - float(python_kind.get("mean_size_norm", 0.0)))
        fill_delta = abs(float(swift_kind.get("fill_ratio", 0.0)) - float(python_kind.get("fill_ratio", 0.0)))
        angle_delta = _angle_delta_deg(
            float(swift_kind.get("mean_angle_deg", 0.0)),
            float(python_kind.get("mean_angle_deg", 0.0)),
        )

        metrics[kind] = {
            "mean_x_norm_delta": position_delta_x,
            "mean_y_norm_delta": position_delta_y,
            "mean_size_norm_delta": size_delta,
            "fill_ratio_delta": fill_delta,
            "mean_angle_delta_deg": angle_delta,
        }

        if position_delta_x > thresholds.mean_position_norm_delta_max:
            statistical_failures.append(f"{kind} mean_x_norm delta {position_delta_x:.4f} > {thresholds.mean_position_norm_delta_max:.4f}")
        if position_delta_y > thresholds.mean_position_norm_delta_max:
            statistical_failures.append(f"{kind} mean_y_norm delta {position_delta_y:.4f} > {thresholds.mean_position_norm_delta_max:.4f}")
        if size_delta > thresholds.mean_size_norm_delta_max:
            statistical_failures.append(f"{kind} mean_size_norm delta {size_delta:.4f} > {thresholds.mean_size_norm_delta_max:.4f}")
        if fill_delta > thresholds.fill_ratio_delta_max:
            statistical_failures.append(f"{kind} fill_ratio delta {fill_delta:.4f} > {thresholds.fill_ratio_delta_max:.4f}")
        if angle_delta > thresholds.mean_angle_delta_max:
            statistical_failures.append(f"{kind} mean_angle delta {angle_delta:.2f} > {thresholds.mean_angle_delta_max:.2f}")

    return {
        "strict_pass": not strict_failures,
        "statistical_pass": not statistical_failures,
        "strict_failures": strict_failures,
        "statistical_failures": statistical_failures,
        "metrics": metrics,
        "swift_report": swift_report,
        "python_report": python_report,
    }


def run_parity(seed: int, width: int, height: int) -> dict[str, Any]:
    swift_report = run_swift_sample(seed=seed, width=width, height=height)
    python_report = summarize_python_scene(seed=seed, width=width, height=height)
    return compare_reports(swift_report=swift_report, python_report=python_report)


def main() -> int:
    parser = argparse.ArgumentParser(description="Run migration parity comparison between Swift sample core and Python worker core")
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--width", type=int, default=512)
    parser.add_argument("--height", type=int, default=512)
    args = parser.parse_args()

    result = run_parity(seed=args.seed, width=args.width, height=args.height)
    print(json.dumps(result, indent=2, sort_keys=True))

    if result["strict_pass"] and result["statistical_pass"]:
        return 0
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
