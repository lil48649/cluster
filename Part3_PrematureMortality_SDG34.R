#!/usr/bin/env Rscript

# ==============================================================================
# China GBD 2023 disease age-profile clusters — Part 3
# Premature mortality between exact ages 30 and 70
#
# SCIENTIFIC ORDER
#   A. PRIMARY ANALYSIS:
#      Use ALL 292 frozen Stage 1 causes to calculate cluster-specific
#      probabilities of dying between exact ages 30 and 70 for:
#        Infant / Adult / Aging-related.
#      This is the direct bridge from the life-course clustering framework to
#      premature mortality.
#
#   B. POLICY BRIDGE:
#      Calculate the formal NCD4 probability of dying between ages 30 and 70
#      using a frozen 75-cause GBD operationalisation of WHO/UN SDG 3.4.1.
#      NCD4 is calculated because it provides the 2015 baseline and 2030 policy
#      target; it is NOT treated as a separate novel descriptive module.
#
#   C. LINKAGE:
#      Link the 75 NCD4 causes back to the frozen life-course clusters to show
#      which phenotype carries NCD4 mortality.
#
#   D. POLICY ANCHOR:
#      Calculate the 2015 NCD4 baseline, 2023 observed value and the 2030 SDG
#      target (= two-thirds of the 2015 probability).
#
# IMPORTANT INTERPRETATION
#   - The three cluster-specific probabilities are cause-group NET probabilities
#     calculated with the same life-table transformation used by SDG 3.4.1.
#   - They must NOT be added together and must NOT be interpreted as shares of
#     the formal SDG 3.4.1 probability because the probability transformation
#     is nonlinear.
#   - When a composition is needed, this script uses Deaths Number, not ratios
#     of the cluster-specific q30-70 values.
#
# REQUIRED LOCAL INPUTS
#   Seven GBD year-batch CSV files covering:
#     1990-1994, 1995-1999, 2000-2004, 2005-2009,
#     2010-2014, 2015-2019, 2020-2023
#
#   Preferred names:
#     IHME-GBD_2023_DATA-1990-1994.csv
#     IHME-GBD_2023_DATA-1995-1999.csv
#     IHME-GBD_2023_DATA-2000-2004.csv
#     IHME-GBD_2023_DATA-2005-2009.csv
#     IHME-GBD_2023_DATA-2010-2014.csv
#     IHME-GBD_2023_DATA-2015-2019.csv
#     IHME-GBD_2023_DATA-2020-2023.csv
#
#   Frozen cluster membership:
#     Stage2_frozen_cluster_membership_used.csv
#     OR Figure1_k3_cluster_membership.csv
#     OR Part2_cluster_membership.csv
#
# Data used from the GBD files:
#   Location = China
#   Sex = Both
#   Measure = Deaths
#   Metrics = Number and Rate
#   Ages = 30-34 ... 65-69 years
#   Years = 1990-2023
#
# OUTPUT DIRECTORY
#   Part3_PrematureMortality_outputs/
# ==============================================================================


# ------------------------------------------------------------------------------
# 0. Packages and global configuration
# ------------------------------------------------------------------------------

required_packages <- c(
  "readr", "dplyr", "tidyr", "ggplot2", "scales", "tibble"
)

missing_packages <- required_packages[
  !vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)
]

if (length(missing_packages) > 0L) {
  stop(
    "Missing R packages: ",
    paste(missing_packages, collapse = ", "),
    "\nInstall them first, e.g. install.packages(c(",
    paste(sprintf('"%s"', missing_packages), collapse = ", "),
    "))"
  )
}

output_dir <- "Part3_PrematureMortality_outputs"
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

years_expected <- 1990:2023

age_30_69 <- c(
  "30-34 years", "35-39 years", "40-44 years", "45-49 years",
  "50-54 years", "55-59 years", "60-64 years", "65-69 years"
)

age_start <- c(30L, 35L, 40L, 45L, 50L, 55L, 60L, 65L)

cluster_order <- c("Infant", "Adult", "Aging-related")

cluster_colors <- c(
  "Infant" = "#2CA02C",
  "Adult" = "#2878B5",
  "Aging-related" = "#E31A1C"
)

expected_cluster_counts <- c(
  "Infant" = 57L,
  "Adult" = 71L,
  "Aging-related" = 164L
)

expected_n_clustered_causes <- 292L
expected_n_detailed_causes_full <- 304L
expected_n_detailed_causes_age30_69_download <- 303L

# Sudden infant death syndrome belongs to the frozen 292-cause solution, but
# GBD omits it entirely from an age-restricted 30-69 download because there are
# no applicable age cells in this window.
expected_frozen_causes_absent_from_age30_69_download <- c(
  "Sudden infant death syndrome"
)

membership_file_candidates <- c(
  "Stage2_frozen_cluster_membership_used.csv",
  file.path(
    "Stage2_Redesigned_30_69_outputs",
    "Stage2_frozen_cluster_membership_used.csv"
  ),
  file.path(
    "Stage2_Figure2_onward_outputs",
    "Stage2_frozen_cluster_membership_used.csv"
  ),
  "Figure1_k3_cluster_membership.csv",
  "Part2_cluster_membership.csv"
)


# ------------------------------------------------------------------------------
# 1. Helpers
# ------------------------------------------------------------------------------

first_existing_file <- function(candidates, label) {
  hit <- candidates[file.exists(candidates)]

  if (length(hit) == 0L) {
    stop(
      label,
      " not found. Looked for:\n  ",
      paste(candidates, collapse = "\n  ")
    )
  }

  hit[[1L]]
}


resolve_batch_file <- function(start_year, end_year) {
  preferred <- c(
    sprintf(
      "IHME-GBD_2023_DATA-%d-%d.csv",
      start_year,
      end_year
    ),
    sprintf(
      "GBD_China_%d_%d.csv",
      start_year,
      end_year
    ),
    sprintf(
      "GBD_China_%d-%d.csv",
      start_year,
      end_year
    )
  )

  preferred_hit <- preferred[file.exists(preferred)]

  if (length(preferred_hit) == 1L) {
    return(preferred_hit[[1L]])
  }

  if (length(preferred_hit) > 1L) {
    stop(
      "More than one preferred file exists for ",
      start_year, "-", end_year, ": ",
      paste(preferred_hit, collapse = "; ")
    )
  }

  csv_files <- list.files(
    path = ".",
    pattern = "\\.csv$",
    full.names = FALSE
  )

  generic_hit <- csv_files[
    grepl(as.character(start_year), csv_files, fixed = TRUE) &
      grepl(as.character(end_year), csv_files, fixed = TRUE)
  ]

  if (length(generic_hit) != 1L) {
    stop(
      "Could not uniquely identify the ",
      start_year, "-", end_year,
      " GBD batch file. Candidates found: ",
      ifelse(
        length(generic_hit) == 0L,
        "none",
        paste(generic_hit, collapse = "; ")
      )
    )
  }

  generic_hit[[1L]]
}


safe_ratio <- function(num, den) {
  n <- max(length(num), length(den))
  num <- rep_len(num, n)
  den <- rep_len(den, n)

  out <- num / den
  out[!is.finite(den) | den == 0] <- NA_real_
  out
}


relative_change_percent <- function(old, new) {
  100 * safe_ratio(new - old, old)
}


rate_to_5q <- function(rate_per_100k) {
  mx <- rate_per_100k / 100000

  if (any(!is.finite(mx))) {
    stop("Non-finite mortality rate detected in q30-70 calculation.")
  }

  if (any(mx < 0)) {
    stop("Negative mortality rate detected in q30-70 calculation.")
  }

  (5 * mx) / (1 + 2.5 * mx)
}


q30_70_from_5year_rates <- function(rate_per_100k) {
  if (length(rate_per_100k) != 8L) {
    stop(
      "q30-70 requires exactly eight 5-year age-specific mortality rates."
    )
  }

  q5 <- rate_to_5q(rate_per_100k)

  1 - prod(1 - q5)
}


save_plot_pair <- function(plot_object, stem, width, height) {
  ggplot2::ggsave(
    filename = file.path(
      output_dir,
      paste0(stem, ".png")
    ),
    plot = plot_object,
    width = width,
    height = height,
    units = "in",
    dpi = 300,
    bg = "white"
  )

  ggplot2::ggsave(
    filename = file.path(
      output_dir,
      paste0(stem, ".pdf")
    ),
    plot = plot_object,
    width = width,
    height = height,
    units = "in",
    bg = "white"
  )
}


# ------------------------------------------------------------------------------
# 2. Frozen 75-cause NCD4 mapping
# ------------------------------------------------------------------------------

# WHO/UN ICD-10 definition:
#   Cancer:                       C00-C97
#   Cardiovascular diseases:     I00-I99
#   Diabetes:                     E10-E14
#   Chronic respiratory disease: J30-J98
#
# This study operationalises those four categories within the mutually
# exclusive detailed GBD 2023 cause hierarchy so that the same disease causes
# can also be linked to the frozen life-course cluster membership.

ncd4_mapping_version <-
  "GBD2023_SDG341_detailed_causes_v1_2026-09-24"


# ---- Cancer: 45 detailed causes -----------------------------------------------
#
# Excluded from the GBD Neoplasms parent:
#   Myelodysplastic, myeloproliferative, and other hematopoietic neoplasms
#   Benign and in situ intestinal neoplasms
#   Benign and in situ cervical and uterine neoplasms
#   Other benign and in situ neoplasms
#
# Parent causes are not mixed with mutually exclusive child causes.

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


# ---- Cardiovascular diseases: 18 detailed causes ------------------------------

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


# ---- Chronic respiratory diseases: 8 detailed causes --------------------------

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


# ---- Diabetes: 4 detailed causes ----------------------------------------------
#
# WHO/UN uses ICD-10 E10-E14. In the detailed GBD hierarchy, diabetes-related
# renal deaths are represented separately under CKD due to diabetes; therefore
# both diabetic CKD leaf causes are retained in this operational definition.

diabetes_causes <- c(
  "Diabetes mellitus type 1",
  "Diabetes mellitus type 2",
  "Chronic kidney disease due to diabetes mellitus type 1",
  "Chronic kidney disease due to diabetes mellitus type 2"
)


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

observed_ncd4_named <- stats::setNames(
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
    "Duplicate causes detected in the frozen NCD4 mapping: ",
    paste(duplicated_causes, collapse = "; ")
  )
}

if (
  !all(
    observed_ncd4_named[
      names(expected_ncd4_counts)
    ] ==
      expected_ncd4_counts
  )
) {
  stop(
    "Frozen NCD4 component counts do not match the prespecified ",
    "45/18/8/4 mapping."
  )
}


# ------------------------------------------------------------------------------
# 3. Resolve the seven historical GBD files
# ------------------------------------------------------------------------------

batch_periods <- tibble::tribble(
  ~start_year, ~end_year,
  1990L, 1994L,
  1995L, 1999L,
  2000L, 2004L,
  2005L, 2009L,
  2010L, 2014L,
  2015L, 2019L,
  2020L, 2023L
) |>
  dplyr::rowwise() |>
  dplyr::mutate(
    source_file = resolve_batch_file(
      start_year,
      end_year
    )
  ) |>
  dplyr::ungroup()

input_files <- batch_periods$source_file

if (anyDuplicated(input_files) > 0L) {
  stop(
    "The same CSV file was matched to more than one year batch."
  )
}

membership_file <- first_existing_file(
  membership_file_candidates,
  "Frozen Stage 1/2 cluster membership"
)

message("Frozen membership: ", membership_file)
message(
  "Historical GBD files:\n  ",
  paste(input_files, collapse = "\n  ")
)
message(
  "Output directory: ",
  normalizePath(output_dir, mustWork = FALSE)
)


# ------------------------------------------------------------------------------
# 4. Read and validate the frozen 292-cause membership
# ------------------------------------------------------------------------------

membership_raw <- readr::read_csv(
  membership_file,
  show_col_types = FALSE
)

if (
  "disease" %in% names(membership_raw) &&
    !"cause" %in% names(membership_raw)
) {
  membership_raw <- dplyr::rename(
    membership_raw,
    cause = disease
  )
}

if (
  !all(
    c("cause", "cluster_name") %in%
      names(membership_raw)
  )
) {
  stop(
    "Membership file must contain cause and cluster_name columns."
  )
}

cluster_membership <- membership_raw |>
  dplyr::transmute(
    cause = as.character(cause),
    cluster_name = as.character(cluster_name)
  ) |>
  dplyr::distinct(
    cause,
    .keep_all = TRUE
  ) |>
  dplyr::mutate(
    cluster_name = factor(
      cluster_name,
      levels = cluster_order
    )
  ) |>
  dplyr::arrange(
    cluster_name,
    cause
  )

if (nrow(cluster_membership) != expected_n_clustered_causes) {
  stop(
    "Frozen membership contains ",
    nrow(cluster_membership),
    " causes; expected ",
    expected_n_clustered_causes,
    "."
  )
}

if (
  any(is.na(cluster_membership$cluster_name))
) {
  stop(
    "Unexpected cluster labels were found in the frozen membership."
  )
}

if (anyDuplicated(cluster_membership$cause) > 0L) {
  stop(
    "Duplicate causes were found in the frozen cluster membership."
  )
}

membership_counts <- cluster_membership |>
  dplyr::count(
    cluster_name,
    name = "n"
  ) |>
  dplyr::mutate(
    cluster_name = as.character(cluster_name)
  )

observed_cluster_counts <- stats::setNames(
  rep(0L, length(cluster_order)),
  cluster_order
)

observed_cluster_counts[
  membership_counts$cluster_name
] <- membership_counts$n

if (
  !all(
    observed_cluster_counts[cluster_order] ==
      expected_cluster_counts[cluster_order]
  )
) {
  stop(
    "Frozen cluster sizes do not match the finalized solution. Observed: ",
    paste(
      paste0(
        cluster_order,
        "=",
        observed_cluster_counts[cluster_order]
      ),
      collapse = "; "
    )
  )
}

readr::write_csv(
  cluster_membership,
  file.path(
    output_dir,
    "Part3_frozen_cluster_membership_used.csv"
  )
)


# ------------------------------------------------------------------------------
# 5. Read the seven historical batches
# ------------------------------------------------------------------------------

required_columns <- c(
  "population_group", "measure", "location", "sex", "age",
  "cause", "metric", "year", "val", "upper", "lower"
)

death_batch_list <- vector(
  "list",
  nrow(batch_periods)
)

batch_cause_list <- vector(
  "list",
  nrow(batch_periods)
)

batch_audit_list <- vector(
  "list",
  nrow(batch_periods)
)

for (i in seq_len(nrow(batch_periods))) {
  source_file <- batch_periods$source_file[i]
  start_year <- batch_periods$start_year[i]
  end_year <- batch_periods$end_year[i]
  expected_years <- start_year:end_year

  message("Reading: ", source_file)

  dat <- readr::read_csv(
    source_file,
    show_col_types = FALSE
  )

  missing_cols <- setdiff(
    required_columns,
    names(dat)
  )

  if (length(missing_cols) > 0L) {
    stop(
      source_file,
      " is missing columns: ",
      paste(missing_cols, collapse = ", ")
    )
  }

  relevant_all_measures <- dat |>
    dplyr::filter(
      population_group == "All Population",
      location == "China",
      sex == "Both",
      year %in% expected_years,
      age %in% age_30_69
    )

  years_found <- sort(
    unique(relevant_all_measures$year)
  )

  if (
    !identical(
      as.integer(years_found),
      as.integer(expected_years)
    )
  ) {
    stop(
      source_file,
      " does not contain exactly the expected years. Found: ",
      paste(years_found, collapse = ", "),
      "; expected: ",
      paste(expected_years, collapse = ", ")
    )
  }

  batch_cause_list[[i]] <-
    relevant_all_measures |>
      dplyr::filter(
        cause != "All causes"
      ) |>
      dplyr::distinct(cause) |>
      dplyr::mutate(
        source_file = source_file
      )

  death_dat <- relevant_all_measures |>
    dplyr::filter(
      measure == "Deaths",
      metric %in% c("Number", "Rate")
    ) |>
    dplyr::select(
      year,
      age,
      cause,
      metric,
      val,
      upper,
      lower
    ) |>
    dplyr::mutate(
      source_file = source_file
    )

  duplicate_n <- death_dat |>
    dplyr::count(
      year,
      age,
      cause,
      metric,
      name = "n"
    ) |>
    dplyr::filter(
      n > 1L
    ) |>
    nrow()

  if (duplicate_n > 0L) {
    stop(
      source_file,
      " contains duplicated Deaths year-age-cause-metric cells."
    )
  }

  batch_audit_list[[i]] <- tibble::tibble(
    source_file = source_file,
    expected_start_year = start_year,
    expected_end_year = end_year,
    observed_years = dplyr::n_distinct(
      relevant_all_measures$year
    ),
    detailed_causes_in_full_export =
      dplyr::n_distinct(
        relevant_all_measures$cause[
          relevant_all_measures$cause !=
            "All causes"
        ]
      ),
    causes_with_death_rows =
      dplyr::n_distinct(
        death_dat$cause[
          death_dat$cause !=
            "All causes"
        ]
      ),
    death_rows = nrow(death_dat),
    duplicated_death_cells = duplicate_n
  )

  death_batch_list[[i]] <- death_dat

  rm(
    dat,
    relevant_all_measures,
    death_dat
  )

  invisible(gc())
}

death_observed <- dplyr::bind_rows(
  death_batch_list
)

source_cause_universe <- dplyr::bind_rows(
  batch_cause_list
) |>
  dplyr::distinct(cause) |>
  dplyr::arrange(cause)

batch_audit <- dplyr::bind_rows(
  batch_audit_list
)

readr::write_csv(
  batch_audit,
  file.path(
    output_dir,
    "Part3_input_batch_audit.csv"
  )
)


# ------------------------------------------------------------------------------
# 6. Combined-data and disease-universe QC
# ------------------------------------------------------------------------------

if (
  !identical(
    as.integer(
      sort(unique(death_observed$year))
    ),
    as.integer(years_expected)
  )
) {
  stop(
    "Combined historical files do not cover every year from 1990 through 2023."
  )
}

if (
  !all(
    age_30_69 %in%
      unique(death_observed$age)
  )
) {
  stop(
    "Missing age groups: ",
    paste(
      setdiff(
        age_30_69,
        unique(death_observed$age)
      ),
      collapse = ", "
    )
  )
}

if (
  nrow(source_cause_universe) !=
    expected_n_detailed_causes_age30_69_download
) {
  stop(
    "Combined age-30-69 source data contain ",
    nrow(source_cause_universe),
    " detailed causes; expected ",
    expected_n_detailed_causes_age30_69_download,
    ". The full Stage 1 universe contains ",
    expected_n_detailed_causes_full,
    " causes and the expected age-window omission is Sudden infant death syndrome."
  )
}

missing_frozen_causes_from_source <- cluster_membership |>
  dplyr::mutate(
    cluster_name = as.character(cluster_name)
  ) |>
  dplyr::anti_join(
    source_cause_universe,
    by = "cause"
  ) |>
  dplyr::arrange(cause)

if (
  !identical(
    sort(
      missing_frozen_causes_from_source$cause
    ),
    sort(
      expected_frozen_causes_absent_from_age30_69_download
    )
  )
) {
  stop(
    "Unexpected frozen causes are absent from the 30-69 source data. Found: ",
    paste(
      missing_frozen_causes_from_source$cause,
      collapse = "; "
    ),
    ". Expected only: ",
    paste(
      expected_frozen_causes_absent_from_age30_69_download,
      collapse = "; "
    )
  )
}

readr::write_csv(
  missing_frozen_causes_from_source,
  file.path(
    output_dir,
    "Part3_frozen_causes_absent_from_age30_69_source.csv"
  )
)

missing_ncd4_from_source <- ncd4_mapping |>
  dplyr::anti_join(
    source_cause_universe,
    by = "cause"
  )

if (nrow(missing_ncd4_from_source) > 0L) {
  stop(
    "Frozen NCD4 causes are missing from the GBD source data: ",
    paste(
      missing_ncd4_from_source$cause,
      collapse = "; "
    )
  )
}

missing_ncd4_from_membership <- ncd4_mapping |>
  dplyr::anti_join(
    cluster_membership |>
      dplyr::select(cause),
    by = "cause"
  )

if (nrow(missing_ncd4_from_membership) > 0L) {
  stop(
    "Frozen NCD4 causes cannot be linked to the 292-cause membership: ",
    paste(
      missing_ncd4_from_membership$cause,
      collapse = "; "
    )
  )
}


# ------------------------------------------------------------------------------
# 7. Build complete Deaths Number/Rate grids
# ------------------------------------------------------------------------------

death_pairs_observed <- death_observed |>
  dplyr::select(
    year,
    age,
    cause,
    metric,
    val
  ) |>
  tidyr::pivot_wider(
    names_from = metric,
    values_from = val
  )

# All-causes rows must be complete and are never zero-filled.
all_causes_deaths <- death_pairs_observed |>
  dplyr::filter(
    cause == "All causes"
  ) |>
  dplyr::mutate(
    age = factor(
      age,
      levels = age_30_69,
      ordered = TRUE
    ),
    age_index = as.integer(age),
    age_start = age_start[age_index]
  ) |>
  dplyr::arrange(
    year,
    age_index
  )

expected_all_causes_rows <-
  length(years_expected) *
  length(age_30_69)

if (
  nrow(all_causes_deaths) !=
    expected_all_causes_rows
) {
  stop(
    "All-causes Deaths grid is incomplete. Found ",
    nrow(all_causes_deaths),
    " year-age rows; expected ",
    expected_all_causes_rows,
    "."
  )
}

if (
  any(!is.finite(all_causes_deaths$Number)) ||
    any(!is.finite(all_causes_deaths$Rate))
) {
  stop(
    "All-causes Deaths contain missing or non-finite Number/Rate values."
  )
}

# Complete grid for all 292 frozen causes.
expected_classified_death_grid <- tidyr::expand_grid(
  year = years_expected,
  age = age_30_69,
  cause = cluster_membership$cause
)

classified_deaths <- expected_classified_death_grid |>
  dplyr::left_join(
    death_pairs_observed |>
      dplyr::filter(
        cause != "All causes"
      ),
    by = c(
      "year",
      "age",
      "cause"
    )
  ) |>
  dplyr::mutate(
    number_missing = is.na(Number),
    rate_missing = is.na(Rate),
    both_missing =
      number_missing & rate_missing,
    one_sided_missing =
      xor(
        number_missing,
        rate_missing
      )
  )

one_sided_missing <- classified_deaths |>
  dplyr::filter(
    one_sided_missing
  )

if (nrow(one_sided_missing) > 0L) {
  readr::write_csv(
    one_sided_missing,
    file.path(
      output_dir,
      "QC_one_sided_missing_death_cells.csv"
    )
  )

  stop(
    "At least one cause-year-age cell has Number without Rate or Rate without Number. ",
    "Review QC_one_sided_missing_death_cells.csv."
  )
}

missing_death_cells <- classified_deaths |>
  dplyr::filter(
    both_missing
  ) |>
  dplyr::select(
    year,
    age,
    cause
  ) |>
  dplyr::left_join(
    cluster_membership |>
      dplyr::mutate(
        cluster_name =
          as.character(cluster_name)
      ),
    by = "cause"
  ) |>
  dplyr::arrange(
    cause,
    year,
    age
  )

readr::write_csv(
  missing_death_cells,
  file.path(
    output_dir,
    "QC_death_cells_omitted_by_GBD_filled_zero.csv"
  )
)

missing_death_summary <- missing_death_cells |>
  dplyr::count(
    cause,
    cluster_name,
    name = "omitted_year_age_cells"
  ) |>
  dplyr::arrange(
    dplyr::desc(omitted_year_age_cells),
    cause
  )

readr::write_csv(
  missing_death_summary,
  file.path(
    output_dir,
    "QC_death_cells_omitted_by_GBD_summary.csv"
  )
)

classified_deaths <- classified_deaths |>
  dplyr::mutate(
    Number = tidyr::replace_na(
      Number,
      0
    ),
    Rate = tidyr::replace_na(
      Rate,
      0
    )
  ) |>
  dplyr::select(
    year,
    age,
    cause,
    Number,
    Rate
  ) |>
  dplyr::left_join(
    cluster_membership |>
      dplyr::mutate(
        cluster_name =
          as.character(cluster_name)
      ),
    by = "cause"
  ) |>
  dplyr::mutate(
    cluster_name = factor(
      cluster_name,
      levels = cluster_order
    ),
    age = factor(
      age,
      levels = age_30_69,
      ordered = TRUE
    ),
    age_index = as.integer(age),
    age_start = age_start[age_index]
  ) |>
  dplyr::arrange(
    year,
    cluster_name,
    age_index,
    cause
  )

if (
  nrow(classified_deaths) !=
    length(years_expected) *
      length(age_30_69) *
      expected_n_clustered_causes
) {
  stop(
    "Completed 292-cause Deaths grid has an unexpected number of rows."
  )
}

if (
  any(classified_deaths$Number < 0) ||
    any(classified_deaths$Rate < 0)
) {
  stop(
    "Negative death Number or Rate detected."
  )
}


# ------------------------------------------------------------------------------
# 8. PRIMARY ANALYSIS — cluster-specific probability of dying ages 30-70
# ------------------------------------------------------------------------------

cluster_age_mortality <- classified_deaths |>
  dplyr::group_by(
    year,
    cluster_name,
    age,
    age_index,
    age_start
  ) |>
  dplyr::summarise(
    death_number =
      sum(Number, na.rm = TRUE),
    death_rate_per_100k =
      sum(Rate, na.rm = TRUE),
    .groups = "drop"
  ) |>
  dplyr::mutate(
    mx =
      death_rate_per_100k /
        100000,
    q5 =
      (5 * mx) /
        (1 + 2.5 * mx)
  ) |>
  dplyr::arrange(
    year,
    cluster_name,
    age_index
  )

if (
  any(!is.finite(cluster_age_mortality$q5)) ||
    any(
      cluster_age_mortality$q5 < 0 |
        cluster_age_mortality$q5 >= 1
    )
) {
  stop(
    "Invalid 5-year death probability detected for a life-course cluster."
  )
}

cluster_q30_70 <- cluster_age_mortality |>
  dplyr::group_by(
    year,
    cluster_name
  ) |>
  dplyr::summarise(
    n_age_groups =
      dplyr::n(),
    q30_70 =
      1 - prod(1 - q5),
    probability_percent =
      100 * q30_70,
    deaths_age30_69 =
      sum(death_number),
    .groups = "drop"
  ) |>
  dplyr::mutate(
    cluster_name = factor(
      cluster_name,
      levels = cluster_order
    )
  ) |>
  dplyr::arrange(
    year,
    cluster_name
  )

if (
  any(
    cluster_q30_70$n_age_groups !=
      length(age_30_69)
  )
) {
  stop(
    "Cluster q30-70 calculation did not use exactly eight age groups."
  )
}

if (
  any(
    !is.finite(
      cluster_q30_70$q30_70
    )
  ) ||
    any(
      cluster_q30_70$q30_70 < 0 |
        cluster_q30_70$q30_70 >= 1
    )
) {
  stop(
    "Invalid cluster-specific q30-70 detected."
  )
}

cluster_q30_70 <- cluster_q30_70 |>
  dplyr::group_by(year) |>
  dplyr::mutate(
    share_of_classified_deaths_age30_69 =
      safe_ratio(
        deaths_age30_69,
        sum(deaths_age30_69)
      )
  ) |>
  dplyr::ungroup()

readr::write_csv(
  cluster_age_mortality,
  file.path(
    output_dir,
    "Part3_cluster_age_specific_mortality_1990_2023.csv"
  )
)

readr::write_csv(
  cluster_q30_70,
  file.path(
    output_dir,
    "Figure4_cluster_q30_70_source_data.csv"
  )
)


# ------------------------------------------------------------------------------
# 9. Figure 4 — 1990-2023 cluster-specific premature mortality
# ------------------------------------------------------------------------------

figure4_label_data <- cluster_q30_70 |>
  dplyr::filter(
    year == 2023
  ) |>
  dplyr::mutate(
    label = paste0(
      cluster_name,
      ": ",
      scales::percent(
        q30_70,
        accuracy = 0.1
      )
    )
  )

p4 <- ggplot2::ggplot(
  cluster_q30_70,
  ggplot2::aes(
    x = year,
    y = q30_70,
    color = cluster_name,
    group = cluster_name
  )
) +
  ggplot2::geom_line(
    linewidth = 1.1,
    lineend = "round"
  ) +
  ggplot2::geom_point(
    data = figure4_label_data,
    size = 2.5
  ) +
  ggplot2::scale_color_manual(
    values = cluster_colors,
    breaks = cluster_order,
    drop = FALSE
  ) +
  ggplot2::scale_y_continuous(
    labels = scales::percent_format(
      accuracy = 1
    ),
    expand = ggplot2::expansion(
      mult = c(0.02, 0.10)
    )
  ) +
  ggplot2::scale_x_continuous(
    breaks = seq(
      1990,
      2020,
      by = 5
    ),
    minor_breaks = NULL
  ) +
  ggplot2::labs(
    title =
      "Probability of dying between ages 30 and 70 by life-course disease cluster",
    subtitle =
      "China, Both sexes, 1990–2023; frozen 2023 cluster membership",
    x = NULL,
    y = "Probability of dying between ages 30 and 70",
    color = "Disease cluster",
    caption = paste0(
      "Cause-group net probabilities were calculated from eight 5-year ",
      "age-specific mortality rates using the WHO/UN life-table transformation. ",
      "The three probabilities are not additive."
    )
  ) +
  ggplot2::theme_bw(
    base_size = 12.5
  ) +
  ggplot2::theme(
    legend.position = "bottom",
    panel.grid.minor =
      ggplot2::element_blank(),
    panel.grid.major =
      ggplot2::element_line(
        color = "grey92",
        linewidth = 0.4
      ),
    plot.title =
      ggplot2::element_text(
        face = "bold",
        size = 15
      ),
    plot.subtitle =
      ggplot2::element_text(
        color = "grey35"
      ),
    plot.caption =
      ggplot2::element_text(
        size = 8,
        color = "grey40",
        hjust = 0
      )
  )

save_plot_pair(
  p4,
  "Figure4_cluster_q30_70_1990_2023",
  width = 10.5,
  height = 6.5
)


# ------------------------------------------------------------------------------
# 10. Table 2 — key-year cluster premature-mortality results
# ------------------------------------------------------------------------------

cluster_key_years <- cluster_q30_70 |>
  dplyr::filter(
    year %in% c(
      1990L,
      2015L,
      2023L
    )
  ) |>
  dplyr::select(
    cluster_name,
    year,
    q30_70,
    probability_percent,
    deaths_age30_69,
    share_of_classified_deaths_age30_69
  )

cluster_key_years_wide <- cluster_key_years |>
  dplyr::select(
    cluster_name,
    year,
    q30_70,
    deaths_age30_69
  ) |>
  tidyr::pivot_wider(
    names_from = year,
    values_from = c(
      q30_70,
      deaths_age30_69
    ),
    names_sep = "_"
  ) |>
  dplyr::mutate(
    q30_70_absolute_change_1990_2023 =
      q30_70_2023 -
        q30_70_1990,
    q30_70_relative_change_percent_1990_2023 =
      relative_change_percent(
        q30_70_1990,
        q30_70_2023
      ),
    q30_70_absolute_change_2015_2023 =
      q30_70_2023 -
        q30_70_2015,
    q30_70_relative_change_percent_2015_2023 =
      relative_change_percent(
        q30_70_2015,
        q30_70_2023
      )
  )

readr::write_csv(
  cluster_key_years,
  file.path(
    output_dir,
    "Table2_cluster_premature_mortality_key_years_long.csv"
  )
)

readr::write_csv(
  cluster_key_years_wide,
  file.path(
    output_dir,
    "Table2_cluster_premature_mortality_key_years.csv"
  )
)


# ------------------------------------------------------------------------------
# 11. Closure QC against GBD All causes
# ------------------------------------------------------------------------------

classified_all_cluster_by_age <- classified_deaths |>
  dplyr::group_by(
    year,
    age,
    age_index
  ) |>
  dplyr::summarise(
    classified_deaths_number =
      sum(Number),
    classified_death_rate_per_100k =
      sum(Rate),
    .groups = "drop"
  )

closure_by_year_age <- classified_all_cluster_by_age |>
  dplyr::left_join(
    all_causes_deaths |>
      dplyr::select(
        year,
        age,
        all_causes_deaths_number = Number,
        all_causes_death_rate_per_100k = Rate
      ),
    by = c(
      "year",
      "age"
    )
  ) |>
  dplyr::mutate(
    number_closure_ratio =
      safe_ratio(
        classified_deaths_number,
        all_causes_deaths_number
      ),
    rate_closure_ratio =
      safe_ratio(
        classified_death_rate_per_100k,
        all_causes_death_rate_per_100k
      )
  ) |>
  dplyr::arrange(
    year,
    age_index
  )

if (
  any(
    closure_by_year_age$number_closure_ratio >
      1.01,
    na.rm = TRUE
  ) ||
    any(
      closure_by_year_age$rate_closure_ratio >
        1.01,
      na.rm = TRUE
    )
) {
  stop(
    "The classified 292-cause death burden exceeds GBD All causes by >1% ",
    "in at least one year-age cell."
  )
}

closure_by_year <- closure_by_year_age |>
  dplyr::group_by(year) |>
  dplyr::summarise(
    min_number_closure =
      min(
        number_closure_ratio,
        na.rm = TRUE
      ),
    max_number_closure =
      max(
        number_closure_ratio,
        na.rm = TRUE
      ),
    min_rate_closure =
      min(
        rate_closure_ratio,
        na.rm = TRUE
      ),
    max_rate_closure =
      max(
        rate_closure_ratio,
        na.rm = TRUE
      ),
    .groups = "drop"
  )

readr::write_csv(
  closure_by_year_age,
  file.path(
    output_dir,
    "QC_cluster_death_closure_by_year_age.csv"
  )
)

readr::write_csv(
  closure_by_year,
  file.path(
    output_dir,
    "QC_cluster_death_closure_by_year.csv"
  )
)


# ------------------------------------------------------------------------------
# 12. Frozen 75-cause mapping linked to life-course clusters
# ------------------------------------------------------------------------------

ncd4_mapping_with_cluster <- ncd4_mapping |>
  dplyr::left_join(
    cluster_membership |>
      dplyr::mutate(
        cluster_name =
          as.character(cluster_name)
      ),
    by = "cause"
  ) |>
  dplyr::mutate(
    cluster_name = factor(
      cluster_name,
      levels = cluster_order
    )
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
    ),
    cluster_name,
    cause
  )

if (
  any(
    is.na(
      ncd4_mapping_with_cluster$cluster_name
    )
  )
) {
  stop(
    "At least one frozen NCD4 cause did not map to a life-course cluster."
  )
}

ncd4_mapping_audit <- ncd4_mapping_with_cluster |>
  dplyr::count(
    sdg_component,
    who_icd10_scope,
    cluster_name,
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
    ),
    cluster_name
  )

readr::write_csv(
  ncd4_mapping_with_cluster,
  file.path(
    output_dir,
    "NCD4_frozen_75_cause_mapping.csv"
  )
)

readr::write_csv(
  ncd4_mapping_audit,
  file.path(
    output_dir,
    "NCD4_frozen_75_cause_mapping_audit.csv"
  )
)


# ------------------------------------------------------------------------------
# 13. POLICY BRIDGE — formal combined NCD4 q30-70
# ------------------------------------------------------------------------------

ncd4_deaths <- classified_deaths |>
  dplyr::inner_join(
    ncd4_mapping |>
      dplyr::select(
        cause,
        sdg_component,
        who_icd10_scope
      ),
    by = "cause"
  )

if (
  dplyr::n_distinct(
    ncd4_deaths$cause
  ) != 75L
) {
  stop(
    "The completed NCD4 mortality grid does not contain all 75 frozen causes."
  )
}

ncd4_age_mortality <- ncd4_deaths |>
  dplyr::group_by(
    year,
    age,
    age_index,
    age_start
  ) |>
  dplyr::summarise(
    death_number =
      sum(Number),
    death_rate_per_100k =
      sum(Rate),
    .groups = "drop"
  ) |>
  dplyr::mutate(
    mx =
      death_rate_per_100k /
        100000,
    q5 =
      (5 * mx) /
        (1 + 2.5 * mx)
  ) |>
  dplyr::arrange(
    year,
    age_index
  )

ncd4_q30_70 <- ncd4_age_mortality |>
  dplyr::group_by(year) |>
  dplyr::summarise(
    n_age_groups =
      dplyr::n(),
    q30_70 =
      1 - prod(1 - q5),
    probability_percent =
      100 * q30_70,
    deaths_age30_69 =
      sum(death_number),
    .groups = "drop"
  ) |>
  dplyr::arrange(year)

if (
  any(
    ncd4_q30_70$n_age_groups !=
      length(age_30_69)
  )
) {
  stop(
    "Formal NCD4 q30-70 calculation did not use exactly eight age groups."
  )
}

if (
  any(
    !is.finite(
      ncd4_q30_70$q30_70
    )
  ) ||
    any(
      ncd4_q30_70$q30_70 < 0 |
        ncd4_q30_70$q30_70 >= 1
    )
) {
  stop(
    "Invalid formal NCD4 q30-70 detected."
  )
}

readr::write_csv(
  ncd4_age_mortality,
  file.path(
    output_dir,
    "NCD4_age_specific_mortality_1990_2023.csv"
  )
)

readr::write_csv(
  ncd4_q30_70,
  file.path(
    output_dir,
    "NCD4_q30_70_1990_2023.csv"
  )
)


# ------------------------------------------------------------------------------
# 14. Supporting NCD4 component-specific probabilities
# ------------------------------------------------------------------------------

ncd4_component_age_mortality <- ncd4_deaths |>
  dplyr::group_by(
    year,
    sdg_component,
    age,
    age_index,
    age_start
  ) |>
  dplyr::summarise(
    death_number =
      sum(Number),
    death_rate_per_100k =
      sum(Rate),
    .groups = "drop"
  ) |>
  dplyr::mutate(
    mx =
      death_rate_per_100k /
        100000,
    q5 =
      (5 * mx) /
        (1 + 2.5 * mx)
  )

ncd4_component_q30_70 <- ncd4_component_age_mortality |>
  dplyr::group_by(
    year,
    sdg_component
  ) |>
  dplyr::summarise(
    n_age_groups =
      dplyr::n(),
    q30_70 =
      1 - prod(1 - q5),
    probability_percent =
      100 * q30_70,
    deaths_age30_69 =
      sum(death_number),
    .groups = "drop"
  ) |>
  dplyr::arrange(
    year,
    sdg_component
  )

if (
  any(
    ncd4_component_q30_70$n_age_groups !=
      length(age_30_69)
  )
) {
  stop(
    "An NCD4 component q30-70 calculation did not use exactly eight age groups."
  )
}

readr::write_csv(
  ncd4_component_q30_70,
  file.path(
    output_dir,
    "NCD4_component_q30_70_1990_2023_supporting.csv"
  )
)


# ------------------------------------------------------------------------------
# 15. LINKAGE — NCD4 mortality by life-course cluster
# ------------------------------------------------------------------------------

ncd4_cluster_age_mortality <- ncd4_deaths |>
  dplyr::group_by(
    year,
    cluster_name,
    age,
    age_index,
    age_start
  ) |>
  dplyr::summarise(
    death_number =
      sum(Number),
    death_rate_per_100k =
      sum(Rate),
    .groups = "drop"
  ) |>
  dplyr::mutate(
    mx =
      death_rate_per_100k /
        100000,
    q5 =
      (5 * mx) /
        (1 + 2.5 * mx)
  )

ncd4_cluster_q30_70 <- ncd4_cluster_age_mortality |>
  dplyr::group_by(
    year,
    cluster_name
  ) |>
  dplyr::summarise(
    n_age_groups =
      dplyr::n(),
    q30_70 =
      1 - prod(1 - q5),
    probability_percent =
      100 * q30_70,
    deaths_age30_69 =
      sum(death_number),
    .groups = "drop"
  ) |>
  dplyr::group_by(year) |>
  dplyr::mutate(
    share_of_NCD4_deaths_age30_69 =
      safe_ratio(
        deaths_age30_69,
        sum(deaths_age30_69)
      )
  ) |>
  dplyr::ungroup() |>
  dplyr::mutate(
    cluster_name = factor(
      cluster_name,
      levels = cluster_order
    )
  ) |>
  dplyr::arrange(
    year,
    cluster_name
  )

if (
  any(
    ncd4_cluster_q30_70$n_age_groups !=
      length(age_30_69)
  )
) {
  stop(
    "An NCD4-by-cluster q30-70 calculation did not use exactly eight age groups."
  )
}

ncd4_cluster_linkage <- ncd4_cluster_q30_70 |>
  dplyr::left_join(
    cluster_q30_70 |>
      dplyr::select(
        year,
        cluster_name,
        all_cluster_q30_70 = q30_70,
        all_cluster_deaths_age30_69 =
          deaths_age30_69
      ),
    by = c(
      "year",
      "cluster_name"
    )
  ) |>
  dplyr::mutate(
    share_of_cluster_deaths_that_are_NCD4 =
      safe_ratio(
        deaths_age30_69,
        all_cluster_deaths_age30_69
      )
  )

readr::write_csv(
  ncd4_cluster_q30_70,
  file.path(
    output_dir,
    "NCD4_by_lifecourse_cluster_q30_70_1990_2023.csv"
  )
)

readr::write_csv(
  ncd4_cluster_linkage,
  file.path(
    output_dir,
    "NCD4_lifecourse_cluster_linkage_1990_2023.csv"
  )
)

readr::write_csv(
  ncd4_cluster_linkage |>
    dplyr::filter(
      year %in% c(
        1990L,
        2015L,
        2023L
      )
    ),
  file.path(
    output_dir,
    "NCD4_lifecourse_cluster_linkage_key_years.csv"
  )
)


# ------------------------------------------------------------------------------
# 16. SDG 3.4 policy anchor: 2015 -> 2023 -> 2030 target
# ------------------------------------------------------------------------------

q2015 <- ncd4_q30_70 |>
  dplyr::filter(
    year == 2015L
  ) |>
  dplyr::pull(q30_70)

q2023 <- ncd4_q30_70 |>
  dplyr::filter(
    year == 2023L
  ) |>
  dplyr::pull(q30_70)

if (
  length(q2015) != 1L ||
    length(q2023) != 1L
) {
  stop(
    "Could not uniquely retrieve the 2015 and 2023 formal NCD4 probabilities."
  )
}

q2030_sdg_target <- (2 / 3) * q2015

required_absolute_reduction_2015_2030 <-
  q2015 - q2030_sdg_target

achieved_absolute_reduction_2015_2023 <-
  q2015 - q2023

progress_fraction_of_required_reduction <-
  safe_ratio(
    achieved_absolute_reduction_2015_2023,
    required_absolute_reduction_2015_2030
  )

target_gap_at_2023 <-
  q2023 - q2030_sdg_target

remaining_relative_reduction_from_2023 <-
  1 - safe_ratio(
    q2030_sdg_target,
    q2023
  )

required_annual_relative_change_2023_2030 <-
  (
    q2030_sdg_target /
      q2023
  )^(1 / 7) - 1

sdg_policy_anchor <- tibble::tibble(
  q30_70_2015 =
    q2015,
  q30_70_2023 =
    q2023,
  q30_70_2030_SDG_target =
    q2030_sdg_target,
  probability_percent_2015 =
    100 * q2015,
  probability_percent_2023 =
    100 * q2023,
  probability_percent_2030_SDG_target =
    100 * q2030_sdg_target,
  relative_change_percent_2015_2023 =
    relative_change_percent(
      q2015,
      q2023
    ),
  required_absolute_reduction_2015_2030 =
    required_absolute_reduction_2015_2030,
  achieved_absolute_reduction_2015_2023 =
    achieved_absolute_reduction_2015_2023,
  progress_fraction_of_required_reduction =
    progress_fraction_of_required_reduction,
  progress_percent_of_required_reduction =
    100 *
      progress_fraction_of_required_reduction,
  target_gap_at_2023 =
    target_gap_at_2023,
  target_gap_percentage_points_at_2023 =
    100 *
      target_gap_at_2023,
  remaining_relative_reduction_from_2023 =
    remaining_relative_reduction_from_2023,
  remaining_relative_reduction_percent_from_2023 =
    100 *
      remaining_relative_reduction_from_2023,
  required_annual_relative_change_2023_2030 =
    required_annual_relative_change_2023_2030,
  required_annual_relative_change_percent_2023_2030 =
    100 *
      required_annual_relative_change_2023_2030
)

readr::write_csv(
  sdg_policy_anchor,
  file.path(
    output_dir,
    "NCD4_SDG34_policy_anchor_2015_2023_2030target.csv"
  )
)


# ------------------------------------------------------------------------------
# 17. Compact analysis audit and reproducibility bundle
# ------------------------------------------------------------------------------

analysis_audit <- tibble::tibble(
  check = c(
    "historical_files",
    "years",
    "age_groups",
    "frozen_clustered_causes",
    "Infant_causes",
    "Adult_causes",
    "Aging_related_causes",
    "detailed_causes_observed_in_age30_69_source",
    "frozen_causes_absent_from_age30_69_source",
    "frozen_NCD4_causes",
    "Cancer_causes",
    "Cardiovascular_causes",
    "Chronic_respiratory_causes",
    "Diabetes_causes",
    "cluster_q30_70_age_groups_per_estimate",
    "formal_NCD4_q30_70_age_groups_per_estimate"
  ),
  value = c(
    paste(input_files, collapse = " | "),
    "1990-2023",
    paste(age_30_69, collapse = " | "),
    as.character(
      nrow(cluster_membership)
    ),
    as.character(
      observed_cluster_counts["Infant"]
    ),
    as.character(
      observed_cluster_counts["Adult"]
    ),
    as.character(
      observed_cluster_counts["Aging-related"]
    ),
    as.character(
      nrow(source_cause_universe)
    ),
    paste(
      missing_frozen_causes_from_source$cause,
      collapse = " | "
    ),
    as.character(
      nrow(ncd4_mapping)
    ),
    as.character(
      expected_ncd4_counts["Cancer"]
    ),
    as.character(
      expected_ncd4_counts["Cardiovascular diseases"]
    ),
    as.character(
      expected_ncd4_counts["Chronic respiratory diseases"]
    ),
    as.character(
      expected_ncd4_counts["Diabetes"]
    ),
    "8",
    "8"
  )
)

readr::write_csv(
  analysis_audit,
  file.path(
    output_dir,
    "Part3_analysis_audit.csv"
  )
)

saveRDS(
  list(
    configuration = list(
      years = years_expected,
      age_30_69 = age_30_69,
      cluster_order = cluster_order,
      mapping_version =
        ncd4_mapping_version,
      sdg_target_rule =
        "2030 target = two-thirds of 2015 NCD4 q30-70"
    ),
    batch_periods = batch_periods,
    cluster_membership =
      cluster_membership,
    ncd4_mapping =
      ncd4_mapping_with_cluster,
    classified_deaths =
      classified_deaths,
    cluster_age_mortality =
      cluster_age_mortality,
    cluster_q30_70 =
      cluster_q30_70,
    ncd4_age_mortality =
      ncd4_age_mortality,
    ncd4_q30_70 =
      ncd4_q30_70,
    ncd4_component_q30_70 =
      ncd4_component_q30_70,
    ncd4_cluster_linkage =
      ncd4_cluster_linkage,
    sdg_policy_anchor =
      sdg_policy_anchor,
    closure_by_year_age =
      closure_by_year_age
  ),
  file.path(
    output_dir,
    "Part3_PrematureMortality_analysis_objects.rds"
  )
)

capture.output(
  utils::sessionInfo(),
  file = file.path(
    output_dir,
    "Part3_sessionInfo.txt"
  )
)


# ------------------------------------------------------------------------------
# 18. Console summary
# ------------------------------------------------------------------------------

cat("\n============================================================\n")
cat("PART 3 PREMATURE-MORTALITY ANALYSIS COMPLETE\n")
cat("============================================================\n")
cat("Clustering rerun: NO\n")
cat("Frozen cluster membership: 57 / 71 / 164 = 292 causes\n")
cat("Frozen NCD4 mapping: 45 / 18 / 8 / 4 = 75 causes\n")

cat("\nPrimary result — cluster-specific q30-70 in 2023:\n")
print(
  cluster_q30_70 |>
    dplyr::filter(
      year == 2023L
    ) |>
    dplyr::select(
      cluster_name,
      q30_70,
      probability_percent,
      deaths_age30_69,
      share_of_classified_deaths_age30_69
    )
)

cat("\nFormal NCD4 policy anchor:\n")
print(
  sdg_policy_anchor
)

cat("\nNCD4 x life-course cluster linkage in 2023:\n")
print(
  ncd4_cluster_linkage |>
    dplyr::filter(
      year == 2023L
    ) |>
    dplyr::select(
      cluster_name,
      q30_70,
      probability_percent,
      deaths_age30_69,
      share_of_NCD4_deaths_age30_69,
      share_of_cluster_deaths_that_are_NCD4
    )
)

cat("\nCluster death-closure range across 1990-2023:\n")
print(
  closure_by_year |>
    dplyr::summarise(
      min_number_closure =
        min(
          min_number_closure,
          na.rm = TRUE
        ),
      max_number_closure =
        max(
          max_number_closure,
          na.rm = TRUE
        ),
      min_rate_closure =
        min(
          min_rate_closure,
          na.rm = TRUE
        ),
      max_rate_closure =
        max(
          max_rate_closure,
          na.rm = TRUE
        )
    )
)

cat(
  "\nOutputs saved to: ",
  normalizePath(
    output_dir,
    mustWork = FALSE
  ),
  "\n",
  sep = ""
)

cat("============================================================\n")
