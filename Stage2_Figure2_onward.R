#!/usr/bin/env Rscript

# ==============================================================================
# China GBD 2023 disease age-profile clusters — Stage 2 (redesigned)
# Health loss within the 30–69-year premature-mortality monitoring age window
#
# SCIENTIFIC ROLE OF THIS STAGE
#   Stage 1 identified three life-course disease-burden phenotypes from the
#   full-age 2023 DALY-rate trajectories:
#     Infant / Adult / Aging-related.
#
#   Stage 2 does NOT rerun clustering. It asks a narrower question:
#
#     To what extent do these independently defined life-course phenotypes
#     already generate health loss at ages 30–69 years?
#
#   Ages 30–69 are used because they correspond to the age range used in
#   monitoring premature NCD mortality between exact ages 30 and 70.
#   IMPORTANT: DALYs at ages 30–69 are broader fatal + non-fatal health loss;
#   they are NOT the SDG 3.4.1 probability of premature death.
#
# CORE QUESTIONS
#   Q1. Who accounts for health loss in the 30–69-year window?
#       -> share of classified DALYs at ages 30–69 by disease cluster.
#
#   Q2. How much of each cluster's own all-age DALY burden has already occurred
#       at ages 30–69?
#       -> DALYs ages 30–69 / all-age DALYs within the same cluster.
#
#   Q3. How does cluster contribution change across ages 30–34 to 65–69?
#       -> age-specific DALY-rate composition.
#
# SUPPORTING CHARACTERISATION
#   - YLL versus YLD composition at ages 30–69.
#   - Leading 30–69 DALY causes within each cluster.
#
# MAIN-TEXT OUTPUTS
#   Figure 2  Two complementary views of DALY burden at ages 30–69:
#             A) cluster share of classified 30–69 DALYs;
#             B) proportion of each cluster's all-age DALYs occurring at 30–69.
#
#   Figure 3  Age gradient in DALY composition from 30–34 to 65–69 years.
#
#   Table 1   Core cluster summary:
#             all-age DALYs, 30–69 DALYs, 30–69 composition,
#             within-cluster 30–69/all-age fraction, YLL/YLD phenotype.
#
# SUPPLEMENTARY OUTPUTS
#   Figure S1  Fatal (YLL) vs non-fatal (YLD) composition at ages 30–69.
#   Figure S2  Top 10 DALY causes within each cluster at ages 30–69.
#   Table S1   Full Deaths/YLL/YLD/DALY cluster burden at ages 30–69.
#
# QC OUTPUTS
#   - Frozen membership used.
#   - 304 -> 292 Stage 1 exclusion audit.
#   - Classified-cause closure against GBD All causes.
#
# REQUIRED LOCAL INPUTS
#   1) IHME-GBD_2023_DATA-26354bec-1.csv
#      OR IHME-GBD_2023_DATA-26354bec-1(1).csv
#   2) Figure1_k3_cluster_membership.csv
#      OR Part2_cluster_membership.csv
#
# The analysis uses China, Both sexes, 2023.
# ==============================================================================

# ------------------------------------------------------------------------------
# 0. User configuration
# ------------------------------------------------------------------------------

input_file_candidates <- c(
  "IHME-GBD_2023_DATA-26354bec-1.csv",
  "IHME-GBD_2023_DATA-26354bec-1(1).csv"
)

membership_file_candidates <- c(
  "Figure1_k3_cluster_membership.csv",
  "Part2_cluster_membership.csv",
  "Stage2_frozen_cluster_membership_used.csv"
)

# A new output folder is used so that the redesigned Stage 2 results cannot be
# confused with files created by the earlier, broader Stage 2 script.
output_dir <- "Stage2_Redesigned_30_69_outputs"

expected_n_candidate_causes <- 304L
expected_n_clustered_causes <- 292L
expected_n_unclassified_causes <- 12L

expected_cluster_counts <- c(
  "Infant" = 57L,
  "Adult" = 71L,
  "Aging-related" = 164L
)

cluster_order <- c("Infant", "Adult", "Aging-related")
cluster_colors <- c(
  "Infant" = "#2CA02C",
  "Adult" = "#2878B5",
  "Aging-related" = "#E31A1C"
)

age_levels <- c(
  "<1 year", "12-23 months", "2-4 years",
  "5-9 years", "10-14 years", "15-19 years",
  "20-24 years", "25-29 years", "30-34 years",
  "35-39 years", "40-44 years", "45-49 years",
  "50-54 years", "55-59 years", "60-64 years",
  "65-69 years", "70-74 years", "75-79 years",
  "80-84 years", "85-89 years", "90-94 years",
  "95+ years"
)

age_midpoints <- c(0.5, 1.5, 3.5, seq(7, 92, by = 5), 97.5)
stopifnot(length(age_levels) == length(age_midpoints))

age_30_69 <- c(
  "30-34 years", "35-39 years", "40-44 years", "45-49 years",
  "50-54 years", "55-59 years", "60-64 years", "65-69 years"
)

age_midpoints_30_69 <- c(32, 37, 42, 47, 52, 57, 62, 67)

measure_order <- c(
  "Deaths",
  "YLLs (Years of Life Lost)",
  "YLDs (Years Lived with Disability)",
  "DALYs (Disability-Adjusted Life Years)"
)

measure_short_lookup <- c(
  "Deaths" = "Deaths",
  "YLLs (Years of Life Lost)" = "YLLs",
  "YLDs (Years Lived with Disability)" = "YLDs",
  "DALYs (Disability-Adjusted Life Years)" = "DALYs"
)

daly_measure <- "DALYs (Disability-Adjusted Life Years)"
yll_measure <- "YLLs (Years of Life Lost)"
yld_measure <- "YLDs (Years Lived with Disability)"

# ------------------------------------------------------------------------------
# 1. Package checks
# ------------------------------------------------------------------------------

required_packages <- c(
  "readr", "dplyr", "tidyr", "ggplot2", "scales", "forcats", "tibble"
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

# ------------------------------------------------------------------------------
# 2. Helpers
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

safe_ratio <- function(num, den) {
  # Explicitly recycle scalar/vector inputs to a common length.
  # Base ifelse() returns the length of its test argument; therefore using a
  # scalar denominator as the test would otherwise collapse a vector ratio to
  # its first value and dplyr::mutate() would recycle that value across rows.
  n <- max(length(num), length(den))
  num <- rep_len(num, n)
  den <- rep_len(den, n)

  out <- num / den
  invalid <- !is.finite(den) | den == 0
  out[invalid] <- NA_real_
  out
}

save_plot_pair <- function(plot_object, stem, width, height) {
  ggplot2::ggsave(
    filename = file.path(output_dir, paste0(stem, ".png")),
    plot = plot_object,
    width = width,
    height = height,
    units = "in",
    dpi = 300,
    bg = "white"
  )

  ggplot2::ggsave(
    filename = file.path(output_dir, paste0(stem, ".pdf")),
    plot = plot_object,
    width = width,
    height = height,
    units = "in",
    bg = "white"
  )
}

# ------------------------------------------------------------------------------
# 3. Locate inputs
# ------------------------------------------------------------------------------

input_file <- first_existing_file(
  input_file_candidates,
  "GBD 2023 burden file"
)

membership_file <- first_existing_file(
  membership_file_candidates,
  "Frozen Stage 1 cluster-membership file"
)

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

message("Using burden data: ", input_file)
message("Using frozen cluster membership: ", membership_file)
message(
  "Output directory: ",
  normalizePath(output_dir, mustWork = FALSE)
)

# ------------------------------------------------------------------------------
# 4. Read and validate frozen Stage 1 membership
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

required_membership_columns <- c("cause", "cluster_name")
missing_membership_columns <- setdiff(
  required_membership_columns,
  names(membership_raw)
)

if (length(missing_membership_columns) > 0L) {
  stop(
    "Membership file is missing columns: ",
    paste(missing_membership_columns, collapse = ", ")
  )
}

cluster_membership <- membership_raw |>
  dplyr::transmute(
    cause = as.character(cause),
    cluster_name = as.character(cluster_name)
  ) |>
  dplyr::distinct(cause, .keep_all = TRUE) |>
  dplyr::mutate(
    cluster_name = factor(
      cluster_name,
      levels = cluster_order
    )
  ) |>
  dplyr::arrange(cluster_name, cause)

if (any(is.na(cluster_membership$cluster_name))) {
  stop(
    "Unexpected cluster labels were found in the frozen membership file."
  )
}

if (anyDuplicated(cluster_membership$cause) > 0L) {
  stop(
    "Duplicate causes were found in the frozen membership file."
  )
}

membership_counts <- cluster_membership |>
  dplyr::count(cluster_name, name = "n") |>
  dplyr::mutate(
    cluster_name = as.character(cluster_name)
  )

observed_counts <- stats::setNames(
  rep(0L, length(cluster_order)),
  cluster_order
)

observed_counts[membership_counts$cluster_name] <-
  membership_counts$n

if (nrow(cluster_membership) != expected_n_clustered_causes) {
  stop(
    "Frozen membership contains ",
    nrow(cluster_membership),
    " causes; expected ",
    expected_n_clustered_causes,
    ". Reconcile Stage 1 before continuing."
  )
}

if (
  !all(
    observed_counts[cluster_order] ==
      expected_cluster_counts[cluster_order]
  )
) {
  stop(
    "Frozen cluster sizes do not match the finalized solution.\nObserved: ",
    paste(
      paste0(
        cluster_order,
        "=",
        observed_counts[cluster_order]
      ),
      collapse = "; "
    ),
    "\nExpected: ",
    paste(
      paste0(
        cluster_order,
        "=",
        expected_cluster_counts[cluster_order]
      ),
      collapse = "; "
    )
  )
}

readr::write_csv(
  cluster_membership,
  file.path(
    output_dir,
    "Stage2_frozen_cluster_membership_used.csv"
  )
)

# ------------------------------------------------------------------------------
# 5. Read and validate GBD 2023 burden data
# ------------------------------------------------------------------------------

raw <- readr::read_csv(
  input_file,
  show_col_types = FALSE
)

required_columns <- c(
  "population_group", "measure", "location", "sex", "age",
  "cause", "metric", "year", "val", "upper", "lower"
)

missing_columns <- setdiff(
  required_columns,
  names(raw)
)

if (length(missing_columns) > 0L) {
  stop(
    "Missing GBD columns: ",
    paste(missing_columns, collapse = ", ")
  )
}

analysis_data <- raw |>
  dplyr::filter(
    population_group == "All Population",
    location == "China",
    sex == "Both",
    year == 2023,
    measure %in% measure_order,
    metric %in% c("Number", "Rate"),
    age %in% c("All ages", age_levels)
  ) |>
  dplyr::mutate(
    measure_short = unname(
      measure_short_lookup[measure]
    )
  )

if (nrow(analysis_data) == 0L) {
  stop(
    "No China/Both/2023 burden rows remained after filtering."
  )
}

if (
  anyDuplicated(
    analysis_data[
      c("measure", "age", "cause", "metric")
    ]
  ) > 0L
) {
  stop(
    "Duplicate measure-age-cause-metric records were found in the GBD data."
  )
}

if (
  !all(
    measure_order %in%
      unique(analysis_data$measure)
  )
) {
  stop(
    "Missing measures: ",
    paste(
      setdiff(
        measure_order,
        unique(analysis_data$measure)
      ),
      collapse = ", "
    )
  )
}

if (
  !all(
    c("All ages", age_levels) %in%
      unique(analysis_data$age)
  )
) {
  stop(
    "Missing age groups: ",
    paste(
      setdiff(
        c("All ages", age_levels),
        unique(analysis_data$age)
      ),
      collapse = ", "
    )
  )
}

missing_cluster_causes <- setdiff(
  cluster_membership$cause,
  unique(analysis_data$cause)
)

if (length(missing_cluster_causes) > 0L) {
  stop(
    "The burden file is missing frozen Stage 1 causes: ",
    paste(
      missing_cluster_causes,
      collapse = "; "
    )
  )
}

classified_data <- analysis_data |>
  dplyr::filter(
    cause != "All causes"
  ) |>
  dplyr::inner_join(
    cluster_membership,
    by = "cause"
  ) |>
  dplyr::mutate(
    cluster_name = factor(
      cluster_name,
      levels = cluster_order
    )
  )

# ------------------------------------------------------------------------------
# 6. Re-audit the Stage 1 304 -> 292 exclusion rule
# ------------------------------------------------------------------------------

candidate_gbd_causes <- analysis_data |>
  dplyr::filter(
    cause != "All causes"
  ) |>
  dplyr::distinct(cause) |>
  dplyr::arrange(cause)

if (
  nrow(candidate_gbd_causes) !=
    expected_n_candidate_causes
) {
  stop(
    "The burden file contains ",
    nrow(candidate_gbd_causes),
    " detailed causes; expected ",
    expected_n_candidate_causes,
    ". Reconcile the GBD cause selection before continuing."
  )
}

unclassified_gbd_causes <- candidate_gbd_causes |>
  dplyr::anti_join(
    cluster_membership,
    by = "cause"
  ) |>
  dplyr::arrange(cause)

if (
  nrow(unclassified_gbd_causes) !=
    expected_n_unclassified_causes
) {
  stop(
    "Found ",
    nrow(unclassified_gbd_causes),
    " unclassified detailed causes; expected ",
    expected_n_unclassified_causes,
    ". Reconcile Stage 1 membership before continuing."
  )
}

excluded_daly_rate_grid <- analysis_data |>
  dplyr::filter(
    cause %in% unclassified_gbd_causes$cause,
    measure == daly_measure,
    metric == "Rate",
    age %in% age_levels
  ) |>
  dplyr::select(
    cause,
    age,
    val
  ) |>
  dplyr::mutate(
    age = as.character(age)
  ) |>
  tidyr::complete(
    cause = unclassified_gbd_causes$cause,
    age = age_levels
  ) |>
  dplyr::mutate(
    val_filled_zero =
      tidyr::replace_na(val, 0)
  )

excluded_profile_audit <- excluded_daly_rate_grid |>
  dplyr::group_by(cause) |>
  dplyr::summarise(
    age_cells_expected = length(age_levels),
    age_cells_observed = sum(!is.na(val)),
    missing_age_cells = sum(is.na(val)),
    nonzero_age_cells =
      sum(val_filled_zero != 0),
    min_DALY_rate_per_100k =
      min(val_filled_zero),
    max_DALY_rate_per_100k =
      max(val_filled_zero),
    mean_DALY_rate_per_100k =
      mean(val_filled_zero),
    sd_DALY_rate_per_100k =
      stats::sd(val_filled_zero),
    all_zero_DALY_rate =
      all(val_filled_zero == 0),
    zero_standard_deviation =
      stats::sd(val_filled_zero) == 0,
    .groups = "drop"
  )

excluded_daly_numbers <- analysis_data |>
  dplyr::filter(
    cause %in% unclassified_gbd_causes$cause,
    measure == daly_measure,
    metric == "Number",
    age %in% c("All ages", age_30_69)
  ) |>
  dplyr::mutate(
    analysis_window = dplyr::if_else(
      age == "All ages",
      "all_ages",
      "age30_69"
    )
  ) |>
  dplyr::group_by(
    cause,
    analysis_window
  ) |>
  dplyr::summarise(
    DALY_number =
      sum(val, na.rm = TRUE),
    .groups = "drop"
  ) |>
  tidyr::complete(
    cause = unclassified_gbd_causes$cause,
    analysis_window = c(
      "all_ages",
      "age30_69"
    ),
    fill = list(
      DALY_number = 0
    )
  ) |>
  tidyr::pivot_wider(
    names_from = analysis_window,
    values_from = DALY_number,
    names_prefix = "DALYs_"
  )

excluded_all_measure_check <- analysis_data |>
  dplyr::filter(
    cause %in% unclassified_gbd_causes$cause,
    metric == "Number",
    age == "All ages"
  ) |>
  dplyr::group_by(cause) |>
  dplyr::summarise(
    nonzero_all_age_measure_count =
      sum(val != 0, na.rm = TRUE),
    max_abs_all_age_number =
      max(abs(val), na.rm = TRUE),
    .groups = "drop"
  )

excluded_cause_audit <- excluded_profile_audit |>
  dplyr::left_join(
    excluded_daly_numbers,
    by = "cause"
  ) |>
  dplyr::left_join(
    excluded_all_measure_check,
    by = "cause"
  ) |>
  dplyr::mutate(
    exclusion_reason =
      dplyr::case_when(
        missing_age_cells > 0 ~
          "requires_review_missing_age_cells",
        all_zero_DALY_rate &
          zero_standard_deviation ~
          "all_zero_DALY_rate_across_22_ages",
        zero_standard_deviation ~
          "zero_standard_deviation_DALY_rate",
        TRUE ~
          "requires_review_nonzero_variable_profile"
      )
  ) |>
  dplyr::arrange(cause)

unexpected_excluded <- excluded_cause_audit |>
  dplyr::filter(
    age_cells_observed != length(age_levels) |
      missing_age_cells != 0 |
      !all_zero_DALY_rate |
      !zero_standard_deviation |
      nonzero_all_age_measure_count != 0
  )

if (nrow(unexpected_excluded) > 0L) {
  print(unexpected_excluded)

  stop(
    "One or more of the 12 unclassified causes do not meet the expected ",
    "all-zero/zero-variance exclusion rule. Review the audit table."
  )
}

readr::write_csv(
  unclassified_gbd_causes,
  file.path(
    output_dir,
    "Stage2_unclassified_GBD_causes.csv"
  )
)

readr::write_csv(
  excluded_cause_audit,
  file.path(
    output_dir,
    "Stage1_excluded_12_causes_audit.csv"
  )
)

# ------------------------------------------------------------------------------
# 7. Core DALY quantities for the redesigned Stage 2
# ------------------------------------------------------------------------------

daly_all_age_cluster <- classified_data |>
  dplyr::filter(
    measure == daly_measure,
    metric == "Number",
    age == "All ages"
  ) |>
  dplyr::group_by(cluster_name) |>
  dplyr::summarise(
    DALYs_all_ages =
      sum(val, na.rm = TRUE),
    .groups = "drop"
  )

daly_30_69_cluster <- classified_data |>
  dplyr::filter(
    measure == daly_measure,
    metric == "Number",
    age %in% age_30_69
  ) |>
  dplyr::group_by(cluster_name) |>
  dplyr::summarise(
    DALYs_age30_69 =
      sum(val, na.rm = TRUE),
    .groups = "drop"
  )

daly_all_age_classified_total <-
  sum(daly_all_age_cluster$DALYs_all_ages)

daly_30_69_classified_total <-
  sum(daly_30_69_cluster$DALYs_age30_69)

all_causes_daly_all_age <- analysis_data |>
  dplyr::filter(
    cause == "All causes",
    measure == daly_measure,
    metric == "Number",
    age == "All ages"
  ) |>
  dplyr::summarise(
    value = sum(val, na.rm = TRUE)
  ) |>
  dplyr::pull(value)

all_causes_daly_30_69 <- analysis_data |>
  dplyr::filter(
    cause == "All causes",
    measure == daly_measure,
    metric == "Number",
    age %in% age_30_69
  ) |>
  dplyr::summarise(
    value = sum(val, na.rm = TRUE)
  ) |>
  dplyr::pull(value)

if (
  length(all_causes_daly_all_age) != 1L ||
    length(all_causes_daly_30_69) != 1L
) {
  stop(
    "All-causes DALY denominator lookup failed."
  )
}

if (
  !is.finite(all_causes_daly_all_age) ||
    !is.finite(all_causes_daly_30_69)
) {
  stop(
    "Non-finite All-causes DALY denominator detected."
  )
}

core_daly_summary <- cluster_membership |>
  dplyr::count(
    cluster_name,
    name = "n_causes"
  ) |>
  dplyr::left_join(
    daly_all_age_cluster,
    by = "cluster_name"
  ) |>
  dplyr::left_join(
    daly_30_69_cluster,
    by = "cluster_name"
  ) |>
  dplyr::mutate(
    share_of_classified_DALYs_age30_69 =
      safe_ratio(
        DALYs_age30_69,
        daly_30_69_classified_total
      ),
    share_of_all_causes_DALYs_age30_69 =
      safe_ratio(
        DALYs_age30_69,
        all_causes_daly_30_69
      ),
    proportion_cluster_all_age_DALYs_occurring_age30_69 =
      safe_ratio(
        DALYs_age30_69,
        DALYs_all_ages
      ),
    share_of_classified_DALYs_all_age =
      safe_ratio(
        DALYs_all_ages,
        daly_all_age_classified_total
      )
  ) |>
  dplyr::mutate(
    cluster_name = factor(
      cluster_name,
      levels = cluster_order
    )
  ) |>
  dplyr::arrange(cluster_name)

overall_daly_window_summary <- tibble::tibble(
  denominator = c(
    "Classified 292 causes",
    "GBD All causes"
  ),
  DALYs_all_ages = c(
    daly_all_age_classified_total,
    all_causes_daly_all_age
  ),
  DALYs_age30_69 = c(
    daly_30_69_classified_total,
    all_causes_daly_30_69
  )
) |>
  dplyr::mutate(
    proportion_all_age_DALYs_occurring_age30_69 =
      safe_ratio(
        DALYs_age30_69,
        DALYs_all_ages
      )
  )

# Hard validation for the two distinct denominators used in the core result.
# Panel A must be a composition of the three clusters and therefore sum to 1.
panelA_sum <- sum(
  core_daly_summary$share_of_classified_DALYs_age30_69,
  na.rm = TRUE
)

if (!isTRUE(all.equal(panelA_sum, 1, tolerance = 1e-10))) {
  stop(
    "Core DALY composition error: cluster shares at ages 30–69 sum to ",
    signif(panelA_sum, 8),
    " rather than 1."
  )
}

if (
  dplyr::n_distinct(
    round(
      core_daly_summary$share_of_classified_DALYs_age30_69,
      10
    )
  ) < 2L
) {
  stop(
    "Core DALY composition error: all cluster shares at ages 30–69 are ",
    "identical. Review denominator/vector recycling."
  )
}

# The sum of cluster shares using GBD All causes as denominator should equal
# the classified-cause closure ratio, not necessarily exactly 1.
panelA_all_causes_share_sum <- sum(
  core_daly_summary$share_of_all_causes_DALYs_age30_69,
  na.rm = TRUE
)

expected_panelA_all_causes_share_sum <-
  daly_30_69_classified_total / all_causes_daly_30_69

if (
  !isTRUE(
    all.equal(
      panelA_all_causes_share_sum,
      expected_panelA_all_causes_share_sum,
      tolerance = 1e-10
    )
  )
) {
  stop(
    "All-causes denominator check failed for the 30–69 DALY shares."
  )
}

readr::write_csv(
  core_daly_summary,
  file.path(
    output_dir,
    "Stage2_core_DALY_summary.csv"
  )
)

readr::write_csv(
  overall_daly_window_summary,
  file.path(
    output_dir,
    "Stage2_overall_DALY_30_69_fraction.csv"
  )
)

# ------------------------------------------------------------------------------
# 8. Fatal vs non-fatal health-loss phenotype at ages 30–69
# ------------------------------------------------------------------------------

yll_yld_30_69 <- classified_data |>
  dplyr::filter(
    metric == "Number",
    age %in% age_30_69,
    measure %in% c(
      yll_measure,
      yld_measure
    )
  ) |>
  dplyr::group_by(
    cluster_name,
    measure
  ) |>
  dplyr::summarise(
    estimate = sum(val, na.rm = TRUE),
    .groups = "drop"
  ) |>
  dplyr::mutate(
    component = dplyr::recode(
      measure,
      "YLLs (Years of Life Lost)" = "YLLs",
      "YLDs (Years Lived with Disability)" = "YLDs"
    )
  ) |>
  dplyr::select(
    cluster_name,
    component,
    estimate
  ) |>
  tidyr::pivot_wider(
    names_from = component,
    values_from = estimate,
    values_fill = 0
  )

phenotype_30_69 <- core_daly_summary |>
  dplyr::left_join(
    yll_yld_30_69,
    by = "cluster_name"
  ) |>
  dplyr::mutate(
    YLL_plus_YLD = YLLs + YLDs,
    YLL_fraction_of_YLL_plus_YLD =
      safe_ratio(
        YLLs,
        YLL_plus_YLD
      ),
    YLD_fraction_of_YLL_plus_YLD =
      safe_ratio(
        YLDs,
        YLL_plus_YLD
      ),
    YLL_fraction_of_reported_DALYs =
      safe_ratio(
        YLLs,
        DALYs_age30_69
      ),
    YLD_fraction_of_reported_DALYs =
      safe_ratio(
        YLDs,
        DALYs_age30_69
      ),
    DALY_identity_relative_error =
      safe_ratio(
        abs(
          DALYs_age30_69 -
            YLL_plus_YLD
        ),
        DALYs_age30_69
      )
  )

if (
  any(
    !is.finite(
      phenotype_30_69$YLL_fraction_of_YLL_plus_YLD
    )
  ) ||
    any(
      !is.finite(
        phenotype_30_69$YLD_fraction_of_YLL_plus_YLD
      )
    )
) {
  stop(
    "Non-finite YLL/YLD component shares detected."
  )
}

# ------------------------------------------------------------------------------
# 9. Table 1 — the core Stage 2 summary
# ------------------------------------------------------------------------------

table1 <- phenotype_30_69 |>
  dplyr::select(
    cluster_name,
    n_causes,
    DALYs_all_ages,
    DALYs_age30_69,
    share_of_classified_DALYs_age30_69,
    share_of_all_causes_DALYs_age30_69,
    proportion_cluster_all_age_DALYs_occurring_age30_69,
    YLLs,
    YLDs,
    YLL_fraction_of_YLL_plus_YLD,
    YLD_fraction_of_YLL_plus_YLD,
    DALY_identity_relative_error
  ) |>
  dplyr::arrange(cluster_name)

readr::write_csv(
  table1,
  file.path(
    output_dir,
    "Table1_core_health_loss_summary_2023.csv"
  )
)

# ------------------------------------------------------------------------------
# 10. Figure 2 — two complementary views of 30–69 DALY burden
# ------------------------------------------------------------------------------
# Panel A:
#   Of all classified DALYs occurring at ages 30–69, what share belongs to each
#   life-course disease cluster?
#
# Panel B:
#   Within each life-course disease cluster, what proportion of its own all-age
#   DALY burden has already occurred at ages 30–69?
#
# These are deliberately different denominators and therefore answer different
# scientific questions.

figure2_data <- dplyr::bind_rows(
  core_daly_summary |>
    dplyr::transmute(
      cluster_name,
      panel =
        "A. Share of DALYs occurring at ages 30–69",
      value =
        share_of_classified_DALYs_age30_69,
      denominator =
        "All classified DALYs at ages 30–69",
      DALYs_age30_69,
      DALYs_all_ages
    ),
  core_daly_summary |>
    dplyr::transmute(
      cluster_name,
      panel =
        "B. Proportion of each cluster's all-age DALYs occurring at ages 30–69",
      value =
        proportion_cluster_all_age_DALYs_occurring_age30_69,
      denominator =
        "All-age DALYs within the same cluster",
      DALYs_age30_69,
      DALYs_all_ages
    )
) |>
  dplyr::mutate(
    cluster_name = factor(
      cluster_name,
      levels = cluster_order
    ),
    panel = factor(
      panel,
      levels = c(
        "A. Share of DALYs occurring at ages 30–69",
        "B. Proportion of each cluster's all-age DALYs occurring at ages 30–69"
      )
    )
  )

if (
  any(
    !is.finite(
      figure2_data$value
    )
  )
) {
  stop(
    "Non-finite values detected before Figure 2."
  )
}

readr::write_csv(
  figure2_data,
  file.path(
    output_dir,
    "Figure2_source_data.csv"
  )
)

p2 <- ggplot2::ggplot(
  figure2_data,
  ggplot2::aes(
    x = cluster_name,
    y = value,
    fill = cluster_name
  )
) +
  ggplot2::geom_col(
    width = 0.66
  ) +
  ggplot2::geom_text(
    ggplot2::aes(
      label = scales::percent(
        value,
        accuracy = 0.1
      )
    ),
    vjust = -0.35,
    fontface = "bold",
    size = 3.8
  ) +
  ggplot2::facet_wrap(
    ~panel,
    nrow = 1
  ) +
  ggplot2::scale_fill_manual(
    values = cluster_colors,
    guide = "none",
    drop = FALSE
  ) +
  ggplot2::scale_y_continuous(
    labels = scales::percent_format(
      accuracy = 10
    ),
    limits = c(0, 1),
    expand = ggplot2::expansion(
      mult = c(0, 0.08)
    )
  ) +
  ggplot2::labs(
    title =
      "Health loss at ages 30–69 across life-course disease clusters, China, 2023",
    subtitle = paste0(
      "Panel A asks which clusters account for health loss in the 30–69-year window; ",
      "Panel B asks how much of each cluster's own all-age DALY burden occurs in this window."
    ),
    x = NULL,
    y = "Proportion",
    caption = paste0(
      "Source: GBD 2023, Both sexes. The 30–69-year window corresponds to the ",
      "age range used for premature NCD mortality monitoring, but DALYs represent ",
      "broader fatal and non-fatal health loss and are not the SDG 3.4.1 mortality probability."
    )
  ) +
  ggplot2::theme_bw(
    base_size = 12.5
  ) +
  ggplot2::theme(
    panel.grid.minor =
      ggplot2::element_blank(),
    panel.grid.major.x =
      ggplot2::element_blank(),
    strip.background =
      ggplot2::element_rect(
        fill = "grey94",
        color = "grey75"
      ),
    strip.text =
      ggplot2::element_text(
        face = "bold",
        size = 11
      ),
    axis.text.x =
      ggplot2::element_text(
        angle = 20,
        hjust = 1
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
  p2,
  "Figure2_health_loss_age30_69_two_perspectives",
  width = 12,
  height = 6.5
)

# ------------------------------------------------------------------------------
# 11. Figure 3 — age gradient in DALY composition at ages 30–69
# ------------------------------------------------------------------------------

age_cluster_daly_rates <- classified_data |>
  dplyr::filter(
    measure == daly_measure,
    metric == "Rate",
    age %in% age_30_69
  ) |>
  dplyr::group_by(
    cluster_name,
    age
  ) |>
  dplyr::summarise(
    rate_per_100k =
      sum(val, na.rm = TRUE),
    .groups = "drop"
  ) |>
  tidyr::complete(
    cluster_name =
      factor(
        cluster_order,
        levels = cluster_order
      ),
    age = age_30_69,
    fill = list(
      rate_per_100k = 0
    )
  ) |>
  dplyr::mutate(
    cluster_name =
      factor(
        cluster_name,
        levels = cluster_order
      ),
    age =
      factor(
        age,
        levels = age_30_69,
        ordered = TRUE
      ),
    age_index =
      as.integer(age),
    age_midpoint =
      age_midpoints_30_69[age_index]
  )

figure3_data <- age_cluster_daly_rates |>
  dplyr::group_by(
    age,
    age_index,
    age_midpoint
  ) |>
  dplyr::mutate(
    classified_DALY_rate_per_100k =
      sum(rate_per_100k),
    share_of_classified_DALY_rate =
      safe_ratio(
        rate_per_100k,
        classified_DALY_rate_per_100k
      )
  ) |>
  dplyr::ungroup() |>
  dplyr::arrange(
    age_index,
    cluster_name
  )

if (
  any(
    !is.finite(
      figure3_data$share_of_classified_DALY_rate
    )
  )
) {
  stop(
    "Non-finite DALY shares detected before Figure 3."
  )
}

readr::write_csv(
  figure3_data,
  file.path(
    output_dir,
    "Figure3_age30_69_DALY_gradient_source_data.csv"
  )
)

p3 <- ggplot2::ggplot(
  figure3_data,
  ggplot2::aes(
    x = age_midpoint,
    y = share_of_classified_DALY_rate,
    color = cluster_name,
    group = cluster_name
  )
) +
  ggplot2::geom_line(
    linewidth = 1.15,
    lineend = "round"
  ) +
  ggplot2::geom_point(
    size = 2.25
  ) +
  ggplot2::scale_color_manual(
    values = cluster_colors,
    breaks = cluster_order,
    drop = FALSE
  ) +
  ggplot2::scale_x_continuous(
    breaks = age_midpoints_30_69,
    labels = age_30_69,
    expand = ggplot2::expansion(
      mult = c(0.02, 0.02)
    )
  ) +
  ggplot2::scale_y_continuous(
    labels = scales::percent_format(
      accuracy = 10
    ),
    limits = c(0, 1),
    expand = ggplot2::expansion(
      mult = c(0, 0.02)
    )
  ) +
  ggplot2::labs(
    title =
      "Age gradient in DALY composition across the 30–69-year window, China, 2023",
    subtitle = paste0(
      "Share of the classified age-specific DALY rate contributed by each ",
      "life-course disease cluster"
    ),
    x = "Age group",
    y = "Share of classified DALY rate",
    color = "Disease cluster",
    caption = paste0(
      "Source: GBD 2023, Both sexes. Cluster membership was fixed from the ",
      "independent full-life-course 2023 DALY trajectory classification."
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
    axis.text.x =
      ggplot2::element_text(
        angle = 45,
        hjust = 1
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
  p3,
  "Figure3_age30_69_DALY_cluster_gradient",
  width = 10.5,
  height = 6.6
)

# ------------------------------------------------------------------------------
# 12. Supplementary Figure S1 — fatal vs non-fatal DALY composition
# ------------------------------------------------------------------------------

figure_s1_data <- phenotype_30_69 |>
  dplyr::select(
    cluster_name,
    YLL_fraction_of_YLL_plus_YLD,
    YLD_fraction_of_YLL_plus_YLD
  ) |>
  tidyr::pivot_longer(
    cols = c(
      YLL_fraction_of_YLL_plus_YLD,
      YLD_fraction_of_YLL_plus_YLD
    ),
    names_to = "component",
    values_to = "share"
  ) |>
  dplyr::mutate(
    component = dplyr::recode(
      component,
      "YLL_fraction_of_YLL_plus_YLD" =
        "YLL (fatal burden)",
      "YLD_fraction_of_YLL_plus_YLD" =
        "YLD (non-fatal burden)"
    ),
    component = factor(
      component,
      levels = c(
        "YLL (fatal burden)",
        "YLD (non-fatal burden)"
      )
    ),
    cluster_name = factor(
      cluster_name,
      levels = cluster_order
    )
  )

readr::write_csv(
  figure_s1_data,
  file.path(
    output_dir,
    "FigureS1_YLL_YLD_composition_source_data.csv"
  )
)

p_s1 <- ggplot2::ggplot(
  figure_s1_data,
  ggplot2::aes(
    x = cluster_name,
    y = share,
    fill = component
  )
) +
  ggplot2::geom_col(
    width = 0.68,
    color = "white",
    linewidth = 0.3
  ) +
  ggplot2::geom_text(
    ggplot2::aes(
      label = scales::percent(
        share,
        accuracy = 0.1
      )
    ),
    position =
      ggplot2::position_stack(
        vjust = 0.5
      ),
    color = "white",
    fontface = "bold",
    size = 3.5
  ) +
  ggplot2::scale_y_continuous(
    labels = scales::percent_format(
      accuracy = 10
    ),
    expand = ggplot2::expansion(
      mult = c(0, 0.02)
    )
  ) +
  ggplot2::coord_cartesian(
    ylim = c(0, 1)
  ) +
  ggplot2::labs(
    title =
      "Fatal and non-fatal composition of health loss at ages 30–69, China, 2023",
    x = NULL,
    y = "Share of YLL + YLD",
    fill = NULL,
    caption = paste0(
      "YLL and YLD shares are normalized to YLL + YLD within each cluster. ",
      "The main Table 1 retains the reported DALY totals and the DALY identity check."
    )
  ) +
  ggplot2::theme_bw(
    base_size = 12
  ) +
  ggplot2::theme(
    legend.position = "bottom",
    panel.grid.minor =
      ggplot2::element_blank(),
    panel.grid.major.x =
      ggplot2::element_blank(),
    plot.title =
      ggplot2::element_text(
        face = "bold",
        size = 14
      ),
    plot.caption =
      ggplot2::element_text(
        size = 8,
        color = "grey40",
        hjust = 0
      )
  )

save_plot_pair(
  p_s1,
  "FigureS1_age30_69_YLL_YLD_composition",
  width = 8.4,
  height = 5.9
)

# ------------------------------------------------------------------------------
# 13. Supplementary Figure S2 — leading 30–69 DALY causes by cluster
# ------------------------------------------------------------------------------

cause_daly_30_69 <- classified_data |>
  dplyr::filter(
    measure == daly_measure,
    metric == "Number",
    age %in% age_30_69
  ) |>
  dplyr::group_by(
    cluster_name,
    cause
  ) |>
  dplyr::summarise(
    DALYs_age30_69 =
      sum(val, na.rm = TRUE),
    .groups = "drop"
  ) |>
  dplyr::group_by(
    cluster_name
  ) |>
  dplyr::mutate(
    cluster_DALYs_age30_69 =
      sum(DALYs_age30_69),
    share_within_cluster =
      safe_ratio(
        DALYs_age30_69,
        cluster_DALYs_age30_69
      )
  ) |>
  dplyr::ungroup() |>
  dplyr::mutate(
    cluster_name = factor(
      cluster_name,
      levels = cluster_order
    )
  )

top10_daly_30_69 <- cause_daly_30_69 |>
  dplyr::group_by(
    cluster_name
  ) |>
  dplyr::slice_max(
    DALYs_age30_69,
    n = 10,
    with_ties = FALSE
  ) |>
  dplyr::arrange(
    cluster_name,
    dplyr::desc(DALYs_age30_69)
  ) |>
  dplyr::mutate(
    rank_within_cluster =
      dplyr::row_number()
  ) |>
  dplyr::ungroup() |>
  dplyr::mutate(
    cause_panel =
      paste(
        cause,
        cluster_name,
        sep = "___"
      ),
    cause_panel =
      forcats::fct_reorder(
        cause_panel,
        DALYs_age30_69
      )
  )

readr::write_csv(
  cause_daly_30_69,
  file.path(
    output_dir,
    "TableS2_age30_69_DALY_cause_burden.csv"
  )
)

readr::write_csv(
  top10_daly_30_69 |>
    dplyr::select(
      -cause_panel
    ),
  file.path(
    output_dir,
    "FigureS2_top10_DALY_causes_source_data.csv"
  )
)

p_s2 <- ggplot2::ggplot(
  top10_daly_30_69,
  ggplot2::aes(
    x = DALYs_age30_69,
    y = cause_panel,
    fill = cluster_name
  )
) +
  ggplot2::geom_col(
    width = 0.72
  ) +
  ggplot2::facet_wrap(
    ~cluster_name,
    scales = "free_y",
    ncol = 1
  ) +
  ggplot2::scale_fill_manual(
    values = cluster_colors,
    guide = "none"
  ) +
  ggplot2::scale_y_discrete(
    labels = function(x) {
      sub("___.*$", "", x)
    }
  ) +
  ggplot2::scale_x_continuous(
    labels = scales::label_number(
      scale = 1e-6,
      suffix = " M",
      accuracy = 0.1
    )
  ) +
  ggplot2::labs(
    title =
      "Leading causes of DALYs within each life-course disease cluster, ages 30–69",
    subtitle =
      "Supplementary descriptive context; not used to define cluster membership",
    x = "DALYs (millions)",
    y = NULL,
    caption =
      "Source: GBD 2023, China, Both sexes."
  ) +
  ggplot2::theme_bw(
    base_size = 11
  ) +
  ggplot2::theme(
    panel.grid.minor =
      ggplot2::element_blank(),
    panel.grid.major.y =
      ggplot2::element_blank(),
    strip.background =
      ggplot2::element_rect(
        fill = "grey94",
        color = "grey75"
      ),
    strip.text =
      ggplot2::element_text(
        face = "bold"
      ),
    plot.title =
      ggplot2::element_text(
        face = "bold",
        size = 14
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
  p_s2,
  "FigureS2_age30_69_top10_DALY_causes",
  width = 12.3,
  height = 12
)

# ------------------------------------------------------------------------------
# 14. Supplementary Table S1 — all four measures at ages 30–69
# ------------------------------------------------------------------------------

all_measure_30_69 <- classified_data |>
  dplyr::filter(
    metric == "Number",
    age %in% age_30_69
  ) |>
  dplyr::group_by(
    measure,
    measure_short,
    cluster_name
  ) |>
  dplyr::summarise(
    estimate =
      sum(val, na.rm = TRUE),
    .groups = "drop"
  ) |>
  dplyr::group_by(
    measure,
    measure_short
  ) |>
  dplyr::mutate(
    classified_total =
      sum(estimate),
    share_of_classified =
      safe_ratio(
        estimate,
        classified_total
      )
  ) |>
  dplyr::ungroup() |>
  dplyr::mutate(
    measure_short =
      factor(
        measure_short,
        levels = c(
          "Deaths",
          "YLLs",
          "YLDs",
          "DALYs"
        )
      ),
    cluster_name =
      factor(
        cluster_name,
        levels = cluster_order
      )
  ) |>
  dplyr::arrange(
    measure_short,
    cluster_name
  )

all_causes_30_69 <- analysis_data |>
  dplyr::filter(
    cause == "All causes",
    metric == "Number",
    age %in% age_30_69
  ) |>
  dplyr::group_by(
    measure,
    measure_short
  ) |>
  dplyr::summarise(
    all_causes_value =
      sum(val, na.rm = TRUE),
    .groups = "drop"
  )

table_s1 <- all_measure_30_69 |>
  dplyr::left_join(
    all_causes_30_69,
    by = c(
      "measure",
      "measure_short"
    )
  ) |>
  dplyr::mutate(
    share_of_all_causes =
      safe_ratio(
        estimate,
        all_causes_value
      )
  )

readr::write_csv(
  table_s1,
  file.path(
    output_dir,
    "TableS1_age30_69_all_measure_cluster_burden.csv"
  )
)

# ------------------------------------------------------------------------------
# 15. Closure and internal consistency checks
# ------------------------------------------------------------------------------

closure_all_measure <- table_s1 |>
  dplyr::group_by(
    measure,
    measure_short,
    all_causes_value
  ) |>
  dplyr::summarise(
    classified_total =
      sum(estimate),
    .groups = "drop"
  ) |>
  dplyr::mutate(
    classified_to_all_ratio =
      safe_ratio(
        classified_total,
        all_causes_value
      )
  ) |>
  dplyr::arrange(
    measure_short
  )

daly_closure <- tibble::tibble(
  analysis_window = c(
    "All ages",
    "Ages 30–69"
  ),
  classified_DALYs = c(
    daly_all_age_classified_total,
    daly_30_69_classified_total
  ),
  all_causes_DALYs = c(
    all_causes_daly_all_age,
    all_causes_daly_30_69
  )
) |>
  dplyr::mutate(
    classified_to_all_ratio =
      safe_ratio(
        classified_DALYs,
        all_causes_DALYs
      )
  )

readr::write_csv(
  closure_all_measure,
  file.path(
    output_dir,
    "Stage2_age30_69_all_measure_closure.csv"
  )
)

readr::write_csv(
  daly_closure,
  file.path(
    output_dir,
    "Stage2_DALY_all_age_vs_30_69_closure.csv"
  )
)

if (
  any(
    closure_all_measure$classified_to_all_ratio >
      1.01
  )
) {
  stop(
    "Classified burden exceeds GBD All causes by >1%; review aggregation."
  )
}

# ------------------------------------------------------------------------------
# 16. Audit, reproducibility bundle and session information
# ------------------------------------------------------------------------------

analysis_audit <- tibble::tibble(
  check = c(
    "input_file",
    "membership_file",
    "raw_rows",
    "analysis_rows",
    "candidate_detailed_causes",
    "frozen_clustered_causes",
    "unclassified_GBD_causes",
    "excluded_all_zero_DALY_rate_causes",
    "all_age_groups_available",
    "age30_69_groups_used",
    "measures_available",
    "sex",
    "year",
    "classified_DALY_closure_all_ages",
    "classified_DALY_closure_age30_69"
  ),
  value = c(
    input_file,
    membership_file,
    as.character(
      nrow(raw)
    ),
    as.character(
      nrow(analysis_data)
    ),
    as.character(
      nrow(candidate_gbd_causes)
    ),
    as.character(
      nrow(cluster_membership)
    ),
    as.character(
      nrow(unclassified_gbd_causes)
    ),
    as.character(
      sum(
        excluded_cause_audit$all_zero_DALY_rate
      )
    ),
    as.character(
      length(age_levels)
    ),
    as.character(
      length(age_30_69)
    ),
    as.character(
      length(measure_order)
    ),
    "Both",
    "2023",
    format(
      daly_closure$classified_to_all_ratio[
        daly_closure$analysis_window ==
          "All ages"
      ],
      digits = 10
    ),
    format(
      daly_closure$classified_to_all_ratio[
        daly_closure$analysis_window ==
          "Ages 30–69"
      ],
      digits = 10
    )
  )
)

readr::write_csv(
  analysis_audit,
  file.path(
    output_dir,
    "Stage2_data_audit.csv"
  )
)

saveRDS(
  list(
    configuration = list(
      input_file = input_file,
      membership_file = membership_file,
      year = 2023L,
      sex = "Both",
      cluster_order = cluster_order,
      age_levels = age_levels,
      age_30_69 = age_30_69,
      scientific_question = paste0(
        "How much health loss generated by independently defined life-course ",
        "disease phenotypes already occurs within ages 30–69?"
      )
    ),
    membership =
      cluster_membership,
    excluded_cause_audit =
      excluded_cause_audit,
    core_daly_summary =
      core_daly_summary,
    overall_daly_window_summary =
      overall_daly_window_summary,
    phenotype_30_69 =
      phenotype_30_69,
    table1 =
      table1,
    figure2_data =
      figure2_data,
    figure3_data =
      figure3_data,
    cause_daly_30_69 =
      cause_daly_30_69,
    top10_daly_30_69 =
      top10_daly_30_69,
    table_s1 =
      table_s1,
    closure_all_measure =
      closure_all_measure,
    daly_closure =
      daly_closure
  ),
  file.path(
    output_dir,
    "Stage2_Redesigned_analysis_objects.rds"
  )
)

capture.output(
  utils::sessionInfo(),
  file = file.path(
    output_dir,
    "Stage2_sessionInfo.txt"
  )
)

# ------------------------------------------------------------------------------
# 17. Console summary
# ------------------------------------------------------------------------------

cat("\n============================================================\n")
cat("STAGE 2 REDESIGNED ANALYSIS COMPLETE\n")
cat("============================================================\n")
cat("Clustering rerun: NO\n")
cat("Scientific focus: health loss at ages 30–69, not formal premature mortality.\n")
cat("Frozen clustered causes:", nrow(cluster_membership), "\n")

cat("\nCluster counts:\n")
print(
  membership_counts
)

cat("\nCore DALY summary:\n")
print(
  table1 |>
    dplyr::select(
      cluster_name,
      n_causes,
      DALYs_all_ages,
      DALYs_age30_69,
      share_of_classified_DALYs_age30_69,
      proportion_cluster_all_age_DALYs_occurring_age30_69,
      YLL_fraction_of_YLL_plus_YLD,
      YLD_fraction_of_YLL_plus_YLD
    )
)

cat("\nOverall proportion of all-age DALYs occurring at ages 30–69:\n")
print(
  overall_daly_window_summary
)

cat("\nDALY closure against GBD All causes:\n")
print(
  daly_closure
)

cat("\nAll-measure 30–69 closure:\n")
print(
  closure_all_measure
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
