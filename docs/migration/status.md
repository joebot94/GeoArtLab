# Swift/Metal Migration Status

Last updated: 2026-03-19
Branch: `codex/swift-metal-migration`

## Milestones

### M1: Swift Core Parity
- [x] Create migration branch
- [x] Add migration governance docs (`docs/migration/*`)
- [x] Add PR template milestone/docs gates
- [x] Add internal render-engine feature flag scaffold
- [x] Add non-breaking `render_engine` metadata on Python export path
- [x] Add Swift deterministic RNG + RenderCore scaffold
- [x] Add parity harness runner (Python-vs-Swift compare path)
- [x] Add first parity tests scaffold (strict + statistical thresholds)
- [x] Add parity report generator + CI artifact workflow

M1 parity baseline snapshot (2026-03-19):
- strict parity: pass (4/4 scenarios)
- statistical parity: 2/4 scenarios pass
- known gap: `rectangle mean_y_norm` exceeds threshold for seed `1337` at `512x512` and `1024x1024`
- action: keep reporting this in CI artifacts while thresholds/renderer behavior are refined in M1-M2

### M2: Metal Preview Backend
- [ ] Metal preview path behind internal feature flag
- [ ] Coalesced preview cadence and stale response suppression
- [ ] Baseline preview performance measurements

### M3: Export Parity
- [ ] Swift static export parity (`PNG + SVG + .jbt` + `index.jbtl`)
- [ ] Swift animation export parity (`frames + animation.jbt` + `index.jbtl`)
- [ ] Contract test suite green for both engines

### M4: Timeline + Animation
- [ ] Swift timeline playback/scrub parity
- [ ] Keyframe editing parity (add/move/delete/interpolation)
- [ ] Animation preview behavior parity

### M5: Cutover + Promotion
- [ ] Parity suite passing for sustained soak window
- [ ] Manual regression pass (no critical issues)
- [ ] Remove `/python` worker + IPC fallback path
- [ ] Merge to `main` and tag `v4.0.0`

## Performance Baselines (M1 Max)

### Current Python Baseline (to be measured in-repo)
- 200 shapes preview FPS: TODO
- 500 shapes preview FPS: TODO
- 1000 shapes preview FPS (stress): TODO
- 2160x1620 static export time: TODO
- 4K static export time: TODO

### Swift/Metal Targets
- 200 shapes preview: 120fps (required)
- 500 shapes preview: 120fps (required)
- 1000 shapes preview: 60fps (stretch)
- 2160x1620 static export: < 2s (required)
- 4K static export: < 5s (required)

## Promotion Gates
- [ ] Strict parity checks pass
- [ ] Statistical parity checks pass
- [ ] Export contract tests pass (static + animation)
- [ ] Existing `.jbt` corpus round-trip compatibility pass
- [ ] Manual creative workflow validation pass
