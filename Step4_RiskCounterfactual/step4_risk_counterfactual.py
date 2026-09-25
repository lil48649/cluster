#!/usr/bin/env python3
"""Step 4: Level-2 risk counterfactuals by frozen life-course cluster.

This module uses only the Python standard library.  It deliberately evaluates
one risk at a time: estimates for different risks are not mutually exclusive
and must not be summed to represent a joint intervention.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import statistics
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any, Iterable, Mapping, Sequence


AGES = (
    "30-34 years",
    "35-39 years",
    "40-44 years",
    "45-49 years",
    "50-54 years",
    "55-59 years",
    "60-64 years",
    "65-69 years",
)

CLUSTERS = ("Infant", "Adult", "Aging-related")

DEATHS = "Deaths"
DALYS = "DALYs (Disability-Adjusted Life Years)"

# This is the complete GBD 2023 Level-2 selection present in the supplied file.
# The file itself has no numeric hierarchy column, so the level is validated by
# the exact label set rather than inferred from row order.
EXPECTED_LEVEL2_RISKS = (
    "Air pollution",
    "Child and maternal malnutrition",
    "Dietary risks",
    "Drug use",
    "High LDL cholesterol",
    "High alcohol use",
    "High body-mass index",
    "High fasting plasma glucose",
    "High systolic blood pressure",
    "Intimate partner violence",
    "Kidney dysfunction",
    "Low bone mineral density",
    "Low physical activity",
    "Non-optimal temperature",
    "Occupational risks",
    "Other environmental risks",
    "Sexual violence against children and bullying",
    "Tobacco",
    "Unsafe sex",
    "Unsafe water, sanitation, and handwashing",
)

RISK_REQUIRED_COLUMNS = (
    "population_group",
    "measure",
    "location",
    "sex",
    "age",
    "cause",
    "rei",
    "metric",
    "year",
    "val",
    "upper",
    "lower",
)

RISK_KEY_COLUMNS = (
    "population_group",
    "measure",
    "location",
    "sex",
    "age",
    "cause",
    "rei",
    "metric",
    "year",
)


class InputValidationError(ValueError):
    """Raised when an input cannot support the prespecified analysis."""


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        if not reader.fieldnames:
            raise InputValidationError(f"No header found in {path}")
        return list(reader)


def as_float(value: str, *, field: str, context: str) -> float:
    try:
        result = float(value)
    except (TypeError, ValueError) as exc:
        raise InputValidationError(
            f"Non-numeric {field}={value!r} in {context}"
        ) from exc
    if not math.isfinite(result):
        raise InputValidationError(f"Non-finite {field} in {context}")
    return result


def require_exact_values(
    rows: Sequence[Mapping[str, str]], column: str, expected: Iterable[str]
) -> None:
    observed = {row[column] for row in rows}
    expected_set = set(expected)
    if observed != expected_set:
        missing = sorted(expected_set - observed)
        extra = sorted(observed - expected_set)
        raise InputValidationError(
            f"Unexpected {column} coverage; missing={missing}, extra={extra}"
        )


def validate_risk_input(rows: Sequence[Mapping[str, str]]) -> dict[str, Any]:
    if not rows:
        raise InputValidationError("Risk input is empty")

    columns = set(rows[0])
    missing_columns = sorted(set(RISK_REQUIRED_COLUMNS) - columns)
    if missing_columns:
        raise InputValidationError(f"Risk input missing columns: {missing_columns}")

    require_exact_values(rows, "population_group", ("All Population",))
    require_exact_values(rows, "location", ("China",))
    require_exact_values(rows, "sex", ("Both",))
    require_exact_values(rows, "year", ("2023",))
    require_exact_values(rows, "age", AGES)
    require_exact_values(rows, "measure", (DEATHS, DALYS))
    require_exact_values(rows, "metric", ("Number", "Rate"))
    require_exact_values(rows, "rei", EXPECTED_LEVEL2_RISKS)

    full_keys = [tuple(row[column] for column in RISK_KEY_COLUMNS) for row in rows]
    duplicate_key_count = sum(value > 1 for value in Counter(full_keys).values())
    if duplicate_key_count:
        raise InputValidationError(
            f"Risk input contains {duplicate_key_count} duplicate full keys"
        )

    pair_columns = tuple(column for column in RISK_KEY_COLUMNS if column != "metric")
    paired_metrics: dict[tuple[str, ...], set[str]] = defaultdict(set)
    paired_values: dict[tuple[str, ...], dict[str, float]] = defaultdict(dict)
    bounds_failures = 0
    negative_value_rows = 0
    zero_value_rows = 0

    for index, row in enumerate(rows, start=2):
        context = f"risk row {index}"
        estimate = as_float(row["val"], field="val", context=context)
        lower = as_float(row["lower"], field="lower", context=context)
        upper = as_float(row["upper"], field="upper", context=context)
        if not lower <= estimate <= upper:
            bounds_failures += 1
        if estimate < 0:
            negative_value_rows += 1
        if estimate == 0:
            zero_value_rows += 1
        pair_key = tuple(row[column] for column in pair_columns)
        paired_metrics[pair_key].add(row["metric"])
        paired_values[pair_key][row["metric"]] = estimate

    incomplete_metric_pairs = sum(
        metrics != {"Number", "Rate"} for metrics in paired_metrics.values()
    )
    if incomplete_metric_pairs:
        raise InputValidationError(
            f"Risk input contains {incomplete_metric_pairs} incomplete Number/Rate pairs"
        )
    if bounds_failures:
        raise InputValidationError(
            f"Risk input contains {bounds_failures} rows outside uncertainty bounds"
        )

    age_position = pair_columns.index("age")
    implied_population_by_age: dict[str, list[float]] = defaultdict(list)
    for key, values in paired_values.items():
        rate = values["Rate"]
        number = values["Number"]
        if rate != 0:
            implied_population_by_age[key[age_position]].append(number / rate * 100_000.0)

    population_qc: dict[str, dict[str, float | int]] = {}
    maximum_population_relative_deviation = 0.0
    for age in AGES:
        values = implied_population_by_age[age]
        median = statistics.median(values)
        maximum_relative_deviation = max(abs(value - median) / median for value in values)
        maximum_population_relative_deviation = max(
            maximum_population_relative_deviation, maximum_relative_deviation
        )
        population_qc[age] = {
            "nonzero_pairs": len(values),
            "median_implied_population": median,
            "maximum_relative_deviation": maximum_relative_deviation,
        }
    if maximum_population_relative_deviation > 0.01:
        raise InputValidationError(
            "Number/Rate pairs imply inconsistent age-specific populations "
            f"(maximum relative deviation={maximum_population_relative_deviation:.6g})"
        )

    causes = {row["cause"] for row in rows}
    risk_cause_pairs = {(row["rei"], row["cause"]) for row in rows}
    return {
        "risk_rows": len(rows),
        "columns": list(rows[0]),
        "n_risks": len(EXPECTED_LEVEL2_RISKS),
        "n_causes_in_risk_file": len(causes),
        "n_risk_cause_pairs": len(risk_cause_pairs),
        "n_number_rate_pairs": len(paired_metrics),
        "duplicate_full_keys": duplicate_key_count,
        "incomplete_number_rate_pairs": incomplete_metric_pairs,
        "bounds_failures": bounds_failures,
        "negative_point_estimate_rows": negative_value_rows,
        "zero_point_estimate_rows": zero_value_rows,
        "rows_by_measure_metric": dict(
            Counter(f"{row['measure']}/{row['metric']}" for row in rows)
        ),
        "number_rate_implied_population_by_age": population_qc,
        "maximum_implied_population_relative_deviation": (
            maximum_population_relative_deviation
        ),
    }


def load_membership(path: Path) -> dict[str, str]:
    rows = read_csv(path)
    required = {"cause", "cluster_name"}
    if not rows or not required.issubset(rows[0]):
        raise InputValidationError(f"Invalid membership file: {path}")
    membership: dict[str, str] = {}
    for row in rows:
        cause = row["cause"]
        cluster = row["cluster_name"]
        if cluster not in CLUSTERS:
            raise InputValidationError(f"Unknown cluster {cluster!r} for {cause!r}")
        if cause in membership:
            raise InputValidationError(f"Duplicate membership cause: {cause}")
        membership[cause] = cluster
    if len(membership) != 292:
        raise InputValidationError(
            f"Expected 292 frozen causes, found {len(membership)}"
        )
    expected_counts = {"Infant": 57, "Adult": 71, "Aging-related": 164}
    observed_counts = Counter(membership.values())
    if dict(observed_counts) != expected_counts:
        raise InputValidationError(
            f"Frozen membership counts changed: {dict(observed_counts)}"
        )
    return membership


def load_mortality_baseline(path: Path) -> dict[tuple[str, str], dict[str, float]]:
    rows = read_csv(path)
    required = {
        "year",
        "cluster_name",
        "age",
        "death_number",
        "death_rate_per_100k",
        "mx",
        "q5",
    }
    if not rows or not required.issubset(rows[0]):
        raise InputValidationError(f"Invalid mortality baseline file: {path}")

    selected = [row for row in rows if row["year"] == "2023"]
    baseline: dict[tuple[str, str], dict[str, float]] = {}
    for row in selected:
        cluster = row["cluster_name"]
        age = row["age"]
        if cluster not in CLUSTERS or age not in AGES:
            continue
        key = (cluster, age)
        if key in baseline:
            raise InputValidationError(f"Duplicate mortality baseline key: {key}")
        context = f"mortality {cluster}/{age}"
        death_number = as_float(row["death_number"], field="death_number", context=context)
        rate = as_float(
            row["death_rate_per_100k"], field="death_rate_per_100k", context=context
        )
        mx = as_float(row["mx"], field="mx", context=context)
        q5 = as_float(row["q5"], field="q5", context=context)
        if min(death_number, rate, mx, q5) < 0:
            raise InputValidationError(f"Negative mortality baseline in {context}")
        if not math.isclose(mx, rate / 100_000.0, rel_tol=0, abs_tol=1e-14):
            raise InputValidationError(f"mx/rate mismatch in {context}")
        if not math.isclose(q5, mx_to_q5(mx), rel_tol=0, abs_tol=1e-14):
            raise InputValidationError(f"q5 does not reproduce Stage 3 in {context}")
        if q5 >= 1:
            raise InputValidationError(f"Invalid q5 >= 1 in {context}")
        baseline[key] = {
            "death_number": death_number,
            "death_rate_per_100k": rate,
            "mx": mx,
            "q5": q5,
        }

    expected_keys = {(cluster, age) for cluster in CLUSTERS for age in AGES}
    if set(baseline) != expected_keys:
        raise InputValidationError(
            f"Mortality baseline incomplete; missing={sorted(expected_keys - set(baseline))}"
        )
    return baseline


def load_daly_baseline(path: Path) -> dict[str, float]:
    rows = read_csv(path)
    required = {"cluster_name", "DALYs_age30_69"}
    if not rows or not required.issubset(rows[0]):
        raise InputValidationError(f"Invalid DALY baseline file: {path}")
    result: dict[str, float] = {}
    for row in rows:
        cluster = row["cluster_name"]
        if cluster not in CLUSTERS:
            continue
        if cluster in result:
            raise InputValidationError(f"Duplicate DALY baseline cluster: {cluster}")
        result[cluster] = as_float(
            row["DALYs_age30_69"], field="DALYs_age30_69", context=cluster
        )
    if set(result) != set(CLUSTERS) or any(value <= 0 for value in result.values()):
        raise InputValidationError("DALY baseline is incomplete or non-positive")
    return result


def q30_70_from_q5(q5_values: Iterable[float]) -> float:
    survival = 1.0
    count = 0
    for q5 in q5_values:
        if not 0 <= q5 < 1:
            raise InputValidationError(f"q5 outside [0,1): {q5}")
        survival *= 1.0 - q5
        count += 1
    if count != len(AGES):
        raise InputValidationError(f"q30-70 requires {len(AGES)} age groups, found {count}")
    return 1.0 - survival


def mx_to_q5(mx: float, *, interval_years: float = 5.0, ax: float = 2.5) -> float:
    """Convert a central death rate to interval death probability as in Stage 3."""
    if mx < 0 or not math.isfinite(mx):
        raise InputValidationError(f"Invalid mx: {mx}")
    q5 = interval_years * mx / (1.0 + (interval_years - ax) * mx)
    if not 0 <= q5 < 1:
        raise InputValidationError(f"Converted q5 outside [0,1): {q5}")
    return q5


def bounded_attributable(raw: float, baseline: float) -> tuple[float, str]:
    """Return a nonnegative burden capped at its corresponding baseline."""
    if raw < 0:
        return 0.0, "lower_bound_zero"
    if raw > baseline:
        return baseline, "upper_bound_baseline"
    return raw, "none"


def write_csv(path: Path, rows: Sequence[Mapping[str, Any]]) -> None:
    if not rows:
        raise ValueError(f"Refusing to write an empty CSV: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    fields = list(rows[0])
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, extrasaction="raise")
        writer.writeheader()
        writer.writerows(rows)


def analysis_qc_rows(qc: Mapping[str, Any]) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for check, value in qc.items():
        if isinstance(value, (list, tuple, set)):
            formatted = " | ".join(map(str, value))
        elif isinstance(value, dict):
            formatted = json.dumps(value, ensure_ascii=False, sort_keys=True)
        else:
            formatted = value
        rows.append({"check": check, "value": formatted})
    return rows


def write_key_results_report(
    path: Path,
    qc: Mapping[str, Any],
    summary_rows: Sequence[Mapping[str, Any]],
    baseline_q: Mapping[str, float],
) -> None:
    lines = [
        "# Step 4 key QC and results",
        "",
        "## Input and linkage QC",
        "",
        f"- Risk input: {qc['risk_rows']:,} rows, {qc['n_risks']} Level-2 risks, "
        f"{qc['n_causes_in_risk_file']} causes, and {qc['n_risk_cause_pairs']} risk-cause pairs.",
        f"- Coverage: China, Both, 2023; eight 5-year age groups from 30-34 through 65-69; "
        "Deaths and DALYs; Number and Rate.",
        f"- Frozen membership: {qc['frozen_clustered_causes']} causes "
        f"({qc['frozen_cluster_counts']}).",
        f"- Linkage: {qc['risk_causes_mapped']} risk-file causes mapped; "
        f"{qc['risk_causes_unmapped']} unmapped cause ({' | '.join(qc['unmapped_cause_names'])}), "
        "whose excluded attributable estimates are all zero.",
        f"- Frozen causes without an exported Level-2 risk-cause record: "
        f"{qc['frozen_causes_absent_from_risk_file']} (zero-filled in the analysis grid).",
        f"- Key integrity checks: 0 duplicate keys, 0 incomplete Number/Rate pairs, "
        f"0 uncertainty-bound failures; maximum Number/Rate implied-population deviation "
        f"{100 * float(qc['maximum_implied_population_relative_deviation']):.3f}%.",
        f"- Signed estimates: {qc['negative_point_estimate_rows']} source rows are negative. "
        "Raw values are retained; prevention endpoints are bounded at zero and every adjustment is flagged.",
        "- Uncertainty: lower/upper bounds pass internal checks but are not aggregated without "
        "draw-level covariance; reported counterfactuals are point estimates.",
        "",
        "## Baseline q30-70",
        "",
        "| Cluster | Baseline q30-70 |",
        "|---|---:|",
    ]
    for cluster in CLUSTERS:
        lines.append(f"| {cluster} | {100 * baseline_q[cluster]:.3f}% |")

    for cluster in CLUSTERS:
        cluster_rows = [row for row in summary_rows if row["cluster_name"] == cluster]
        lines.extend(
            [
                "",
                f"## {cluster}: largest q30-70 reductions",
                "",
                "| Level-2 risk removed to TMREL | Absolute reduction (percentage points) | Relative reduction | Avoidable deaths, ages 30-69 |",
                "|---|---:|---:|---:|",
            ]
        )
        for row in sorted(
            cluster_rows,
            key=lambda item: float(item["absolute_q30_70_reduction"]),
            reverse=True,
        )[:5]:
            lines.append(
                f"| {row['risk']} | {100 * float(row['absolute_q30_70_reduction']):.3f} | "
                f"{float(row['relative_q30_70_reduction_percent']):.2f}% | "
                f"{float(row['avoidable_deaths_age30_69']):,.0f} |"
            )

        lines.extend(
            [
                "",
                f"## {cluster}: largest avoidable DALY estimates",
                "",
                "| Level-2 risk removed to TMREL | Avoidable DALYs, ages 30-69 | Share of cluster DALYs |",
                "|---|---:|---:|",
            ]
        )
        for row in sorted(
            cluster_rows,
            key=lambda item: float(item["avoidable_DALYs_age30_69"]),
            reverse=True,
        )[:5]:
            lines.append(
                f"| {row['risk']} | {float(row['avoidable_DALYs_age30_69']):,.0f} | "
                f"{float(row['avoidable_DALY_percent']):.2f}% |"
            )

    lines.extend(
        [
            "",
            "## Interpretation guardrail",
            "",
            "Every row is a separate one-risk TMREL counterfactual. These effects must not be summed "
            "across risks because GBD risk-attributable burdens overlap and may include mediation.",
            "",
        ]
    )
    path.write_text("\n".join(lines), encoding="utf-8")


def run_analysis(
    risk_csv: Path,
    membership_csv: Path,
    mortality_csv: Path,
    daly_baseline_csv: Path,
    output_dir: Path,
) -> dict[str, Any]:
    risk_rows = read_csv(risk_csv)
    qc = validate_risk_input(risk_rows)
    membership = load_membership(membership_csv)
    mortality = load_mortality_baseline(mortality_csv)
    daly_baseline = load_daly_baseline(daly_baseline_csv)

    risk_causes = sorted({row["cause"] for row in risk_rows})
    unmapped_causes = sorted(set(risk_causes) - set(membership))
    mapped_causes = sorted(set(risk_causes) & set(membership))
    frozen_causes_absent_from_risk_file = sorted(set(membership) - set(risk_causes))
    risk_count_by_cause = Counter((row["cause"], row["rei"]) for row in risk_rows)
    cause_mapping_rows = [
        {
            "cause": cause,
            "cluster_name": membership.get(cause, "UNMAPPED_EXCLUDED"),
            "mapped_to_frozen_cluster": cause in membership,
            "present_in_risk_file": cause in risk_causes,
            "number_of_level2_risks_with_exported_rows": len(
                {risk for (pair_cause, risk) in risk_count_by_cause if pair_cause == cause}
            ),
        }
        for cause in sorted(set(risk_causes) | set(membership))
    ]

    # Aggregate within a single risk across mutually exclusive causes.  No code
    # path aggregates across risks, which prevents accidental joint estimates.
    aggregate: dict[tuple[str, str, str, str], dict[str, Any]] = defaultdict(
        lambda: {
            "Number": 0.0,
            "Rate": 0.0,
            "source_rows": 0,
            "negative_number_rows": 0,
            "negative_rate_rows": 0,
            "causes": set(),
        }
    )
    excluded_unmapped_rows = 0
    excluded_unmapped_values = Counter()

    for row in risk_rows:
        cause = row["cause"]
        if cause not in membership:
            excluded_unmapped_rows += 1
            excluded_unmapped_values[(row["measure"], row["metric"])] += as_float(
                row["val"], field="val", context=f"unmapped {cause}"
            )
            continue
        cluster = membership[cause]
        key = (row["rei"], cluster, row["age"], row["measure"])
        estimate = as_float(row["val"], field="val", context="risk aggregation")
        cell = aggregate[key]
        cell[row["metric"]] += estimate
        cell["source_rows"] += 1
        cell["causes"].add(cause)
        if estimate < 0:
            field = (
                "negative_number_rows" if row["metric"] == "Number" else "negative_rate_rows"
            )
            cell[field] += 1

    baseline_rows: list[dict[str, Any]] = []
    baseline_q: dict[str, float] = {}
    for cluster in CLUSTERS:
        ordered = [mortality[(cluster, age)] for age in AGES]
        q_value = q30_70_from_q5(cell["q5"] for cell in ordered)
        baseline_q[cluster] = q_value
        baseline_rows.append(
            {
                "cluster_name": cluster,
                "n_frozen_causes": Counter(membership.values())[cluster],
                "baseline_deaths_age30_69": sum(cell["death_number"] for cell in ordered),
                "baseline_DALYs_age30_69": daly_baseline[cluster],
                "baseline_q30_70": q_value,
            }
        )

    age_rows: list[dict[str, Any]] = []
    mortality_cf_by_risk_cluster: dict[tuple[str, str], list[dict[str, Any]]] = defaultdict(list)
    daly_by_risk_cluster: dict[tuple[str, str], dict[str, float]] = defaultdict(
        lambda: {"raw": 0.0, "nonnegative": 0.0}
    )

    for risk in EXPECTED_LEVEL2_RISKS:
        for cluster in CLUSTERS:
            for age in AGES:
                baseline = mortality[(cluster, age)]
                for measure in (DEATHS, DALYS):
                    cell = aggregate[(risk, cluster, age, measure)]
                    raw_number = float(cell["Number"])
                    raw_rate = float(cell["Rate"])
                    bounded_number = max(raw_number, 0.0)
                    number_clip = "lower_bound_zero" if raw_number < 0 else "none"
                    bounded_rate = max(raw_rate, 0.0)
                    rate_clip = "lower_bound_zero" if raw_rate < 0 else "none"

                    if measure == DEATHS:
                        bounded_number, number_clip = bounded_attributable(
                            raw_number, baseline["death_number"]
                        )
                        bounded_rate, rate_clip = bounded_attributable(
                            raw_rate, baseline["death_rate_per_100k"]
                        )
                        cf_rate = baseline["death_rate_per_100k"] - bounded_rate
                        cf_mx = cf_rate / 100_000.0
                        mortality_cf_by_risk_cluster[(risk, cluster)].append(
                            {
                                "age": age,
                                "bounded_attributable_death_number": bounded_number,
                                "bounded_attributable_death_rate_per_100k": bounded_rate,
                                "counterfactual_death_rate_per_100k": cf_rate,
                                "counterfactual_q5": mx_to_q5(cf_mx),
                                "number_clip": number_clip,
                                "rate_clip": rate_clip,
                            }
                        )
                    else:
                        daly_by_risk_cluster[(risk, cluster)]["raw"] += raw_number
                        daly_by_risk_cluster[(risk, cluster)]["nonnegative"] += bounded_number

                    age_rows.append(
                        {
                            "risk_level": "Level 2",
                            "risk": risk,
                            "cluster_name": cluster,
                            "age": age,
                            "measure": measure,
                            "source_cause_count": len(cell["causes"]),
                            "source_row_count": cell["source_rows"],
                            "negative_number_rows": cell["negative_number_rows"],
                            "negative_rate_rows": cell["negative_rate_rows"],
                            "raw_attributable_number": raw_number,
                            "raw_attributable_rate_per_100k": raw_rate,
                            "bounded_attributable_number": bounded_number,
                            "bounded_attributable_rate_per_100k": bounded_rate,
                            "number_clip": number_clip,
                            "rate_clip": rate_clip,
                            "baseline_death_number": (
                                baseline["death_number"] if measure == DEATHS else ""
                            ),
                            "baseline_death_rate_per_100k": (
                                baseline["death_rate_per_100k"]
                                if measure == DEATHS
                                else ""
                            ),
                        }
                    )

    q_rows: list[dict[str, Any]] = []
    daly_rows: list[dict[str, Any]] = []
    summary_rows: list[dict[str, Any]] = []

    for risk in EXPECTED_LEVEL2_RISKS:
        for cluster in CLUSTERS:
            cf_cells = sorted(
                mortality_cf_by_risk_cluster[(risk, cluster)],
                key=lambda row: AGES.index(row["age"]),
            )
            if len(cf_cells) != len(AGES):
                raise AssertionError(f"Incomplete counterfactual: {risk}/{cluster}")
            cf_q = q30_70_from_q5(row["counterfactual_q5"] for row in cf_cells)
            delta_q = baseline_q[cluster] - cf_q
            relative_delta = delta_q / baseline_q[cluster]
            attributable_deaths = sum(
                row["bounded_attributable_death_number"] for row in cf_cells
            )
            attributable_death_rate_sum = sum(
                row["bounded_attributable_death_rate_per_100k"] for row in cf_cells
            )
            lower_clips = sum(row["rate_clip"] == "lower_bound_zero" for row in cf_cells)
            upper_clips = sum(row["rate_clip"] == "upper_bound_baseline" for row in cf_cells)

            q_row = {
                "risk_level": "Level 2",
                "risk": risk,
                "cluster_name": cluster,
                "baseline_q30_70": baseline_q[cluster],
                "counterfactual_q30_70_TMREL": cf_q,
                "absolute_q30_70_reduction": delta_q,
                "relative_q30_70_reduction": relative_delta,
                "relative_q30_70_reduction_percent": 100.0 * relative_delta,
                "avoidable_deaths_age30_69": attributable_deaths,
                "sum_age_specific_attributable_rate_per_100k": attributable_death_rate_sum,
                "age_cells_clipped_at_zero": lower_clips,
                "age_cells_capped_at_baseline": upper_clips,
            }
            q_rows.append(q_row)

            raw_dalys = daly_by_risk_cluster[(risk, cluster)]["raw"]
            avoidable_dalys = max(raw_dalys, 0.0)
            # Summing per-age nonnegative cells is retained for QC.  The primary
            # result clips only after aggregation so signed estimates remain
            # internally consistent within each risk/cluster.
            cellwise_nonnegative_dalys = daly_by_risk_cluster[(risk, cluster)][
                "nonnegative"
            ]
            daly_fraction = avoidable_dalys / daly_baseline[cluster]
            daly_row = {
                "risk_level": "Level 2",
                "risk": risk,
                "cluster_name": cluster,
                "baseline_DALYs_age30_69": daly_baseline[cluster],
                "raw_signed_attributable_DALYs_age30_69": raw_dalys,
                "avoidable_DALYs_age30_69": avoidable_dalys,
                "avoidable_DALY_fraction": daly_fraction,
                "avoidable_DALY_percent": 100.0 * daly_fraction,
                "cellwise_nonnegative_DALYs_QC": cellwise_nonnegative_dalys,
            }
            daly_rows.append(daly_row)

            summary_rows.append({**q_row, **{k: v for k, v in daly_row.items() if k not in {"risk_level", "risk", "cluster_name"}}})

    for cluster in CLUSTERS:
        cluster_rows = [row for row in summary_rows if row["cluster_name"] == cluster]
        for rank, row in enumerate(
            sorted(
                cluster_rows,
                key=lambda item: float(item["absolute_q30_70_reduction"]),
                reverse=True,
            ),
            start=1,
        ):
            row["q30_70_reduction_rank_within_cluster"] = rank
        for rank, row in enumerate(
            sorted(
                cluster_rows,
                key=lambda item: float(item["avoidable_DALYs_age30_69"]),
                reverse=True,
            ),
            start=1,
        ):
            row["avoidable_DALY_rank_within_cluster"] = rank

    # Prove by construction that every result row is risk-specific.
    expected_result_keys = {
        (risk, cluster) for risk in EXPECTED_LEVEL2_RISKS for cluster in CLUSTERS
    }
    observed_result_keys = {(row["risk"], row["cluster_name"]) for row in summary_rows}
    if observed_result_keys != expected_result_keys or len(summary_rows) != 60:
        raise AssertionError("Risk-specific output grid is incomplete")

    qc.update(
        {
            "risk_hierarchy_level": "Level 2 (validated from exact 20-label selection)",
            "age_groups": AGES,
            "measures": (DEATHS, DALYS),
            "metrics": ("Number", "Rate"),
            "frozen_clustered_causes": len(membership),
            "frozen_cluster_counts": dict(Counter(membership.values())),
            "risk_causes_mapped": len(mapped_causes),
            "risk_causes_unmapped": len(unmapped_causes),
            "unmapped_cause_names": unmapped_causes,
            "frozen_causes_present_in_risk_file": len(mapped_causes),
            "frozen_causes_absent_from_risk_file": len(
                frozen_causes_absent_from_risk_file
            ),
            "excluded_unmapped_rows": excluded_unmapped_rows,
            "excluded_unmapped_values": {
                f"{measure}/{metric}": value
                for (measure, metric), value in sorted(excluded_unmapped_values.items())
            },
            "baseline_q30_70": baseline_q,
            "risk_cluster_result_rows": len(summary_rows),
            "cross_risk_aggregation_performed": False,
            "negative_estimate_handling": (
                "Raw signed values retained; prevention endpoints bounded at zero. "
                "Death attribution also capped at the corresponding cluster-age baseline."
            ),
            "uncertainty_interval_propagation": (
                "Not performed: draw-level covariance is unavailable, so lower/upper "
                "bounds are validated but not summed across causes. Results are point estimates."
            ),
        }
    )

    output_dir.mkdir(parents=True, exist_ok=True)
    write_csv(output_dir / "Step4_input_QC.csv", analysis_qc_rows(qc))
    write_csv(output_dir / "Step4_risk_cause_cluster_mapping.csv", cause_mapping_rows)
    write_csv(output_dir / "Step4_baseline_cluster_2023.csv", baseline_rows)
    write_csv(output_dir / "Step4_risk_cluster_age_aggregates.csv", age_rows)
    write_csv(output_dir / "Step4_q30_70_counterfactuals.csv", q_rows)
    write_csv(output_dir / "Step4_DALY_counterfactuals.csv", daly_rows)
    write_csv(output_dir / "Step4_risk_cluster_summary.csv", summary_rows)
    write_key_results_report(
        output_dir / "Step4_key_results.md", qc, summary_rows, baseline_q
    )

    manifest = {
        "analysis": "Step 4 risk-factor TMREL counterfactuals",
        "risk_level": "GBD 2023 Level 2",
        "inputs": {
            "risk_csv": str(risk_csv.resolve()),
            "membership_csv": str(membership_csv.resolve()),
            "mortality_csv": str(mortality_csv.resolve()),
            "daly_baseline_csv": str(daly_baseline_csv.resolve()),
        },
        "outputs": sorted(path.name for path in output_dir.glob("Step4_*")),
        "method_notes": [
            "Each risk is evaluated independently against TMREL.",
            "Risk-specific results must not be summed across risks.",
            "q30-70 uses the exact Stage 3 transformation q5 = 5mx / (1 + 2.5mx).",
            "Negative point estimates are retained in raw fields and bounded for prevention endpoints.",
            "Lower/upper bounds are validated but not propagated without draw-level covariance.",
        ],
    }
    with (output_dir / "Step4_manifest.json").open("w", encoding="utf-8") as handle:
        json.dump(manifest, handle, ensure_ascii=False, indent=2)

    return {
        "qc": qc,
        "summary_rows": summary_rows,
        "q_rows": q_rows,
        "daly_rows": daly_rows,
        "output_dir": output_dir,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--risk-csv", type=Path, required=True)
    parser.add_argument("--membership-csv", type=Path, required=True)
    parser.add_argument("--mortality-csv", type=Path, required=True)
    parser.add_argument("--daly-baseline-csv", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    result = run_analysis(
        risk_csv=args.risk_csv,
        membership_csv=args.membership_csv,
        mortality_csv=args.mortality_csv,
        daly_baseline_csv=args.daly_baseline_csv,
        output_dir=args.output_dir,
    )
    print(json.dumps(result["qc"], ensure_ascii=False, indent=2, default=str))
    print(f"Outputs written to {result['output_dir'].resolve()}")


if __name__ == "__main__":
    main()

