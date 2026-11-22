import json
import os
import sys
from statistics import median


def metrics(path):
    with open(path, encoding="utf-8") as source:
        tests = json.load(source)
    return [metric for test in tests for run in test["testRuns"] for metric in run["metrics"]]


def measured_median(metrics, family, suffix, unit):
    matching = [
        metric
        for metric in metrics
        if metric["identifier"].startswith(f"com.apple.dt.XCTMetric_{family}-")
        and metric["identifier"].endswith(f".{suffix}")
    ]
    if len(matching) != 1:
        sys.exit(f"Expected one XCTest metric for {family}.{suffix}")
    metric = matching[0]
    if metric["unitOfMeasurement"] != unit or len(metric["measurements"]) != 5:
        sys.exit(f"Expected five {family}.{suffix} measurements in {unit}")
    return median(metric["measurements"])


def main(base_path, pr_path):
    base, pr = metrics(base_path), metrics(pr_path)
    lines = [
        "### Fixed search (median of five runs)",
        "",
        "| Metric | Base | PR | Change | Allowed increase | Status |",
        "| --- | ---: | ---: | ---: | ---: | --- |",
    ]
    for family, suffix, label, unit, display_unit, scale, floor in (
        ("CPU", "time", "CPU time", "s", "ms", 1_000, 20),
        ("Memory", "physical_peak", "Peak physical memory", "kB", "MB", 0.001, 4),
    ):
        before = measured_median(base, family, suffix, unit) * scale
        after = measured_median(pr, family, suffix, unit) * scale
        change = after - before
        # Ignore small absolute differences even when the baseline is near zero.
        limit = max(before * 0.25, floor)
        status = "OK"
        if change > limit:
            status = "Warning"
            print(
                f"::warning title=iOS performance::{label} rose by {change:.1f} {display_unit}; "
                f"limit {limit:.1f} {display_unit}."
            )
        lines.append(
            f"| {label} ({display_unit}) | {before:.1f} | {after:.1f} | "
            f"{change:+.1f} | {limit:.1f} | {status} |"
        )
    report = "\n".join(lines) + "\n"
    print(report, end="")
    if summary := os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(summary, "a", encoding="utf-8") as target:
            target.write(report)


if __name__ == "__main__":
    main(*sys.argv[1:])
