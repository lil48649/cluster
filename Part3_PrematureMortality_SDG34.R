#!/usr/bin/env Rscript

# ==============================================================================
# Part 3 — Premature mortality between ages 30 and 70
# Frozen NCD4 mapping and analysis order
#
# This stage follows the redesigned Stage 2.
#
# IMPORTANT ANALYSIS ORDER
#   1) First quantify cluster-specific probability of dying between ages 30
#      and 70 for ALL frozen Stage 1 causes in each of the three life-course
#      clusters (Infant / Adult / Aging-related).
#      This is the primary bridge from the life-course clustering framework
#      to premature mortality.
#
#   2) Then calculate the formal NCD4 probability of dying between ages 30
#      and 70 using the WHO/UN SDG 3.4.1 disease definition.
#
#   3) Link the frozen NCD4 causes back to the three life-course clusters to
#      characterize which life-course phenotype carries NCD4 premature
#      mortality.
#
#   4) Finally evaluate 2015 baseline, 2023 observed level, 2030 SDG target,
#      and later the business-as-usual 2030 projection.
#
# The formal SDG 3.4.1 indicator is the combined NCD4 probability. The
# cluster-specific probabilities are analogous cause-group net probabilities
# and must NOT be summed or interpreted as shares of the formal SDG indicator.
# ==============================================================================

# ------------------------------------------------------------------------------
# 0. Frozen WHO/UN SDG 3.4.1 operational definition within GBD 2023
# ------------------------------------------------------------------------------

# WHO/UN ICD-10 definition:
#   Cancer:                       C00-C97
#   Cardiovascular diseases:     I00-I99
#   Diabetes:                     E10-E14
#   Chronic respiratory disease: J30-J98
#
# The analysis retains mutually exclusive detailed GBD causes so that every
# selected cause can be linked back to the frozen Stage 1 cluster membership.
#
# Mapping version:
ncd4_mapping_version <- "GBD2023_SDG341_detailed_causes_v1_2026-09-24"

# ---- Cancer (45 detailed causes) ----------------------------------------------
#
# Excludes the GBD "Other neoplasms" non-malignant/uncertain-behaviour branch:
#   - Myelodysplastic, myeloproliferative, and other hematopoietic neoplasms
#   - Benign and in situ intestinal neoplasms
#   - Benign and in situ cervical and uterine neoplasms
#   - Other benign and in situ neoplasms
#
# Parent causes (e.g. Liver cancer, Non-Hodgkin lymphoma, Leukemia, Eye cancer,
# Non-melanoma skin cancer) are not included when mutually exclusive child
# causes are used.

cancer_causes <- c(
  "Esophageal cancer",
  "Stomach cancer",
  "Liver cancer due to hepatitis B",
  "Liver cancer due to hepatitis C",
  "Liver cancer due to alcohol use",
  "Liver cancer due to other causes",
  "Larynx cancer",
  "Tracheal, bronchus, and lung cancer",
  "Breast cancer",
  "Cervical cancer",
  "Uterine cancer",
  "Prostate cancer",
  "Colon and rectum cancer",
  "Lip and oral cavity cancer",
  "Nasopharynx cancer",
  "Other pharynx cancer",
  "Gallbladder and biliary tract cancer",
  "Pancreatic cancer",
  "Malignant skin melanoma",
  "Ovarian cancer",
  "Testicular cancer",
  "Kidney cancer",
  "Bladder cancer",
  "Brain and central nervous system cancer",
  "Thyroid cancer",
  "Mesothelioma",
  "Hodgkin lymphoma",
  "Multiple myeloma",
  "Other malignant neoplasms",
  "Acute lymphoid leukemia",
  "Chronic lymphoid leukemia",
  "Acute myeloid leukemia",
  "Chronic myeloid leukemia",
  "Non-melanoma skin cancer (squamous-cell carcinoma)",
  "Non-melanoma skin cancer (basal-cell carcinoma)",
  "Other leukemia",
  "Liver cancer due to NASH",
  "Hepatoblastoma",
  "Burkitt lymphoma",
  "Other non-Hodgkin lymphoma",
  "Retinoblastoma",
  "Other eye cancers",
  "Soft tissue and other extraosseous sarcomas",
  "Malignant neoplasm of bone and articular cartilage",
  "Neuroblastoma and other peripheral nervous cell tumors"
)

# ---- Cardiovascular diseases (18 detailed causes) -----------------------------

cardiovascular_causes <- c(
  "Rheumatic heart disease",
  "Ischemic heart disease",
  "Ischemic stroke",
  "Intracerebral hemorrhage",
  "Subarachnoid hemorrhage",
  "Hypertensive heart disease",
  "Non-rheumatic calcific aortic valve disease",
  "Non-rheumatic degenerative mitral valve disease",
  "Other non-rheumatic valve diseases",
  "Myocarditis",
  "Alcoholic cardiomyopathy",
  "Other cardiomyopathy",
  "Pulmonary Arterial Hypertension",
  "Atrial fibrillation and flutter",
  "Aortic aneurysm",
  "Lower extremity peripheral arterial disease",
  "Endocarditis",
  "Other cardiovascular and circulatory diseases"
)

# ---- Chronic respiratory diseases (8 detailed causes) -------------------------

chronic_respiratory_causes <- c(
  "Chronic obstructive pulmonary disease",
  "Silicosis",
  "Asbestosis",
  "Coal workers pneumoconiosis",
  "Other pneumoconiosis",
  "Asthma",
  "Interstitial lung disease and pulmonary sarcoidosis",
  "Other chronic respiratory diseases"
)

# ---- Diabetes (4 detailed causes) ---------------------------------------------
#
# WHO/UN defines diabetes mortality as ICD-10 E10-E14.
# In the GBD cause hierarchy, diabetes-related renal deaths are represented
# separately under CKD due to diabetes. They are therefore retained here when
# operationalising the WHO/UN diabetes definition from detailed GBD causes.

diabetes_causes <- c(
  "Diabetes mellitus type 1",
  "Diabetes mellitus type 2",
  "Chronic kidney disease due to diabetes mellitus type 1",
  "Chronic kidney disease due to diabetes mellitus type 2"
)

# ------------------------------------------------------------------------------
# 1. Construct the frozen 75-cause NCD4 mapping
# ------------------------------------------------------------------------------

ncd4_mapping <- dplyr::bind_rows(
  tibble::tibble(
    cause = cancer_causes,
    sdg_component = "Cancer",
    who_icd10_scope = "C00-C97"
  ),
  tibble::tibble(
    cause = cardiovascular_causes,
    sdg_component = "Cardiovascular diseases",
    who_icd10_scope = "I00-I99"
  ),
  tibble::tibble(
    cause = chronic_respiratory_causes,
    sdg_component = "Chronic respiratory diseases",
    who_icd10_scope = "J30-J98"
  ),
  tibble::tibble(
    cause = diabetes_causes,
    sdg_component = "Diabetes",
    who_icd10_scope = "E10-E14"
  )
) |>
  dplyr::mutate(
    mapping_version = ncd4_mapping_version
  )

# ------------------------------------------------------------------------------
# 2. Frozen mapping QC
# ------------------------------------------------------------------------------

expected_ncd4_counts <- c(
  "Cancer" = 45L,
  "Cardiovascular diseases" = 18L,
  "Chronic respiratory diseases" = 8L,
  "Diabetes" = 4L
)

observed_ncd4_counts <- ncd4_mapping |>
  dplyr::count(
    sdg_component,
    name = "n_causes"
  )

observed_named <- stats::setNames(
  observed_ncd4_counts$n_causes,
  observed_ncd4_counts$sdg_component
)

if (nrow(ncd4_mapping) != 75L) {
  stop(
    "Frozen NCD4 mapping contains ",
    nrow(ncd4_mapping),
    " causes; expected 75."
  )
}

if (anyDuplicated(ncd4_mapping$cause) > 0L) {
  duplicated_causes <- unique(
    ncd4_mapping$cause[
      duplicated(ncd4_mapping$cause)
    ]
  )

  stop(
    "Duplicate causes detected in frozen NCD4 mapping: ",
    paste(duplicated_causes, collapse = "; ")
  )
}

if (
  !all(
    observed_named[names(expected_ncd4_counts)] ==
      expected_ncd4_counts
  )
) {
  stop(
    "Frozen NCD4 component counts do not match the prespecified mapping."
  )
}

# A readable object to print/save later when the full Part 3 analysis is run.
ncd4_mapping_audit <- ncd4_mapping |>
  dplyr::count(
    sdg_component,
    who_icd10_scope,
    mapping_version,
    name = "n_detailed_causes"
  ) |>
  dplyr::arrange(
    factor(
      sdg_component,
      levels = c(
        "Cardiovascular diseases",
        "Cancer",
        "Diabetes",
        "Chronic respiratory diseases"
      )
    )
  )

print(ncd4_mapping_audit)

# ==============================================================================
# NEXT ANALYSIS BLOCKS TO BE IMPLEMENTED
# ==============================================================================
#
# A. PRIMARY: cluster-specific premature mortality using ALL frozen Stage 1
#    causes (57 Infant / 71 Adult / 164 Aging-related; 292 total).
#
#    For each year and 5-year age group:
#      M_x,cluster = sum of detailed-cause Death Rate within that cluster
#
#    Then:
#      5q_x = (5 * M_x) / (1 + 2.5 * M_x)
#      q_30_70 = 1 - product(1 - 5q_x), x = 30-34 ... 65-69
#
#    This is performed independently for Infant, Adult, and Aging-related.
#
# B. FORMAL SDG 3.4.1:
#    aggregate the frozen 75 NCD4 causes by age/year first, then calculate the
#    combined NCD4 q_30_70 using the same WHO/UN life-table transformation.
#
# C. NCD4 x life-course phenotype:
#    join the 75-cause mapping to the frozen 292-cause membership and calculate
#    NCD4 mortality by life-course cluster. This connects the SDG analysis back
#    to the Stage 1 phenotype framework.
#
# D. POLICY TARGETS:
#    2015 baseline -> 2023 observed -> 2030 SDG target (two-thirds of 2015),
#    followed later by the business-as-usual 2030 projection.
#
# ==============================================================================
