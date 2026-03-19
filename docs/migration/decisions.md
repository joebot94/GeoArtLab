# Migration Decision Log

## 2026-03-18 - Migration Starts Immediately
Decision:
- Start Swift/Metal migration now from current app baseline.
- Skip additional Python polish before migration kickoff.

Rationale:
- Time-to-value is higher by moving directly to Swift core work.
- Existing app is sufficient baseline for parity harness and fallback.

## 2026-03-18 - Branch Strategy
Decision:
- Use one long-lived migration branch: `codex/swift-metal-migration`.
- Use short-lived `codex/*` branches for scoped milestone work.

Rationale:
- Keeps `main` stable and minimizes integration risk.
- Supports milestone-gated PR workflow.

## 2026-03-18 - `.jbt` Compatibility Policy
Decision:
- Preserve existing `jbt_type` values and schema during migration:
  - `geo_art_piece`
  - `geo_art_animation`
- Add non-breaking `render_engine` metadata field.

Rationale:
- Ecosystem consumers already rely on current contract.
- Non-breaking metadata enables migration observability.

Notes:
- Compatibility target is schema + semantic exactness.
- Byte-for-byte identity is not required.

## 2026-03-18 - Parity Test Strategy
Decision:
- Use strict parity for contractual fields/semantics.
- Use statistical parity for stochastic geometry distributions.

Rationale:
- Deterministic behavior contracts matter.
- Different RNG implementations can still be behaviorally equivalent.

## 2026-03-18 - Kill Switch Exposure
Decision:
- Keep renderer fallback switch internal-only.
- Do not expose engine toggle in primary UI during migration.

Rationale:
- Avoid confusing normal users with temporary migration controls.
- Preserve emergency rollback path for internal validation.

## 2026-03-19 - Parity CI Gating Mode
Decision:
- Keep parity report generation non-blocking by default in CI.
- Preserve explicit failure mode via `--fail-on-mismatch` for manual enforcement and promotion windows.

Rationale:
- Early migration phases need continuous visibility into parity deltas without turning the branch red for known gaps.
- Promotion gates still require strict+statistical parity to pass before cutover.
