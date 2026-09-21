# China GBD 2023 disease age-profile clustering — Stage 2

This repository continues the finalized Stage 1 K-means++ age-profile clustering analysis.

## Current analysis script

`Stage2_Figure2_onward.R`

The script **does not rerun clustering**. It reads the frozen three-cluster membership from Stage 1 and reorganizes the downstream burden analysis around the study's main public-health window, ages 30–69 years.

### Main-text figure structure

- **Figure 1** is produced by the completed Stage 1 clustering script and is not regenerated here.
- **Figure 2:** all-age age-specific mortality and YLD rates by disease cluster. This bridges the life-course clustering result to real-world mortality and disability burden.
- **Figure 3:** all-age versus ages 30–69 burden composition for Deaths, YLLs, YLDs and DALYs.
- **Figure 4:** cluster contribution across the eight five-year age groups from 30–34 to 65–69 years, focusing on Deaths and DALYs.
- **Figure 5:** top 10 DALY causes within each cluster among ages 30–69 years.

The former all-age Top-10-cause figure is retained as a supplementary figure rather than as a main-text figure.

### Required local inputs

Place the script in the same working directory as:

1. `IHME-GBD_2023_DATA-26354bec-1.csv` or `IHME-GBD_2023_DATA-26354bec-1(1).csv`; and
2. the frozen Stage 1 membership file, either `Figure1_k3_cluster_membership.csv` or `Part2_cluster_membership.csv`.

The script checks the finalized solution before proceeding:

- Infant: 57 causes
- Adult: 71 causes
- Aging-related: 164 causes
- Total: 292 causes

If those counts do not match, execution stops so that later burden analyses cannot silently change the disease classification.

### Outputs

Outputs are written to `Stage2_Figure2_onward_outputs/` and include:

- main Figures 2–5 in PNG and PDF;
- supplementary all-age Top-10 DALY causes;
- supplementary four-measure age-specific rate figure for ages 30–69;
- supplementary YLL-versus-YLD DALY composition figure;
- source-data CSVs for every main figure;
- all-age and 30–69 closure checks against GBD `All causes`;
- 30–69 cluster burden tables and cause-level burden tables;
- an RDS bundle and `sessionInfo.txt` for reproducibility.

## Methodological rule

The disease classification is defined only by the completed Stage 1 all-age 2023 DALY-rate trajectory clustering. Ages 30–69 are an independent downstream public-health analysis window; disease membership is never re-estimated within that window.


---

## Part 3: 1990–2023 trends at ages 30–69

Script:

`Part3_1990_2023_trends.R`

This analysis keeps the finalized 2023 three-cluster membership fixed and applies it retrospectively to every year from 1990 through 2023. Clustering is never rerun by year.

### Required trend files

Place these seven CSVs in the working directory:

- `IHME-GBD_2023_DATA-1990-1994.csv`
- `IHME-GBD_2023_DATA-1995-1999.csv`
- `IHME-GBD_2023_DATA-2000-2004.csv`
- `IHME-GBD_2023_DATA-2005-2009.csv`
- `IHME-GBD_2023_DATA-2010-2014.csv`
- `IHME-GBD_2023_DATA-2015-2019.csv`
- `IHME-GBD_2023_DATA-2020-2023.csv`

Each batch should use the same settings: China, Both sexes, ages 30–34 through 65–69, Deaths/YLLs/YLDs/DALYs, Number + Rate, All causes plus all 304 detailed causes, and All Population.

The script automatically looks for the frozen membership in `Stage2_Figure2_onward_outputs/Stage2_frozen_cluster_membership_used.csv` first, then falls back to the original Stage 1 membership filenames.

### Part 3 main outputs

- **Figure 6:** Death and DALY trends, showing absolute numbers and standardized rates.
- **Figure 7:** changing cluster shares of Deaths, YLLs, YLDs and DALYs from 1990 to 2023.
- **Figure 8:** three-factor Shapley decomposition of the 1990→2023 burden change into population size, age structure and age-specific rates.
- **Table 2:** 1990 vs 2023 values, percentage changes and EAPC of standardized rates.
- **Table 3:** Shapley decomposition results for all four measures.
- Cause-level DALY changes between 1990 and 2023.
- Yearly closure against GBD `All causes` and historical burden auditing for the 12 causes excluded from the 2023 clustering.

### Rate standardization

Because the downloaded data contain eight age-specific rates rather than a pre-computed 30–69 age-standardized rate, Part 3 uses direct standardization with the **GBD 2021 world population age standard**. The published GBD standard percentages for ages 30–34 through 65–69 are:

7.32171, 6.82805, 6.14735, 5.51133, 4.91312, 4.34586, 3.68223 and 2.98509.

These eight weights sum to 41.73474% of the full GBD standard population. Because the analysis is deliberately restricted to ages 30–69, the script re-normalizes these eight weights to sum to 1 before calculating the directly age-standardized 30–69 rate.
