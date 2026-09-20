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
