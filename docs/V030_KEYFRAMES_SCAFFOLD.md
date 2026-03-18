# GeoArtLab v0.3.0 Keyframes Scaffold

## Goal
Add timeline/keyframe animation so parameters can evolve over time, preview quickly, and export frame/image sequences into dedicated animation folders.

## Planned Capability

- Timeline with keyframes per parameter.
- Interpolation over frame/time range.
- Quick preview playback in app.
- Animation export to dedicated folder structure.

## Parameters In Scope

- `shape_counts` per shape kind
- `rotation`
- `stroke_width`
- `fill_ratio`
- `symmetry`
- (future) other scalar controls and color/palette modes

## Proposed Output Structure

`~/JBT/geo_art_lab/animations/<project_name_or_timestamp>/`

- `frames/frame_000001.png`
- `frames/frame_000002.png`
- `...`
- `animation.jbt`
- `index.jbtl` append record
- `preview/preview.gif` (optional quick preview)

## Data Model Draft

- `animation_timeline`:
  - `fps`
  - `duration_seconds` or `frame_count`
  - `tracks[]`
- `track`:
  - `parameter_id`
  - `keyframes[]`
- `keyframe`:
  - `frame`
  - `value`
  - `interpolation` (`hold`, `linear`, `ease_in_out`)

## Initial Milestones

1. Schema + worker interpolation core.
2. Frame sequence export path.
3. Timeline UI + keyframe editing.
4. Quick preview rendering path.
5. Optional GIF/MP4 pass.
