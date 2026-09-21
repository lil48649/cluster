#!/usr/bin/env Rscript

# ==============================================================================
# China GBD 2023 disease age-profile clusters — Part 3
# 1990–2023 trends in disease-cluster burden among adults aged 30–69 years
#
# IMPORTANT METHOD RULE
#   - This script NEVER reruns clustering.
#   - The 2023 Stage 1 k=3 disease membership is frozen and projected backward
#     onto every year from 1990 through 2023.
#   - The public-health analysis window is ages 30–69 years (eight 5-year groups).
#
# Required local inputs
#   Seven GBD CSV files:
#     IHME-GBD_2023_DATA-1990-1994.csv
#     IHME-GBD_2023_DATA-1995-1999.csv
#     IHME-GBD_2023_DATA-2000-2004.csv
#     IHME-GBD_2023_DATA-2005-2009.csv
#     IHME-GBD_2023_DATA-2010-2014.csv
#     IHME-GBD_2023_DATA-2015-2019.csv
#     IHME-GBD_2023_DATA-2020-2023.csv
#
#   Frozen cluster membership, tried in this order:
#     Stage2_Figure2_onward_outputs/Stage2_frozen_cluster_membership_used.csv
#     Stage2_frozen_cluster_membership_used.csv
#     Figure1_k3_cluster_membership.csv
#     Part2_cluster_membership.csv
#
# Main-text outputs
#   Figure 6: 1990–2023 trends in Deaths and DALYs:
#             absolute numbers + standardized rates
#   Figure 7: changing cluster composition of Deaths, YLLs, YLDs and DALYs
#   Figure 8: Shapley decomposition of 1990→2023 change into:
#             population size, age structure, age-specific rates
#   Table 2 : 1990 vs 2023 burden, percentage change and EAPC
#   Table 3 : decomposition results for all four burden measures
#
# Standardized rates
#   The GBD download contains eight age-specific rates rather than a pre-computed
#   30–69 age-standardized rate. This script therefore performs direct
#   standardization using the GBD 2021 world population age standard.
#
#   For the restricted 30–69-year analysis window, the official GBD standard
#   weights for ages 30–34 through 65–69 are re-normalized to sum to 1 across
#   these eight included age groups. The resulting rate is the directly
#   age-standardized 30–69 rate under the GBD 2021 world age standard.
#
# Decomposition
#   Burden = total population × age share × age-specific rate.
#   A three-factor Shapley decomposition averages marginal contributions over
#   all six factor orderings, making the result order-independent.
# ==============================================================================

# ------------------------------------------------------------------------------
# 0. User configuration
# ------------------------------------------------------------------------------

input_files <- c(
  "IHME-GBD_2023_DATA-1990-1994.csv",
  "IHME-GBD_2023_DATA-1995-1999.csv",
  "IHME-GBD_2023_DATA-2000-2004.csv",
  "IHME-GBD_2023_DATA-2005-2009.csv",
  "IHME-GBD_2023_DATA-2010-2014.csv",
  "IHME-GBD_2023_DATA-2015-2019.csv",
  "IHME-GBD_2023_DATA-2020-2023.csv"
)

input_year_ranges <- list(
  1990:1994,
  1995:1999,
  2000:2004,
  2005:2009,
  2010:2014,
  2015:2019,
  2020:2023
)

membership_file_candidates <- c(
  file.path(
    "Stage2_Figure2_onward_outputs",
    "Stage2_frozen_cluster_membership_used.csv"
  ),
  "Stage2_frozen_cluster_membership_used.csv",
  "Figure1_k3_cluster_membership.csv",
  "Part2_cluster_membership.csv"
)

output_dir <- "Part3_1990_2023_trends_outputs"

years_expected <- 1990:2023

age_30_69 <- c(
  "30-34 years", "35-39 years", "40-44 years", "45-49 years",
  "50-54 years", "55-59 years", "60-64 years", "65-69 years"
)

age_midpoints_30_69 <- c(32, 37, 42, 47, 52, 57, 62, 67)

# GBD 2021 world population age standard: exact "Percent of Population"
# values for the eight age groups included in the 30–69 analysis.
# Source: GBD 2021 Appendix Table S14.
gbd2021_world_standard_percent_30_69 <- c(
  7.32171,  # 30-34 years
  6.82805,  # 35-39 years
  6.14735,  # 40-44 years
  5.51133,  # 45-49 years
  4.91312,  # 50-54 years
  4.34586,  # 55-59 years
  3.68223,  # 60-64 years
  2.98509   # 65-69 years
)

if (
  length(gbd2021_world_standard_percent_30_69) !=
    length(age_30_69)
) {
  stop("GBD 2021 standard-weight vector does not match the eight age groups.")
}

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

cluster_order <- c("Infant", "Adult", "Aging-related")
cluster_colors <- c(
  "Infant" = "#2CA02C",
  "Adult" = "#2878B5",
  "Aging-related" = "#E31A1C"
)

decomposition_colors <- c(
  "Population size" = "#4C78A8",
  "Age structure" = "#F58518",
  "Age-specific rates" = "#54A24B"
)

expected_n_detailed_causes <- 304L
expected_n_clustered_causes <- 292L
expected_n_unclassified_causes <- 12L

expected_cluster_counts <- c(
  "Infant" = 57L,
  "Adult" = 71L,
  "Aging-related" = 164L
)

# Known structurally age-inapplicable causes from the Stage 1 audit.
# Missing selected cause-age cells are set to zero; all missing cells are also
# exported so any unexpected pattern can be reviewed.
known_structural_zero_causes <- c(
  "Sudden infant death syndrome",
  "Indirect maternal deaths",
  "Late maternal deaths",
  "Maternal deaths aggravated by HIV/AIDS",
  "Aortic aneurysm"
)

# ------------------------------------------------------------------------------
# 1. Package checks
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

safe_ratio <- function(num, den) {
  ifelse(is.finite(den) & den != 0, num / den, NA_real_)
}

percent_change <- function(v0, v1) {
  ifelse(is.finite(v0) & v0 != 0, (v1 / v0 - 1) * 100, NA_real_)
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

fit_eapc <- function(year, value) {
  ok <- is.finite(year) & is.finite(value) & value > 0

  if (sum(ok) < 3L) {
    return(
      tibble::tibble(
        EAPC_percent = NA_real_,
        EAPC_lower95 = NA_real_,
        EAPC_upper95 = NA_real_,
        loglinear_R2 = NA_real_
      )
    )
  }

  fit <- stats::lm(log(value[ok]) ~ year[ok])
  sm <- summary(fit)
  beta <- stats::coef(fit)[2]
  se <- sm$coefficients[2, "Std. Error"]

  tibble::tibble(
    EAPC_percent = (exp(beta) - 1) * 100,
    EAPC_lower95 = (exp(beta - 1.96 * se) - 1) * 100,
    EAPC_upper95 = (exp(beta + 1.96 * se) - 1) * 100,
    loglinear_R2 = sm$r.squared
  )
}

shapley_decompose_one <- function(
  age_rate_population,
  actual_summary,
  measure_value,
  cluster_value,
  year0 = 1990L,
  year1 = 2023L
) {
  d0 <- age_rate_population |>
    dplyr::filter(
      year == year0,
      measure == measure_value,
      cluster_name == cluster_value
    ) |>
    dplyr::arrange(age_index)

  d1 <- age_rate_population |>
    dplyr::filter(
      year == year1,
      measure == measure_value,
      cluster_name == cluster_value
    ) |>
    dplyr::arrange(age_index)

  if (nrow(d0) != length(age_30_69) || nrow(d1) != length(age_30_69)) {
    stop(
      "Decomposition requires eight age groups for ",
      measure_value, " / ", cluster_value, "."
    )
  }

  n0 <- sum(d0$population)
  n1 <- sum(d1$population)

  s0 <- d0$population / n0
  s1 <- d1$population / n1

  r0 <- d0$rate_per_100k
  r1 <- d1$rate_per_100k

  burden_fun <- function(n_total, age_share, age_rate) {
    n_total * sum(age_share * age_rate) / 100000
  }

  permutations <- list(
    c("population_size", "age_structure", "age_specific_rates"),
    c("population_size", "age_specific_rates", "age_structure"),
    c("age_structure", "population_size", "age_specific_rates"),
    c("age_structure", "age_specific_rates", "population_size"),
    c("age_specific_rates", "population_size", "age_structure"),
    c("age_specific_rates", "age_structure", "population_size")
  )

  contributions <- matrix(
    0,
    nrow = length(permutations),
    ncol = 3,
    dimnames = list(
      NULL,
      c("population_size", "age_structure", "age_specific_rates")
    )
  )

  for (p in seq_along(permutations)) {
    n_now <- n0
    s_now <- s0
    r_now <- r0

    prev <- burden_fun(n_now, s_now, r_now)

    for (factor_name in permutations[[p]]) {
      if (factor_name == "population_size") {
        n_now <- n1
      } else if (factor_name == "age_structure") {
        s_now <- s1
      } else if (factor_name == "age_specific_rates") {
        r_now <- r1
      }

      current <- burden_fun(n_now, s_now, r_now)
      contributions[p, factor_name] <-
        contributions[p, factor_name] + (current - prev)
      prev <- current
    }
  }

  mean_contrib <- colMeans(contributions)

  modeled_1990 <- burden_fun(n0, s0, r0)
  modeled_2023 <- burden_fun(n1, s1, r1)

  actual_1990 <- actual_summary |>
    dplyr::filter(
      year == year0,
      measure == measure_value,
      cluster_name == cluster_value
    ) |>
    dplyr::pull(number)

  actual_2023 <- actual_summary |>
    dplyr::filter(
      year == year1,
      measure == measure_value,
      cluster_name == cluster_value
    ) |>
    dplyr::pull(number)

  if (length(actual_1990) != 1L || length(actual_2023) != 1L) {
    stop("Actual burden lookup failed during decomposition.")
  }

  component_labels <- c(
    population_size = "Population size",
    age_structure = "Age structure",
    age_specific_rates = "Age-specific rates"
  )

  tibble::tibble(
    measure = measure_value,
    measure_short = unname(measure_short_lookup[measure_value]),
    cluster_name = cluster_value,
    component_key = names(mean_contrib),
    component = unname(component_labels[names(mean_contrib)]),
    contribution_number = as.numeric(mean_contrib),
    modeled_1990 = modeled_1990,
    modeled_2023 = modeled_2023,
    modeled_net_change = modeled_2023 - modeled_1990,
    actual_1990 = actual_1990,
    actual_2023 = actual_2023,
    actual_net_change = actual_2023 - actual_1990,
    contribution_sum = sum(mean_contrib),
    modeled_reconstruction_error =
      sum(mean_contrib) - (modeled_2023 - modeled_1990),
    actual_vs_modeled_change_difference =
      (actual_2023 - actual_1990) - (modeled_2023 - modeled_1990)
  )
}

# ------------------------------------------------------------------------------
# 3. Locate inputs and read frozen membership
# ------------------------------------------------------------------------------

missing_input_files <- input_files[!file.exists(input_files)]
if (length(missing_input_files) > 0L) {
  stop(
    "Missing Part 3 GBD files:\n  ",
    paste(missing_input_files, collapse = "\n  ")
  )
}

membership_file <- first_existing_file(
  membership_file_candidates,
  "Frozen Stage 1/2 cluster-membership file"
)

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

message("Frozen membership: ", membership_file)
message("Output directory: ", normalizePath(output_dir, mustWork = FALSE))

membership_raw <- readr::read_csv(membership_file, show_col_types = FALSE)

if ("disease" %in% names(membership_raw) && !"cause" %in% names(membership_raw)) {
  membership_raw <- dplyr::rename(membership_raw, cause = disease)
}

if (!all(c("cause", "cluster_name") %in% names(membership_raw))) {
  stop("Membership file must contain cause and cluster_name columns.")
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

if (nrow(cluster_membership) != expected_n_clustered_causes) {
  stop(
    "Frozen membership contains ", nrow(cluster_membership),
    " causes; expected ", expected_n_clustered_causes, "."
  )
}

if (any(is.na(cluster_membership$cluster_name))) {
  stop("Unexpected cluster labels were found in the membership file.")
}

membership_counts <- cluster_membership |>
  dplyr::count(cluster_name, name = "n") |>
  dplyr::mutate(cluster_name = as.character(cluster_name))

observed_cluster_counts <- stats::setNames(
  rep(0L, length(cluster_order)),
  cluster_order
)
observed_cluster_counts[membership_counts$cluster_name] <- membership_counts$n

if (!all(observed_cluster_counts == expected_cluster_counts[cluster_order])) {
  stop(
    "Frozen cluster sizes do not match the finalized solution. Observed: ",
    paste(
      paste0(cluster_order, "=", observed_cluster_counts[cluster_order]),
      collapse = "; "
    )
  )
}

# ------------------------------------------------------------------------------
# 4. Read the seven year-batch files
# ------------------------------------------------------------------------------

required_columns <- c(
  "population_group", "measure", "location", "sex", "age",
  "cause", "metric", "year", "val", "upper", "lower"
)

batch_list <- vector("list", length(input_files))
batch_audit_rows <- vector("list", length(input_files))

for (i in seq_along(input_files)) {
  message("Reading: ", input_files[i])

  dat <- readr::read_csv(input_files[i], show_col_types = FALSE)

  missing_cols <- setdiff(required_columns, names(dat))
  if (length(missing_cols) > 0L) {
    stop(
      input_files[i],
      " is missing columns: ",
      paste(missing_cols, collapse = ", ")
    )
  }

  filtered <- dat |>
    dplyr::filter(
      population_group == "All Population",
      location == "China",
      sex == "Both",
      year %in% input_year_ranges[[i]],
      age %in% age_30_69,
      measure %in% measure_order,
      metric %in% c("Number", "Rate")
    ) |>
    dplyr::mutate(
      source_file = input_files[i],
      measure_short = unname(measure_short_lookup[measure])
    )

  years_found <- sort(unique(filtered$year))

  if (!identical(as.integer(years_found), as.integer(input_year_ranges[[i]]))) {
    stop(
      input_files[i],
      " does not contain exactly the expected years. Found: ",
      paste(years_found, collapse = ", "),
      "; expected: ",
      paste(input_year_ranges[[i]], collapse = ", ")
    )
  }

  duplicate_n <- filtered |>
    dplyr::count(year, measure, age, cause, metric, name = "n") |>
    dplyr::filter(n > 1L) |>
    nrow()

  if (duplicate_n > 0L) {
    stop(
      input_files[i],
      " contains duplicated year-measure-age-cause-metric cells."
    )
  }

  batch_audit_rows[[i]] <- tibble::tibble(
    source_file = input_files[i],
    expected_start_year = min(input_year_ranges[[i]]),
    expected_end_year = max(input_year_ranges[[i]]),
    filtered_rows = nrow(filtered),
    distinct_years = dplyr::n_distinct(filtered$year),
    distinct_causes = dplyr::n_distinct(filtered$cause),
    distinct_ages = dplyr::n_distinct(filtered$age),
    distinct_measures = dplyr::n_distinct(filtered$measure),
    distinct_metrics = dplyr::n_distinct(filtered$metric),
    duplicated_cells = duplicate_n
  )

  batch_list[[i]] <- filtered

  rm(dat, filtered)
  invisible(gc())
}

analysis_observed <- dplyr::bind_rows(batch_list)
batch_audit <- dplyr::bind_rows(batch_audit_rows)

readr::write_csv(
  batch_audit,
  file.path(output_dir, "Part3_input_batch_audit.csv")
)

# ------------------------------------------------------------------------------
# 5. Combined-data QC and complete fixed 292-cause grid
# ------------------------------------------------------------------------------

if (!identical(
  as.integer(sort(unique(analysis_observed$year))),
  as.integer(years_expected)
)) {
  stop("Combined files do not cover every year from 1990 through 2023.")
}

if (!all(age_30_69 %in% unique(analysis_observed$age))) {
  stop(
    "Missing age groups: ",
    paste(
      setdiff(age_30_69, unique(analysis_observed$age)),
      collapse = ", "
    )
  )
}

if (!all(measure_order %in% unique(analysis_observed$measure))) {
  stop(
    "Missing measures: ",
    paste(
      setdiff(measure_order, unique(analysis_observed$measure)),
      collapse = ", "
    )
  )
}

candidate_detailed_causes <- analysis_observed |>
  dplyr::filter(cause != "All causes") |>
  dplyr::distinct(cause) |>
  dplyr::arrange(cause)

if (nrow(candidate_detailed_causes) != expected_n_detailed_causes) {
  stop(
    "Combined data contain ", nrow(candidate_detailed_causes),
    " detailed causes; expected ", expected_n_detailed_causes, "."
  )
}

unclassified_causes <- candidate_detailed_causes |>
  dplyr::anti_join(cluster_membership, by = "cause") |>
  dplyr::arrange(cause)

if (nrow(unclassified_causes) != expected_n_unclassified_causes) {
  stop(
    "Found ", nrow(unclassified_causes),
    " detailed causes outside the frozen 292-cause membership; expected ",
    expected_n_unclassified_causes, "."
  )
}

readr::write_csv(
  unclassified_causes,
  file.path(output_dir, "Part3_unclassified_12_causes.csv")
)

# All-causes rows are essential for population inference and closure.
all_causes_data <- analysis_observed |>
  dplyr::filter(cause == "All causes") |>
  dplyr::select(
    year, measure, measure_short, age, metric,
    val, upper, lower
  )

expected_all_causes_cells <-
  length(years_expected) *
  length(measure_order) *
  length(age_30_69) *
  2L

if (nrow(all_causes_data) != expected_all_causes_cells) {
  stop(
    "All-causes grid is incomplete. Found ", nrow(all_causes_data),
    " rows; expected ", expected_all_causes_cells, "."
  )
}

# Build the complete expected grid for the frozen 292 diseases.
classified_observed <- analysis_observed |>
  dplyr::filter(cause != "All causes") |>
  dplyr::inner_join(
    cluster_membership |>
      dplyr::mutate(cluster_name = as.character(cluster_name)),
    by = "cause"
  ) |>
  dplyr::select(
    year, measure, measure_short, age, cause, metric,
    val, upper, lower, cluster_name
  )

expected_classified_grid <- tidyr::expand_grid(
  year = years_expected,
  measure = measure_order,
  age = age_30_69,
  cause = cluster_membership$cause,
  metric = c("Number", "Rate")
)

missing_classified_cells <- expected_classified_grid |>
  dplyr::anti_join(
    classified_observed,
    by = c("year", "measure", "age", "cause", "metric")
  ) |>
  dplyr::left_join(
    cluster_membership |>
      dplyr::mutate(cluster_name = as.character(cluster_name)),
    by = "cause"
  ) |>
  dplyr::mutate(
    known_structural_zero_cause =
      cause %in% known_structural_zero_causes
  ) |>
  dplyr::arrange(cause, year, measure, age, metric)

readr::write_csv(
  missing_classified_cells,
  file.path(output_dir, "Part3_missing_classified_cells_filled_zero.csv")
)

missing_cell_summary <- missing_classified_cells |>
  dplyr::count(
    cause,
    known_structural_zero_cause,
    measure,
    metric,
    name = "missing_cells"
  ) |>
  dplyr::arrange(
    dplyr::desc(known_structural_zero_cause),
    cause,
    measure,
    metric
  )

readr::write_csv(
  missing_cell_summary,
  file.path(output_dir, "Part3_missing_cells_summary.csv")
)

classified_data <- expected_classified_grid |>
  dplyr::left_join(
    classified_observed |>
      dplyr::select(
        year, measure, age, cause, metric,
        val, upper, lower
      ),
    by = c("year", "measure", "age", "cause", "metric")
  ) |>
  dplyr::mutate(
    val = tidyr::replace_na(val, 0),
    upper = tidyr::replace_na(upper, 0),
    lower = tidyr::replace_na(lower, 0),
    measure_short = unname(measure_short_lookup[measure])
  ) |>
  dplyr::left_join(
    cluster_membership |>
      dplyr::mutate(cluster_name = as.character(cluster_name)),
    by = "cause"
  ) |>
  dplyr::mutate(
    age = factor(age, levels = age_30_69, ordered = TRUE),
    age_index = as.integer(age),
    age_midpoint = age_midpoints_30_69[age_index],
    cluster_name = factor(cluster_name, levels = cluster_order),
    measure_short = factor(
      measure_short,
      levels = c("Deaths", "YLLs", "YLDs", "DALYs")
    )
  )

# ------------------------------------------------------------------------------
# 6. Audit the 12 causes excluded because their 2023 trajectory was all-zero
# ------------------------------------------------------------------------------
# Some of these diseases may have had historical burden even though they had
# no informative China 2023 trajectory. They remain outside the frozen clusters,
# but their yearly burden is quantified so historical coverage is transparent.

unclassified_yearly <- analysis_observed |>
  dplyr::filter(
    cause %in% unclassified_causes$cause,
    metric == "Number"
  ) |>
  dplyr::group_by(year, measure, measure_short, cause) |>
  dplyr::summarise(
    number = sum(val, na.rm = TRUE),
    .groups = "drop"
  )

unclassified_yearly_total <- unclassified_yearly |>
  dplyr::group_by(year, measure, measure_short) |>
  dplyr::summarise(
    unclassified_12_number = sum(number, na.rm = TRUE),
    .groups = "drop"
  )

readr::write_csv(
  unclassified_yearly,
  file.path(output_dir, "Part3_unclassified_12_cause_burden_by_year.csv")
)

# ------------------------------------------------------------------------------
# 7. Infer age-specific population denominators
# ------------------------------------------------------------------------------
# For any all-cause measure:
#   population = Number / Rate × 100,000.
# We infer population independently from all four measures and use the median.
# The spread among the four estimates is retained as a QC metric.

population_candidates <- all_causes_data |>
  dplyr::select(year, measure, age, metric, val) |>
  tidyr::pivot_wider(
    names_from = metric,
    values_from = val
  ) |>
  dplyr::mutate(
    population_implied = dplyr::if_else(
      is.finite(Number) & is.finite(Rate) & Rate > 0,
      Number / Rate * 100000,
      NA_real_
    )
  )

population_by_age <- population_candidates |>
  dplyr::mutate(
    age = factor(age, levels = age_30_69, ordered = TRUE),
    age_index = as.integer(age),
    age_midpoint = age_midpoints_30_69[age_index]
  ) |>
  dplyr::group_by(year, age, age_index, age_midpoint) |>
  dplyr::summarise(
    n_population_estimates = sum(is.finite(population_implied)),
    population = stats::median(population_implied, na.rm = TRUE),
    population_min = min(population_implied, na.rm = TRUE),
    population_max = max(population_implied, na.rm = TRUE),
    max_relative_deviation = max(
      abs(
        population_implied -
          stats::median(population_implied, na.rm = TRUE)
      ) /
        stats::median(population_implied, na.rm = TRUE),
      na.rm = TRUE
    ),
    .groups = "drop"
  ) |>
  dplyr::arrange(year, age_index)

if (nrow(population_by_age) != length(years_expected) * length(age_30_69)) {
  stop("Population inference did not return 8 age groups for every year.")
}

if (any(!is.finite(population_by_age$population))) {
  stop("Non-finite population denominator detected.")
}

readr::write_csv(
  population_candidates,
  file.path(output_dir, "Part3_population_denominator_candidates.csv")
)

readr::write_csv(
  population_by_age,
  file.path(output_dir, "Part3_population_by_age_1990_2023.csv")
)

population_total <- population_by_age |>
  dplyr::group_by(year) |>
  dplyr::summarise(
    population_30_69 = sum(population),
    .groups = "drop"
  )

# GBD 2021 world population age-standard weights for ages 30–69.
#
# The published percentages are defined relative to the full GBD world standard
# population. Because this study deliberately restricts the standardized rate
# to ages 30–69, the eight included weights are re-normalized to sum to 1.
# Their unnormalized total is retained for auditing.
standard_weights <- tibble::tibble(
  age = factor(age_30_69, levels = age_30_69, ordered = TRUE),
  age_index = seq_along(age_30_69),
  age_midpoint = age_midpoints_30_69,
  gbd2021_world_standard_percent =
    gbd2021_world_standard_percent_30_69
) |>
  dplyr::mutate(
    gbd2021_30_69_percent_total =
      sum(gbd2021_world_standard_percent),
    standard_weight =
      gbd2021_world_standard_percent /
      gbd2021_30_69_percent_total
  )

if (
  abs(
    unique(standard_weights$gbd2021_30_69_percent_total) -
      41.73474
  ) > 1e-8
) {
  stop("Unexpected sum of GBD 2021 world-standard percentages for ages 30–69.")
}

if (abs(sum(standard_weights$standard_weight) - 1) > 1e-12) {
  stop("Re-normalized GBD 2021 standard age weights do not sum to 1.")
}

readr::write_csv(
  standard_weights,
  file.path(
    output_dir,
    "Part3_standard_weights_GBD2021_world_age30_69.csv"
  )
)

# ------------------------------------------------------------------------------
# 8. Cluster burden by year: Number, crude rate, standardized rate and shares
# ------------------------------------------------------------------------------

cluster_number <- classified_data |>
  dplyr::filter(metric == "Number") |>
  dplyr::group_by(
    year, measure, measure_short, cluster_name
  ) |>
  dplyr::summarise(
    number = sum(val, na.rm = TRUE),
    .groups = "drop"
  )

classified_total <- cluster_number |>
  dplyr::group_by(year, measure, measure_short) |>
  dplyr::summarise(
    classified_total = sum(number),
    .groups = "drop"
  )

all_causes_number <- all_causes_data |>
  dplyr::filter(metric == "Number") |>
  dplyr::group_by(year, measure, measure_short) |>
  dplyr::summarise(
    all_causes_number = sum(val, na.rm = TRUE),
    .groups = "drop"
  )

age_cluster_rates <- classified_data |>
  dplyr::filter(metric == "Rate") |>
  dplyr::group_by(
    year, measure, measure_short,
    cluster_name, age, age_index, age_midpoint
  ) |>
  dplyr::summarise(
    rate_per_100k = sum(val, na.rm = TRUE),
    .groups = "drop"
  )

standardized_cluster_rates <- age_cluster_rates |>
  dplyr::left_join(
    standard_weights |>
      dplyr::select(age, standard_weight),
    by = "age"
  ) |>
  dplyr::group_by(
    year, measure, measure_short, cluster_name
  ) |>
  dplyr::summarise(
    standardized_rate_per_100k_GBD2021 =
      sum(rate_per_100k * standard_weight),
    .groups = "drop"
  )

cluster_summary <- cluster_number |>
  dplyr::left_join(
    population_total,
    by = "year"
  ) |>
  dplyr::left_join(
    standardized_cluster_rates,
    by = c("year", "measure", "measure_short", "cluster_name")
  ) |>
  dplyr::left_join(
    classified_total,
    by = c("year", "measure", "measure_short")
  ) |>
  dplyr::left_join(
    all_causes_number,
    by = c("year", "measure", "measure_short")
  ) |>
  dplyr::mutate(
    crude_rate_per_100k = number / population_30_69 * 100000,
    share_of_classified = safe_ratio(number, classified_total),
    share_of_all_causes = safe_ratio(number, all_causes_number),
    cluster_name = factor(cluster_name, levels = cluster_order),
    measure_short = factor(
      measure_short,
      levels = c("Deaths", "YLLs", "YLDs", "DALYs")
    )
  ) |>
  dplyr::arrange(measure_short, cluster_name, year)

readr::write_csv(
  cluster_summary,
  file.path(output_dir, "Part3_cluster_burden_1990_2023.csv")
)

# Join population to age-specific cluster rates for decomposition.
age_rate_population <- age_cluster_rates |>
  dplyr::left_join(
    population_by_age |>
      dplyr::select(year, age, population),
    by = c("year", "age")
  )

# ------------------------------------------------------------------------------
# 9. Yearly closure against GBD All causes
# ------------------------------------------------------------------------------

closure_yearly <- classified_total |>
  dplyr::left_join(
    all_causes_number,
    by = c("year", "measure", "measure_short")
  ) |>
  dplyr::left_join(
    unclassified_yearly_total,
    by = c("year", "measure", "measure_short")
  ) |>
  dplyr::mutate(
    unclassified_12_number =
      tidyr::replace_na(unclassified_12_number, 0),
    classified_to_all_ratio =
      safe_ratio(classified_total, all_causes_number),
    unclassified_12_share_of_all =
      safe_ratio(unclassified_12_number, all_causes_number),
    classified_plus_unclassified_to_all =
      safe_ratio(
        classified_total + unclassified_12_number,
        all_causes_number
      )
  ) |>
  dplyr::arrange(measure_short, year)

readr::write_csv(
  closure_yearly,
  file.path(output_dir, "Part3_yearly_closure_1990_2023.csv")
)

# ------------------------------------------------------------------------------
# 10. Table 2 — 1990 vs 2023 change and EAPC
# ------------------------------------------------------------------------------

trend_keys <- tidyr::expand_grid(
  measure = measure_order,
  cluster_name = cluster_order
)

trend_rows <- vector("list", nrow(trend_keys))

for (i in seq_len(nrow(trend_keys))) {
  this_measure <- trend_keys$measure[i]
  this_cluster <- trend_keys$cluster_name[i]

  d <- cluster_summary |>
    dplyr::filter(
      measure == this_measure,
      as.character(cluster_name) == this_cluster
    ) |>
    dplyr::arrange(year)

  d1990 <- d |>
    dplyr::filter(year == 1990)

  d2023 <- d |>
    dplyr::filter(year == 2023)

  if (nrow(d1990) != 1L || nrow(d2023) != 1L) {
    stop("Endpoint lookup failed for trend table.")
  }

  eapc <- fit_eapc(
    d$year,
    d$standardized_rate_per_100k_GBD2021
  )

  trend_rows[[i]] <- tibble::tibble(
    measure = this_measure,
    measure_short = unname(measure_short_lookup[this_measure]),
    cluster_name = this_cluster,

    number_1990 = d1990$number,
    number_2023 = d2023$number,
    number_absolute_change = d2023$number - d1990$number,
    number_percent_change =
      percent_change(d1990$number, d2023$number),

    crude_rate_1990 = d1990$crude_rate_per_100k,
    crude_rate_2023 = d2023$crude_rate_per_100k,
    crude_rate_percent_change =
      percent_change(
        d1990$crude_rate_per_100k,
        d2023$crude_rate_per_100k
      ),

    standardized_rate_1990 =
      d1990$standardized_rate_per_100k_GBD2021,
    standardized_rate_2023 =
      d2023$standardized_rate_per_100k_GBD2021,
    standardized_rate_percent_change =
      percent_change(
        d1990$standardized_rate_per_100k_GBD2021,
        d2023$standardized_rate_per_100k_GBD2021
      ),

    share_of_classified_1990 = d1990$share_of_classified,
    share_of_classified_2023 = d2023$share_of_classified,
    share_change_percentage_points =
      (d2023$share_of_classified - d1990$share_of_classified) * 100,

    EAPC_standardized_rate_percent = eapc$EAPC_percent,
    EAPC_lower95 = eapc$EAPC_lower95,
    EAPC_upper95 = eapc$EAPC_upper95,
    EAPC_loglinear_R2 = eapc$loglinear_R2
  )
}

trend_table <- dplyr::bind_rows(trend_rows) |>
  dplyr::mutate(
    cluster_name = factor(cluster_name, levels = cluster_order),
    measure_short = factor(
      measure_short,
      levels = c("Deaths", "YLLs", "YLDs", "DALYs")
    )
  ) |>
  dplyr::arrange(measure_short, cluster_name)

readr::write_csv(
  trend_table,
  file.path(output_dir, "Table2_cluster_trends_1990_2023.csv")
)

# ------------------------------------------------------------------------------
# 11. Figure 6 — absolute and standardized Death/DALY trends
# ------------------------------------------------------------------------------

figure6_data <- cluster_summary |>
  dplyr::filter(
    as.character(measure_short) %in% c("Deaths", "DALYs")
  ) |>
  dplyr::transmute(
    year,
    measure_short = as.character(measure_short),
    cluster_name,
    number_millions = number / 1e6,
    standardized_rate =
      standardized_rate_per_100k_GBD2021
  ) |>
  tidyr::pivot_longer(
    cols = c(number_millions, standardized_rate),
    names_to = "trend_metric",
    values_to = "value"
  ) |>
  dplyr::mutate(
    panel = dplyr::case_when(
      measure_short == "Deaths" &
        trend_metric == "number_millions" ~
        "Deaths — Number (millions)",
      measure_short == "Deaths" &
        trend_metric == "standardized_rate" ~
        "Deaths — Standardized rate",
      measure_short == "DALYs" &
        trend_metric == "number_millions" ~
        "DALYs — Number (millions)",
      measure_short == "DALYs" &
        trend_metric == "standardized_rate" ~
        "DALYs — Standardized rate",
      TRUE ~ NA_character_
    ),
    panel = factor(
      panel,
      levels = c(
        "Deaths — Number (millions)",
        "Deaths — Standardized rate",
        "DALYs — Number (millions)",
        "DALYs — Standardized rate"
      )
    )
  )

p6 <- ggplot2::ggplot(
  figure6_data,
  ggplot2::aes(
    x = year,
    y = value,
    color = cluster_name,
    group = cluster_name
  )
) +
  ggplot2::geom_line(linewidth = 1.05, lineend = "round") +
  ggplot2::facet_wrap(~panel, scales = "free_y", ncol = 2) +
  ggplot2::scale_color_manual(
    values = cluster_colors,
    breaks = cluster_order,
    drop = FALSE
  ) +
  ggplot2::scale_x_continuous(
    breaks = c(1990, 2000, 2010, 2020, 2023)
  ) +
  ggplot2::scale_y_continuous(
    labels = scales::label_number(big.mark = ",")
  ) +
  ggplot2::labs(
    title = "Trends in disease-cluster burden among adults aged 30–69 years, China, 1990–2023",
    subtitle = paste0(
      "Numbers and directly standardized rates; standardized rates use the ",
      "GBD 2021 world population age standard, re-normalized to ages 30–69"
    ),
    x = "Year",
    y = NULL,
    color = "Disease cluster",
    caption = paste0(
      "Source: GBD 2023, Both sexes. Cluster membership is fixed from the ",
      "2023 all-age DALY age-profile classification."
    )
  ) +
  ggplot2::theme_bw(base_size = 11.5) +
  ggplot2::theme(
    legend.position = "bottom",
    panel.grid.minor = ggplot2::element_blank(),
    panel.grid.major = ggplot2::element_line(
      color = "grey92",
      linewidth = 0.4
    ),
    strip.background = ggplot2::element_rect(
      fill = "grey94",
      color = "grey75"
    ),
    strip.text = ggplot2::element_text(face = "bold"),
    plot.title = ggplot2::element_text(face = "bold", size = 15),
    plot.subtitle = ggplot2::element_text(color = "grey35"),
    plot.caption = ggplot2::element_text(
      size = 8,
      color = "grey40",
      hjust = 0
    )
  )

save_plot_pair(
  p6,
  "Figure6_cluster_trends_Deaths_DALYs_1990_2023",
  width = 11,
  height = 8
)

# ------------------------------------------------------------------------------
# 12. Figure 7 — changing composition of the 30–69 burden
# ------------------------------------------------------------------------------

p7 <- ggplot2::ggplot(
  cluster_summary,
  ggplot2::aes(
    x = year,
    y = share_of_classified,
    color = cluster_name,
    group = cluster_name
  )
) +
  ggplot2::geom_line(linewidth = 1.05, lineend = "round") +
  ggplot2::facet_wrap(
    ~measure_short,
    ncol = 2
  ) +
  ggplot2::scale_color_manual(
    values = cluster_colors,
    breaks = cluster_order,
    drop = FALSE
  ) +
  ggplot2::scale_x_continuous(
    breaks = c(1990, 2000, 2010, 2020, 2023)
  ) +
  ggplot2::scale_y_continuous(
    labels = scales::percent_format(accuracy = 1),
    expand = ggplot2::expansion(mult = c(0.01, 0.03))
  ) +
  ggplot2::coord_cartesian(ylim = c(0, 1)) +
  ggplot2::labs(
    title = "Changing disease-cluster composition of burden at ages 30–69, China, 1990–2023",
    subtitle = "Shares are calculated within the fixed 292 classified causes in each year",
    x = "Year",
    y = "Share of classified burden",
    color = "Disease cluster",
    caption = paste0(
      "Source: GBD 2023, Both sexes. The same 2023 disease-cluster membership ",
      "is applied retrospectively to all years."
    )
  ) +
  ggplot2::theme_bw(base_size = 11.5) +
  ggplot2::theme(
    legend.position = "bottom",
    panel.grid.minor = ggplot2::element_blank(),
    panel.grid.major = ggplot2::element_line(
      color = "grey92",
      linewidth = 0.4
    ),
    strip.background = ggplot2::element_rect(
      fill = "grey94",
      color = "grey75"
    ),
    strip.text = ggplot2::element_text(face = "bold"),
    plot.title = ggplot2::element_text(face = "bold", size = 15),
    plot.subtitle = ggplot2::element_text(color = "grey35"),
    plot.caption = ggplot2::element_text(
      size = 8,
      color = "grey40",
      hjust = 0
    )
  )

save_plot_pair(
  p7,
  "Figure7_cluster_composition_1990_2023",
  width = 11,
  height = 8
)

# ------------------------------------------------------------------------------
# 13. Table 3 — Shapley decomposition of 1990→2023 burden change
# ------------------------------------------------------------------------------

decomposition_rows <- list()
row_id <- 0L

for (this_measure in measure_order) {
  for (this_cluster in cluster_order) {
    row_id <- row_id + 1L
    decomposition_rows[[row_id]] <- shapley_decompose_one(
      age_rate_population = age_rate_population,
      actual_summary = cluster_summary,
      measure_value = this_measure,
      cluster_value = this_cluster,
      year0 = 1990L,
      year1 = 2023L
    )
  }
}

decomposition_table <- dplyr::bind_rows(decomposition_rows) |>
  dplyr::mutate(
    cluster_name = factor(cluster_name, levels = cluster_order),
    measure_short = factor(
      measure_short,
      levels = c("Deaths", "YLLs", "YLDs", "DALYs")
    ),
    component = factor(
      component,
      levels = c(
        "Population size",
        "Age structure",
        "Age-specific rates"
      )
    ),
    contribution_share_of_modeled_net_change =
      safe_ratio(contribution_number, modeled_net_change)
  ) |>
  dplyr::arrange(measure_short, cluster_name, component)

readr::write_csv(
  decomposition_table,
  file.path(output_dir, "Table3_ShAPLEY_decomposition_1990_2023.csv")
)

# ------------------------------------------------------------------------------
# 14. Figure 8 — decomposition for Deaths and DALYs
# ------------------------------------------------------------------------------

figure8_data <- decomposition_table |>
  dplyr::filter(
    as.character(measure_short) %in% c("Deaths", "DALYs")
  ) |>
  dplyr::mutate(
    contribution_millions = contribution_number / 1e6
  )

figure8_net <- figure8_data |>
  dplyr::distinct(
    measure_short,
    cluster_name,
    modeled_net_change
  ) |>
  dplyr::mutate(
    modeled_net_change_millions = modeled_net_change / 1e6
  )

p8 <- ggplot2::ggplot(
  figure8_data,
  ggplot2::aes(
    x = cluster_name,
    y = contribution_millions,
    fill = component
  )
) +
  ggplot2::geom_hline(
    yintercept = 0,
    linewidth = 0.45,
    color = "grey35"
  ) +
  ggplot2::geom_col(
    width = 0.68,
    position = "stack"
  ) +
  ggplot2::geom_point(
    data = figure8_net,
    ggplot2::aes(
      x = cluster_name,
      y = modeled_net_change_millions
    ),
    inherit.aes = FALSE,
    shape = 18,
    size = 3.2
  ) +
  ggplot2::facet_wrap(
    ~measure_short,
    nrow = 1,
    scales = "free_y"
  ) +
  ggplot2::scale_fill_manual(
    values = decomposition_colors,
    drop = FALSE
  ) +
  ggplot2::labs(
    title = "Drivers of change in disease-cluster burden at ages 30–69, China, 1990–2023",
    subtitle = paste0(
      "Three-factor Shapley decomposition; black diamonds show the modeled ",
      "net change"
    ),
    x = NULL,
    y = "Contribution to change (millions)",
    fill = "Component",
    caption = paste0(
      "Population size, age structure and age-specific rates are decomposed ",
      "symmetrically over all six factor orderings."
    )
  ) +
  ggplot2::theme_bw(base_size = 11.5) +
  ggplot2::theme(
    legend.position = "bottom",
    panel.grid.minor = ggplot2::element_blank(),
    panel.grid.major.x = ggplot2::element_blank(),
    strip.background = ggplot2::element_rect(
      fill = "grey94",
      color = "grey75"
    ),
    strip.text = ggplot2::element_text(face = "bold"),
    plot.title = ggplot2::element_text(face = "bold", size = 15),
    plot.subtitle = ggplot2::element_text(color = "grey35"),
    plot.caption = ggplot2::element_text(
      size = 8,
      color = "grey40",
      hjust = 0
    )
  )

save_plot_pair(
  p8,
  "Figure8_ShAPLEY_decomposition_1990_2023",
  width = 10.5,
  height = 6.5
)

# ------------------------------------------------------------------------------
# 15. Supplementary Figure S4 — YLL and YLD trends
# ------------------------------------------------------------------------------

figure_s4_data <- cluster_summary |>
  dplyr::filter(
    as.character(measure_short) %in% c("YLLs", "YLDs")
  ) |>
  dplyr::transmute(
    year,
    measure_short = as.character(measure_short),
    cluster_name,
    number_millions = number / 1e6,
    standardized_rate =
      standardized_rate_per_100k_GBD2021
  ) |>
  tidyr::pivot_longer(
    cols = c(number_millions, standardized_rate),
    names_to = "trend_metric",
    values_to = "value"
  ) |>
  dplyr::mutate(
    panel = dplyr::case_when(
      measure_short == "YLLs" &
        trend_metric == "number_millions" ~
        "YLLs — Number (millions)",
      measure_short == "YLLs" &
        trend_metric == "standardized_rate" ~
        "YLLs — Standardized rate",
      measure_short == "YLDs" &
        trend_metric == "number_millions" ~
        "YLDs — Number (millions)",
      measure_short == "YLDs" &
        trend_metric == "standardized_rate" ~
        "YLDs — Standardized rate",
      TRUE ~ NA_character_
    ),
    panel = factor(
      panel,
      levels = c(
        "YLLs — Number (millions)",
        "YLLs — Standardized rate",
        "YLDs — Number (millions)",
        "YLDs — Standardized rate"
      )
    )
  )

p_s4 <- ggplot2::ggplot(
  figure_s4_data,
  ggplot2::aes(
    x = year,
    y = value,
    color = cluster_name,
    group = cluster_name
  )
) +
  ggplot2::geom_line(linewidth = 1.05, lineend = "round") +
  ggplot2::facet_wrap(~panel, scales = "free_y", ncol = 2) +
  ggplot2::scale_color_manual(
    values = cluster_colors,
    breaks = cluster_order,
    drop = FALSE
  ) +
  ggplot2::scale_x_continuous(
    breaks = c(1990, 2000, 2010, 2020, 2023)
  ) +
  ggplot2::scale_y_continuous(
    labels = scales::label_number(big.mark = ",")
  ) +
  ggplot2::labs(
    title = "Trends in YLL and YLD burden by disease cluster, ages 30–69, China, 1990–2023",
    x = "Year",
    y = NULL,
    color = "Disease cluster",
    caption = paste0(
      "Standardized rates use the 2023 China 30–69 population age ",
      "distribution as a fixed reference."
    )
  ) +
  ggplot2::theme_bw(base_size = 11.5) +
  ggplot2::theme(
    legend.position = "bottom",
    panel.grid.minor = ggplot2::element_blank(),
    strip.background = ggplot2::element_rect(
      fill = "grey94",
      color = "grey75"
    ),
    strip.text = ggplot2::element_text(face = "bold"),
    plot.title = ggplot2::element_text(face = "bold", size = 14),
    plot.caption = ggplot2::element_text(
      size = 8,
      color = "grey40",
      hjust = 0
    )
  )

save_plot_pair(
  p_s4,
  "FigureS4_YLL_YLD_trends_1990_2023",
  width = 11,
  height = 8
)

# ------------------------------------------------------------------------------
# 16. Supplementary Figure S5 — yearly classified-cause closure
# ------------------------------------------------------------------------------

p_s5 <- ggplot2::ggplot(
  closure_yearly,
  ggplot2::aes(
    x = year,
    y = classified_to_all_ratio,
    color = measure_short,
    group = measure_short
  )
) +
  ggplot2::geom_hline(
    yintercept = 1,
    linetype = "dashed",
    linewidth = 0.5,
    color = "grey45"
  ) +
  ggplot2::geom_line(linewidth = 0.95) +
  ggplot2::scale_x_continuous(
    breaks = c(1990, 2000, 2010, 2020, 2023)
  ) +
  ggplot2::scale_y_continuous(
    labels = scales::percent_format(accuracy = 0.1)
  ) +
  ggplot2::labs(
    title = "Coverage of GBD all-cause burden by the fixed 292 classified causes",
    subtitle = "Ages 30–69 years, China, 1990–2023",
    x = "Year",
    y = "Classified causes / All causes",
    color = "Measure",
    caption = paste0(
      "The 12 causes excluded from the 2023 clustering are audited separately ",
      "for historical burden."
    )
  ) +
  ggplot2::theme_bw(base_size = 11.5) +
  ggplot2::theme(
    legend.position = "bottom",
    panel.grid.minor = ggplot2::element_blank(),
    plot.title = ggplot2::element_text(face = "bold", size = 14),
    plot.subtitle = ggplot2::element_text(color = "grey35"),
    plot.caption = ggplot2::element_text(
      size = 8,
      color = "grey40",
      hjust = 0
    )
  )

save_plot_pair(
  p_s5,
  "FigureS5_yearly_classified_cause_closure",
  width = 9,
  height = 6
)

# ------------------------------------------------------------------------------
# 17. Cause-level DALY change, 1990 vs 2023
# ------------------------------------------------------------------------------

cause_age_rate <- classified_data |>
  dplyr::filter(
    measure == "DALYs (Disability-Adjusted Life Years)",
    metric == "Rate"
  ) |>
  dplyr::select(
    year, cause, cluster_name,
    age, age_index, rate_per_100k = val
  )

cause_standardized_rate <- cause_age_rate |>
  dplyr::left_join(
    standard_weights |>
      dplyr::select(age, standard_weight),
    by = "age"
  ) |>
  dplyr::group_by(year, cause, cluster_name) |>
  dplyr::summarise(
    standardized_DALY_rate =
      sum(rate_per_100k * standard_weight),
    .groups = "drop"
  )

cause_number <- classified_data |>
  dplyr::filter(
    measure == "DALYs (Disability-Adjusted Life Years)",
    metric == "Number"
  ) |>
  dplyr::group_by(year, cause, cluster_name) |>
  dplyr::summarise(
    DALY_number = sum(val, na.rm = TRUE),
    .groups = "drop"
  )

cause_daly_summary <- cause_number |>
  dplyr::left_join(
    cause_standardized_rate,
    by = c("year", "cause", "cluster_name")
  )

cause_1990 <- cause_daly_summary |>
  dplyr::filter(year == 1990) |>
  dplyr::transmute(
    cause,
    cluster_name,
    DALY_number_1990 = DALY_number,
    standardized_DALY_rate_1990 = standardized_DALY_rate
  )

cause_2023 <- cause_daly_summary |>
  dplyr::filter(year == 2023) |>
  dplyr::transmute(
    cause,
    cluster_name,
    DALY_number_2023 = DALY_number,
    standardized_DALY_rate_2023 = standardized_DALY_rate
  )

cause_change <- cause_1990 |>
  dplyr::left_join(
    cause_2023,
    by = c("cause", "cluster_name")
  ) |>
  dplyr::mutate(
    DALY_number_absolute_change =
      DALY_number_2023 - DALY_number_1990,
    DALY_number_percent_change =
      percent_change(DALY_number_1990, DALY_number_2023),
    standardized_DALY_rate_absolute_change =
      standardized_DALY_rate_2023 - standardized_DALY_rate_1990,
    standardized_DALY_rate_percent_change =
      percent_change(
        standardized_DALY_rate_1990,
        standardized_DALY_rate_2023
      )
  ) |>
  dplyr::arrange(
    cluster_name,
    dplyr::desc(abs(DALY_number_absolute_change))
  )

readr::write_csv(
  cause_change,
  file.path(output_dir, "Part3_cause_level_DALY_change_1990_2023.csv")
)

# ------------------------------------------------------------------------------
# 18. Final audit and reproducibility bundle
# ------------------------------------------------------------------------------

part3_audit <- tibble::tibble(
  check = c(
    "input_files",
    "years",
    "age_groups",
    "measures",
    "metrics",
    "detailed_causes_in_download",
    "frozen_clustered_causes",
    "unclassified_causes",
    "cluster_Infant",
    "cluster_Adult",
    "cluster_Aging_related",
    "missing_classified_cells_filled_zero",
    "max_population_relative_deviation",
    "GBD2021_world_standard_percent_sum_age30_69",
    "standard_weight_sum_after_renormalization"
  ),
  value = c(
    as.character(length(input_files)),
    as.character(length(years_expected)),
    as.character(length(age_30_69)),
    as.character(length(measure_order)),
    "2",
    as.character(nrow(candidate_detailed_causes)),
    as.character(nrow(cluster_membership)),
    as.character(nrow(unclassified_causes)),
    as.character(observed_cluster_counts["Infant"]),
    as.character(observed_cluster_counts["Adult"]),
    as.character(observed_cluster_counts["Aging-related"]),
    as.character(nrow(missing_classified_cells)),
    format(
      max(population_by_age$max_relative_deviation, na.rm = TRUE),
      scientific = TRUE,
      digits = 6
    ),
    format(
      unique(standard_weights$gbd2021_30_69_percent_total),
      scientific = FALSE,
      digits = 12
    ),
    format(
      sum(standard_weights$standard_weight),
      scientific = FALSE,
      digits = 12
    )
  )
)

readr::write_csv(
  part3_audit,
  file.path(output_dir, "Part3_data_audit.csv")
)

saveRDS(
  list(
    configuration = list(
      input_files = input_files,
      membership_file = membership_file,
      years = years_expected,
      age_groups = age_30_69,
      cluster_order = cluster_order,
      standard_population =
        "GBD 2021 world population age standard, re-normalized within ages 30–69"
    ),
    membership = cluster_membership,
    batch_audit = batch_audit,
    missing_classified_cells = missing_classified_cells,
    population_by_age = population_by_age,
    standard_weights = standard_weights,
    cluster_summary = cluster_summary,
    closure_yearly = closure_yearly,
    unclassified_yearly = unclassified_yearly,
    trend_table = trend_table,
    decomposition_table = decomposition_table,
    cause_change = cause_change
  ),
  file.path(output_dir, "Part3_1990_2023_analysis_objects.rds")
)

capture.output(
  utils::sessionInfo(),
  file = file.path(output_dir, "Part3_sessionInfo.txt")
)

# ------------------------------------------------------------------------------
# 19. Console summary
# ------------------------------------------------------------------------------

cat("\n============================================================\n")
cat("PART 3 COMPLETE: China age 30–69 trends, 1990–2023\n")
cat("============================================================\n")
cat("Clustering rerun: NO\n")
cat("Years:", min(years_expected), "to", max(years_expected), "\n")
cat("Frozen clustered causes:", nrow(cluster_membership), "\n")
cat("Unclassified 2023-zero causes:", nrow(unclassified_causes), "\n")

cat("\nFrozen cluster counts:\n")
print(membership_counts)

cat("\nGBD 2021 world-standard weights for ages 30–69 (re-normalized):\n")
print(standard_weights)

cat("\n1990 vs 2023 trend table:\n")
print(
  trend_table |>
    dplyr::select(
      measure_short,
      cluster_name,
      number_1990,
      number_2023,
      number_percent_change,
      standardized_rate_1990,
      standardized_rate_2023,
      standardized_rate_percent_change,
      EAPC_standardized_rate_percent
    )
)

cat("\nHistorical closure: minimum classified / All causes by measure:\n")
print(
  closure_yearly |>
    dplyr::group_by(measure_short) |>
    dplyr::summarise(
      minimum_closure = min(classified_to_all_ratio, na.rm = TRUE),
      year_of_minimum = year[which.min(classified_to_all_ratio)],
      maximum_unclassified_12_share =
        max(unclassified_12_share_of_all, na.rm = TRUE),
      .groups = "drop"
    )
)

cat("\nDecomposition reconstruction check:\n")
print(
  decomposition_table |>
    dplyr::group_by(measure_short, cluster_name) |>
    dplyr::summarise(
      modeled_net_change = dplyr::first(modeled_net_change),
      contribution_sum = dplyr::first(contribution_sum),
      reconstruction_error =
        dplyr::first(modeled_reconstruction_error),
      actual_vs_modeled_change_difference =
        dplyr::first(actual_vs_modeled_change_difference),
      .groups = "drop"
    )
)

cat(
  "\nOutputs saved to: ",
  normalizePath(output_dir, mustWork = FALSE),
  "\n",
  sep = ""
)
cat("============================================================\n")
