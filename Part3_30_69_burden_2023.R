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
