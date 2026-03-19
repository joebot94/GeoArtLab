# GeoArtLab

GeoArtLab is a macOS SwiftUI app with a long-lived Python worker for deterministic geometric artwork generation.

## Features

- Live preview with debounced updates
- Core 10 geometric controls and canvas presets/custom dimensions
- Deterministic seed + repeat batch exports (`S..S+N-1`)
- Export bundle per piece: `PNG + SVG + .jbt`
- PNG textual metadata embedding (best effort)
- Searchable append-only `index.jbtl`

## Project Layout

- `Sources/GeoArtLab`: SwiftUI app, state model, Python IPC client
- `python/worker`: geometry/render/export engine + JSONL stdio protocol server
- `python/tests`: determinism and protocol tests

## Run

1. `cd /Users/joe/Documents/GeoArtLab`
2. Create a venv if desired: `python3 -m venv .venv && source .venv/bin/activate`
3. Install Python deps: `python3 -m pip install -r python/requirements.txt`
4. Launch app: `./run_geoartlab.sh` (recommended) or `swift run`

For Xcode workflow, open the package folder in Xcode and run the `GeoArtLab` executable target.

## Worker Protocol

Request envelope:

```json
{ "request_id": "...", "type": "...", "payload": { ... } }
```

Response envelope:

```json
{ "request_id": "...", "type": "...", "ok": true, "payload": { ... } }
```

Error envelope:

```json
{ "request_id": "...", "type": "error", "ok": false, "error": { "message": "..." } }
```

Supported request types:

- `hello`
- `ping`
- `render_preview`
- `export_batch`
- `cancel`

## Default Output

`~/JBT/geo_art_lab`

Each export writes:

- `YYYYMMDD_HHMMSS_s####_clean-geometric.png`
- `YYYYMMDD_HHMMSS_s####_clean-geometric.svg`
- `YYYYMMDD_HHMMSS_s####_clean-geometric.jbt`
- `index.jbtl` append record

## Swift/Metal Migration

Active migration branch: `codex/swift-metal-migration`

Migration docs:
- `docs/migration/swift-metal-migration.md`
- `docs/migration/status.md`
- `docs/migration/decisions.md`

Parity harness (M1 scaffold):
- Swift sample report: `swift run GeoArtLab --migration-parity-sample --seed 42 --width 512 --height 512`
- Python-vs-Swift compare: `python3 python/tests/migration_parity_harness.py --seed 42 --width 512 --height 512`

Internal M2 preview path:
- Enable Swift renderer + Metal preview: `GEOARTLAB_ENABLE_SWIFT_RENDERER=1 GEOARTLAB_ENABLE_METAL_PREVIEW=1 ./run_geoartlab.sh`
- Preview benchmark (CLI): `swift run GeoArtLab --migration-preview-benchmark --width 1024 --height 1024 --iterations 5 --shape-counts 200,500,1000 --seed 42`
