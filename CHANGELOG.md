# Changelog

All notable changes to GeoArtLab are documented here.

## [0.2.0] - 2026-03-18

- Added per-shape absolute counts for circles, triangles, rectangles, and lines.
- Added per-shape angle ranges and normalized placement regions.
- Added aspect-ratio workflow with ratio presets, lock toggle, and long-edge sizing.
- Expanded curated palette library by 8 new presets.
- Added legacy payload compatibility for `shape_count` + `shape_family` inputs.
- Extended `.jbt` and `index.jbtl` metadata with shape/placement/canvas parameter blocks.
- Added/expanded unit and protocol tests for new payload schema and compatibility behavior.

## [0.1.0] - 2026-03-18

- Initial macOS SwiftUI app and persistent Python worker integration.
- Seeded deterministic geometric generation with live preview and batch export.
- Export bundle contract: `PNG + SVG + .jbt` with append-only `index.jbtl`.
