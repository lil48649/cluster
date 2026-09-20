# China GBD 2023 disease age-profile clustering — Stage 2

This repository contains the next analysis step after the finalized China 2023 K-means++ disease age-profile clustering.

## Current script

`Part3_30_69_burden_2023.R`

The script analyzes the burden of the **frozen three-cluster solution** among adults aged **30–69 years** in China in 2023. It does **not** rerun K-means++.

### Required local inputs

Place the script in the same directory as:

1. `IHME-GBD_2023_DATA-26354bec-1.csv` (or the `(1)` filename variant), containing China, Both sexes, 2023, Deaths/YLLs/YLDs/DALYs, Number and Rate; and
2. the finalized Stage 1 membership file, either:
   - `Figure1_k3_cluster_membership.csv`, or
   - `Part2_cluster_membership.csv`.

The frozen solution is checked against the finalized cluster sizes:

- Infant: 57 causes
- Adult: 71 causes
- Aging-related: 164 causes
- Total: 292 causes

### Analysis window

Eight mutually exclusive age groups are included:

30–34, 35–39, 40–44, 45–49, 50–54, 55–59, 60–64 and 65–69 years.

### Main outputs

The script creates a `Part3_30_69_2023_outputs/` directory containing:

- cluster burden summaries for Deaths, YLLs, YLDs and DALYs;
- classified-cause closure against GBD All causes;
- crude 30–69 rates per 100,000 using population denominators inferred from GBD Number/Rate pairs;
- age-specific cluster rates and cluster shares;
- YLL/DALY and YLD/DALY burden phenotype by cluster;
- top-10 causes within each cluster for all four measures;
- manuscript figures in PNG and PDF;
- an RDS bundle and `sessionInfo.txt` for reproducibility.

### Main figures

- **Figure 5:** 30–69 burden composition by cluster.
- **Figure 6:** age gradient in cluster shares for Deaths and DALYs.
- **Figure 7:** top 10 DALY causes within each cluster among ages 30–69.
- **Figure S1:** age-specific cluster rates for all four measures.
- **Figure S2:** fatal (YLL) versus non-fatal (YLD) composition of DALYs.

## Methodological rule

The disease classification is based only on the completed Stage 1 2023 all-age DALY-rate age-profile clustering. The 30–69-year analysis is a downstream public-health analysis window and must not re-estimate disease clusters.
