from __future__ import annotations

import hashlib
import json
import math
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable

import numpy as np
from PIL import Image, ImageDraw, PngImagePlugin

APP_ID = "GeoArtLab"
RENDER_ENGINE = "python"
JBT_TYPE = "geo_art_piece"
ANIMATION_JBT_TYPE = "geo_art_animation"
JBT_VERSION = "1.0"
DEFAULT_STYLE_ID = "clean_geometric"

PALETTES: dict[str, list[str]] = {
    "synthwave": ["#2D1E2F", "#D7263D", "#F46036", "#2E294E", "#1B998B"],
    "oceanic": ["#011627", "#2EC4B6", "#4DA8DA", "#F6F7EB", "#E71D36"],
    "citrus": ["#1B4332", "#95D5B2", "#F9C74F", "#F8961E", "#F3722C"],
    "monoPop": ["#111111", "#2A2A2A", "#666666", "#EAEAEA", "#FF4D6D"],
    "sunset": ["#003049", "#D62828", "#F77F00", "#FCBF49", "#EAE2B7"],
    "forest": ["#14342B", "#2D6A4F", "#40916C", "#95D5B2", "#D8F3DC"],
    "neonSign": ["#141414", "#00F5D4", "#F15BB5", "#9B5DE5", "#FEE440"],
    "clay": ["#2B2D42", "#8D99AE", "#EDF2F4", "#EF233C", "#D90429"],
    "aurora": ["#151E3F", "#00A8E8", "#00D9C0", "#F4D35E", "#EE964B"],
    "desertBloom": ["#3D2C2E", "#B06C49", "#E28F83", "#F2CC8F", "#3A7D44"],
    "retroPrint": ["#1F271B", "#19647E", "#28AFB0", "#F4D35E", "#EE964B"],
    "electricMint": ["#05204A", "#0A2463", "#1E96FC", "#D7FFAB", "#7AE582"],
    "duskDrive": ["#1B1B3A", "#693668", "#A74482", "#F84AA7", "#FF3562"],
    "candyStore": ["#3A0CA3", "#7209B7", "#F72585", "#4CC9F0", "#BDE0FE"],
    "blueprint": ["#0B1D51", "#1E3A8A", "#2563EB", "#93C5FD", "#E2E8F0"],
    "emberSmoke": ["#161A1D", "#660708", "#A4161A", "#E5383B", "#F4A261"],
}

BACKGROUND_COLORS: dict[str, str] = {
    "paper": "#F4F1EA",
    "midnight": "#0D1321",
    "warm": "#2F1B12",
    "flat": "#111111",
    "pure_black": "#000000",
    "creme": "#F5E9D8",
}

SHAPE_ORDER = ("circle", "triangle", "rectangle", "line")
LEGACY_FAMILY_TO_KIND = {
    "circles": "circle",
    "triangles": "triangle",
    "rectangles": "rectangle",
    "lines": "line",
}


def clamp_int(value: Any, minimum: int, maximum: int, default: int) -> int:
    try:
        parsed = int(value)
    except (TypeError, ValueError):
        return default
    return min(max(parsed, minimum), maximum)


def clamp_float(value: Any, minimum: float, maximum: float, default: float) -> float:
    try:
        parsed = float(value)
    except (TypeError, ValueError):
        return default
    return min(max(parsed, minimum), maximum)


def iso_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def ensure_output_root(path_like: str | Path) -> Path:
    path = Path(path_like).expanduser().resolve()
    path.mkdir(parents=True, exist_ok=True)
    return path


def slugify(value: str) -> str:
    lowered = value.strip().lower()
    normalized = re.sub(r"[^a-z0-9_-]+", "-", lowered)
    normalized = re.sub(r"-+", "-", normalized)
    return normalized.strip("-") or "animation"


def generate_seed_sequence(base_seed: int, repeats: int) -> list[int]:
    repeats = max(1, int(repeats))
    return [int(base_seed) + i for i in range(repeats)]


def parse_palette(render_params: dict[str, Any]) -> list[str]:
    explicit = render_params.get("palette_colors")
    if isinstance(explicit, list):
        cleaned = [str(value).strip().upper() for value in explicit if str(value).strip()]
        normalized = [value if value.startswith("#") else f"#{value}" for value in cleaned]
        if len(normalized) >= 3:
            return normalized

    palette_id = str(render_params.get("palette_id", "synthwave"))
    return PALETTES.get(palette_id, PALETTES["synthwave"])


def normalize_canvas(canvas: dict[str, Any] | None, max_dimension: int = 4096) -> dict[str, int]:
    canvas = canvas or {}
    max_dim = max(64, int(max_dimension))
    width = clamp_int(canvas.get("width"), 64, max_dim, min(1024, max_dim))
    height = clamp_int(canvas.get("height"), 64, max_dim, min(1024, max_dim))
    return {"width": width, "height": height}


def normalize_canvas_meta(render_params: dict[str, Any]) -> dict[str, Any]:
    raw = render_params.get("canvas_meta")
    if not isinstance(raw, dict):
        raw = {}
    preview_max = clamp_int(raw.get("preview_max_dim"), 512, 4096, 4096)
    export_max = clamp_int(raw.get("export_max_dim"), 1024, 16384, 16384)
    return {
        "lock_ratio": bool(raw.get("lock_ratio", False)),
        "ratio_preset": str(raw.get("ratio_preset", "1:1")),
        "long_edge_px": clamp_int(raw.get("long_edge_px"), 512, export_max, 1024),
        "resolution_preset": str(raw.get("resolution_preset", "custom")),
        "preview_max_dim": preview_max,
        "export_max_dim": export_max,
    }


def legacy_shape_counts(shape_family: str, shape_count: Any) -> dict[str, int]:
    total = clamp_int(shape_count, 1, 1200, 80)
    counts = {kind: 0 for kind in SHAPE_ORDER}

    matched_kind = LEGACY_FAMILY_TO_KIND.get(shape_family)
    if matched_kind:
        counts[matched_kind] = total
        return counts

    base = total // len(SHAPE_ORDER)
    remainder = total % len(SHAPE_ORDER)
    for index, kind in enumerate(SHAPE_ORDER):
        counts[kind] = base + (1 if index < remainder else 0)
    return counts


def normalize_shape_counts(render_params: dict[str, Any], shape_family: str) -> dict[str, int]:
    raw = render_params.get("shape_counts")
    if isinstance(raw, dict):
        counts: dict[str, int] = {}
        for kind in SHAPE_ORDER:
            value = raw.get(kind)
            if value is None:
                value = raw.get(f"{kind}s")
            counts[kind] = clamp_int(value, 0, 300, 0)
        return counts

    total_shapes = render_params.get("total_shapes")
    if total_shapes is not None:
        return legacy_shape_counts(shape_family, total_shapes)

    return legacy_shape_counts(shape_family, render_params.get("shape_count"))


def normalize_angle_ranges(render_params: dict[str, Any]) -> dict[str, dict[str, float]]:
    raw = render_params.get("angle_ranges_deg")
    if not isinstance(raw, dict):
        raw = {}

    normalized: dict[str, dict[str, float]] = {}
    for kind in SHAPE_ORDER:
        item = raw.get(kind)
        if not isinstance(item, dict):
            item = {}
        min_deg = clamp_float(item.get("min"), 0.0, 360.0, 0.0)
        max_deg = clamp_float(item.get("max"), 0.0, 360.0, 360.0)
        if min_deg > max_deg:
            min_deg, max_deg = max_deg, min_deg
        normalized[kind] = {"min": min_deg, "max": max_deg}
    return normalized


def normalize_placement_regions(render_params: dict[str, Any]) -> dict[str, dict[str, float]]:
    raw = render_params.get("placement_regions")
    if not isinstance(raw, dict):
        raw = {}

    normalized: dict[str, dict[str, float]] = {}
    for kind in SHAPE_ORDER:
        item = raw.get(kind)
        if not isinstance(item, dict):
            item = {}
        x_min = clamp_float(item.get("x_min"), 0.0, 1.0, 0.0)
        x_max = clamp_float(item.get("x_max"), 0.0, 1.0, 1.0)
        y_min = clamp_float(item.get("y_min"), 0.0, 1.0, 0.0)
        y_max = clamp_float(item.get("y_max"), 0.0, 1.0, 1.0)
        if x_min > x_max:
            x_min, x_max = x_max, x_min
        if y_min > y_max:
            y_min, y_max = y_max, y_min
        normalized[kind] = {"x_min": x_min, "x_max": x_max, "y_min": y_min, "y_max": y_max}
    return normalized


def normalize_fill_ratios(render_params: dict[str, Any], global_fill_ratio: float) -> dict[str, float]:
    raw = render_params.get("fill_ratios")
    if not isinstance(raw, dict):
        raw = {}

    normalized: dict[str, float] = {}
    for kind in SHAPE_ORDER:
        value = raw.get(kind)
        if value is None:
            value = raw.get(f"{kind}s")
        normalized[kind] = clamp_float(value, 0.0, 1.0, global_fill_ratio)
    return normalized


def normalize_render_params(render_params: dict[str, Any], seed_override: int | None = None) -> dict[str, Any]:
    palette_colors = parse_palette(render_params)
    seed_source = seed_override if seed_override is not None else render_params.get("seed", 42)
    shape_family = str(render_params.get("shape_family", "mixed"))
    shape_counts = normalize_shape_counts(render_params, shape_family)
    angle_ranges_deg = normalize_angle_ranges(render_params)
    placement_regions = normalize_placement_regions(render_params)
    canvas_meta = normalize_canvas_meta(render_params)
    fill_ratio = clamp_float(render_params.get("fill_ratio"), 0.0, 1.0, 0.65)
    fill_ratios = normalize_fill_ratios(render_params, fill_ratio)
    symmetry_mode_raw = str(render_params.get("symmetry_mode", "radial")).strip().lower()
    symmetry_mode = "none" if symmetry_mode_raw in {"none", "off", "random"} else "radial"

    normalized = {
        "style_id": str(render_params.get("style_id", DEFAULT_STYLE_ID)),
        "shape_family": shape_family,
        "shape_count": sum(shape_counts.values()),
        "total_shapes": sum(shape_counts.values()),
        "symmetry": clamp_int(render_params.get("symmetry"), 1, 12, 4),
        "symmetry_mode": symmetry_mode,
        "rotation": clamp_float(render_params.get("rotation"), 0.0, 360.0, 0.0),
        "scale_range": clamp_float(render_params.get("scale_range"), 0.1, 1.0, 0.45),
        "stroke_width": clamp_float(render_params.get("stroke_width"), 0.5, 18.0, 2.0),
        "fill_ratio": fill_ratio,
        "fill_ratios": fill_ratios,
        "background_style": str(render_params.get("background_style", "paper")),
        "palette_id": str(render_params.get("palette_id", "synthwave")),
        "color_mode": str(render_params.get("color_mode", "random_per_shape")),
        "palette_colors": palette_colors,
        "shape_counts": shape_counts,
        "angle_ranges_deg": angle_ranges_deg,
        "placement_regions": placement_regions,
        "canvas_meta": canvas_meta,
        "seed": int(seed_source),
        "tags": render_params.get("tags", ["geo", "clean", "geometric"]),
    }
    return normalized


def hex_to_rgb(hex_color: str) -> tuple[int, int, int]:
    value = hex_color.strip().lstrip("#")
    if len(value) != 6:
        return (255, 255, 255)
    return tuple(int(value[i : i + 2], 16) for i in (0, 2, 4))


def rotate_point(x: float, y: float, cx: float, cy: float, angle_rad: float) -> tuple[float, float]:
    dx = x - cx
    dy = y - cy
    cos_a = math.cos(angle_rad)
    sin_a = math.sin(angle_rad)
    return (cx + dx * cos_a - dy * sin_a, cy + dx * sin_a + dy * cos_a)


def choose_shape_color(
    *,
    color_mode: str,
    palette: list[str],
    rng: np.random.Generator,
    base_color: str,
    base_index: int,
    symmetry_index: int,
    x: float,
    y: float,
    width: int,
    height: int,
    seed: int,
) -> str:
    if not palette:
        return "#FFFFFF"

    if color_mode == "palette_cycle":
        return palette[(base_index + symmetry_index) % len(palette)]

    if color_mode == "quadrant":
        quadrant = 0
        if x >= width / 2.0:
            quadrant += 1
        if y >= height / 2.0:
            quadrant += 2
        return palette[quadrant % len(palette)]

    if color_mode == "palette_lock":
        return palette[base_index % len(palette)]

    if color_mode == "palette_rotate_per_ring":
        return palette[(base_index + symmetry_index * 2) % len(palette)]

    if color_mode == "seed_derived_index":
        derived = int(abs((seed * 31) + (x * 0.71) + (y * 0.37) + (base_index * 13)))
        return palette[derived % len(palette)]

    if color_mode == "random_per_instance":
        return str(rng.choice(palette))

    return base_color


def build_scene(render_params: dict[str, Any], canvas: dict[str, Any]) -> dict[str, Any]:
    params = normalize_render_params(render_params)
    max_dimension = int(params["canvas_meta"].get("export_max_dim", 16384))
    canvas_norm = normalize_canvas(canvas, max_dimension=max_dimension)

    width = canvas_norm["width"]
    height = canvas_norm["height"]
    min_dim = min(width, height)
    seed = params["seed"]

    rng = np.random.default_rng(np.random.PCG64(seed))
    center_x = width / 2.0
    center_y = height / 2.0

    shape_counts = params["shape_counts"]
    angle_ranges_deg = params["angle_ranges_deg"]
    placement_regions = params["placement_regions"]
    symmetry = params["symmetry"]
    symmetry_mode = str(params.get("symmetry_mode", "radial"))
    global_rotation = math.radians(params["rotation"])
    scale_range = params["scale_range"]
    fill_ratio_global = params["fill_ratio"]
    fill_ratios = params["fill_ratios"]
    stroke_width = params["stroke_width"]
    palette = params["palette_colors"]
    color_mode = params["color_mode"]

    size_low = max(6.0, min_dim * 0.015)
    size_high = max(size_low + 1.0, min_dim * 0.26 * scale_range)

    shapes: list[dict[str, Any]] = []

    base_index = 0
    for kind in SHAPE_ORDER:
        kind_count = clamp_int(shape_counts.get(kind), 0, 300, 0)
        angle_config = angle_ranges_deg.get(kind, {"min": 0.0, "max": 360.0})
        region = placement_regions.get(kind, {"x_min": 0.0, "x_max": 1.0, "y_min": 0.0, "y_max": 1.0})

        x_min = float(region["x_min"]) * width
        x_max = float(region["x_max"]) * width
        y_min = float(region["y_min"]) * height
        y_max = float(region["y_max"]) * height
        angle_min = float(angle_config["min"])
        angle_max = float(angle_config["max"])

        kind_fill_ratio = clamp_float(fill_ratios.get(kind), 0.0, 1.0, fill_ratio_global)

        for _ in range(kind_count):
            base_x = float(rng.uniform(x_min, x_max))
            base_y = float(rng.uniform(y_min, y_max))
            size = float(rng.uniform(size_low, size_high))
            angle_deg = angle_min if angle_max <= angle_min else float(rng.uniform(angle_min, angle_max))
            angle = math.radians(angle_deg)
            ratio = float(rng.uniform(0.55, 1.65))
            base_color = str(rng.choice(palette))
            is_filled = bool(rng.random() <= kind_fill_ratio)

            instance_count = symmetry if symmetry_mode == "radial" else 1
            for symmetry_index in range(instance_count):
                if symmetry_mode == "radial":
                    orbit_angle = global_rotation + (2.0 * math.pi * symmetry_index / symmetry)
                    x, y = rotate_point(base_x, base_y, center_x, center_y, orbit_angle)
                    x = min(max(x, x_min), x_max)
                    y = min(max(y, y_min), y_max)
                    shape_angle = angle + orbit_angle
                else:
                    x = min(max(base_x, x_min), x_max)
                    y = min(max(base_y, y_min), y_max)
                    shape_angle = angle + global_rotation
                color = choose_shape_color(
                    color_mode=color_mode,
                    palette=palette,
                    rng=rng,
                    base_color=base_color,
                    base_index=base_index,
                    symmetry_index=symmetry_index,
                    x=x,
                    y=y,
                    width=width,
                    height=height,
                    seed=seed,
                )
                shapes.append(
                    {
                        "kind": kind,
                        "x": round(x, 4),
                        "y": round(y, 4),
                        "size": round(size, 4),
                        "angle": round(shape_angle, 6),
                        "ratio": round(ratio, 4),
                        "color": color,
                        "filled": is_filled,
                        "stroke_width": stroke_width,
                    }
                )
            base_index += 1

    background_style = params["background_style"]
    background = BACKGROUND_COLORS.get(background_style, BACKGROUND_COLORS["paper"])

    return {
        "style_id": params["style_id"],
        "seed": seed,
        "canvas": canvas_norm,
        "params": params,
        "background": background,
        "shapes": shapes,
    }


def scene_signature(scene: dict[str, Any]) -> str:
    canonical = json.dumps(scene, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(canonical).hexdigest()


def _rectangle_points(shape: dict[str, Any]) -> list[tuple[float, float]]:
    cx = float(shape["x"])
    cy = float(shape["y"])
    width = float(shape["size"])
    height = width * float(shape["ratio"])
    angle = float(shape["angle"])

    local = [
        (-width / 2.0, -height / 2.0),
        (width / 2.0, -height / 2.0),
        (width / 2.0, height / 2.0),
        (-width / 2.0, height / 2.0),
    ]

    points = []
    cos_a = math.cos(angle)
    sin_a = math.sin(angle)
    for lx, ly in local:
        points.append((cx + lx * cos_a - ly * sin_a, cy + lx * sin_a + ly * cos_a))
    return points


def _triangle_points(shape: dict[str, Any]) -> list[tuple[float, float]]:
    cx = float(shape["x"])
    cy = float(shape["y"])
    radius = float(shape["size"])
    angle = float(shape["angle"])

    points = []
    for i in range(3):
        theta = angle + i * (2.0 * math.pi / 3.0)
        points.append((cx + radius * math.cos(theta), cy + radius * math.sin(theta)))
    return points


def _line_points(shape: dict[str, Any]) -> tuple[tuple[float, float], tuple[float, float]]:
    cx = float(shape["x"])
    cy = float(shape["y"])
    length = float(shape["size"]) * 2.0
    angle = float(shape["angle"])
    dx = math.cos(angle) * length / 2.0
    dy = math.sin(angle) * length / 2.0
    return (cx - dx, cy - dy), (cx + dx, cy + dy)


def render_scene_png(scene: dict[str, Any], path: Path, embed_metadata: dict[str, str] | None = None) -> None:
    width = int(scene["canvas"]["width"])
    height = int(scene["canvas"]["height"])
    image = Image.new("RGB", (width, height), color=hex_to_rgb(scene["background"]))
    draw = ImageDraw.Draw(image)

    for shape in scene["shapes"]:
        color = hex_to_rgb(str(shape["color"]))
        stroke_width = max(1, int(round(float(shape.get("stroke_width", 2.0)))))
        filled = bool(shape.get("filled", True))
        kind = shape["kind"]

        if kind == "circle":
            radius = float(shape["size"])
            x = float(shape["x"])
            y = float(shape["y"])
            bbox = [x - radius, y - radius, x + radius, y + radius]
            if filled:
                draw.ellipse(bbox, fill=color, outline=color, width=stroke_width)
            else:
                draw.ellipse(bbox, outline=color, width=stroke_width)
        elif kind == "triangle":
            points = _triangle_points(shape)
            if filled:
                draw.polygon(points, fill=color, outline=color)
            else:
                draw.polygon(points, outline=color)
        elif kind == "rectangle":
            points = _rectangle_points(shape)
            if filled:
                draw.polygon(points, fill=color, outline=color)
            else:
                draw.polygon(points, outline=color)
        else:
            a, b = _line_points(shape)
            draw.line([a, b], fill=color, width=stroke_width)

    pnginfo = None
    if embed_metadata:
        pnginfo = PngImagePlugin.PngInfo()
        for key, value in embed_metadata.items():
            pnginfo.add_text(str(key), str(value))

    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="PNG", pnginfo=pnginfo)


def _svg_color(shape: dict[str, Any]) -> str:
    return str(shape["color"])


def render_scene_svg(scene: dict[str, Any], path: Path) -> None:
    width = int(scene["canvas"]["width"])
    height = int(scene["canvas"]["height"])
    bg = scene["background"]

    lines: list[str] = [
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
        f"<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"{width}\" height=\"{height}\" viewBox=\"0 0 {width} {height}\">",
        f"  <rect x=\"0\" y=\"0\" width=\"{width}\" height=\"{height}\" fill=\"{bg}\" />",
    ]

    for shape in scene["shapes"]:
        color = _svg_color(shape)
        stroke_width = float(shape.get("stroke_width", 2.0))
        fill = color if bool(shape.get("filled", True)) else "none"

        if shape["kind"] == "circle":
            lines.append(
                "  <circle cx=\"{cx}\" cy=\"{cy}\" r=\"{r}\" fill=\"{fill}\" stroke=\"{stroke}\" stroke-width=\"{sw}\" />".format(
                    cx=shape["x"],
                    cy=shape["y"],
                    r=shape["size"],
                    fill=fill,
                    stroke=color,
                    sw=stroke_width,
                )
            )
        elif shape["kind"] == "triangle":
            points = _triangle_points(shape)
            points_str = " ".join(f"{x:.3f},{y:.3f}" for x, y in points)
            lines.append(
                f"  <polygon points=\"{points_str}\" fill=\"{fill}\" stroke=\"{color}\" stroke-width=\"{stroke_width}\" />"
            )
        elif shape["kind"] == "rectangle":
            points = _rectangle_points(shape)
            points_str = " ".join(f"{x:.3f},{y:.3f}" for x, y in points)
            lines.append(
                f"  <polygon points=\"{points_str}\" fill=\"{fill}\" stroke=\"{color}\" stroke-width=\"{stroke_width}\" />"
            )
        else:
            a, b = _line_points(shape)
            lines.append(
                "  <line x1=\"{x1:.3f}\" y1=\"{y1:.3f}\" x2=\"{x2:.3f}\" y2=\"{y2:.3f}\" stroke=\"{stroke}\" stroke-width=\"{sw}\" />".format(
                    x1=a[0],
                    y1=a[1],
                    x2=b[0],
                    y2=b[1],
                    stroke=color,
                    sw=stroke_width,
                )
            )

    lines.append("</svg>")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines), encoding="utf-8")


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        while True:
            chunk = f.read(65536)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest()


def style_slug(style_id: str) -> str:
    return style_id.replace("_", "-").lower()


def build_filename_base(seed: int, style_id: str, when: datetime | None = None) -> str:
    when = when or datetime.now()
    ts = when.strftime("%Y%m%d_%H%M%S")
    seed_part = f"s{seed:04d}" if seed >= 0 else f"sn{abs(seed):04d}"
    return f"{ts}_{seed_part}_{style_slug(style_id)}"


def build_jbt_document(
    *,
    base_name: str,
    created_at: str,
    render_params: dict[str, Any],
    canvas: dict[str, int],
    seed: int,
    repeat_index: int,
    png_path: Path,
    svg_path: Path,
    png_hash: str,
    svg_hash: str,
) -> dict[str, Any]:
    payload = {
        "app": APP_ID,
        "render_engine": RENDER_ENGINE,
        "style_id": render_params["style_id"],
        "seed": seed,
        "repeat_index": repeat_index,
        "canvas": canvas,
        "palette": {
            "palette_id": render_params.get("palette_id", "custom"),
            "colors": render_params["palette_colors"],
        },
        "parameters": {
            "shape_family": render_params["shape_family"],
            "shape_count": render_params["shape_count"],
            "total_shapes": render_params.get("total_shapes", render_params["shape_count"]),
            "shape_counts": render_params["shape_counts"],
            "symmetry": render_params["symmetry"],
            "symmetry_mode": render_params.get("symmetry_mode", "radial"),
            "rotation": render_params["rotation"],
            "scale_range": render_params["scale_range"],
            "stroke_width": render_params["stroke_width"],
            "fill_ratio": render_params["fill_ratio"],
            "fill_ratios": render_params.get("fill_ratios", {}),
            "color_mode": render_params["color_mode"],
            "angle_ranges_deg": render_params["angle_ranges_deg"],
            "placement_regions": render_params["placement_regions"],
            "canvas_meta": render_params["canvas_meta"],
            "background_style": render_params["background_style"],
        },
        "output_files": {
            "png": str(png_path),
            "svg": str(svg_path),
        },
        "hashes": {
            "png_sha256": png_hash,
            "svg_sha256": svg_hash,
        },
        "tags": render_params.get("tags", ["geo", "clean", "geometric"]),
    }

    return {
        "jbt_type": JBT_TYPE,
        "version": JBT_VERSION,
        "created_at": created_at,
        "name": base_name,
        "payload": payload,
    }


def append_index_record(index_path: Path, record: dict[str, Any]) -> None:
    index_path.parent.mkdir(parents=True, exist_ok=True)
    with index_path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(record, separators=(",", ":")) + "\n")


def export_piece(
    *,
    output_root: Path,
    render_params: dict[str, Any],
    canvas: dict[str, int],
    seed: int,
    repeat_index: int,
) -> dict[str, Any]:
    created_at = iso_now()
    scene = build_scene({**render_params, "seed": seed}, canvas)
    signature = scene_signature(scene)

    base_name = build_filename_base(seed, scene["style_id"])
    png_path = output_root / f"{base_name}.png"
    svg_path = output_root / f"{base_name}.svg"
    jbt_path = output_root / f"{base_name}.jbt"

    metadata = {
        "jbt_type": JBT_TYPE,
        "render_engine": RENDER_ENGINE,
        "seed": str(seed),
        "style": str(scene["style_id"]),
        "palette": str(render_params.get("palette_id", "custom")),
        "params_hash": signature[:16],
        "created_at": created_at,
    }

    render_scene_png(scene, png_path, embed_metadata=metadata)
    render_scene_svg(scene, svg_path)

    png_hash = sha256_file(png_path)
    svg_hash = sha256_file(svg_path)

    jbt_doc = build_jbt_document(
        base_name=base_name,
        created_at=created_at,
        render_params=scene["params"],
        canvas=scene["canvas"],
        seed=seed,
        repeat_index=repeat_index,
        png_path=png_path,
        svg_path=svg_path,
        png_hash=png_hash,
        svg_hash=svg_hash,
    )
    jbt_path.write_text(json.dumps(jbt_doc, indent=2), encoding="utf-8")

    index_record = {
        "created_at": created_at,
        "base_name": base_name,
        "seed": seed,
        "style_id": scene["style_id"],
        "render_engine": RENDER_ENGINE,
        "canvas": scene["canvas"],
        "canvas_meta": scene["params"].get("canvas_meta", {}),
        "palette_id": scene["params"].get("palette_id", "custom"),
        "shape_counts": scene["params"].get("shape_counts", {}),
        "symmetry_mode": scene["params"].get("symmetry_mode", "radial"),
        "fill_ratios": scene["params"].get("fill_ratios", {}),
        "png_path": str(png_path),
        "svg_path": str(svg_path),
        "jbt_path": str(jbt_path),
        "png_sha256": png_hash,
        "svg_sha256": svg_hash,
        "scene_signature": signature,
    }
    append_index_record(output_root / "index.jbtl", index_record)

    return {
        "base_name": base_name,
        "seed": seed,
        "repeat_index": repeat_index,
        "png_path": str(png_path),
        "svg_path": str(svg_path),
        "jbt_path": str(jbt_path),
        "png_sha256": png_hash,
        "svg_sha256": svg_hash,
        "scene_signature": signature,
    }


def export_batch(
    *,
    output_root: str | Path,
    render_params: dict[str, Any],
    canvas: dict[str, Any],
    base_seed: int,
    repeats: int,
    progress_cb: Callable[[int, int, int, str], None] | None = None,
) -> list[dict[str, Any]]:
    out_root = ensure_output_root(output_root)
    normalized_render = normalize_render_params(render_params)
    max_dim = int(normalized_render["canvas_meta"].get("export_max_dim", 16384))
    normalized_canvas = normalize_canvas(canvas, max_dimension=max_dim)

    seeds = generate_seed_sequence(base_seed, repeats)
    items: list[dict[str, Any]] = []

    for idx, seed in enumerate(seeds):
        item = export_piece(
            output_root=out_root,
            render_params=normalized_render,
            canvas=normalized_canvas,
            seed=seed,
            repeat_index=idx,
        )
        items.append(item)
        if progress_cb:
            progress_cb(idx + 1, len(seeds), seed, item["base_name"])

    return items


def render_preview(
    *,
    output_root: str | Path,
    render_params: dict[str, Any],
    canvas: dict[str, Any],
) -> dict[str, Any]:
    out_root = ensure_output_root(output_root)
    preview_dir = out_root / ".preview"
    preview_dir.mkdir(parents=True, exist_ok=True)

    normalized_render = normalize_render_params(render_params)
    preview_max_dim = int(normalized_render["canvas_meta"].get("preview_max_dim", 4096))
    normalized_canvas = normalize_canvas(canvas, max_dimension=preview_max_dim)
    scene = build_scene(normalized_render, normalized_canvas)
    signature = scene_signature(scene)

    preview_path = preview_dir / f"preview_{normalized_render['seed']}_{signature[:12]}.png"
    render_scene_png(scene, preview_path)

    return {
        "preview_path": str(preview_path),
        "scene_signature": signature,
        "width": normalized_canvas["width"],
        "height": normalized_canvas["height"],
    }


def normalize_timeline(payload: dict[str, Any]) -> dict[str, Any]:
    fps = clamp_int(payload.get("fps"), 1, 120, 24)

    frame_count_raw = payload.get("frame_count")
    if frame_count_raw is None:
        duration = clamp_float(payload.get("duration_seconds"), 0.1, 120.0, 4.0)
        frame_count = max(1, int(round(duration * fps)))
    else:
        frame_count = clamp_int(frame_count_raw, 1, 4096, 96)
        duration = frame_count / float(fps)

    tracks_raw = payload.get("tracks")
    tracks: list[dict[str, Any]] = []
    if isinstance(tracks_raw, list):
        for item in tracks_raw:
            if not isinstance(item, dict):
                continue
            parameter_id = str(item.get("parameter_id", "")).strip()
            if not parameter_id:
                continue
            keyframes_raw = item.get("keyframes")
            if not isinstance(keyframes_raw, list):
                continue
            parsed_keyframes: list[dict[str, Any]] = []
            for keyframe in keyframes_raw:
                if not isinstance(keyframe, dict):
                    continue
                frame = clamp_int(keyframe.get("frame"), 0, frame_count - 1, 0)
                value = float(keyframe.get("value", 0.0))
                interpolation = str(keyframe.get("interpolation", "linear"))
                if interpolation not in {"hold", "linear", "ease_in_out"}:
                    interpolation = "linear"
                parsed_keyframes.append({"frame": frame, "value": value, "interpolation": interpolation})
            if not parsed_keyframes:
                continue
            parsed_keyframes.sort(key=lambda k: k["frame"])
            tracks.append({"parameter_id": parameter_id, "keyframes": parsed_keyframes})

    return {
        "fps": fps,
        "duration_seconds": duration,
        "frame_count": frame_count,
        "tracks": tracks,
    }


def _ease_in_out(t: float) -> float:
    if t <= 0:
        return 0.0
    if t >= 1:
        return 1.0
    return t * t * (3.0 - 2.0 * t)


def sample_track_value(track: dict[str, Any], frame: int) -> float:
    keyframes = track.get("keyframes", [])
    if not keyframes:
        return 0.0

    if frame <= keyframes[0]["frame"]:
        return float(keyframes[0]["value"])
    if frame >= keyframes[-1]["frame"]:
        return float(keyframes[-1]["value"])

    left = keyframes[0]
    right = keyframes[-1]
    for idx in range(len(keyframes) - 1):
        candidate_left = keyframes[idx]
        candidate_right = keyframes[idx + 1]
        if candidate_left["frame"] <= frame <= candidate_right["frame"]:
            left = candidate_left
            right = candidate_right
            break

    if left["frame"] == right["frame"]:
        return float(right["value"])

    interpolation = str(right.get("interpolation", "linear"))
    if interpolation == "hold":
        return float(left["value"])

    span = max(1, right["frame"] - left["frame"])
    t = (frame - left["frame"]) / float(span)
    if interpolation == "ease_in_out":
        t = _ease_in_out(t)

    start = float(left["value"])
    end = float(right["value"])
    return start + ((end - start) * t)


def apply_track_value(render_params: dict[str, Any], parameter_id: str, sampled_value: float) -> None:
    if parameter_id == "rotation":
        render_params["rotation"] = clamp_float(sampled_value, 0.0, 360.0, 0.0)
        return

    if parameter_id == "stroke_width":
        render_params["stroke_width"] = clamp_float(sampled_value, 0.5, 18.0, 2.0)
        return

    if parameter_id == "fill_ratio":
        render_params["fill_ratio"] = clamp_float(sampled_value, 0.0, 1.0, render_params.get("fill_ratio", 0.65))
        return

    if parameter_id == "symmetry":
        render_params["symmetry"] = clamp_int(round(sampled_value), 1, 12, render_params.get("symmetry", 4))
        return

    if parameter_id.startswith("shape_counts."):
        kind = parameter_id.split(".", 1)[1]
        if kind in SHAPE_ORDER:
            shape_counts = dict(render_params.get("shape_counts", {}))
            shape_counts[kind] = clamp_int(round(sampled_value), 0, 300, shape_counts.get(kind, 0))
            render_params["shape_counts"] = shape_counts
            render_params["shape_count"] = sum(int(shape_counts.get(k, 0)) for k in SHAPE_ORDER)
            render_params["total_shapes"] = render_params["shape_count"]
        return

    if parameter_id.startswith("fill_ratios."):
        kind = parameter_id.split(".", 1)[1]
        if kind in SHAPE_ORDER:
            fill_ratios = dict(render_params.get("fill_ratios", {}))
            fill_ratios[kind] = clamp_float(sampled_value, 0.0, 1.0, fill_ratios.get(kind, render_params.get("fill_ratio", 0.65)))
            render_params["fill_ratios"] = fill_ratios


def apply_animation_frame(base_render_params: dict[str, Any], timeline: dict[str, Any], frame: int) -> dict[str, Any]:
    render = json.loads(json.dumps(base_render_params))

    for track in timeline.get("tracks", []):
        parameter_id = str(track.get("parameter_id", ""))
        if not parameter_id:
            continue
        sampled = sample_track_value(track, frame)
        apply_track_value(render, parameter_id, sampled)

    return normalize_render_params(render, seed_override=render.get("seed"))


def render_animation_preview(
    *,
    output_root: str | Path,
    render_params: dict[str, Any],
    canvas: dict[str, Any],
    timeline: dict[str, Any],
    frame: int,
) -> dict[str, Any]:
    out_root = ensure_output_root(output_root)
    preview_dir = out_root / ".preview" / "animation"
    preview_dir.mkdir(parents=True, exist_ok=True)

    base_render = normalize_render_params(render_params)
    timeline_norm = normalize_timeline(timeline)
    frame_idx = clamp_int(frame, 0, timeline_norm["frame_count"] - 1, 0)

    preview_max_dim = int(base_render["canvas_meta"].get("preview_max_dim", 4096))
    normalized_canvas = normalize_canvas(canvas, max_dimension=preview_max_dim)

    frame_render_params = apply_animation_frame(base_render, timeline_norm, frame_idx)
    scene = build_scene(frame_render_params, normalized_canvas)
    signature = scene_signature(scene)

    preview_path = preview_dir / f"anim_preview_f{frame_idx:05d}_{signature[:12]}.png"
    render_scene_png(scene, preview_path)

    return {
        "preview_path": str(preview_path),
        "scene_signature": signature,
        "frame": frame_idx,
        "frame_count": timeline_norm["frame_count"],
        "fps": timeline_norm["fps"],
        "width": normalized_canvas["width"],
        "height": normalized_canvas["height"],
    }


def export_animation(
    *,
    output_root: str | Path,
    render_params: dict[str, Any],
    canvas: dict[str, Any],
    timeline: dict[str, Any],
    animation_name: str | None = None,
    progress_cb: Callable[[int, int, int, str], None] | None = None,
) -> dict[str, Any]:
    root = ensure_output_root(output_root)
    animations_root = ensure_output_root(root / "animations")

    base_render = normalize_render_params(render_params)
    timeline_norm = normalize_timeline(timeline)
    frame_count = timeline_norm["frame_count"]

    animation_label = slugify(animation_name or "")
    if not animation_label:
        animation_label = datetime.now().strftime("%Y%m%d_%H%M%S")

    base_folder = animations_root / animation_label
    export_folder = base_folder
    suffix = 1
    while export_folder.exists():
        export_folder = animations_root / f"{animation_label}_{suffix:02d}"
        suffix += 1

    frames_dir = export_folder / "frames"
    frames_dir.mkdir(parents=True, exist_ok=True)

    export_max_dim = int(base_render["canvas_meta"].get("export_max_dim", 16384))
    normalized_canvas = normalize_canvas(canvas, max_dimension=export_max_dim)

    frame_paths: list[Path] = []
    frame_hashes: list[str] = []
    signature_chain = hashlib.sha256()

    for frame_idx in range(frame_count):
        frame_render_params = apply_animation_frame(base_render, timeline_norm, frame_idx)
        scene = build_scene(frame_render_params, normalized_canvas)
        frame_path = frames_dir / f"frame_{frame_idx + 1:06d}.png"
        render_scene_png(scene, frame_path)

        frame_hash = sha256_file(frame_path)
        frame_paths.append(frame_path)
        frame_hashes.append(frame_hash)
        signature_chain.update(frame_hash.encode("utf-8"))

        if progress_cb:
            progress_cb(frame_idx + 1, frame_count, frame_idx, frame_path.name)

    created_at = iso_now()
    animation_jbt_path = export_folder / "animation.jbt"
    animation_doc = {
        "jbt_type": ANIMATION_JBT_TYPE,
        "version": JBT_VERSION,
        "created_at": created_at,
        "name": export_folder.name,
        "payload": {
            "app": APP_ID,
            "render_engine": RENDER_ENGINE,
            "style_id": base_render.get("style_id", DEFAULT_STYLE_ID),
            "canvas": normalized_canvas,
            "timeline": timeline_norm,
            "source_render_params": base_render,
            "output_files": {
                "frames_dir": str(frames_dir),
                "frame_pattern": "frame_%06d.png",
                "first_frame": str(frame_paths[0]) if frame_paths else None,
                "last_frame": str(frame_paths[-1]) if frame_paths else None,
            },
            "hashes": {
                "frames_sha256_chain": signature_chain.hexdigest(),
                "first_frame_sha256": frame_hashes[0] if frame_hashes else None,
                "last_frame_sha256": frame_hashes[-1] if frame_hashes else None,
            },
            "tags": base_render.get("tags", ["geo", "clean", "geometric", "animation"]),
        },
    }
    animation_jbt_path.write_text(json.dumps(animation_doc, indent=2), encoding="utf-8")

    index_record = {
        "created_at": created_at,
        "animation_name": export_folder.name,
        "style_id": base_render.get("style_id", DEFAULT_STYLE_ID),
        "render_engine": RENDER_ENGINE,
        "canvas": normalized_canvas,
        "timeline": {
            "fps": timeline_norm["fps"],
            "frame_count": timeline_norm["frame_count"],
            "duration_seconds": timeline_norm["duration_seconds"],
        },
        "frames_dir": str(frames_dir),
        "animation_jbt_path": str(animation_jbt_path),
        "frames_sha256_chain": signature_chain.hexdigest(),
    }
    append_index_record(animations_root / "index.jbtl", index_record)

    return {
        "animation_name": export_folder.name,
        "output_root": str(export_folder),
        "frames_dir": str(frames_dir),
        "frame_count": frame_count,
        "animation_jbt_path": str(animation_jbt_path),
        "first_frame": str(frame_paths[0]) if frame_paths else "",
        "last_frame": str(frame_paths[-1]) if frame_paths else "",
        "frames_sha256_chain": signature_chain.hexdigest(),
    }
