## Summary
- 

## Milestone
- [ ] `M1` Swift Core Parity
- [ ] `M2` Metal Preview Backend
- [ ] `M3` Export Parity
- [ ] `M4` Timeline + Animation
- [ ] `M5` Cutover + Promotion

## Change Type
- [ ] Feature
- [ ] Bug fix
- [ ] Refactor
- [ ] Docs/process
- [ ] Test-only

## Migration Governance
- [ ] I updated `docs/migration/status.md` with current milestone progress.
- [ ] I updated `docs/migration/decisions.md` for any behavior/scope decisions.
- [ ] I updated `docs/migration/swift-metal-migration.md` if execution scope changed.

## Compatibility Checklist
- [ ] `.jbt` contract remains compatible (`geo_art_piece` / `geo_art_animation`).
- [ ] Protocol envelope/message types remain non-breaking.
- [ ] If metadata changed, change is non-breaking and documented.

## Validation
- [ ] `swift build`
- [ ] `python3 -m unittest discover -s python/tests`
- [ ] Manual smoke check (preview + export path affected by this PR)

## Notes
- 
