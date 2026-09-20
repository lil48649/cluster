#!/usr/bin/env Rscript

# ==============================================================================
# China GBD 2023 disease age-profile clusters — Stage 2
# Figures 2 onward: all-age bridge -> ages 30–69 public-health analysis
#
# IMPORTANT METHOD RULE
#   This script NEVER reruns K-means++.
#   It reads the frozen Stage 1 k=3 disease membership and applies it to GBD 2023
#   Deaths, YLLs, YLDs and DALYs.
#
# Main-text figure plan
#   Figure 2  All-age age-specific mortality and YLD rates by cluster
#   Figure 3  All-age vs ages 30–69 burden composition
#   Figure 4  Cluster contribution across 30–69 five-year age groups
#   Figure 5  Leading DALY causes within each cluster at ages 30–69
#
# Supplementary outputs
#   Figure S1 All-age top DALY causes within each cluster
#   Figure S2 30–69 age-specific rates for Deaths/YLLs/YLDs/DALYs
#   Figure S3 30–69 fatal (YLL) vs non-fatal (YLD) DALY composition
#
# Required local inputs
#   1) IHME-GBD_2023_DATA-26354bec-1.csv (or filename with '(1)')
#   2) Figure1_k3_cluster_membership.csv OR Part2_cluster_membership.csv
#
# The analysis uses China, Both sexes, 2023 only.
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
  "Part2_cluster_membership.csv"
)

output_dir <- "Stage2_Figure2_onward_outputs"

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

# Used for plotting only.
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

  # Standard PDF device is used for portability across Windows/macOS/Linux.
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
# 3. Locate input files
# ------------------------------------------------------------------------------

input_file <- first_existing_file(input_file_candidates, "GBD 2023 burden file")
membership_file <- first_existing_file(
  membership_file_candidates,
  "Frozen Stage 1 cluster-membership file"
)

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

message("Using burden data: ", input_file)
message("Using frozen cluster membership: ", membership_file)
message("Output directory: ", normalizePath(output_dir, mustWork = FALSE))

# ------------------------------------------------------------------------------
# 4. Read and validate the frozen k=3 membership
# ------------------------------------------------------------------------------

membership_raw <- readr::read_csv(membership_file, show_col_types = FALSE)

if ("disease" %in% names(membership_raw) && !"cause" %in% names(membership_raw)) {
  membership_raw <- dplyr::rename(membership_raw, cause = disease)
}

required_membership_columns <- c("cause", "cluster_name")
missing_membership_columns <- setdiff(required_membership_columns, names(membership_raw))

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
    cluster_name = factor(cluster_name, levels = cluster_order)
  ) |>
  dplyr::arrange(cluster_name, cause)

if (any(is.na(cluster_membership$cluster_name))) {
  stop("Unexpected cluster labels were found in the frozen membership file.")
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
    ". Reconcile Stage 1 before continuing."
  )
}

if (!all(observed_counts == expected_cluster_counts[cluster_order])) {
  stop(
    "Frozen cluster sizes do not match the finalized solution.\nObserved: ",
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
  file.path(output_dir, "Stage2_frozen_cluster_membership_used.csv")
)

# ------------------------------------------------------------------------------
# 5. Read and validate the GBD 2023 burden data
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
    age %in% c("All ages", age_levels)
  ) |>
  dplyr::mutate(
    measure_short = unname(measure_short_lookup[measure])
  )

if (nrow(analysis_data) == 0L) {
  stop("No China/Both/2023 burden rows remained after filtering.")
}

if (anyDuplicated(analysis_data[c("measure", "age", "cause", "metric")]) > 0L) {
  stop("Duplicate measure-age-cause-metric records were found in the GBD data.")
}

if (!all(measure_order %in% unique(analysis_data$measure))) {
  stop(
    "Missing measures: ",
    paste(setdiff(measure_order, unique(analysis_data$measure)), collapse = ", ")
  )
}

if (!all(c("All ages", age_levels) %in% unique(analysis_data$age))) {
  stop(
    "Missing age groups: ",
    paste(setdiff(c("All ages", age_levels), unique(analysis_data$age)), collapse = ", ")
  )
}

missing_cluster_causes <- setdiff(cluster_membership$cause, unique(analysis_data$cause))
if (length(missing_cluster_causes) > 0L) {
  stop(
    "The burden file is missing frozen Stage 1 causes: ",
    paste(missing_cluster_causes, collapse = "; ")
  )
}

# Detailed rows used in cluster summaries. Cluster assignment is frozen.
classified_data <- analysis_data |>
  dplyr::filter(cause != "All causes") |>
  dplyr::inner_join(cluster_membership, by = "cause") |>
  dplyr::mutate(
    cluster_name = factor(cluster_name, levels = cluster_order)
  )

# Audit GBD causes not in the frozen 292-cause membership.
unclassified_gbd_causes <- analysis_data |>
  dplyr::filter(cause != "All causes") |>
  dplyr::distinct(cause) |>
  dplyr::anti_join(cluster_membership, by = "cause") |>
  dplyr::arrange(cause)

readr::write_csv(
  unclassified_gbd_causes,
  file.path(output_dir, "Stage2_unclassified_GBD_causes.csv")
)

# ------------------------------------------------------------------------------
# 6. Figure 2 — all-age mortality and disability by cluster
# ------------------------------------------------------------------------------
# This is the bridge between the all-age clustering and the later 30–69 analysis.
# GBD age-specific rates are per 100,000. Because the denominator is identical
# within a given age group, cause-specific rates can be summed within a cluster.

figure2_data <- classified_data |>
  dplyr::filter(
    metric == "Rate",
    age %in% age_levels,
    measure %in% c("Deaths", "YLDs (Years Lived with Disability)")
  ) |>
  dplyr::group_by(measure, cluster_name, age) |>
  dplyr::summarise(rate_per_100k = sum(val, na.rm = TRUE), .groups = "drop") |>
  tidyr::complete(
    measure,
    cluster_name = factor(cluster_order, levels = cluster_order),
    age = age_levels,
    fill = list(rate_per_100k = 0)
  ) |>
  dplyr::mutate(
    age = factor(age, levels = age_levels, ordered = TRUE),
    age_index = as.integer(age),
    age_numeric = age_midpoints[age_index],
    cluster_name = factor(cluster_name, levels = cluster_order),
    panel = dplyr::recode(
      measure,
      "Deaths" = "Mortality",
      "YLDs (Years Lived with Disability)" = "Disability (YLD)"
    ),
    rate_per_person = rate_per_100k / 100000
  )

readr::write_csv(
  figure2_data,
  file.path(output_dir, "Figure2_source_data.csv")
)

p2 <- ggplot2::ggplot(
  figure2_data,
  ggplot2::aes(
    x = age_numeric,
    y = rate_per_person,
    color = cluster_name,
    group = cluster_name
  )
) +
  ggplot2::geom_line(linewidth = 1.25, lineend = "round") +
  ggplot2::facet_wrap(~panel, nrow = 1, scales = "free_y") +
  ggplot2::scale_color_manual(
    values = cluster_colors,
    breaks = cluster_order,
    drop = FALSE
  ) +
  ggplot2::scale_x_continuous(
    breaks = c(0, 25, 50, 75, 100),
    limits = c(0, 100),
    expand = ggplot2::expansion(mult = c(0.01, 0.02))
  ) +
  ggplot2::scale_y_continuous(
    labels = scales::label_number(accuracy = 0.001)
  ) +
  ggplot2::labs(
    title = "Mortality and disability burden by disease cluster in China, 2023",
    subtitle = "Age-specific cluster rates across the full life course",
    x = "Age (years)",
    y = "Rate per person",
    color = "Disease cluster",
    caption = paste0(
      "Source: GBD 2023, Both sexes. Cause-specific rates per 100,000 were ",
      "summed within the fixed Stage 1 clusters and divided by 100,000."
    )
  ) +
  ggplot2::theme_bw(base_size = 13) +
  ggplot2::theme(
    legend.position = "bottom",
    panel.grid.minor = ggplot2::element_blank(),
    panel.grid.major = ggplot2::element_line(color = "grey92", linewidth = 0.4),
    strip.background = ggplot2::element_rect(fill = "grey94", color = "grey75"),
    strip.text = ggplot2::element_text(face = "bold"),
    plot.title = ggplot2::element_text(face = "bold", size = 16),
    plot.subtitle = ggplot2::element_text(color = "grey35"),
    plot.caption = ggplot2::element_text(size = 8, color = "grey40", hjust = 0)
  )

save_plot_pair(
  p2,
  "Figure2_age_specific_mortality_YLD",
  width = 11,
  height = 6.4
)

# ------------------------------------------------------------------------------
# 7. Figure 3 — all ages vs ages 30–69 burden composition
# ------------------------------------------------------------------------------
# This figure explicitly shows how the burden composition changes when moving
# from the national all-age burden to the study's public-health window (30–69).

all_age_numbers <- classified_data |>
  dplyr::filter(metric == "Number", age == "All ages") |>
  dplyr::group_by(measure, measure_short, cluster_name) |>
  dplyr::summarise(estimate = sum(val, na.rm = TRUE), .groups = "drop") |>
  dplyr::mutate(analysis_window = "All ages")

age30_69_numbers <- classified_data |>
  dplyr::filter(metric == "Number", age %in% age_30_69) |>
  dplyr::group_by(measure, measure_short, cluster_name) |>
  dplyr::summarise(estimate = sum(val, na.rm = TRUE), .groups = "drop") |>
  dplyr::mutate(analysis_window = "Ages 30–69")

burden_comparison <- dplyr::bind_rows(all_age_numbers, age30_69_numbers) |>
  dplyr::group_by(analysis_window, measure, measure_short) |>
  dplyr::mutate(
    classified_total = sum(estimate),
    share_of_classified = safe_ratio(estimate, classified_total)
  ) |>
  dplyr::ungroup() |>
  dplyr::mutate(
    analysis_window = factor(
      analysis_window,
      levels = c("All ages", "Ages 30–69")
    ),
    measure_short = factor(
      measure_short,
      levels = c("Deaths", "YLLs", "YLDs", "DALYs")
    ),
    cluster_name = factor(cluster_name, levels = cluster_order)
  ) |>
  dplyr::arrange(analysis_window, measure_short, cluster_name)

# Closure against GBD All causes for each analysis window.
all_causes_all_age <- analysis_data |>
  dplyr::filter(metric == "Number", age == "All ages", cause == "All causes") |>
  dplyr::transmute(
    analysis_window = "All ages",
    measure,
    measure_short,
    all_causes_value = val
  )

all_causes_30_69 <- analysis_data |>
  dplyr::filter(metric == "Number", age %in% age_30_69, cause == "All causes") |>
  dplyr::group_by(measure, measure_short) |>
  dplyr::summarise(all_causes_value = sum(val, na.rm = TRUE), .groups = "drop") |>
  dplyr::mutate(analysis_window = "Ages 30–69")

all_causes_windows <- dplyr::bind_rows(all_causes_all_age, all_causes_30_69)

closure_windows <- burden_comparison |>
  dplyr::group_by(analysis_window, measure, measure_short) |>
  dplyr::summarise(classified_total = sum(estimate), .groups = "drop") |>
  dplyr::mutate(analysis_window = as.character(analysis_window)) |>
  dplyr::left_join(
    all_causes_windows,
    by = c("analysis_window", "measure", "measure_short")
  ) |>
  dplyr::mutate(
    classified_to_all_ratio = safe_ratio(classified_total, all_causes_value)
  )

burden_comparison <- burden_comparison |>
  dplyr::mutate(analysis_window_chr = as.character(analysis_window)) |>
  dplyr::left_join(
    closure_windows |>
      dplyr::select(
        analysis_window,
        measure,
        all_causes_value,
        classified_to_all_ratio
      ),
    by = c(
      "analysis_window_chr" = "analysis_window",
      "measure" = "measure"
    )
  ) |>
  dplyr::mutate(
    share_of_all_causes = safe_ratio(estimate, all_causes_value)
  ) |>
  dplyr::select(-analysis_window_chr)

readr::write_csv(
  burden_comparison,
  file.path(output_dir, "Figure3_all_age_vs_30_69_burden_composition.csv")
)
readr::write_csv(
  closure_windows,
  file.path(output_dir, "Stage2_all_age_vs_30_69_closure.csv")
)

p3 <- ggplot2::ggplot(
  burden_comparison,
  ggplot2::aes(
    x = measure_short,
    y = share_of_classified,
    fill = cluster_name
  )
) +
  ggplot2::geom_col(width = 0.72, color = "white", linewidth = 0.25) +
  ggplot2::geom_text(
    ggplot2::aes(
      label = dplyr::if_else(
        share_of_classified >= 0.04,
        scales::percent(share_of_classified, accuracy = 0.1),
        ""
      )
    ),
    position = ggplot2::position_stack(vjust = 0.5),
    color = "white",
    fontface = "bold",
    size = 3.1
  ) +
  ggplot2::facet_wrap(~analysis_window, nrow = 1) +
  ggplot2::scale_fill_manual(
    values = cluster_colors,
    breaks = cluster_order,
    drop = FALSE
  ) +
  ggplot2::scale_y_continuous(
    labels = scales::percent_format(accuracy = 1),
    limits = c(0, 1),
    expand = ggplot2::expansion(mult = c(0, 0.02))
  ) +
  ggplot2::labs(
    title = "Disease burden composition by age-profile cluster, China, 2023",
    subtitle = "Comparison of the national all-age burden with the 30–69-year public-health window",
    x = NULL,
    y = "Share of classified burden",
    fill = "Disease cluster",
    caption = paste0(
      "Source: GBD 2023, Both sexes. Shares are calculated within the 292 causes ",
      "classified by the fixed Stage 1 solution."
    )
  ) +
  ggplot2::theme_bw(base_size = 13) +
  ggplot2::theme(
    legend.position = "bottom",
    panel.grid.minor = ggplot2::element_blank(),
    panel.grid.major.x = ggplot2::element_blank(),
    strip.background = ggplot2::element_rect(fill = "grey94", color = "grey75"),
    strip.text = ggplot2::element_text(face = "bold", size = 12),
    plot.title = ggplot2::element_text(face = "bold", size = 16),
    plot.subtitle = ggplot2::element_text(color = "grey35"),
    plot.caption = ggplot2::element_text(size = 8, color = "grey40", hjust = 0)
  )

save_plot_pair(
  p3,
  "Figure3_all_age_vs_30_69_burden_composition",
  width = 11,
  height = 6.5
)

# ------------------------------------------------------------------------------
# 8. Figure 4 — age gradient in cluster contribution within ages 30–69
# ------------------------------------------------------------------------------
# Main-text panels use Deaths and DALYs to emphasize premature mortality and
# total health loss. All four measures are exported as source data and rates.

age_cluster_rates <- classified_data |>
  dplyr::filter(metric == "Rate", age %in% age_30_69) |>
  dplyr::group_by(measure, measure_short, cluster_name, age) |>
  dplyr::summarise(rate_per_100k = sum(val, na.rm = TRUE), .groups = "drop") |>
  tidyr::complete(
    measure,
    cluster_name = factor(cluster_order, levels = cluster_order),
    age = age_30_69,
    fill = list(rate_per_100k = 0)
  ) |>
  dplyr::mutate(
    measure_short = unname(measure_short_lookup[measure]),
    age = factor(age, levels = age_30_69, ordered = TRUE),
    age_index = as.integer(age),
    age_midpoint = age_midpoints_30_69[age_index],
    cluster_name = factor(cluster_name, levels = cluster_order),
    measure_short = factor(
      measure_short,
      levels = c("Deaths", "YLLs", "YLDs", "DALYs")
    )
  )

age_cluster_shares <- age_cluster_rates |>
  dplyr::group_by(measure, measure_short, age, age_index, age_midpoint) |>
  dplyr::mutate(
    classified_rate_per_100k = sum(rate_per_100k),
    share_of_classified = safe_ratio(rate_per_100k, classified_rate_per_100k)
  ) |>
  dplyr::ungroup() |>
  dplyr::arrange(measure_short, age_index, cluster_name)

readr::write_csv(
  age_cluster_rates,
  file.path(output_dir, "Figure4_age30_69_cluster_rates.csv")
)
readr::write_csv(
  age_cluster_shares,
  file.path(output_dir, "Figure4_age30_69_cluster_shares.csv")
)

figure4_data <- age_cluster_shares |>
  dplyr::filter(measure_short %in% c("Deaths", "DALYs")) |>
  dplyr::mutate(
    panel = factor(
      as.character(measure_short),
      levels = c("Deaths", "DALYs")
    )
  )

p4 <- ggplot2::ggplot(
  figure4_data,
  ggplot2::aes(
    x = age_midpoint,
    y = share_of_classified,
    color = cluster_name,
    group = cluster_name
  )
) +
  ggplot2::geom_line(linewidth = 1.15, lineend = "round") +
  ggplot2::geom_point(size = 2.2) +
  ggplot2::facet_wrap(~panel, nrow = 1) +
  ggplot2::scale_color_manual(
    values = cluster_colors,
    breaks = cluster_order,
    drop = FALSE
  ) +
  ggplot2::scale_x_continuous(
    breaks = age_midpoints_30_69,
    labels = age_30_69,
    expand = ggplot2::expansion(mult = c(0.02, 0.02))
  ) +
  ggplot2::scale_y_continuous(
    labels = scales::percent_format(accuracy = 1),
    limits = c(0, 1),
    expand = ggplot2::expansion(mult = c(0, 0.02))
  ) +
  ggplot2::labs(
    title = "Age gradient in disease-cluster contribution, China, 2023",
    subtitle = "Cluster share of classified burden within each five-year age group from 30 to 69 years",
    x = "Age group",
    y = "Share within age group",
    color = "Disease cluster",
    caption = paste0(
      "Source: GBD 2023, Both sexes. Cluster assignment is fixed from the ",
      "all-age 2023 DALY age-profile classification."
    )
  ) +
  ggplot2::theme_bw(base_size = 12.5) +
  ggplot2::theme(
    legend.position = "bottom",
    panel.grid.minor = ggplot2::element_blank(),
    panel.grid.major = ggplot2::element_line(color = "grey92", linewidth = 0.4),
    strip.background = ggplot2::element_rect(fill = "grey94", color = "grey75"),
    strip.text = ggplot2::element_text(face = "bold"),
    axis.text.x = ggplot2::element_text(angle = 45, hjust = 1),
    plot.title = ggplot2::element_text(face = "bold", size = 16),
    plot.subtitle = ggplot2::element_text(color = "grey35"),
    plot.caption = ggplot2::element_text(size = 8, color = "grey40", hjust = 0)
  )

save_plot_pair(
  p4,
  "Figure4_age30_69_cluster_share_gradient",
  width = 11,
  height = 6.2
)

# ------------------------------------------------------------------------------
# 9. 30–69 cause-level burden and Figure 5
# ------------------------------------------------------------------------------

cause_burden_30_69 <- classified_data |>
  dplyr::filter(metric == "Number", age %in% age_30_69) |>
  dplyr::group_by(measure, measure_short, cluster_name, cause) |>
  dplyr::summarise(estimate = sum(val, na.rm = TRUE), .groups = "drop") |>
  dplyr::group_by(measure, measure_short, cluster_name) |>
  dplyr::mutate(
    cluster_total = sum(estimate),
    share_within_cluster = safe_ratio(estimate, cluster_total)
  ) |>
  dplyr::ungroup() |>
  dplyr::group_by(measure, measure_short) |>
  dplyr::mutate(
    classified_total_30_69 = sum(estimate),
    share_of_classified_30_69 = safe_ratio(estimate, classified_total_30_69)
  ) |>
  dplyr::ungroup() |>
  dplyr::mutate(
    measure_short = factor(
      measure_short,
      levels = c("Deaths", "YLLs", "YLDs", "DALYs")
    ),
    cluster_name = factor(cluster_name, levels = cluster_order)
  ) |>
  dplyr::arrange(measure_short, cluster_name, dplyr::desc(estimate))

readr::write_csv(
  cause_burden_30_69,
  file.path(output_dir, "Stage2_age30_69_cause_burden_all_measures.csv")
)

top10_30_69 <- cause_burden_30_69 |>
  dplyr::group_by(measure_short, cluster_name) |>
  dplyr::slice_max(estimate, n = 10, with_ties = FALSE) |>
  dplyr::arrange(measure_short, cluster_name, dplyr::desc(estimate)) |>
  dplyr::mutate(rank_within_cluster = dplyr::row_number()) |>
  dplyr::ungroup()

readr::write_csv(
  top10_30_69,
  file.path(output_dir, "Stage2_age30_69_top10_causes_by_cluster_measure.csv")
)

top10_daly_30_69 <- top10_30_69 |>
  dplyr::filter(measure_short == "DALYs") |>
  dplyr::mutate(
    cause_panel = paste(cause, cluster_name, sep = "___"),
    cause_panel = forcats::fct_reorder(cause_panel, estimate)
  )

readr::write_csv(
  top10_daly_30_69 |>
    dplyr::select(-cause_panel),
  file.path(output_dir, "Figure5_age30_69_top10_DALY_causes.csv")
)

p5 <- ggplot2::ggplot(
  top10_daly_30_69,
  ggplot2::aes(x = estimate, y = cause_panel, fill = cluster_name)
) +
  ggplot2::geom_col(width = 0.72) +
  ggplot2::facet_wrap(~cluster_name, scales = "free_y", ncol = 1) +
  ggplot2::scale_fill_manual(values = cluster_colors, guide = "none") +
  ggplot2::scale_y_discrete(labels = function(x) sub("___.*$", "", x)) +
  ggplot2::scale_x_continuous(
    labels = scales::label_number(scale = 1e-6, suffix = " M", accuracy = 0.1)
  ) +
  ggplot2::labs(
    title = "Leading causes of DALYs within each disease cluster, ages 30–69, China, 2023",
    subtitle = "Top ten detailed causes by DALY numbers within the 30–69-year analysis window",
    x = "DALYs (millions)",
    y = NULL,
    caption = "Source: GBD 2023, Both sexes. Cluster membership is fixed from Stage 1."
  ) +
  ggplot2::theme_bw(base_size = 11) +
  ggplot2::theme(
    panel.grid.minor = ggplot2::element_blank(),
    panel.grid.major.y = ggplot2::element_blank(),
    strip.background = ggplot2::element_rect(fill = "grey94", color = "grey75"),
    strip.text = ggplot2::element_text(face = "bold"),
    plot.title = ggplot2::element_text(face = "bold", size = 15),
    plot.subtitle = ggplot2::element_text(color = "grey35"),
    plot.caption = ggplot2::element_text(size = 8, color = "grey40", hjust = 0)
  )

save_plot_pair(
  p5,
  "Figure5_age30_69_top_DALY_causes_by_cluster",
  width = 10.8,
  height = 12
)

# ------------------------------------------------------------------------------
# 10. Table 1 — 30–69 burden profile by cluster
# ------------------------------------------------------------------------------

cluster_burden_30_69 <- age30_69_numbers |>
  dplyr::group_by(measure, measure_short) |>
  dplyr::mutate(
    classified_total = sum(estimate),
    share_of_classified = safe_ratio(estimate, classified_total)
  ) |>
  dplyr::ungroup() |>
  dplyr::mutate(
    measure_short = factor(
      measure_short,
      levels = c("Deaths", "YLLs", "YLDs", "DALYs")
    ),
    cluster_name = factor(cluster_name, levels = cluster_order)
  ) |>
  dplyr::arrange(measure_short, cluster_name)

# Add GBD All-causes denominator and share of total 30–69 national burden.
cluster_burden_30_69 <- cluster_burden_30_69 |>
  dplyr::left_join(
    all_causes_30_69 |>
      dplyr::select(measure, all_causes_value),
    by = "measure"
  ) |>
  dplyr::mutate(
    share_of_all_causes = safe_ratio(estimate, all_causes_value)
  )

# YLL/YLD phenotype of DALYs by cluster.
phenotype_30_69 <- cluster_burden_30_69 |>
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
  )

readr::write_csv(
  cluster_burden_30_69,
  file.path(output_dir, "Table1_age30_69_cluster_burden_summary.csv")
)
readr::write_csv(
  phenotype_30_69,
  file.path(output_dir, "Table1_age30_69_YLL_YLD_DALY_profile.csv")
)

# ------------------------------------------------------------------------------
# 11. Supplementary Figure S1 — all-age top DALY causes
# ------------------------------------------------------------------------------
# The former all-age Figure 4 is retained as supplementary context rather than
# competing with the 30–69 main-text analysis.

cause_burden_all_age <- classified_data |>
  dplyr::filter(
    metric == "Number",
    age == "All ages",
    measure == "DALYs (Disability-Adjusted Life Years)"
  ) |>
  dplyr::group_by(cluster_name, cause) |>
  dplyr::summarise(estimate = sum(val, na.rm = TRUE), .groups = "drop")

top10_daly_all_age <- cause_burden_all_age |>
  dplyr::group_by(cluster_name) |>
  dplyr::slice_max(estimate, n = 10, with_ties = FALSE) |>
  dplyr::ungroup() |>
  dplyr::mutate(
    cause_panel = paste(cause, cluster_name, sep = "___"),
    cause_panel = forcats::fct_reorder(cause_panel, estimate)
  )

readr::write_csv(
  top10_daly_all_age |>
    dplyr::select(-cause_panel),
  file.path(output_dir, "FigureS1_all_age_top10_DALY_causes.csv")
)

p_s1 <- ggplot2::ggplot(
  top10_daly_all_age,
  ggplot2::aes(x = estimate, y = cause_panel, fill = cluster_name)
) +
  ggplot2::geom_col(width = 0.72) +
  ggplot2::facet_wrap(~cluster_name, scales = "free_y", ncol = 1) +
  ggplot2::scale_fill_manual(values = cluster_colors, guide = "none") +
  ggplot2::scale_y_discrete(labels = function(x) sub("___.*$", "", x)) +
  ggplot2::scale_x_continuous(
    labels = scales::label_number(scale = 1e-6, suffix = " M", accuracy = 0.1)
  ) +
  ggplot2::labs(
    title = "Leading all-age causes of DALYs within each disease cluster, China, 2023",
    subtitle = "Supplementary all-age context for the fixed disease clusters",
    x = "DALYs (millions)",
    y = NULL,
    caption = "Source: GBD 2023, Both sexes."
  ) +
  ggplot2::theme_bw(base_size = 11) +
  ggplot2::theme(
    panel.grid.minor = ggplot2::element_blank(),
    panel.grid.major.y = ggplot2::element_blank(),
    strip.background = ggplot2::element_rect(fill = "grey94", color = "grey75"),
    strip.text = ggplot2::element_text(face = "bold"),
    plot.title = ggplot2::element_text(face = "bold", size = 15),
    plot.subtitle = ggplot2::element_text(color = "grey35"),
    plot.caption = ggplot2::element_text(size = 8, color = "grey40", hjust = 0)
  )

save_plot_pair(
  p_s1,
  "FigureS1_all_age_top_DALY_causes_by_cluster",
  width = 10.5,
  height = 12
)

# ------------------------------------------------------------------------------
# 12. Supplementary Figure S2 — all four 30–69 age-specific cluster rates
# ------------------------------------------------------------------------------

p_s2 <- ggplot2::ggplot(
  age_cluster_rates,
  ggplot2::aes(
    x = age_midpoint,
    y = rate_per_100k,
    color = cluster_name,
    group = cluster_name
  )
) +
  ggplot2::geom_line(linewidth = 1.05, lineend = "round") +
  ggplot2::geom_point(size = 1.8) +
  ggplot2::facet_wrap(~measure_short, scales = "free_y", ncol = 2) +
  ggplot2::scale_color_manual(
    values = cluster_colors,
    breaks = cluster_order,
    drop = FALSE
  ) +
  ggplot2::scale_x_continuous(
    breaks = age_midpoints_30_69,
    labels = age_30_69,
    expand = ggplot2::expansion(mult = c(0.02, 0.02))
  ) +
  ggplot2::scale_y_continuous(
    labels = scales::label_number(big.mark = ",")
  ) +
  ggplot2::labs(
    title = "Age-specific burden rates by disease cluster, ages 30–69, China, 2023",
    subtitle = "Panels use separate y-axis scales",
    x = "Age group",
    y = "Rate per 100,000",
    color = "Disease cluster",
    caption = "Source: GBD 2023, Both sexes. Cause-specific rates are summed within each fixed cluster."
  ) +
  ggplot2::theme_bw(base_size = 11.5) +
  ggplot2::theme(
    legend.position = "bottom",
    panel.grid.minor = ggplot2::element_blank(),
    panel.grid.major = ggplot2::element_line(color = "grey92", linewidth = 0.4),
    strip.background = ggplot2::element_rect(fill = "grey94", color = "grey75"),
    strip.text = ggplot2::element_text(face = "bold"),
    axis.text.x = ggplot2::element_text(angle = 45, hjust = 1),
    plot.title = ggplot2::element_text(face = "bold", size = 15),
    plot.subtitle = ggplot2::element_text(color = "grey35"),
    plot.caption = ggplot2::element_text(size = 8, color = "grey40", hjust = 0)
  )

save_plot_pair(
  p_s2,
  "FigureS2_age30_69_age_specific_cluster_rates",
  width = 11,
  height = 8
)

# ------------------------------------------------------------------------------
# 13. Supplementary Figure S3 — fatal vs non-fatal composition of DALYs
# ------------------------------------------------------------------------------

phenotype_long <- phenotype_30_69 |>
  dplyr::select(cluster_name, YLL_fraction_of_DALYs, YLD_fraction_of_DALYs) |>
  tidyr::pivot_longer(
    cols = c(YLL_fraction_of_DALYs, YLD_fraction_of_DALYs),
    names_to = "component",
    values_to = "share"
  ) |>
  dplyr::mutate(
    component = dplyr::recode(
      component,
      "YLL_fraction_of_DALYs" = "YLL (fatal burden)",
      "YLD_fraction_of_DALYs" = "YLD (non-fatal burden)"
    ),
    component = factor(
      component,
      levels = c("YLL (fatal burden)", "YLD (non-fatal burden)")
    )
  )

p_s3 <- ggplot2::ggplot(
  phenotype_long,
  ggplot2::aes(x = cluster_name, y = share, fill = component)
) +
  ggplot2::geom_col(width = 0.68, color = "white", linewidth = 0.3) +
  ggplot2::geom_text(
    ggplot2::aes(label = scales::percent(share, accuracy = 0.1)),
    position = ggplot2::position_stack(vjust = 0.5),
    color = "white",
    fontface = "bold",
    size = 3.4
  ) +
  ggplot2::scale_y_continuous(
    labels = scales::percent_format(accuracy = 1),
    limits = c(0, 1),
    expand = ggplot2::expansion(mult = c(0, 0.02))
  ) +
  ggplot2::labs(
    title = "Fatal and non-fatal composition of DALYs by disease cluster, ages 30–69",
    x = NULL,
    y = "Share of DALYs",
    fill = NULL,
    caption = "YLL/DALY and YLD/DALY are calculated from 2023 GBD numbers summed across ages 30–69."
  ) +
  ggplot2::theme_bw(base_size = 12) +
  ggplot2::theme(
    legend.position = "bottom",
    panel.grid.minor = ggplot2::element_blank(),
    panel.grid.major.x = ggplot2::element_blank(),
    plot.title = ggplot2::element_text(face = "bold", size = 15),
    plot.caption = ggplot2::element_text(size = 8, color = "grey40", hjust = 0)
  )

save_plot_pair(
  p_s3,
  "FigureS3_age30_69_YLL_YLD_DALY_profile",
  width = 8.2,
  height = 5.8
)

# ------------------------------------------------------------------------------
# 14. Audit, RDS bundle and session information
# ------------------------------------------------------------------------------

analysis_audit <- tibble::tibble(
  check = c(
    "input_file",
    "membership_file",
    "raw_rows",
    "analysis_rows",
    "frozen_clustered_causes",
    "unclassified_GBD_causes",
    "all_age_groups_used",
    "age30_69_groups_used",
    "measures",
    "sex",
    "year"
  ),
  value = c(
    input_file,
    membership_file,
    as.character(nrow(raw)),
    as.character(nrow(analysis_data)),
    as.character(nrow(cluster_membership)),
    as.character(nrow(unclassified_gbd_causes)),
    as.character(length(age_levels)),
    as.character(length(age_30_69)),
    as.character(length(measure_order)),
    "Both",
    "2023"
  )
)

readr::write_csv(
  analysis_audit,
  file.path(output_dir, "Stage2_data_audit.csv")
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
      age_30_69 = age_30_69
    ),
    membership = cluster_membership,
    figure2_data = figure2_data,
    burden_comparison = burden_comparison,
    closure_windows = closure_windows,
    age_cluster_rates = age_cluster_rates,
    age_cluster_shares = age_cluster_shares,
    cause_burden_30_69 = cause_burden_30_69,
    top10_30_69 = top10_30_69,
    cluster_burden_30_69 = cluster_burden_30_69,
    phenotype_30_69 = phenotype_30_69,
    top10_daly_all_age = top10_daly_all_age
  ),
  file.path(output_dir, "Stage2_Figure2_onward_analysis_objects.rds")
)

capture.output(
  utils::sessionInfo(),
  file = file.path(output_dir, "Stage2_sessionInfo.txt")
)

# ------------------------------------------------------------------------------
# 15. Console summary
# ------------------------------------------------------------------------------

cat("\n============================================================\n")
cat("STAGE 2 FIGURE 2 ONWARD COMPLETE\n")
cat("============================================================\n")
cat("Clustering rerun: NO\n")
cat("Frozen clustered causes:", nrow(cluster_membership), "\n")
cat("\nCluster counts:\n")
print(membership_counts)
cat("\nAll-age vs 30–69 closure against GBD All causes:\n")
print(closure_windows)
cat("\n30–69 burden summary:\n")
print(
  cluster_burden_30_69 |>
    dplyr::select(
      measure_short,
      cluster_name,
      estimate,
      share_of_classified,
      share_of_all_causes
    )
)
cat("\n30–69 fatal/non-fatal DALY profile:\n")
print(phenotype_30_69)
cat("\nOutputs saved to: ", normalizePath(output_dir), "\n", sep = "")
cat("============================================================\n")
