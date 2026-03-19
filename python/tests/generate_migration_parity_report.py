from __future__ import annotations

import argparse
import json
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from migration_parity_harness import SHAPE_ORDER, run_parity

ROOT = Path(__file__).resolve().parents[2]


@dataclass
class ScenarioResult:
    seed: int
    width: int
    height: int
    strict_pass: bool
    statistical_pass: bool
    strict_failures: list[str]
    statistical_failures: list[str]
    metrics: dict[str, dict[str, float]]


@dataclass
class Summary:
    total_scenarios: int
    passed_scenarios: int
    failed_scenarios: int
    all_strict_pass: bool
    all_statistical_pass: bool


def parse_seed_list(raw: str) -> list[int]:
    values = [chunk.strip() for chunk in raw.split(",") if chunk.strip()]
    return [int(value) for value in values]


def parse_size_list(raw: str) -> list[tuple[int, int]]:
    sizes: list[tuple[int, int]] = []
    for chunk in [item.strip() for item in raw.split(",") if item.strip()]:
        if "x" not in chunk.lower():
            raise ValueError(f"Invalid size '{chunk}', expected WIDTHxHEIGHT")
        w, h = chunk.lower().split("x", 1)
        sizes.append((int(w), int(h)))
    return sizes


def scenario_markdown(result: ScenarioResult) -> str:
    header = f"- seed={result.seed}, canvas={result.width}x{result.height}, strict={result.strict_pass}, statistical={result.statistical_pass}"
    lines = [header]
    if result.strict_failures:
        lines.append(f"  - strict_failures: {result.strict_failures}")
    if result.statistical_failures:
        lines.append(f"  - statistical_failures: {result.statistical_failures}")

    for kind in SHAPE_ORDER:
        metric = result.metrics.get(kind, {})
        lines.append(
            "  - "
            f"{kind}: "
            f"dx={metric.get('mean_x_norm_delta', 0.0):.4f}, "
            f"dy={metric.get('mean_y_norm_delta', 0.0):.4f}, "
            f"dsize={metric.get('mean_size_norm_delta', 0.0):.4f}, "
            f"dfill={metric.get('fill_ratio_delta', 0.0):.4f}, "
            f"dangle={metric.get('mean_angle_delta_deg', 0.0):.2f}"
        )
    return "\n".join(lines)


def generate_report(seeds: list[int], sizes: list[tuple[int, int]]) -> dict[str, Any]:
    scenario_results: list[ScenarioResult] = []

    for seed in seeds:
        for width, height in sizes:
            parity = run_parity(seed=seed, width=width, height=height)
            scenario_results.append(
                ScenarioResult(
                    seed=seed,
                    width=width,
                    height=height,
                    strict_pass=bool(parity["strict_pass"]),
                    statistical_pass=bool(parity["statistical_pass"]),
                    strict_failures=list(parity.get("strict_failures", [])),
                    statistical_failures=list(parity.get("statistical_failures", [])),
                    metrics=dict(parity.get("metrics", {})),
                )
            )

    passed = sum(1 for s in scenario_results if s.strict_pass and s.statistical_pass)
    summary = Summary(
        total_scenarios=len(scenario_results),
        passed_scenarios=passed,
        failed_scenarios=len(scenario_results) - passed,
        all_strict_pass=all(s.strict_pass for s in scenario_results),
        all_statistical_pass=all(s.statistical_pass for s in scenario_results),
    )

    timestamp = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    return {
        "generated_at": timestamp,
        "seeds": seeds,
        "sizes": [{"width": w, "height": h} for w, h in sizes],
        "summary": asdict(summary),
        "scenarios": [asdict(s) for s in scenario_results],
    }


def report_markdown(report: dict[str, Any]) -> str:
    summary = report["summary"]
    lines = [
        "# Migration Parity Report",
        "",
        f"Generated at: {report['generated_at']}",
        "",
        "## Summary",
        f"- total scenarios: {summary['total_scenarios']}",
        f"- passed scenarios: {summary['passed_scenarios']}",
        f"- failed scenarios: {summary['failed_scenarios']}",
        f"- all strict pass: {summary['all_strict_pass']}",
        f"- all statistical pass: {summary['all_statistical_pass']}",
        "",
        "## Scenarios",
    ]

    for scenario in report["scenarios"]:
        lines.append(
            scenario_markdown(
                ScenarioResult(
                    seed=scenario["seed"],
                    width=scenario["width"],
                    height=scenario["height"],
                    strict_pass=scenario["strict_pass"],
                    statistical_pass=scenario["statistical_pass"],
                    strict_failures=scenario["strict_failures"],
                    statistical_failures=scenario["statistical_failures"],
                    metrics=scenario["metrics"],
                )
            )
        )
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate migration parity report for Swift-vs-Python sampling")
    parser.add_argument("--seeds", default="42,1337,2026", help="Comma-separated seeds")
    parser.add_argument("--sizes", default="512x512,1024x1024", help="Comma-separated WIDTHxHEIGHT entries")
    parser.add_argument("--json-out", default="docs/migration/parity/latest.json", help="JSON report output path")
    parser.add_argument("--md-out", default="docs/migration/parity/latest.md", help="Markdown report output path")
    parser.add_argument(
        "--fail-on-mismatch",
        action="store_true",
        help="Exit non-zero when strict or statistical parity does not fully pass",
    )
    args = parser.parse_args()

    seeds = parse_seed_list(args.seeds)
    sizes = parse_size_list(args.sizes)
    report = generate_report(seeds=seeds, sizes=sizes)

    json_out = Path(args.json_out)
    md_out = Path(args.md_out)
    if not json_out.is_absolute():
        json_out = ROOT / json_out
    if not md_out.is_absolute():
        md_out = ROOT / md_out

    json_out.parent.mkdir(parents=True, exist_ok=True)
    md_out.parent.mkdir(parents=True, exist_ok=True)

    json_out.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    md_out.write_text(report_markdown(report), encoding="utf-8")

    print(f"wrote {json_out}")
    print(f"wrote {md_out}")

    summary = report["summary"]
    if summary["all_strict_pass"] and summary["all_statistical_pass"]:
        return 0

    print(
        "parity mismatches detected: "
        f"strict={summary['all_strict_pass']} "
        f"statistical={summary['all_statistical_pass']}"
    )
    if args.fail_on_mismatch:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
