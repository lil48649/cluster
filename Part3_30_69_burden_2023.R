#!/usr/bin/env Rscript

# ==============================================================================
# GBD 2023 China disease age-profile clusters — Stage 2, Part 1
# 2023 burden among adults aged 30–69 years
#
# IMPORTANT METHOD RULE:
#   This script DOES NOT rerun clustering.
#   It reads the frozen k=3 membership produced by the completed Stage 1
#   K-means++ analysis and applies that membership to 2023 Deaths, YLLs, YLDs
#   and DALYs in the eight mutually exclusive age groups from 30–34 to 65–69.
#
# Primary outputs:
#   - Figure 5: composition of 30–69 burden by cluster
#   - Figure 6: cluster shares across the eight 5-year age groups
#   - Figure 7: leading 30–69 DALY causes within each cluster
#   - Supplementary figure: age-specific cluster rates
#   - CSV tables for burden, age gradients, YLL/YLD phenotype and top causes
#   - RDS object containing all derived datasets
#
# This is the first analysis block of Stage 2. It is intentionally limited to
# China, Both sexes, year 2023. Sex-stratified analyses are not performed.
# ============================================================================== 

# ------------------------------------------------------------------------------
# 0. User configuration
# ------------------------------------------------------------------------------

# The script tries these data filenames in order and uses the first one found.
input_file_candidates <- c(
  "IHME-GBD_2023_DATA-26354bec-1.csv",
  "IHME-GBD_2023_DATA-26354bec-1(1).csv"
)

# Frozen Stage 1 membership. The script tries these files in order.
# Figure1_k3_cluster_membership.csv has column "disease";
# Part2_cluster_membership.csv has column "cause". Both are accepted.
membership_file_candidates <- c(
  "Figure1_k3_cluster_membership.csv",
  "Part2_cluster_membership.csv"
)

output_dir <- "Part3_30_69_2023_outputs"

# Expected final Stage 1 solution shown in the current figures.
expected_n_clustered_causes <- 292L
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
    "Missing R packages: ", paste(missing_packages, collapse = ", "),
    "\nInstall them first, e.g. install.packages(c(",
    paste(sprintf('"%s"', missing_packages), collapse = ", "), "))"
  )
}

# ------------------------------------------------------------------------------
# 2. Helpers
# ------------------------------------------------------------------------------

first_existing_file <- function(candidates, label) {
  hit <- candidates[file.exists(candidates)]
  if (length(hit) == 0L) {
    stop(
      label, " not found. Looked for:\n  ",
      paste(candidates, collapse = "\n  ")
    )
  }
  hit[[1L]]
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

safe_ratio <- function(num, den) {
  ifelse(is.finite(den) & den != 0, num / den, NA_real_)
}

# ------------------------------------------------------------------------------
# 3. Locate files and create output directory
# ------------------------------------------------------------------------------

input_file <- first_existing_file(input_file_candidates, "GBD 2023 burden file")
membership_file <- first_existing_file(
  membership_file_candidates,
  "Frozen Stage 1 cluster-membership file"
)

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

message("Using burden data: ", input_file)
message("Using frozen cluster membership: ", membership_file)
message("Outputs: ", normalizePath(output_dir, mustWork = FALSE))

# ------------------------------------------------------------------------------
# 4. Read and validate frozen cluster membership
# ------------------------------------------------------------------------------

membership_raw <- readr::read_csv(membership_file, show_col_types = FALSE)

if ("disease" %in% names(membership_raw) && !("cause" %in% names(membership_raw))) {
  membership_raw <- dplyr::rename(membership_raw, cause = disease)
}

membership_required <- c("cause", "cluster_name")
missing_membership_columns <- setdiff(membership_required, names(membership_raw))
if (length(missing_membership_columns) > 0L) {
  stop(
    "Membership file is missing required columns: ",
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
    cluster_name = factor(cluster_name, levels = cluster_order)
  ) |>
  dplyr::arrange(cluster_name, cause)

if (any(is.na(cluster_membership$cluster_name))) {
  bad <- unique(as.character(membership_raw$cluster_name)[
    !(as.character(membership_raw$cluster_name) %in% cluster_order)
  ])
  stop(
    "Unexpected cluster labels in frozen membership: ",
    paste(bad, collapse = ", ")
  )
}

if (anyDuplicated(cluster_membership$cause) > 0L) {
  stop("Duplicate causes were found in the frozen membership file.")
}

membership_counts <- cluster_membership |>
  dplyr::count(cluster_name, name = "n") |>
  dplyr::mutate(cluster_name = as.character(cluster_name))

observed_counts <- stats::setNames(rep(0L, length(cluster_order)), cluster_order)
observed_counts[membership_counts$cluster_name] <- membership_counts$n

if (nrow(cluster_membership) != expected_n_clustered_causes) {
  stop(
    "Frozen membership contains ", nrow(cluster_membership),
    " causes; expected ", expected_n_clustered_causes,
    ". Do not continue until the final Stage 1 membership is reconciled."
  )
}

if (!all(observed_counts == expected_cluster_counts[cluster_order])) {
  stop(
    "Frozen membership cluster counts do not match the finalized solution.\n",
    "Observed: ",
    paste(paste0(cluster_order, "=", observed_counts), collapse = "; "),
    "\nExpected: ",
    paste(
      paste0(cluster_order, "=", expected_cluster_counts[cluster_order]),
      collapse = "; "
    )
  )
}

readr::write_csv(
  cluster_membership,
  file.path(output_dir, "Part3_frozen_cluster_membership_used.csv")
)

# ------------------------------------------------------------------------------
# 5. Read and validate GBD 2023 burden data
# ------------------------------------------------------------------------------

raw <- readr::read_csv(input_file, show_col_types = FALSE)

required_columns <- c(
  "population_group", "measure", "location", "sex", "age",
  "cause", "metric", "year", "val", "upper", "lower"
)

missing_columns <- setdiff(required_columns, names(raw))
if (length(missing_columns) > 0L) {
  stop("Missing GBD columns: ", paste(missing_columns, collapse = ", "))
}

analysis_data <- raw |>
  dplyr::filter(
    population_group == "All Population",
    location == "China",
    sex == "Both",
    year == 2023,
    measure %in% measure_order,
    metric %in% c("Number", "Rate"),
    age %in% age_30_69
  ) |>
  dplyr::mutate(
    age = factor(age, levels = age_30_69, ordered = TRUE),
    age_index = as.integer(age),
    age_midpoint = age_midpoints_30_69[age_index],
    measure_short = unname(measure_short_lookup[measure])
  )

if (nrow(analysis_data) == 0L) {
  stop("No China/Both/2023/30-69 rows remained after filtering.")
}

if (anyDuplicated(
  analysis_data[c("measure", "age", "cause", "metric")]
) > 0L) {
  stop("Duplicate measure-age-cause-metric records found in GBD data.")
}

if (!all(measure_order %in% unique(analysis_data$measure))) {
  stop(
    "Missing measures: ",
    paste(setdiff(measure_order, unique(analysis_data$measure)), collapse = ", ")
  )
}

if (!all(age_30_69 %in% as.character(unique(analysis_data$age)))) {
  stop(
    "Missing 30-69 age groups: ",
    paste(
      setdiff(age_30_69, as.character(unique(analysis_data$age))),
      collapse = ", "
    )
  )
}

# Confirm that every frozen cause appears somewhere in the 30-69 extract.
missing_membership_causes <- setdiff(
  cluster_membership$cause,
  unique(analysis_data$cause)
)

if (length(missing_membership_causes) > 0L) {
  stop(
    "The GBD burden file is missing frozen cluster causes: ",
    paste(missing_membership_causes, collapse = "; ")
  )
}

# ------------------------------------------------------------------------------
# 6. Infer the 2023 population denominators for each five-year age group
# ------------------------------------------------------------------------------
# GBD cause-specific rates are per 100,000. For any measure:
#     population = Number / Rate * 100,000
# The denominator should be the same for Deaths, YLLs, YLDs and DALYs.
# We infer it independently from each All-causes measure and use the median.

all_causes_age <- analysis_data |>
  dplyr::filter(cause == "All causes") |>
  dplyr::select(measure, measure_short, age, age_index, age_midpoint, metric, val) |>
  tidyr::pivot_wider(names_from = metric, values_from = val)

if (!all(c("Number", "Rate") %in% names(all_causes_age))) {
  stop("All-causes Number and Rate are both required to infer population.")
}

population_candidates <- all_causes_age |>
  dplyr::mutate(
    population_implied = dplyr::if_else(
      is.finite(Number) & is.finite(Rate) & Rate > 0,
      Number / Rate * 100000,
      NA_real_
    )
  )

population_by_age <- population_candidates |>
  dplyr::group_by(age, age_index, age_midpoint) |>
  dplyr::summarise(
    n_population_estimates = sum(is.finite(population_implied)),
    population = stats::median(population_implied, na.rm = TRUE),
    population_min = min(population_implied, na.rm = TRUE),
    population_max = max(population_implied, na.rm = TRUE),
    max_relative_deviation = max(
      abs(population_implied - stats::median(population_implied, na.rm = TRUE)) /
        stats::median(population_implied, na.rm = TRUE),
      na.rm = TRUE
    ),
    .groups = "drop"
  ) |>
  dplyr::arrange(age_index)

if (any(!is.finite(population_by_age$population))) {
  stop("Failed to infer a finite population denominator for every 30-69 age group.")
}

population_30_69 <- sum(population_by_age$population)

readr::write_csv(
  population_candidates,
  file.path(output_dir, "Part3_population_denominator_candidates.csv")
)
readr::write_csv(
  population_by_age,
  file.path(output_dir, "Part3_population_by_age_30_69.csv")
)

# ------------------------------------------------------------------------------
# 7. Attach the frozen clusters to detailed causes
# ------------------------------------------------------------------------------

classified_data <- analysis_data |>
  dplyr::filter(cause != "All causes") |>
  dplyr::inner_join(cluster_membership, by = "cause") |>
  dplyr::mutate(
    cluster_name = factor(cluster_name, levels = cluster_order)
  )

# Audit which non-All-causes GBD rows are outside the frozen membership.
unclassified_causes <- analysis_data |>
  dplyr::filter(cause != "All causes") |>
  dplyr::distinct(cause) |>
  dplyr::anti_join(cluster_membership, by = "cause") |>
  dplyr::arrange(cause)

readr::write_csv(
  unclassified_causes,
  file.path(output_dir, "Part3_unclassified_GBD_causes.csv")
)

# ------------------------------------------------------------------------------
# 8. 30-69 burden summary by cluster
# ------------------------------------------------------------------------------

cluster_number <- classified_data |>
  dplyr::filter(metric == "Number") |>
  dplyr::group_by(measure, measure_short, cluster_name) |>
  dplyr::summarise(estimate = sum(val, na.rm = TRUE), .groups = "drop")

all_causes_number <- analysis_data |>
  dplyr::filter(metric == "Number", cause == "All causes") |>
  dplyr::group_by(measure, measure_short) |>
  dplyr::summarise(all_causes_30_69 = sum(val, na.rm = TRUE), .groups = "drop")

classified_measure_totals <- cluster_number |>
  dplyr::group_by(measure, measure_short) |>
  dplyr::summarise(classified_total_30_69 = sum(estimate), .groups = "drop")

cluster_burden <- cluster_number |>
  dplyr::left_join(classified_measure_totals, by = c("measure", "measure_short")) |>
  dplyr::left_join(all_causes_number, by = c("measure", "measure_short")) |>
  dplyr::mutate(
    share_of_classified = safe_ratio(estimate, classified_total_30_69),
    share_of_all_causes = safe_ratio(estimate, all_causes_30_69),
    classified_coverage_of_all_causes = safe_ratio(
      classified_total_30_69,
      all_causes_30_69
    ),
    crude_rate_per_100k_30_69 = estimate / population_30_69 * 100000,
    measure_short = factor(
      measure_short,
      levels = c("Deaths", "YLLs", "YLDs", "DALYs")
    ),
    cluster_name = factor(cluster_name, levels = cluster_order)
  ) |>
  dplyr::arrange(measure_short, cluster_name)

readr::write_csv(
  cluster_burden,
  file.path(output_dir, "Part3_30_69_cluster_burden_summary.csv")
)

# Wide, manuscript-friendly table.
cluster_burden_wide <- cluster_burden |>
  dplyr::select(
    cluster_name, measure_short, estimate,
    share_of_classified, share_of_all_causes,
    crude_rate_per_100k_30_69
  ) |>
  tidyr::pivot_wider(
    names_from = measure_short,
    values_from = c(
      estimate, share_of_classified,
      share_of_all_causes, crude_rate_per_100k_30_69
    ),
    names_glue = "{measure_short}_{.value}"
  )

readr::write_csv(
  cluster_burden_wide,
  file.path(output_dir, "Part3_30_69_cluster_burden_table_wide.csv")
)

# Closure of the frozen 292 causes against GBD All causes within 30-69.
closure_30_69 <- classified_measure_totals |>
  dplyr::left_join(all_causes_number, by = c("measure", "measure_short")) |>
  dplyr::mutate(
    classified_to_all_ratio = safe_ratio(
      classified_total_30_69,
      all_causes_30_69
    )
  ) |>
  dplyr::arrange(match(measure, measure_order))

readr::write_csv(
  closure_30_69,
  file.path(output_dir, "Part3_30_69_classified_to_all_causes_closure.csv")
)

# ------------------------------------------------------------------------------
# 9. Mortality-disability phenotype: YLL and YLD composition of DALYs
# ------------------------------------------------------------------------------

phenotype <- cluster_number |>
  dplyr::select(cluster_name, measure_short, estimate) |>
  tidyr::pivot_wider(names_from = measure_short, values_from = estimate) |>
  dplyr::mutate(
    YLL_fraction_of_DALYs = safe_ratio(YLLs, DALYs),
    YLD_fraction_of_DALYs = safe_ratio(YLDs, DALYs),
    YLL_to_YLD_ratio = safe_ratio(YLLs, YLDs),
    DALY_identity_relative_error = safe_ratio(
      abs(DALYs - (YLLs + YLDs)),
      DALYs
    )
  ) |>
  dplyr::arrange(cluster_name)

readr::write_csv(
  phenotype,
  file.path(output_dir, "Part3_30_69_mortality_disability_profile.csv")
)

# ------------------------------------------------------------------------------
# 10. Age-specific cluster rates and cluster shares, ages 30-69
# ------------------------------------------------------------------------------
# Cause-specific GBD rates within one age group have the same denominator, so
# they can be summed across mutually exclusive detailed causes within a cluster.

age_cluster_rates <- classified_data |>
  dplyr::filter(metric == "Rate") |>
  dplyr::group_by(
    measure, measure_short, cluster_name,
    age, age_index, age_midpoint
  ) |>
  dplyr::summarise(rate_per_100k = sum(val, na.rm = TRUE), .groups = "drop") |>
  tidyr::complete(
    measure,
    cluster_name = factor(cluster_order, levels = cluster_order),
    age = factor(age_30_69, levels = age_30_69, ordered = TRUE),
    fill = list(rate_per_100k = 0)
  ) |>
  dplyr::mutate(
    measure_short = unname(measure_short_lookup[measure]),
    age_index = as.integer(age),
    age_midpoint = age_midpoints_30_69[age_index],
    cluster_name = factor(cluster_name, levels = cluster_order),
    measure_short = factor(
      measure_short,
      levels = c("Deaths", "YLLs", "YLDs", "DALYs")
    )
  )

all_causes_age_rates <- analysis_data |>
  dplyr::filter(metric == "Rate", cause == "All causes") |>
  dplyr::transmute(
    measure,
    age,
    all_causes_rate_per_100k = val
  )

age_cluster_shares <- age_cluster_rates |>
  dplyr::group_by(measure, measure_short, age, age_index, age_midpoint) |>
  dplyr::mutate(
    classified_rate_per_100k = sum(rate_per_100k),
    share_of_classified = safe_ratio(rate_per_100k, classified_rate_per_100k)
  ) |>
  dplyr::ungroup() |>
  dplyr::left_join(all_causes_age_rates, by = c("measure", "age")) |>
  dplyr::mutate(
    share_of_all_causes = safe_ratio(
      rate_per_100k,
      all_causes_rate_per_100k
    ),
    classified_coverage_of_all_causes = safe_ratio(
      classified_rate_per_100k,
      all_causes_rate_per_100k
    )
  ) |>
  dplyr::arrange(measure_short, age_index, cluster_name)

readr::write_csv(
  age_cluster_rates,
  file.path(output_dir, "Part3_30_69_age_specific_cluster_rates.csv")
)
readr::write_csv(
  age_cluster_shares,
  file.path(output_dir, "Part3_30_69_age_specific_cluster_shares.csv")
)

# ------------------------------------------------------------------------------
# 11. Cause-level 30-69 burden and leading causes in each cluster
# ------------------------------------------------------------------------------

cause_burden <- classified_data |>
  dplyr::filter(metric == "Number") |>
  dplyr::group_by(measure, measure_short, cluster_name, cause) |>
  dplyr::summarise(estimate = sum(val, na.rm = TRUE), .groups = "drop") |>
  dplyr::left_join(
    cluster_number |>
      dplyr::rename(cluster_total = estimate) |>
      dplyr::select(measure, cluster_name, cluster_total),
    by = c("measure", "cluster_name")
  ) |>
  dplyr::left_join(
    classified_measure_totals,
    by = c("measure", "measure_short")
  ) |>
  dplyr::left_join(
    all_causes_number,
    by = c("measure", "measure_short")
  ) |>
  dplyr::mutate(
    share_within_cluster = safe_ratio(estimate, cluster_total),
    share_of_classified_30_69 = safe_ratio(estimate, classified_total_30_69),
    share_of_all_causes_30_69 = safe_ratio(estimate, all_causes_30_69),
    cluster_name = factor(cluster_name, levels = cluster_order),
    measure_short = factor(
      measure_short,
      levels = c("Deaths", "YLLs", "YLDs", "DALYs")
    )
  ) |>
  dplyr::arrange(measure_short, cluster_name, dplyr::desc(estimate))

readr::write_csv(
  cause_burden,
  file.path(output_dir, "Part3_30_69_cause_burden_all.csv")
)

top10_causes <- cause_burden |>
  dplyr::group_by(measure_short, cluster_name) |>
  dplyr::slice_max(estimate, n = 10, with_ties = FALSE) |>
  dplyr::arrange(measure_short, cluster_name, dplyr::desc(estimate)) |>
  dplyr::mutate(rank_within_cluster = dplyr::row_number()) |>
  dplyr::ungroup()
