import json
import os
import sys
from statistics import median


def read_metrics(path):
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
    base_metrics, pr_metrics = read_metrics(base_path), read_metrics(pr_path)
    lines = [
        "### Stubbed search (median of five runs)",
        "",
        "Measures submit through results rendering with XCTest polling; live MapKit is not exercised.",
        "",
        "| Metric | Base | PR | Change | Allowed increase | Status |",
        "| --- | ---: | ---: | ---: | ---: | --- |",
    ]
    for family, suffix, label, raw_unit, display_unit, display_multiplier, minimum_allowance in (
        ("CPU", "time", "CPU time", "s", "ms", 1_000, 20),
        ("Memory", "physical_peak", "Peak physical memory", "kB", "MB", 0.001, 4),
    ):
        base_median = measured_median(base_metrics, family, suffix, raw_unit) * display_multiplier
        pr_median = measured_median(pr_metrics, family, suffix, raw_unit) * display_multiplier
        change = pr_median - base_median
        allowed_increase = max(base_median * 0.25, minimum_allowance)
        exceeds_allowance = change > allowed_increase
        if exceeds_allowance:
            print(
                f"::warning title=iOS performance::{label} rose by {change:.1f} {display_unit}; "
                f"limit {allowed_increase:.1f} {display_unit}."
            )
        status = "Warning" if exceeds_allowance else "OK"
        lines.append(
            f"| {label} ({display_unit}) | {base_median:.1f} | {pr_median:.1f} | "
            f"{change:+.1f} | {allowed_increase:.1f} | {status} |"
        )
    report = "\n".join(lines) + "\n"
    print(report, end="")
    if summary := os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(summary, "a", encoding="utf-8") as target:
            target.write(report)


if __name__ == "__main__":
    main(*sys.argv[1:])
