# GeoArtLab Swift/Metal Migration (Execution Spec)

Last updated: 2026-03-18

## Summary
GeoArtLab is migrating from a SwiftUI + Python worker architecture to a native Swift renderer stack with Metal preview, while keeping existing export and protocol contracts stable during migration.

This document is the implementation spec for the migration branch `codex/swift-metal-migration`.

## Non-Negotiable Guardrails
- Keep `main` stable until Milestone 5 cutover.
- Keep existing `.jbt` types unchanged during migration:
  - `geo_art_piece`
  - `geo_art_animation`
- Keep static and animation export contracts non-breaking.
- Use parity gates before replacing legacy behavior.
- Keep Python path as internal emergency fallback until cutover.

## Branch + PR Workflow
- Long-lived branch: `codex/swift-metal-migration`.
- Work branches: `codex/<milestone>-<feature>`.
- PR-only merges into migration branch.
- Every migration PR must include:
  - milestone tag (`M1`..`M5`)
  - docs update (`docs/migration/*`)
  - status update in `docs/migration/status.md`

## Milestones

### M1: Swift Core Parity
Goal: Introduce deterministic Swift rendering core and migration scaffolding.

Deliverables:
- Swift `RenderCore` module scaffold with deterministic per-stream RNG utilities.
- Internal render engine flag with Python legacy fallback.
- Parity harness skeleton and first strict parity checks (shape counts, dimensions, metadata contract).

Parity harness commands:
- `swift run GeoArtLab --migration-parity-sample --seed 42 --width 512 --height 512`
- `python3 python/tests/migration_parity_harness.py --seed 42 --width 512 --height 512`
- `python3 python/tests/generate_migration_parity_report.py --seeds 42,1337 --sizes 512x512,1024x1024`
- `python3 python/tests/generate_migration_parity_report.py --fail-on-mismatch` (promotion gate mode)

Exit criteria:
- Swift build passes.
- Existing Python test suite passes.
- Migration docs and status are updated with baseline results.

### M2: Metal Preview Backend
Goal: Add feature-flagged Metal preview path without breaking current workflow.

Deliverables:
- Metal preview path behind internal feature flag.
- Coalesced preview request behavior for smooth interactive updates.
- Preview performance baseline measurements on M1 Max.

Exit criteria:
- Preview remains stable under rapid control changes.
- Required baseline metrics captured in status doc.

Internal enable flags:
- `GEOARTLAB_ENABLE_SWIFT_RENDERER=1`
- `GEOARTLAB_ENABLE_METAL_PREVIEW=1`

Preview benchmark command:
- `swift run GeoArtLab --migration-preview-benchmark --width 1024 --height 1024 --iterations 5 --shape-counts 200,500,1000 --seed 42`

### M3: Export Parity
Goal: Match current export behavior on Swift path.

Deliverables:
- Static export parity: `PNG + SVG + .jbt` + static `index.jbtl` line.
- Animation export parity: frame PNG sequence + `animation.jbt` + animation `index.jbtl` line.
- Add non-breaking `render_engine` metadata.

Exit criteria:
- Contract tests pass for static + animation exports.
- Existing `.jbt` files remain readable by ecosystem consumers.

### M4: Timeline + Animation
Goal: Move DAW/timeline behavior to Swift core path.

Deliverables:
- Timeline scrub/playback/keyframe editing with interpolation parity.
- Responsive animation preview updates on Swift path.
- V3.3-era timeline/animation improvements begin here.

Exit criteria:
- Timeline parity tests pass.
- Manual workflow validation for creation -> preview -> export.

### M5: Cutover + Promotion
Goal: Promote Swift path as canonical and retire Python backend.

Deliverables:
- Sustained parity pass window.
- Manual soak and regression pass.
- Remove `/python` backend path and IPC glue.
- Merge migration branch to `main`, tag `v4.0.0`.

Exit criteria:
- All promotion gates in `status.md` checked.
- Documentation updated to Swift renderer as canonical.

## Compatibility Policy

### Strict parity (must match)
- shape counts and resolved canvas dimensions
- required metadata fields and value semantics
- parameter serialization contract in `.jbt`
- palette and mode selection semantics

### Statistical parity (allowed variance)
- positions, sizes, and angle distributions
- per-palette color usage proportions
- visual similarity thresholds for representative scenes

Byte-for-byte file identity is not required (timestamps/order can differ), but schema and semantic behavior must remain compatible.

## Internal Kill Switch
- Renderer switch is internal-only (debug/defaults), not exposed in the main UI.
- Intended use: emergency fallback to Python path during migration only.

## Deferred Scope
- V3.2 feature expansion remains deferred.
- Major protocol/schema redesign is deferred until after migration cutover.
