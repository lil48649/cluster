# Step 4 — Level-2 risk-factor counterfactuals

This analysis links GBD 2023 risk-attributable burden to the frozen Stage 1
life-course clusters, then evaluates each Level-2 risk independently.

For each risk, detailed-cause attributable Deaths and DALYs are summed within
the frozen `Infant`, `Adult`, and `Aging-related` clusters. The mortality
counterfactual subtracts the risk-attributable age-specific death rate from the
Stage 3 cluster death rate and recomputes q30–70 using the unchanged Stage 3
life-table formula (`q5 = 5mx / (1 + 2.5mx)`). The DALY endpoint reports attributable/avoidable
DALYs at ages 30–69 and its fraction of the Stage 2 cluster DALY baseline.

Each risk is a separate TMREL counterfactual. Results for different risks are
not additive because GBD risks overlap and may mediate one another.

## Primary R implementation

```powershell
Rscript .\Step4_RiskCounterfactual\Step4_RiskCounterfactual.R `
  --risk-csv .\IHME-GBD_2023_risk.csv `
  --membership-csv .\Part3_PrematureMortality_outputs\Part3_frozen_cluster_membership_used.csv `
  --mortality-csv .\Part3_PrematureMortality_outputs\Part3_cluster_age_specific_mortality_1990_2023.csv `
  --daly-baseline-csv .\Stage2_Redesigned_30_69_outputs\Stage2_core_DALY_summary.csv `
  --output-dir .\Step4_RiskCounterfactual_outputs
```

The R script uses base R only. It writes CSV outputs, an RDS analysis bundle,
`sessionInfo()`, a manifest, and a human-readable results report.

## Companion Python cross-check

`step4_risk_counterfactual.py` implements the same estimands and QC rules using
the Python standard library. It is retained for independent cross-checking; the
R script is the primary analysis implementation.

## Important QC choices

- The supplied risk file has no hierarchy-number column. Its Level-2 status is
  validated against the exact 20-label selection in the script.
- Risk-cause pairs absent from the export are structural zeros; the full
  risk × cluster × age × measure grid is zero-filled after aggregation.
- Raw signed GBD point estimates remain in output fields. A theoretical
  "avoidable" burden cannot be negative, so prevention endpoints are bounded
  at zero; attributable deaths/rates are additionally capped at the matching
  cluster-age baseline. Every such adjustment is explicitly flagged.
- Lower and upper bounds are checked for internal validity but are not summed
  across causes. Valid cluster-level uncertainty intervals require draw-level
  covariance, which is not available in the exported file; current results are
  therefore point estimates.
- Causes absent from the frozen 292-cause membership are excluded and listed
  in the mapping and QC outputs.

## Outputs

- `Step4_input_QC.csv`
- `Step4_number_rate_population_QC.csv`
- `Step4_risk_cause_cluster_mapping.csv`
- `Step4_baseline_cluster_2023.csv`
- `Step4_risk_cluster_age_aggregates.csv`
- `Step4_q30_70_counterfactuals.csv`
- `Step4_DALY_counterfactuals.csv`
- `Step4_risk_cluster_summary.csv`
- `Step4_key_results.md`
- `Step4_manifest.txt`
- `Step4_RiskCounterfactual_analysis_objects.rds`
- `Step4_sessionInfo.txt`

