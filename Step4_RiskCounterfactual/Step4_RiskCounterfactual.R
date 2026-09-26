#!/usr/bin/env Rscript

# ==============================================================================
# China GBD 2023 life-course clusters — Step 4
# Level-2 risk-factor TMREL counterfactuals
#
# METHOD RULES
#   1. Never rerun clustering. Use the frozen 292-cause Stage 1 membership.
#   2. Evaluate each Level-2 risk independently. Never sum effects across risks.
#   3. Use the exact Part 3 life-table conversion:
#        5q_x = 5m_x / (1 + 2.5m_x)
#   4. Risk-attributable Deaths/DALYs are already relative to TMREL.
#   5. Preserve signed GBD point estimates for audit. Prevention endpoints are
#      bounded at zero; attributable mortality is also capped at the matching
#      cluster-age baseline and every adjustment is flagged.
#   6. Validate lower/upper bounds but do not aggregate them across causes.
#      Valid cluster-level uncertainty propagation requires draw-level
#      covariance, which is not available in this export.
#
# This script uses base R only.
# ==============================================================================

options(
  stringsAsFactors = FALSE,
  scipen = 999,
  warn = 1
)


# ------------------------------------------------------------------------------
# 0. Constants and command-line configuration
# ------------------------------------------------------------------------------

age_order <- c(
  "30-34 years",
  "35-39 years",
  "40-44 years",
  "45-49 years",
  "50-54 years",
  "55-59 years",
  "60-64 years",
  "65-69 years"
)

cluster_order <- c(
  "Infant",
  "Adult",
  "Aging-related"
)

deaths_label <- "Deaths"
daly_label <- "DALYs (Disability-Adjusted Life Years)"
measure_order <- c(deaths_label, daly_label)

# Exact Level-2 label set present in the supplied GBD 2023 export. The source
# file has no numeric hierarchy column, so hierarchy is validated by this set.
expected_level2_risks <- c(
  "Air pollution",
  "Child and maternal malnutrition",
  "Dietary risks",
  "Drug use",
  "High LDL cholesterol",
  "High alcohol use",
  "High body-mass index",
  "High fasting plasma glucose",
  "High systolic blood pressure",
  "Intimate partner violence",
  "Kidney dysfunction",
  "Low bone mineral density",
  "Low physical activity",
  "Non-optimal temperature",
  "Occupational risks",
  "Other environmental risks",
  "Sexual violence against children and bullying",
  "Tobacco",
  "Unsafe sex",
  "Unsafe water, sanitation, and handwashing"
)

risk_required_columns <- c(
  "population_group",
  "measure",
  "location",
  "sex",
  "age",
  "cause",
  "rei",
  "metric",
  "year",
  "val",
  "upper",
  "lower"
)

risk_key_columns <- c(
  "population_group",
  "measure",
  "location",
  "sex",
  "age",
  "cause",
  "rei",
  "metric",
  "year"
)


stopf <- function(fmt, ...) {
  stop(sprintf(fmt, ...), call. = FALSE)
}


first_existing_file <- function(candidates, label) {
  found <- candidates[file.exists(candidates)]
  if (length(found) == 0L) {
    stopf(
      "Could not locate %s. Tried: %s",
      label,
      paste(candidates, collapse = " | ")
    )
  }
  found[[1L]]
}


parse_cli <- function(args) {
  allowed <- c(
    "--risk-csv",
    "--membership-csv",
    "--mortality-csv",
    "--daly-baseline-csv",
    "--output-dir"
  )

  result <- list()
  i <- 1L
  while (i <= length(args)) {
    flag <- args[[i]]
    if (flag %in% c("-h", "--help")) {
      cat(
        paste0(
          "Usage: Rscript Step4_RiskCounterfactual.R ",
          "[--risk-csv FILE] [--membership-csv FILE] ",
          "[--mortality-csv FILE] [--daly-baseline-csv FILE] ",
          "[--output-dir DIR]\n"
        )
      )
      quit(status = 0L)
    }
    if (!flag %in% allowed) {
      stopf("Unknown command-line option: %s", flag)
    }
    if (i == length(args)) {
      stopf("Missing value after command-line option: %s", flag)
    }
    result[[sub("^--", "", flag)]] <- args[[i + 1L]]
    i <- i + 2L
  }
  result
}


cli <- parse_cli(commandArgs(trailingOnly = TRUE))

risk_csv <- if (!is.null(cli[["risk-csv"]])) {
  cli[["risk-csv"]]
} else {
  first_existing_file(
    c(
      "IHME-GBD_2023_risk.csv",
      file.path("data", "IHME-GBD_2023_risk.csv")
    ),
    "GBD risk-attributable CSV"
  )
}

membership_csv <- if (!is.null(cli[["membership-csv"]])) {
  cli[["membership-csv"]]
} else {
  first_existing_file(
    c(
      file.path(
        "Part3_PrematureMortality_outputs",
        "Part3_frozen_cluster_membership_used.csv"
      ),
      "Part3_frozen_cluster_membership_used.csv",
      file.path(
        "Stage2_Redesigned_30_69_outputs",
        "Stage2_frozen_cluster_membership_used.csv"
      ),
      "Stage2_frozen_cluster_membership_used.csv"
    ),
    "frozen cluster membership"
  )
}

mortality_csv <- if (!is.null(cli[["mortality-csv"]])) {
  cli[["mortality-csv"]]
} else {
  first_existing_file(
    c(
      file.path(
        "Part3_PrematureMortality_outputs",
        "Part3_cluster_age_specific_mortality_1990_2023.csv"
      ),
      "Part3_cluster_age_specific_mortality_1990_2023.csv"
    ),
    "Part 3 cluster age-specific mortality"
  )
}

daly_baseline_csv <- if (!is.null(cli[["daly-baseline-csv"]])) {
  cli[["daly-baseline-csv"]]
} else {
  first_existing_file(
    c(
      file.path(
        "Stage2_Redesigned_30_69_outputs",
        "Stage2_core_DALY_summary.csv"
      ),
      "Stage2_core_DALY_summary.csv"
    ),
    "Stage 2 cluster DALY summary"
  )
}

output_dir <- if (!is.null(cli[["output-dir"]])) {
  cli[["output-dir"]]
} else {
  "Step4_RiskCounterfactual_outputs"
}

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)


# ------------------------------------------------------------------------------
# 1. General helpers
# ------------------------------------------------------------------------------

read_csv_strict <- function(path, label) {
  if (!file.exists(path)) {
    stopf("%s not found: %s", label, path)
  }

  result <- tryCatch(
    utils::read.csv(
      path,
      stringsAsFactors = FALSE,
      check.names = FALSE,
      fileEncoding = "UTF-8-BOM"
    ),
    error = function(e) {
      stopf("Failed to read %s (%s): %s", label, path, conditionMessage(e))
    }
  )

  if (nrow(result) == 0L) {
    stopf("%s is empty: %s", label, path)
  }

  names(result)[1L] <- sub("^\\ufeff", "", names(result)[1L])
  result
}


require_columns <- function(data, required, label) {
  missing <- setdiff(required, names(data))
  if (length(missing) > 0L) {
    stopf(
      "%s is missing columns: %s",
      label,
      paste(missing, collapse = " | ")
    )
  }
}


require_exact_values <- function(data, column, expected, label) {
  observed <- sort(unique(as.character(data[[column]])))
  expected_sorted <- sort(expected)
  if (!identical(observed, expected_sorted)) {
    stopf(
      "%s has unexpected %s coverage. Missing: %s. Extra: %s",
      label,
      column,
      paste(setdiff(expected_sorted, observed), collapse = " | "),
      paste(setdiff(observed, expected_sorted), collapse = " | ")
    )
  }
}


strict_numeric <- function(x, field, label) {
  result <- suppressWarnings(as.numeric(x))
  if (anyNA(result) || any(!is.finite(result))) {
    stopf("%s contains non-finite or non-numeric %s values", label, field)
  }
  result
}


make_key <- function(data, columns) {
  do.call(
    paste,
    c(
      lapply(data[columns], as.character),
      sep = "\r"
    )
  )
}


rate_to_5q <- function(rate_per_100k) {
  mx <- rate_per_100k / 100000
  if (any(!is.finite(mx)) || any(mx < 0)) {
    stop("Invalid mortality rate in q5 calculation.", call. = FALSE)
  }
  q5 <- (5 * mx) / (1 + 2.5 * mx)
  if (any(q5 < 0 | q5 >= 1)) {
    stop("Calculated q5 is outside [0, 1).", call. = FALSE)
  }
  q5
}


q30_70_from_5year_rates <- function(rate_per_100k) {
  if (length(rate_per_100k) != length(age_order)) {
    stopf(
      "q30-70 requires %d age-specific rates; found %d",
      length(age_order),
      length(rate_per_100k)
    )
  }
  1 - prod(1 - rate_to_5q(rate_per_100k))
}


format_counts <- function(x) {
  paste(names(x), as.integer(x), sep = "=", collapse = " | ")
}


write_output_csv <- function(data, filename) {
  utils::write.csv(
    data,
    file.path(output_dir, filename),
    row.names = FALSE,
    na = "",
    fileEncoding = "UTF-8"
  )
}


# ------------------------------------------------------------------------------
# 2. Risk input: schema, hierarchy, coverage, pairing and numeric QC
# ------------------------------------------------------------------------------

risk_data <- read_csv_strict(risk_csv, "risk input")
require_columns(risk_data, risk_required_columns, "risk input")

require_exact_values(
  risk_data,
  "population_group",
  "All Population",
  "risk input"
)
require_exact_values(risk_data, "location", "China", "risk input")
require_exact_values(risk_data, "sex", "Both", "risk input")
require_exact_values(risk_data, "year", "2023", "risk input")
require_exact_values(risk_data, "age", age_order, "risk input")
require_exact_values(risk_data, "measure", measure_order, "risk input")
require_exact_values(risk_data, "metric", c("Number", "Rate"), "risk input")
require_exact_values(
  risk_data,
  "rei",
  expected_level2_risks,
  "risk input"
)

risk_data$val <- strict_numeric(risk_data$val, "val", "risk input")
risk_data$lower <- strict_numeric(risk_data$lower, "lower", "risk input")
risk_data$upper <- strict_numeric(risk_data$upper, "upper", "risk input")

full_key <- make_key(risk_data, risk_key_columns)
duplicate_full_keys <- sum(duplicated(full_key))
if (duplicate_full_keys > 0L) {
  stopf("Risk input contains %d duplicate full keys", duplicate_full_keys)
}

if (any(risk_data$lower > risk_data$val | risk_data$val > risk_data$upper)) {
  stop("Risk input contains point estimates outside lower/upper bounds.", call. = FALSE)
}

pair_columns <- setdiff(risk_key_columns, "metric")
number_rows <- risk_data[risk_data$metric == "Number", c(pair_columns, "val")]
rate_rows <- risk_data[risk_data$metric == "Rate", c(pair_columns, "val")]
number_pair_key <- make_key(number_rows, pair_columns)
rate_pair_key <- make_key(rate_rows, pair_columns)

if (
  anyDuplicated(number_pair_key) ||
    anyDuplicated(rate_pair_key) ||
    !setequal(number_pair_key, rate_pair_key)
) {
  stop("Risk input has incomplete or duplicated Number/Rate pairs.", call. = FALSE)
}

rate_match <- match(number_pair_key, rate_pair_key)
paired_rate <- rate_rows$val[rate_match]
nonzero_rate <- paired_rate != 0
implied_population <- rep(NA_real_, nrow(number_rows))
implied_population[nonzero_rate] <-
  number_rows$val[nonzero_rate] /
  paired_rate[nonzero_rate] *
  100000

population_qc_list <- lapply(
  age_order,
  function(age_value) {
    values <- implied_population[
      number_rows$age == age_value & is.finite(implied_population)
    ]
    median_value <- stats::median(values)
    max_relative_deviation <- max(abs(values - median_value) / median_value)
    data.frame(
      age = age_value,
      nonzero_number_rate_pairs = length(values),
      median_implied_population = median_value,
      maximum_relative_deviation = max_relative_deviation,
      stringsAsFactors = FALSE
    )
  }
)
population_qc <- do.call(rbind, population_qc_list)
maximum_population_relative_deviation <-
  max(population_qc$maximum_relative_deviation)

if (maximum_population_relative_deviation > 0.01) {
  stopf(
    paste0(
      "Number/Rate pairs imply inconsistent age-specific populations ",
      "(maximum relative deviation %.6f)"
    ),
    maximum_population_relative_deviation
  )
}


# ------------------------------------------------------------------------------
# 3. Frozen membership and Stage 2/3 baselines
# ------------------------------------------------------------------------------

membership_data <- read_csv_strict(
  membership_csv,
  "frozen cluster membership"
)
require_columns(
  membership_data,
  c("cause", "cluster_name"),
  "frozen cluster membership"
)

if (anyDuplicated(membership_data$cause)) {
  stop("Frozen membership contains duplicate causes.", call. = FALSE)
}
if (nrow(membership_data) != 292L) {
  stopf(
    "Expected 292 frozen causes; found %d",
    nrow(membership_data)
  )
}
if (!all(membership_data$cluster_name %in% cluster_order)) {
  stop("Frozen membership contains an unknown cluster label.", call. = FALSE)
}

membership_counts <- table(
  factor(membership_data$cluster_name, levels = cluster_order)
)
expected_membership_counts <- c(57L, 71L, 164L)
if (!identical(as.integer(membership_counts), expected_membership_counts)) {
  stopf(
    "Frozen membership counts changed: %s",
    format_counts(membership_counts)
  )
}

cluster_by_cause <- setNames(
  membership_data$cluster_name,
  membership_data$cause
)

mortality_data <- read_csv_strict(
  mortality_csv,
  "Part 3 mortality baseline"
)
require_columns(
  mortality_data,
  c(
    "year",
    "cluster_name",
    "age",
    "death_number",
    "death_rate_per_100k",
    "mx",
    "q5"
  ),
  "Part 3 mortality baseline"
)

mortality_2023 <- mortality_data[
  as.integer(mortality_data$year) == 2023L &
    mortality_data$cluster_name %in% cluster_order &
    mortality_data$age %in% age_order,
  c(
    "cluster_name",
    "age",
    "death_number",
    "death_rate_per_100k",
    "mx",
    "q5"
  )
]

for (column in c("death_number", "death_rate_per_100k", "mx", "q5")) {
  mortality_2023[[column]] <- strict_numeric(
    mortality_2023[[column]],
    column,
    "Part 3 mortality baseline"
  )
}

mortality_2023$cluster_index <- match(
  mortality_2023$cluster_name,
  cluster_order
)
mortality_2023$age_index <- match(mortality_2023$age, age_order)
mortality_2023 <- mortality_2023[
  order(mortality_2023$cluster_index, mortality_2023$age_index),
]

if (
  nrow(mortality_2023) != length(cluster_order) * length(age_order) ||
    anyDuplicated(make_key(mortality_2023, c("cluster_name", "age")))
) {
  stop("Part 3 mortality baseline is incomplete or duplicated.", call. = FALSE)
}

if (
  any(mortality_2023$death_number < 0) ||
    any(mortality_2023$death_rate_per_100k < 0) ||
    any(mortality_2023$mx < 0) ||
    any(mortality_2023$q5 < 0 | mortality_2023$q5 >= 1)
) {
  stop("Part 3 mortality baseline contains invalid values.", call. = FALSE)
}

if (
  any(
    abs(
      mortality_2023$mx -
        mortality_2023$death_rate_per_100k / 100000
    ) > 1e-12
  )
) {
  stop("Part 3 mx values do not match death rates.", call. = FALSE)
}

if (
  any(
    abs(
      mortality_2023$q5 -
        rate_to_5q(mortality_2023$death_rate_per_100k)
    ) > 1e-12
  )
) {
  stop("Part 3 q5 values do not reproduce the Stage 3 formula.", call. = FALSE)
}

baseline_q30_70 <- setNames(
  vapply(
    cluster_order,
    function(cluster_value) {
      rows <- mortality_2023[
        mortality_2023$cluster_name == cluster_value,
      ]
      rows <- rows[order(rows$age_index),]
      q30_70_from_5year_rates(rows$death_rate_per_100k)
    },
    numeric(1L)
  ),
  cluster_order
)

daly_baseline_data <- read_csv_strict(
  daly_baseline_csv,
  "Stage 2 DALY baseline"
)
require_columns(
  daly_baseline_data,
  c("cluster_name", "DALYs_age30_69"),
  "Stage 2 DALY baseline"
)

daly_baseline_data <- daly_baseline_data[
  daly_baseline_data$cluster_name %in% cluster_order,
  c("cluster_name", "DALYs_age30_69")
]
daly_baseline_data$DALYs_age30_69 <- strict_numeric(
  daly_baseline_data$DALYs_age30_69,
  "DALYs_age30_69",
  "Stage 2 DALY baseline"
)

if (
  nrow(daly_baseline_data) != length(cluster_order) ||
    anyDuplicated(daly_baseline_data$cluster_name) ||
    !setequal(daly_baseline_data$cluster_name, cluster_order) ||
    any(daly_baseline_data$DALYs_age30_69 <= 0)
) {
  stop("Stage 2 DALY baseline is incomplete or invalid.", call. = FALSE)
}

baseline_daly <- setNames(
  daly_baseline_data$DALYs_age30_69,
  daly_baseline_data$cluster_name
)


# ------------------------------------------------------------------------------
# 4. Link risk causes to the frozen life-course clusters
# ------------------------------------------------------------------------------

risk_data$cluster_name <- unname(cluster_by_cause[risk_data$cause])
unmapped_rows <- is.na(risk_data$cluster_name)
unmapped_causes <- sort(unique(risk_data$cause[unmapped_rows]))

if (any(unmapped_rows & abs(risk_data$val) > 1e-12)) {
  stopf(
    paste0(
      "Unmapped causes have non-zero attributable burden and cannot be ",
      "silently excluded: %s"
    ),
    paste(unmapped_causes, collapse = " | ")
  )
}

mapped_risk_data <- risk_data[!unmapped_rows,]
risk_causes <- sort(unique(risk_data$cause))
mapped_risk_causes <- sort(intersect(risk_causes, names(cluster_by_cause)))
frozen_causes_absent_from_risk_file <- sort(
  setdiff(names(cluster_by_cause), risk_causes)
)

all_mapping_causes <- sort(unique(c(names(cluster_by_cause), risk_causes)))
cause_mapping <- data.frame(
  cause = all_mapping_causes,
  cluster_name = unname(cluster_by_cause[all_mapping_causes]),
  mapped_to_frozen_cluster = all_mapping_causes %in% names(cluster_by_cause),
  present_in_risk_file = all_mapping_causes %in% risk_causes,
  number_of_level2_risks_with_exported_rows = vapply(
    all_mapping_causes,
    function(cause_value) {
      length(unique(risk_data$rei[risk_data$cause == cause_value]))
    },
    integer(1L)
  ),
  stringsAsFactors = FALSE
)
cause_mapping$cluster_name[is.na(cause_mapping$cluster_name)] <-
  "UNMAPPED_EXCLUDED"


# ------------------------------------------------------------------------------
# 5. Aggregate one risk at a time within cluster and complete the fixed grid
# ------------------------------------------------------------------------------

mapped_risk_data$risk <- mapped_risk_data$rei
aggregate_keys <- c("risk", "cluster_name", "age", "measure")

aggregate_metric <- function(data, metric_value, value_name, negative_name) {
  selected <- data[data$metric == metric_value,]

  value_result <- stats::aggregate(
    selected$val,
    by = selected[aggregate_keys],
    FUN = sum
  )
  names(value_result)[ncol(value_result)] <- value_name

  negative_result <- stats::aggregate(
    as.integer(selected$val < 0),
    by = selected[aggregate_keys],
    FUN = sum
  )
  names(negative_result)[ncol(negative_result)] <- negative_name

  merge(
    value_result,
    negative_result,
    by = aggregate_keys,
    all = TRUE,
    sort = FALSE
  )
}

number_aggregate <- aggregate_metric(
  mapped_risk_data,
  "Number",
  "raw_attributable_number",
  "negative_number_rows"
)
rate_aggregate <- aggregate_metric(
  mapped_risk_data,
  "Rate",
  "raw_attributable_rate_per_100k",
  "negative_rate_rows"
)

source_row_count <- stats::aggregate(
  rep.int(1L, nrow(mapped_risk_data)),
  by = mapped_risk_data[aggregate_keys],
  FUN = sum
)
names(source_row_count)[ncol(source_row_count)] <- "source_row_count"

source_cause_count <- stats::aggregate(
  mapped_risk_data$cause,
  by = mapped_risk_data[aggregate_keys],
  FUN = function(x) length(unique(x))
)
names(source_cause_count)[ncol(source_cause_count)] <- "source_cause_count"

risk_grid <- expand.grid(
  risk = expected_level2_risks,
  cluster_name = cluster_order,
  age = age_order,
  measure = measure_order,
  stringsAsFactors = FALSE,
  KEEP.OUT.ATTRS = FALSE
)

risk_age_aggregate <- merge(
  risk_grid,
  number_aggregate,
  by = aggregate_keys,
  all.x = TRUE,
  sort = FALSE
)
risk_age_aggregate <- merge(
  risk_age_aggregate,
  rate_aggregate,
  by = aggregate_keys,
  all.x = TRUE,
  sort = FALSE
)
risk_age_aggregate <- merge(
  risk_age_aggregate,
  source_row_count,
  by = aggregate_keys,
  all.x = TRUE,
  sort = FALSE
)
risk_age_aggregate <- merge(
  risk_age_aggregate,
  source_cause_count,
  by = aggregate_keys,
  all.x = TRUE,
  sort = FALSE
)

zero_fill_columns <- c(
  "raw_attributable_number",
  "raw_attributable_rate_per_100k",
  "negative_number_rows",
  "negative_rate_rows",
  "source_row_count",
  "source_cause_count"
)
for (column in zero_fill_columns) {
  risk_age_aggregate[[column]][is.na(risk_age_aggregate[[column]])] <- 0
}

risk_age_aggregate$risk_index <- match(
  risk_age_aggregate$risk,
  expected_level2_risks
)
risk_age_aggregate$cluster_index <- match(
  risk_age_aggregate$cluster_name,
  cluster_order
)
risk_age_aggregate$age_index <- match(
  risk_age_aggregate$age,
  age_order
)
risk_age_aggregate$measure_index <- match(
  risk_age_aggregate$measure,
  measure_order
)
risk_age_aggregate <- risk_age_aggregate[
  order(
    risk_age_aggregate$risk_index,
    risk_age_aggregate$cluster_index,
    risk_age_aggregate$age_index,
    risk_age_aggregate$measure_index
  ),
]

if (nrow(risk_age_aggregate) != 20L * 3L * 8L * 2L) {
  stop("Completed risk-by-cluster-by-age grid is not 960 rows.", call. = FALSE)
}

risk_age_aggregate$risk_level <- "Level 2"
risk_age_aggregate$bounded_attributable_number <- pmax(
  risk_age_aggregate$raw_attributable_number,
  0
)
risk_age_aggregate$bounded_attributable_rate_per_100k <- pmax(
  risk_age_aggregate$raw_attributable_rate_per_100k,
  0
)
risk_age_aggregate$number_clip <- ifelse(
  risk_age_aggregate$raw_attributable_number < 0,
  "lower_bound_zero",
  "none"
)
risk_age_aggregate$rate_clip <- ifelse(
  risk_age_aggregate$raw_attributable_rate_per_100k < 0,
  "lower_bound_zero",
  "none"
)
risk_age_aggregate$baseline_death_number <- NA_real_
risk_age_aggregate$baseline_death_rate_per_100k <- NA_real_
risk_age_aggregate$counterfactual_death_rate_per_100k <- NA_real_
risk_age_aggregate$counterfactual_q5 <- NA_real_

death_cells <- risk_age_aggregate$measure == deaths_label
mortality_match <- match(
  make_key(
    risk_age_aggregate[death_cells,],
    c("cluster_name", "age")
  ),
  make_key(mortality_2023, c("cluster_name", "age"))
)

if (anyNA(mortality_match)) {
  stop("Could not match every risk death cell to the Part 3 baseline.", call. = FALSE)
}

baseline_death_number_for_cells <- mortality_2023$death_number[mortality_match]
baseline_death_rate_for_cells <-
  mortality_2023$death_rate_per_100k[mortality_match]

raw_death_number <- risk_age_aggregate$raw_attributable_number[death_cells]
raw_death_rate <-
  risk_age_aggregate$raw_attributable_rate_per_100k[death_cells]

risk_age_aggregate$bounded_attributable_number[death_cells] <- pmin(
  pmax(raw_death_number, 0),
  baseline_death_number_for_cells
)
risk_age_aggregate$bounded_attributable_rate_per_100k[death_cells] <- pmin(
  pmax(raw_death_rate, 0),
  baseline_death_rate_for_cells
)

risk_age_aggregate$number_clip[death_cells] <- ifelse(
  raw_death_number < 0,
  "lower_bound_zero",
  ifelse(
    raw_death_number > baseline_death_number_for_cells,
    "upper_bound_baseline",
    "none"
  )
)
risk_age_aggregate$rate_clip[death_cells] <- ifelse(
  raw_death_rate < 0,
  "lower_bound_zero",
  ifelse(
    raw_death_rate > baseline_death_rate_for_cells,
    "upper_bound_baseline",
    "none"
  )
)

risk_age_aggregate$baseline_death_number[death_cells] <-
  baseline_death_number_for_cells
risk_age_aggregate$baseline_death_rate_per_100k[death_cells] <-
  baseline_death_rate_for_cells
risk_age_aggregate$counterfactual_death_rate_per_100k[death_cells] <-
  baseline_death_rate_for_cells -
  risk_age_aggregate$bounded_attributable_rate_per_100k[death_cells]
risk_age_aggregate$counterfactual_q5[death_cells] <- rate_to_5q(
  risk_age_aggregate$counterfactual_death_rate_per_100k[death_cells]
)


# ------------------------------------------------------------------------------
# 6. Risk-specific q30-70 counterfactuals
# ------------------------------------------------------------------------------

q_result_list <- vector(
  "list",
  length(expected_level2_risks) * length(cluster_order)
)
result_index <- 1L

for (risk_value in expected_level2_risks) {
  for (cluster_value in cluster_order) {
    cells <- risk_age_aggregate[
      risk_age_aggregate$risk == risk_value &
        risk_age_aggregate$cluster_name == cluster_value &
        risk_age_aggregate$measure == deaths_label,
    ]
    cells <- cells[order(cells$age_index),]

    if (nrow(cells) != length(age_order)) {
      stopf("Incomplete death counterfactual for %s / %s", risk_value, cluster_value)
    }

    counterfactual_q <- 1 - prod(1 - cells$counterfactual_q5)
    baseline_q <- baseline_q30_70[[cluster_value]]
    absolute_reduction <- baseline_q - counterfactual_q

    if (
      !is.finite(counterfactual_q) ||
        counterfactual_q < -1e-12 ||
        counterfactual_q > baseline_q + 1e-12 ||
        absolute_reduction < -1e-12
    ) {
      stopf("Invalid q30-70 counterfactual for %s / %s", risk_value, cluster_value)
    }

    q_result_list[[result_index]] <- data.frame(
      risk_level = "Level 2",
      risk = risk_value,
      cluster_name = cluster_value,
      baseline_q30_70 = baseline_q,
      counterfactual_q30_70_TMREL = counterfactual_q,
      absolute_q30_70_reduction = absolute_reduction,
      relative_q30_70_reduction = absolute_reduction / baseline_q,
      relative_q30_70_reduction_percent = 100 * absolute_reduction / baseline_q,
      avoidable_deaths_age30_69 = sum(cells$bounded_attributable_number),
      sum_age_specific_attributable_rate_per_100k = sum(
        cells$bounded_attributable_rate_per_100k
      ),
      age_cells_clipped_at_zero = sum(cells$rate_clip == "lower_bound_zero"),
      age_cells_capped_at_baseline = sum(
        cells$rate_clip == "upper_bound_baseline"
      ),
      stringsAsFactors = FALSE
    )
    result_index <- result_index + 1L
  }
}

q_results <- do.call(rbind, q_result_list)


# ------------------------------------------------------------------------------
# 7. Risk-specific avoidable DALYs at ages 30-69
# ------------------------------------------------------------------------------

daly_result_list <- vector(
  "list",
  length(expected_level2_risks) * length(cluster_order)
)
result_index <- 1L

for (risk_value in expected_level2_risks) {
  for (cluster_value in cluster_order) {
    cells <- risk_age_aggregate[
      risk_age_aggregate$risk == risk_value &
        risk_age_aggregate$cluster_name == cluster_value &
        risk_age_aggregate$measure == daly_label,
    ]
    cells <- cells[order(cells$age_index),]

    if (nrow(cells) != length(age_order)) {
      stopf("Incomplete DALY counterfactual for %s / %s", risk_value, cluster_value)
    }

    raw_signed_dalys <- sum(cells$raw_attributable_number)
    avoidable_dalys <- max(raw_signed_dalys, 0)
    cluster_daly_baseline <- baseline_daly[[cluster_value]]

    daly_result_list[[result_index]] <- data.frame(
      risk_level = "Level 2",
      risk = risk_value,
      cluster_name = cluster_value,
      baseline_DALYs_age30_69 = cluster_daly_baseline,
      raw_signed_attributable_DALYs_age30_69 = raw_signed_dalys,
      avoidable_DALYs_age30_69 = avoidable_dalys,
      avoidable_DALY_fraction = avoidable_dalys / cluster_daly_baseline,
      avoidable_DALY_percent = 100 * avoidable_dalys / cluster_daly_baseline,
      cellwise_nonnegative_DALYs_QC = sum(
        cells$bounded_attributable_number
      ),
      stringsAsFactors = FALSE
    )
    result_index <- result_index + 1L
  }
}

daly_results <- do.call(rbind, daly_result_list)

summary_results <- merge(
  q_results,
  daly_results,
  by = c("risk_level", "risk", "cluster_name"),
  all = TRUE,
  sort = FALSE
)

summary_results$risk_index <- match(
  summary_results$risk,
  expected_level2_risks
)
summary_results$cluster_index <- match(
  summary_results$cluster_name,
  cluster_order
)
summary_results <- summary_results[
  order(summary_results$risk_index, summary_results$cluster_index),
]

summary_results$q30_70_reduction_rank_within_cluster <- NA_integer_
summary_results$avoidable_DALY_rank_within_cluster <- NA_integer_

for (cluster_value in cluster_order) {
  indices <- which(summary_results$cluster_name == cluster_value)

  q_order <- order(
    -summary_results$absolute_q30_70_reduction[indices],
    match(summary_results$risk[indices], expected_level2_risks)
  )
  summary_results$q30_70_reduction_rank_within_cluster[indices[q_order]] <-
    seq_along(q_order)

  daly_order <- order(
    -summary_results$avoidable_DALYs_age30_69[indices],
    match(summary_results$risk[indices], expected_level2_risks)
  )
  summary_results$avoidable_DALY_rank_within_cluster[indices[daly_order]] <-
    seq_along(daly_order)
}

expected_result_keys <- as.vector(
  outer(
    expected_level2_risks,
    cluster_order,
    paste,
    sep = "\r"
  )
)
observed_result_keys <- paste(
  summary_results$risk,
  summary_results$cluster_name,
  sep = "\r"
)

if (
  nrow(summary_results) != 60L ||
    anyDuplicated(observed_result_keys) ||
    !setequal(observed_result_keys, expected_result_keys)
) {
  stop("Risk-specific 20-by-3 result grid is incomplete.", call. = FALSE)
}


# ------------------------------------------------------------------------------
# 8. Baseline summary, QC tables and output files
# ------------------------------------------------------------------------------

baseline_cluster_summary <- do.call(
  rbind,
  lapply(
    cluster_order,
    function(cluster_value) {
      mortality_rows <- mortality_2023[
        mortality_2023$cluster_name == cluster_value,
      ]
      data.frame(
        cluster_name = cluster_value,
        n_frozen_causes = as.integer(membership_counts[[cluster_value]]),
        baseline_deaths_age30_69 = sum(mortality_rows$death_number),
        baseline_DALYs_age30_69 = baseline_daly[[cluster_value]],
        baseline_q30_70 = baseline_q30_70[[cluster_value]],
        stringsAsFactors = FALSE
      )
    }
  )
)

excluded_unmapped_summary <- if (any(unmapped_rows)) {
  aggregate(
    risk_data$val[unmapped_rows],
    by = risk_data[unmapped_rows, c("measure", "metric")],
    FUN = sum
  )
} else {
  data.frame(
    measure = character(0),
    metric = character(0),
    x = numeric(0),
    stringsAsFactors = FALSE
  )
}

excluded_unmapped_text <- if (nrow(excluded_unmapped_summary) > 0L) {
  paste(
    paste0(
      excluded_unmapped_summary$measure,
      "/",
      excluded_unmapped_summary$metric,
      "=",
      format(excluded_unmapped_summary$x, scientific = FALSE, trim = TRUE)
    ),
    collapse = " | "
  )
} else {
  "none"
}

rows_by_measure_metric <- table(risk_data$measure, risk_data$metric)

qc_table <- data.frame(
  check = c(
    "risk_input_file",
    "membership_input_file",
    "mortality_input_file",
    "daly_baseline_input_file",
    "risk_rows",
    "risk_columns",
    "risk_hierarchy_level",
    "level2_risks",
    "causes_in_risk_file",
    "risk_cause_pairs",
    "age_groups",
    "measures",
    "metrics",
    "Deaths_Number_rows",
    "Deaths_Rate_rows",
    "DALYs_Number_rows",
    "DALYs_Rate_rows",
    "duplicate_full_keys",
    "incomplete_number_rate_pairs",
    "uncertainty_bound_failures",
    "negative_point_estimate_rows",
    "zero_point_estimate_rows",
    "maximum_implied_population_relative_deviation",
    "frozen_clustered_causes",
    "frozen_cluster_counts",
    "risk_causes_mapped",
    "risk_causes_unmapped",
    "unmapped_cause_names",
    "frozen_causes_absent_from_risk_file",
    "excluded_unmapped_rows",
    "excluded_unmapped_values",
    "baseline_q30_70",
    "risk_cluster_result_rows",
    "cross_risk_aggregation_performed",
    "negative_estimate_handling",
    "uncertainty_interval_propagation"
  ),
  value = c(
    normalizePath(risk_csv, winslash = "/", mustWork = TRUE),
    normalizePath(membership_csv, winslash = "/", mustWork = TRUE),
    normalizePath(mortality_csv, winslash = "/", mustWork = TRUE),
    normalizePath(daly_baseline_csv, winslash = "/", mustWork = TRUE),
    nrow(risk_data),
    paste(names(risk_data)[names(risk_data) != "cluster_name"], collapse = " | "),
    "Level 2 (validated from exact 20-label selection)",
    length(expected_level2_risks),
    length(risk_causes),
    nrow(unique(risk_data[c("rei", "cause")])),
    paste(age_order, collapse = " | "),
    paste(measure_order, collapse = " | "),
    "Number | Rate",
    rows_by_measure_metric[deaths_label, "Number"],
    rows_by_measure_metric[deaths_label, "Rate"],
    rows_by_measure_metric[daly_label, "Number"],
    rows_by_measure_metric[daly_label, "Rate"],
    duplicate_full_keys,
    0L,
    0L,
    sum(risk_data$val < 0),
    sum(risk_data$val == 0),
    maximum_population_relative_deviation,
    nrow(membership_data),
    format_counts(membership_counts),
    length(mapped_risk_causes),
    length(unmapped_causes),
    if (length(unmapped_causes)) paste(unmapped_causes, collapse = " | ") else "none",
    length(frozen_causes_absent_from_risk_file),
    sum(unmapped_rows),
    excluded_unmapped_text,
    paste(
      names(baseline_q30_70),
      format(baseline_q30_70, digits = 16, trim = TRUE),
      sep = "=",
      collapse = " | "
    ),
    nrow(summary_results),
    "FALSE",
    paste0(
      "Raw signed values retained; prevention endpoints bounded at zero. ",
      "Death attribution also capped at the corresponding cluster-age baseline."
    ),
    paste0(
      "Not performed: draw-level covariance is unavailable, so lower/upper ",
      "bounds are validated but not summed across causes. Results are point estimates."
    )
  ),
  stringsAsFactors = FALSE
)

age_output_columns <- c(
  "risk_level",
  "risk",
  "cluster_name",
  "age",
  "measure",
  "source_cause_count",
  "source_row_count",
  "negative_number_rows",
  "negative_rate_rows",
  "raw_attributable_number",
  "raw_attributable_rate_per_100k",
  "bounded_attributable_number",
  "bounded_attributable_rate_per_100k",
  "number_clip",
  "rate_clip",
  "baseline_death_number",
  "baseline_death_rate_per_100k",
  "counterfactual_death_rate_per_100k",
  "counterfactual_q5"
)

summary_results$risk_index <- NULL
summary_results$cluster_index <- NULL

write_output_csv(qc_table, "Step4_input_QC.csv")
write_output_csv(population_qc, "Step4_number_rate_population_QC.csv")
write_output_csv(cause_mapping, "Step4_risk_cause_cluster_mapping.csv")
write_output_csv(baseline_cluster_summary, "Step4_baseline_cluster_2023.csv")
write_output_csv(
  risk_age_aggregate[age_output_columns],
  "Step4_risk_cluster_age_aggregates.csv"
)
write_output_csv(q_results, "Step4_q30_70_counterfactuals.csv")
write_output_csv(daly_results, "Step4_DALY_counterfactuals.csv")
write_output_csv(summary_results, "Step4_risk_cluster_summary.csv")


# ------------------------------------------------------------------------------
# 9. Human-readable key-results report and reproducibility objects
# ------------------------------------------------------------------------------

report_lines <- c(
  "# Step 4 key QC and results (R implementation)",
  "",
  "## Input and linkage QC",
  "",
  sprintf(
    "- Risk input: %s rows, 20 Level-2 risks, %d causes, and %d risk-cause pairs.",
    format(nrow(risk_data), big.mark = ",", scientific = FALSE),
    length(risk_causes),
    nrow(unique(risk_data[c("rei", "cause")]))
  ),
  paste0(
    "- Coverage: China, Both, 2023; eight 5-year age groups from 30-34 through ",
    "65-69; Deaths and DALYs; Number and Rate."
  ),
  sprintf(
    "- Frozen membership: 292 causes (%s).",
    format_counts(membership_counts)
  ),
  sprintf(
    paste0(
      "- Linkage: %d risk-file causes mapped; %d unmapped cause(s) (%s); ",
      "all excluded attributable estimates are zero."
    ),
    length(mapped_risk_causes),
    length(unmapped_causes),
    if (length(unmapped_causes)) paste(unmapped_causes, collapse = " | ") else "none"
  ),
  sprintf(
    paste0(
      "- Frozen causes without an exported Level-2 risk-cause record: %d ",
      "(zero-filled in the analysis grid)."
    ),
    length(frozen_causes_absent_from_risk_file)
  ),
  sprintf(
    paste0(
      "- Integrity checks: 0 duplicate keys, 0 incomplete Number/Rate pairs, ",
      "0 uncertainty-bound failures; maximum Number/Rate implied-population ",
      "deviation %.3f%%."
    ),
    100 * maximum_population_relative_deviation
  ),
  sprintf(
    paste0(
      "- Signed estimates: %d source rows are negative. Raw values are retained; ",
      "prevention endpoints are bounded at zero and every adjustment is flagged."
    ),
    sum(risk_data$val < 0)
  ),
  paste0(
    "- Uncertainty: lower/upper bounds pass internal checks but are not ",
    "aggregated without draw-level covariance; reported results are point estimates."
  ),
  "",
  "## Baseline q30-70",
  "",
  "| Cluster | Baseline q30-70 |",
  "|---|---:|"
)

for (cluster_value in cluster_order) {
  report_lines <- c(
    report_lines,
    sprintf(
      "| %s | %.3f%% |",
      cluster_value,
      100 * baseline_q30_70[[cluster_value]]
    )
  )
}

for (cluster_value in cluster_order) {
  cluster_rows <- summary_results[
    summary_results$cluster_name == cluster_value,
  ]

  q_top <- cluster_rows[
    order(-cluster_rows$absolute_q30_70_reduction),
  ][seq_len(5L),]

  report_lines <- c(
    report_lines,
    "",
    sprintf("## %s: largest q30-70 reductions", cluster_value),
    "",
    paste0(
      "| Level-2 risk removed to TMREL | Absolute reduction ",
      "(percentage points) | Relative reduction | Avoidable deaths, ages 30-69 |"
    ),
    "|---|---:|---:|---:|"
  )

  for (i in seq_len(nrow(q_top))) {
    report_lines <- c(
      report_lines,
      sprintf(
        "| %s | %.3f | %.2f%% | %s |",
        q_top$risk[[i]],
        100 * q_top$absolute_q30_70_reduction[[i]],
        q_top$relative_q30_70_reduction_percent[[i]],
        format(
          round(q_top$avoidable_deaths_age30_69[[i]]),
          big.mark = ",",
          scientific = FALSE,
          trim = TRUE
        )
      )
    )
  }

  daly_top <- cluster_rows[
    order(-cluster_rows$avoidable_DALYs_age30_69),
  ][seq_len(5L),]

  report_lines <- c(
    report_lines,
    "",
    sprintf("## %s: largest avoidable DALY estimates", cluster_value),
    "",
    paste0(
      "| Level-2 risk removed to TMREL | Avoidable DALYs, ages 30-69 | ",
      "Share of cluster DALYs |"
    ),
    "|---|---:|---:|"
  )

  for (i in seq_len(nrow(daly_top))) {
    report_lines <- c(
      report_lines,
      sprintf(
        "| %s | %s | %.2f%% |",
        daly_top$risk[[i]],
        format(
          round(daly_top$avoidable_DALYs_age30_69[[i]]),
          big.mark = ",",
          scientific = FALSE,
          trim = TRUE
        ),
        daly_top$avoidable_DALY_percent[[i]]
      )
    )
  }
}

report_lines <- c(
  report_lines,
  "",
  "## Interpretation guardrail",
  "",
  paste0(
    "Every row is a separate one-risk TMREL counterfactual. These effects must ",
    "not be summed across risks because GBD risk-attributable burdens overlap ",
    "and may include mediation."
  ),
  ""
)

writeLines(
  report_lines,
  file.path(output_dir, "Step4_key_results.md"),
  useBytes = TRUE
)

manifest_lines <- c(
  "analysis=Step 4 risk-factor TMREL counterfactuals",
  "implementation=R (base R only)",
  "risk_level=GBD 2023 Level 2",
  paste0("risk_csv=", normalizePath(risk_csv, winslash = "/", mustWork = TRUE)),
  paste0(
    "membership_csv=",
    normalizePath(membership_csv, winslash = "/", mustWork = TRUE)
  ),
  paste0(
    "mortality_csv=",
    normalizePath(mortality_csv, winslash = "/", mustWork = TRUE)
  ),
  paste0(
    "daly_baseline_csv=",
    normalizePath(daly_baseline_csv, winslash = "/", mustWork = TRUE)
  ),
  "rule_each_risk_evaluated_independently=TRUE",
  "rule_cross_risk_sums_forbidden=TRUE",
  "q5_formula=5mx/(1+2.5mx)",
  "uncertainty=point estimates; draw-level covariance unavailable"
)
writeLines(
  manifest_lines,
  file.path(output_dir, "Step4_manifest.txt"),
  useBytes = TRUE
)

saveRDS(
  list(
    risk_input_qc = qc_table,
    population_qc = population_qc,
    frozen_membership = membership_data,
    cause_mapping = cause_mapping,
    baseline_cluster_summary = baseline_cluster_summary,
    risk_cluster_age_aggregates = risk_age_aggregate[age_output_columns],
    q30_70_counterfactuals = q_results,
    daly_counterfactuals = daly_results,
    risk_cluster_summary = summary_results
  ),
  file.path(output_dir, "Step4_RiskCounterfactual_analysis_objects.rds")
)

capture.output(
  sessionInfo(),
  file = file.path(output_dir, "Step4_sessionInfo.txt")
)


# ------------------------------------------------------------------------------
# 10. Console summary
# ------------------------------------------------------------------------------

cat("============================================================\n")
cat("STEP 4 RISK-FACTOR COUNTERFACTUAL ANALYSIS COMPLETE\n")
cat("============================================================\n")
cat("Clustering rerun: NO\n")
cat("Frozen membership: 57 / 71 / 164 = 292 causes\n")
cat("Risk hierarchy: Level 2 (20 exact labels)\n")
cat("Cross-risk aggregation: NO\n")
cat("Uncertainty propagation: NO (point estimates; draws unavailable)\n")
cat("\nBaseline cluster q30-70 in 2023:\n")
print(baseline_cluster_summary[c("cluster_name", "baseline_q30_70")])
cat("\nTop q30-70 reduction within each cluster:\n")
print(
  summary_results[
    summary_results$q30_70_reduction_rank_within_cluster == 1L,
    c(
      "cluster_name",
      "risk",
      "absolute_q30_70_reduction",
      "relative_q30_70_reduction_percent"
    )
  ]
)
cat("\nTop avoidable DALY estimate within each cluster:\n")
print(
  summary_results[
    summary_results$avoidable_DALY_rank_within_cluster == 1L,
    c(
      "cluster_name",
      "risk",
      "avoidable_DALYs_age30_69",
      "avoidable_DALY_percent"
    )
  ]
)
cat("\nOutputs written to:\n")
cat(normalizePath(output_dir, winslash = "/", mustWork = TRUE), "\n")

