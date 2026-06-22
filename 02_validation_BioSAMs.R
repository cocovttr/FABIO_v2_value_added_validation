# ==============================================================================
# BioSAMs validation chart — per-year VA comparison at BioSAM categories
#
# Produces, per BioSAM-covered country, FOUR figures: a TOTAL value-added figure
# and one each for the value-added strands WAGES, CAPITAL and TLS (taxes less
# subsidies), all sharing the same three-source / stacked-by-category layout.
# The strands are intrinsic to all three sources:
#     • BioSAMs carry them as three VA accounts
#         LABOUR -> wages, CAPITAL -> capital, TLS-A -> tls   (TLS-C excluded)
#     • GLORIA / COMBINED carry them as the component-split columns written by
#       scripts 14_1 / 14_4:  value_added_wages|capital|tls [USD]  (the TOTAL figure
#       is their sum).
#
#   Benchmark — EUROSTAT for all four figures.  Every figure (total and each
#   strand) draws a horizontal reference line per year-panel taken from EUROSTAT
#   National Accounts (nama_10_a64, current prices), summed over NACE A01 (crop &
#   animal production) + A03 (fishing & aquaculture).  A02 (forestry) is not in
#   that sum, so the reference is forestry-free: the Eurostat A01+A03 total is the
#   FABIO-comparable primary-agriculture figure directly.  Strand mapping:
#       wages   <- D1                         (compensation of employees)
#       tls     <- D29X39                     (other taxes less subsidies on prod.)
#       capital <- B1G - D1 - D29X39          (via the GVA identity; NAMA has no
#                                              standalone B2A3G code)
#       total   <- B1G
#   Eurostat is in EUR millions, converted EUR->USD with the SAME Germany SLC
#   rate the BioSAMs use.  Being A01+A03, the Eurostat line is a PRIMARY-
#   agriculture (ISIC-A) reference, so it is meant to be read against the ISIC-A
#   sub-stack flushed to the bottom of each bar.  The benchmark is READ from the
#   staged nama_10_a64 CSV (the same one FABIO's pipeline stages and reads) and
#   shared across all four measures; if that CSV is missing the figures are still
#   drawn, just without the reference line.
#
#   Note on the TLS strand: all three sources use the PRODUCTION-side taxes
#   less subsidies and exclude the product-side ones — BioSAMs keep TLS-A and
#   drop TLS-C (a tax on products), GLORIA / COMBINED's tls is taxes/subsidies
#   on production, and Eurostat's D29X39 is "other taxes less subsidies on
#   production" (the product-tax code D21X31 is not used).  So the strand is
#   like-for-like across sources and reference.  It can be NET NEGATIVE where
#   subsidies exceed taxes (common in agriculture); the figure then extends the
#   y-axis below zero and draws a thin zero baseline.
#
#   Purpose:
#   Validate the FABIOv2 value-added estimates against the JRC BioSAMs.  TWO
#   year panels are shown per figure — one for 2010, one for 2015 (the years the
#   BioSAMs cover).  Each figure is a grid of per-country panels (facet_wrap over
#   the BioSAM-covered countries); within every panel:
#
#       y  │  ███   up to FIVE sources on the x axis, one stacked bar each:
#          │  ███     BioSAMs (raw JRC) | GLORIA | COMBINED-GLORIA |
#          │  ███     EXIOBASE | COMBINED-EXIOBASE   (the latter four FABIOv2,
#          │  ███     aggregated to BioSAM categories; EXIOBASE pair omitted
#          │  ███     where its pipeline output is absent)
#       ───┼──────   ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─
#          │            • bars stacked by BioSAM category (one colour each),
#          │            • ISIC-C (processing) segments grouped at the TOP and
#          │              outlined in BLACK; ISIC-A (primary) below, no outline,
#          │            • horizontal line(s) = the country's primary-agriculture
#          │              value-added (Eurostat A01+A03).
#       ───┼──────   ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─
#
#   Why ISIC-A at the bottom: the Eurostat A01+A03 reference is a PRIMARY-
#   agriculture (ISIC-A) figure, so flushing the ISIC-A sub-stack to the bottom
#   of each bar lets it be read directly against the reference line, with the
#   framed ISIC-C processing layer sitting on top.
#
#   The three sources are made comparable as follows:
#     • BioSAMs are the RAW JRC input (the reference data), at BioSAM categories
#       directly.  Their three retained VA accounts (CAPITAL, LABOUR, TLS-A;
#       TLS-C excluded as a tax on products, not VA) are summed to a single
#       value-added figure per (area, item, year) and CONVERTED EUR -> USD using
#       Germany's SLC series from the FAOSTAT exchange-rate file — the same file
#       and direction script 14_4 uses to fold FSDN into COMBINED
#       (value_USD = value_EUR / rate(year)).
#     • GLORIA-FABIOv2 and COMBINED-FABIOv2 are the 14_1 / 14_4 VA
#       outputs (already USD).  Their FABIO-item value-added is AGGREGATED UP to
#       the BioSAM categories via the BioSAM<->FABIO item concordance, separately
#       per ISIC level.  The aggregation is clean: no FABIO item maps to more
#       than one BioSAM category within a single ISIC level, so the sum involves
#       no double-counting.
#
#   ISIC assignment of the RAW BioSAM bars.  BioSAM VA carries no ISIC tag, so
#   each BioSAM item is assigned the ISIC level held by the MAJORITY of its
#   mapped FABIO items in the concordance (ties -> A); a FABIO item tagged at
#   BOTH levels counts only toward A.  All but one category are unambiguous; only
#   A_OANM ("Other animals, live and their products") maps across both levels,
#   and resolves to ISIC-A.  For GLORIA/COMBINED the ISIC level is intrinsic — it
#   is simply which of the two ISIC-level RDS files the FABIO item came from; a
#   category can therefore carry BOTH an A and a C segment (same colour, the C one
#   framed).
#
#   Colours: one stable colour per BioSAM category (a base palette interpolated
#   to the category count, assigned in descending-total order),
#   shared across every country figure and all three source bars.
#
# Outputs:
#   output/biosam_validation/by_country/<ISO3>.svg          (TOTAL value-added)
#   output/biosam_validation/by_country/<ISO3>_wages.svg
#   output/biosam_validation/by_country/<ISO3>_capital.svg
#   output/biosam_validation/by_country/<ISO3>_tls.svg      (per-strand figures)
#       — every figure carries the Eurostat A01+A03 reference line for its measure
#       (total or the matching strand).
#   output/biosam_validation/biosam_vs_fabio_comparison.csv
#       tidy long table behind the figures, BioSAM-covered countries only
#       (iso3c, year, source, isic, biosam_item_code, category, strand, value_usd)
#   output/biosam_validation/eurostat_A01_A03_benchmark.csv
#       the Eurostat NAMA A01+A03 benchmark behind every reference line
#       (iso3c, year, strand, bench_usd) — written only if the fetch succeeded.
#   output/biosam_validation/metrics_vs_nationalaccounts.csv
#       agreement statistics, one row per (measure, source), for all five sources
#       against the Eurostat A01+A03 national-accounts line at ISIC-A scope
#       (measure, source, n, med_ratio, bias_dex, RMSLE_dex, within_2x,
#       sign_agree, med_ratio_mag) — written only if the benchmark is available.
#   output/biosam_validation/metrics_biosam_vs_fabio.csv
#       the same statistics for the four FABIOv2 variants against the raw BioSAMs
#       reference at full ISIC A+C scope (same columns).
#   output/biosam_validation/metrics_biosam_vs_fabio_by_item.csv
#       the same statistics resolved per BioSAM category, so each item's agreement
#       is recoverable on its own (a leading `category` column, then the same
#       columns, one row per category x measure x source).
#
#
# Author:   Coco Vetter
# Rewritten as a validation script: <fill in>
# ==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(dplyr)
  library(tidyr)
  library(readr)
  library(ggplot2)
  library(scales)
})

# ── FABIO + validation-repo integration ──────────────────────────────────────
# The value-added pipeline is now folded into FABIO (lives in ~/fabio). Rather
# than re-deriving paths here, we source the pipeline's single source of truth,
# R/00_value_added_config.R, which (a) sources R/00_value_added_helpers.R — so
# load_item_conc / load_area_conc / the FAOSTAT rate readers come into scope —
# and (b) exports the canonical path/constant set this validator reads from:
#   VA_VALUE_ADDED_OUTPUT_DIR  FABIOv2_*_value_added_ISIC-*.rds  (14_1 / 14_4)
#   VA_EXCHANGE_RATE_CSV       input/fao/Exchange_rate_…(Normalized).csv
#   VA_GERMANY_AREA_CODE (79)  /  VA_FX_ELEMENT_CODE ("SLC")
# Override the repo location with the FABIO_ROOT env var.
FABIO_ROOT <- path.expand(Sys.getenv("FABIO_ROOT", unset = "~/fabio"))
fabio_path <- function(...) file.path(FABIO_ROOT, ...)

# The config resolves `years` (from R/00_system_variables.R) and sources the
# helpers using paths RELATIVE to the FABIO repo root, so source it with the
# working directory temporarily set there. Its constants/helpers land in the
# global environment; the working directory is restored immediately after.
local({
  .old_wd <- getwd(); on.exit(setwd(.old_wd), add = TRUE)
  setwd(FABIO_ROOT)
  sys.source(file.path(FABIO_ROOT, "R", "00_value_added_config.R"),
             envir = globalenv())
})

# This validation repo ships its OWN reference inputs (raw JRC BioSAMs, the
# BioSAM<->FABIO concordances) and receives the validation figures/CSVs. Anchor
# those on the validation-repo root — the directory holding input/ and output/.
# Defaults to the working directory (the .Rproj root); override with the
# VALIDATION_ROOT env var when run head-less.
VALIDATION_ROOT <- path.expand(Sys.getenv("VALIDATION_ROOT", unset = getwd()))
if (!dir.exists(file.path(VALIDATION_ROOT, "input")))
  stop("VALIDATION_ROOT (", VALIDATION_ROOT, ") has no input/ folder. Run from ",
       "the validation repo root, or set the VALIDATION_ROOT env var.")
validation_path       <- function(...) file.path(VALIDATION_ROOT, ...)
VALIDATION_CONC_DIR   <- validation_path("input", "concordances")
# Validation outputs default to the repo's own output/; flip via VALIDATION_OUTPUT_DIR.
VALIDATION_OUTPUT_DIR <- path.expand(Sys.getenv("VALIDATION_OUTPUT_DIR",
                                                unset = validation_path("output")))

# Local validation helper (hline_spec()), shipped alongside this script.
source(validation_path("00_validation_helpers.R"))

# Compatibility shim: the standalone helper faostat_rate_vector(path, area,
# element) was consolidated into faostat_rate_table(path, element), which now
# returns an all-areas data.table (fabio_area_code, year, rate_lcu_per_usd).
# Re-derive the old year-named vector for one area so the call sites below are
# unchanged. `require_years` (optional) hard-fails if any requested year is
# absent, matching the old contract.
faostat_rate_vector <- function(path, area_code, element = "SLC",
                                require_years = NULL) {
  rt <- faostat_rate_table(path, element = element)
  rt <- rt[fabio_area_code == as.integer(area_code)]
  if (nrow(rt) == 0L)
    stop("No FAOSTAT '", element, "' exchange-rate rows for area code ",
         area_code, " in ", path)
  v <- setNames(rt$rate_lcu_per_usd, as.character(rt$year))
  if (!is.null(require_years)) {
    miss <- setdiff(as.character(require_years), names(v))
    if (length(miss))
      stop("FAOSTAT exchange rate ('", element, "', area ", area_code,
           ") missing year(s): ", paste(miss, collapse = ", "))
  }
  v
}


# ── Configuration ────────────────────────────────────────────────────────────

# Validation-only concordances. The FABIO pipeline keeps ITS shared concordances
# in inst/value_added/ (VA_CONCORDANCE_DIR), but the BioSAM<->FABIO concordances
# are validation-specific and ship inside this repo under input/concordances/.
INPUT_DIR      <- VALIDATION_CONC_DIR
ITEM_CONC_PATH <- file.path(INPUT_DIR, "concordance_items_biosam_fabio.csv")
AREA_CONC_PATH <- file.path(INPUT_DIR, "concordance_areas_biosam_fabio.csv")

# FABIOv2 VA outputs (already USD). FOUR variants: the two pure bases written
# by 14_1 (GLORIA / EXIOBASE) and the two synthesis bases written by 14_4
# (COMBINED-GLORIA / COMBINED-EXIOBASE). They live in FABIO's output/value_added/
# (= VA_VALUE_ADDED_OUTPUT_DIR from the config; filenames unchanged).
# EXIOBASE may be absent on a given machine — those sources then drop out of
# the figure rather than failing (see the RUN section).
VA_OUTPUT_DIR  <- VA_VALUE_ADDED_OUTPUT_DIR
GLORIA_VA_PATH            <- function(suffix)
  file.path(VA_OUTPUT_DIR, sprintf("FABIOv2_GLORIA_value_added_ISIC-%s.rds",            suffix))
COMBINED_GLORIA_VA_PATH   <- function(suffix)
  file.path(VA_OUTPUT_DIR, sprintf("FABIOv2_COMBINED_GLORIA_value_added_ISIC-%s.rds",   suffix))
EXIOBASE_VA_PATH          <- function(suffix)
  file.path(VA_OUTPUT_DIR, sprintf("FABIOv2_EXIOBASE_value_added_ISIC-%s.rds",          suffix))
COMBINED_EXIOBASE_VA_PATH <- function(suffix)
  file.path(VA_OUTPUT_DIR, sprintf("FABIOv2_COMBINED_EXIOBASE_value_added_ISIC-%s.rds", suffix))

# Raw JRC BioSAMs input (validation reference data, not pipeline-produced).
# Ships inside this repo under input/.
BIOSAM_DIR   <- validation_path("input")
BIOSAM_FILES <- file.path(BIOSAM_DIR, c(
  "Dataset_JRC_-_BioSAMs_for_the_EU_Member_States_-_2010.csv",
  "Dataset_JRC_-_BioSAMs_for_the_EU_Member_States_-_2015.csv"
))

# EUR -> USD: Germany's SLC row from the FAOSTAT exchange-rate file. FABIO
# downloads the NORMALIZED bulk into input/fao/ (long layout: Element Code /
# Area Code / Year / Value); VA_EXCHANGE_RATE_CSV (from the config) points at it,
# and faostat_rate_vector() reads it. Area code + element come from the config so
# this validator and the pipeline agree on the single currency source of truth.
EXCHANGE_RATE_PATH <- VA_EXCHANGE_RATE_CSV
GERMANY_AREA_CODE  <- VA_GERMANY_AREA_CODE
EXCHANGE_ELEMENT   <- VA_FX_ELEMENT_CODE

# Output locations: this validator's figures/CSVs live in the validation repo's
# own output/ tree (VALIDATION_OUTPUT_DIR). The eurostat benchmark CSV written
# below is read back by 01 — both sides resolve it from VALIDATION_OUTPUT_DIR.
OUT_DIR         <- file.path(VALIDATION_OUTPUT_DIR, "biosam_validation")
OUT_DIR_COUNTRY <- file.path(OUT_DIR, "by_country")
dir.create(OUT_DIR_COUNTRY, recursive = TRUE, showWarnings = FALSE)

# BioSAM CSV column names + retained VA accounts (matched on CODES).
BIOSAM_VALUE_COL <- "Value (MILLION EUROS)"
BIOSAM_AREA_COL  <- "Country (ISO2)"
BIOSAM_ITEM_COL  <- "Spending Agent (Code)"
BIOSAM_VA_COL    <- "Receiving Agent (Code)"
BIOSAM_YEAR_COL  <- "Year"

# Retained BioSAM VA accounts -> strand.  TLS-C (a tax on products, not VA) is
# excluded by omission.  Each account is carried through as its own strand so the
# per-strand figures can be built; the TOTAL figure sums them at the end.
BIOSAM_ACCOUNT_TO_STRAND <- c(CAPITAL = "capital", LABOUR = "wages", `TLS-A` = "tls")
VA_ACCOUNTS <- names(BIOSAM_ACCOUNT_TO_STRAND)   # CAPITAL, LABOUR, TLS-A

# The two validation years (== the years the BioSAMs cover).
YEARS <- c(2010L, 2015L)

# Known-erroneous BioSAM country-years, identified against the Eurostat National
# Accounts and dropped from the agreement statistics (the per-country figures
# still draw them, so the discrepancy stays visible).  Romania 2010: the raw
# BioSAM VA sub-components are clearly corrupt — net-negative agricultural capital
# and a taxes-less-subsidies figure off by roughly +20 bn USD against Eurostat.
BIOSAM_EXCLUDE <- data.table(iso3c = "ROU", year = 2010L)

# Measures plotted, one figure each.  All four (total + three strands) take the
# Eurostat A01+A03 reference line for the matching measure.
STRANDS  <- c("wages", "capital", "tls")
MEASURES <- c("total", STRANDS)

# Human labels (title / y-axis / subtitle) per measure.
MEASURE_TITLE <- c(total   = "value-added",
                   wages   = "wages",
                   capital = "capital",
                   tls     = "taxes less subsidies")
MEASURE_AXIS  <- c(total   = "Value-added (current US$)",
                   wages   = "Wages — compensation of employees (current US$)",
                   capital = "Capital — operating surplus, mixed income & CFC (current US$)",
                   tls     = "Taxes less subsidies on production (current US$)")

# ── Eurostat benchmark (A01 + A03) config ────────────────────────────────────
# Reads the staged nama_10_a64 CSV (same loader logic as script 14_4's
# load_eurostat_nama_activity).  A01 (crop & animal production) + A03
# (fishing & aquaculture); A02 (forestry) is excluded simply by not being in the
# sum, so no separate forestry deduction is needed.  capital comes from the GVA
# identity (NAMA has no standalone B2A3G code); use D1 / D29X39 (NOT the
# similarly named D11 / D21X31 — the code versions differ).
EU_NAMA_TABLE <- "nama_10_a64"
EU_NAMA_UNIT  <- "CP_MEUR"
EU_NACE_BENCH <- c("A01", "A03")
EU_TOTAL <- "B1G"; EU_LAB <- "D1"; EU_TLS <- "D29X39"
# Whole nama_10_a64 table staged as CSV by FABIO's R/00_9_prep_value_added.R
# (stage_eurostat_nama) into VA_VALUE_ADDED_INPUT_DIR; the benchmark loader below
# READS + filters it — no live eurostat fetch.  Same file script 14_4's
# load_eurostat_nama_activity() reads, so validator and pipeline share one source.
EUROSTAT_NAMA_PATH <- file.path(VA_VALUE_ADDED_INPUT_DIR, "eurostat_nama_10_a64.csv")

# Eurostat ISO2 geo -> ISO3 (matches the base's iso3c); EL/GR=Greece, UK/GB=UK.
EU_ISO2_TO_ISO3 <- c(
  AT="AUT", BE="BEL", BG="BGR", HR="HRV", CY="CYP", CZ="CZE", DK="DNK",
  EE="EST", FI="FIN", FR="FRA", DE="DEU", EL="GRC", GR="GRC", HU="HUN",
  IE="IRL", IT="ITA", LV="LVA", LT="LTU", LU="LUX", MT="MLT", NL="NLD",
  PL="POL", PT="PRT", RO="ROU", SK="SVK", SI="SVN", ES="ESP", SE="SWE",
  UK="GBR", GB="GBR", NO="NOR", IS="ISL", CH="CHE", LI="LIE", TR="TUR")

# Source ordering / display labels (x-axis order within each country panel).
# Base-grouped to match script 01: each base's pure output then its COMBINED
# (FSDN-overlaid) version.  EXIOBASE entries that produced no rows are dropped
# from this vector after the data are assembled (see RUN), so a machine without
# the EXIOBASE pipeline still draws the BioSAMs / GLORIA / COMBINED-GLORIA bars.
SOURCE_LEVELS <- c("BioSAMs",
                   "GLORIA-FABIOv2 (agg.)",
                   "COMBINED-GLORIA-FABIOv2 (agg.)",
                   "EXIOBASE-FABIOv2 (agg.)",
                   "COMBINED-EXIOBASE-FABIOv2 (agg.)")


# ── Concordance loading ──────────────────────────────────────────────────────

# load_item_conc(): now in va_helpers.R

# load_area_conc(): now in va_helpers.R

#' Per-BioSAM-item ISIC assignment for the RAW BioSAM bars: the ISIC level held
#' by the MAJORITY of the item's mapped FABIO items (ties -> A), where a FABIO
#' item tagged at both levels counts only toward A.  Also returns the canonical
#' BioSAM label per code.
build_biosam_item_isic <- function(path) {
  ic <- fread(path)
  ic <- ic[
    !is.na(BioSAM_item_code) & BioSAM_item_code != "" &
      !is.na(FABIO_item_code) & ISIC %in% c("A", "C"),
    .(biosam_item_code = trimws(as.character(BioSAM_item_code)),
      biosam_item      = trimws(as.character(BioSAM_item)),
      fabio_item_code  = as.integer(FABIO_item_code),
      isic             = toupper(trimws(as.character(ISIC))))
  ]
  # FABIO items tagged at both levels count only toward A: drop their C rows
  # before the vote.
  both <- ic[, .(n_isic = uniqueN(isic)), by = fabio_item_code][n_isic == 2L,
                                                                fabio_item_code]
  ic <- ic[!(isic == "C" & fabio_item_code %in% both)]
  counts <- ic[, .(n = .N), by = .(biosam_item_code, biosam_item, isic)]
  counts <- dcast(counts, biosam_item_code + biosam_item ~ isic,
                  value.var = "n", fill = 0)
  if (!"A" %in% names(counts)) counts[, A := 0]
  if (!"C" %in% names(counts)) counts[, C := 0]
  counts[, isic := fifelse(A >= C, "A", "C")]      # ties -> A
  counts[, .(biosam_item_code, biosam_item, isic)]
}


# ── Raw BioSAMs loading + EUR -> USD ─────────────────────────────────────────

#' Load one JRC BioSAM CSV to long VA rows (year, area, item, strand,
#' va_value[EUR]), filtered to the three retained VA accounts and tagged with
#' the strand each account maps to (LABOUR->wages, CAPITAL->capital, TLS-A->tls).
#' Source column is MILLION EUROS; multiplied by 1e6 to EUR here.
load_biosam_va_single <- function(path) {
  df <- fread(path)
  req <- c(BIOSAM_YEAR_COL, BIOSAM_AREA_COL, BIOSAM_ITEM_COL,
           BIOSAM_VA_COL, BIOSAM_VALUE_COL)
  missing <- setdiff(req, names(df))
  if (length(missing) > 0L)
    stop("BioSAM CSV ", path, " is missing column(s): ",
         paste(missing, collapse = ", "))
  acct <- trimws(as.character(df[[BIOSAM_VA_COL]]))
  va   <- df[acct %in% VA_ACCOUNTS]
  acct <- trimws(as.character(va[[BIOSAM_VA_COL]]))
  data.table(
    year             = as.integer(va[[BIOSAM_YEAR_COL]]),
    biosam_area_code = trimws(as.character(va[[BIOSAM_AREA_COL]])),
    biosam_item_code = trimws(as.character(va[[BIOSAM_ITEM_COL]])),
    strand           = unname(BIOSAM_ACCOUNT_TO_STRAND[acct]),
    va_value_eur     = as.numeric(va[[BIOSAM_VALUE_COL]]) * 1e6
  )
}

load_biosam_va <- function(paths) {
  rbindlist(lapply(paths, function(p) {
    message("  Reading ", basename(p), " ...")
    load_biosam_va_single(p)
  }))
}

# load_eur_per_usd(): now faostat_rate_vector() in va_helpers.R


# ── Build the per-source long tables (all at BioSAM categories) ──────────────

#' GLORIA / COMBINED: aggregate FABIO-item VA up to BioSAM categories per ISIC
#' level AND per strand.  `va_path_fun(suffix)` returns the RDS path for ISIC
#' level `suffix`.  The component-split scripts 14_1 / 14_4 write the three strand
#' columns; their sum is the total value-added (rebuilt downstream).
build_fabio_source <- function(source_label, va_path_fun,
                               item_conc_a, item_conc_c) {
  strand_cols <- c(wages   = "value_added_wages [USD]",
                   capital = "value_added_capital [USD]",
                   tls     = "value_added_tls [USD]")
  one_level <- function(suffix, conc) {
    path <- va_path_fun(suffix)
    if (!file.exists(path)) {
      message("  NOTE: ", path, " not found — skipping ", source_label,
              " ISIC-", suffix, ".")
      return(NULL)
    }
    raw  <- as.data.table(readRDS(path))
    miss <- setdiff(unname(strand_cols), names(raw))
    if (length(miss))
      stop("VA file ", path, " is missing strand column(s): ",
           paste(miss, collapse = ", "), ".\n  The figures need the ",
           "COMPONENT-SPLIT output of scripts 14_1 / 14_4 (value_added_wages|",
           "capital|tls [USD]).  Re-run those to generate it.")
    va <- raw[year %in% YEARS,
              .(iso3c           = as.character(iso3c),
                year            = as.integer(year),
                fabio_item_code = as.integer(fabio_item_code),
                wages           = `value_added_wages [USD]`,
                capital         = `value_added_capital [USD]`,
                tls             = `value_added_tls [USD]`)]
    va <- melt(va, id.vars = c("iso3c", "year", "fabio_item_code"),
               measure.vars = names(strand_cols),
               variable.name = "strand", value.name = "value_usd")
    va[, strand := as.character(strand)]
    # FABIO items with no BioSAM mapping at this level are dropped by the join
    # (outside the BioSAM agricultural scope).
    out <- conc[va, on = "fabio_item_code", nomatch = NULL,
                allow.cartesian = TRUE]
    out[, .(value_usd = sum(value_usd, na.rm = TRUE)),
        by = .(iso3c, year, biosam_item_code, biosam_item, strand)][
          , isic := suffix][]
  }
  res <- rbindlist(list(one_level("A", item_conc_a),
                        one_level("C", item_conc_c)),
                   use.names = TRUE, fill = TRUE)
  if (nrow(res)) res[, source := source_label]
  res
}

#' Raw BioSAMs: sum within each strand per (area, item, year, strand), convert
#' EUR -> USD, map area -> iso3c, restrict to mapped (agricultural) categories,
#' assign ISIC via the majority rule, attach the BioSAM label.
build_biosam_source <- function(va_long, area_conc, item_isic, eur_per_usd) {
  agg <- va_long[, .(va_eur = sum(va_value_eur, na.rm = TRUE)),
                 by = .(year, biosam_area_code, biosam_item_code, strand)]
  agg[, rate := eur_per_usd[as.character(year)]]
  miss_rate <- agg[!is.finite(rate), sort(unique(year))]
  if (length(miss_rate))
    stop("No EUR/USD rate for BioSAM year(s): ",
         paste(miss_rate, collapse = ", "))
  agg[, value_usd := va_eur / rate]
  
  # area (2-letter) -> iso3c; unmapped aggregate areas (e.g. EU27-2020) drop out.
  agg <- area_conc[agg, on = "biosam_area_code", nomatch = NULL]
  # restrict to mapped categories + attach ISIC level and label.
  agg <- item_isic[agg, on = "biosam_item_code", nomatch = NULL]
  
  agg[, .(value_usd = sum(value_usd, na.rm = TRUE)),
      by = .(iso3c, year, biosam_item_code, biosam_item, isic, strand)][
        , source := "BioSAMs"][]
}


# ── Reference: Eurostat NAMA A01+A03, per measure (all four figures) ─────────
#
# Reads the staged nama_10_a64 CSV (mirrors script 14_4's
# load_eurostat_nama_activity, generalized to a SET of NACE divisions summed
# together).  Returns a tidy long table keyed (iso3c, year, strand) with
# bench_usd in USD, where
#   wages   <- D1
#   tls     <- D29X39
#   capital <- B1G - D1 - D29X39      (GVA identity; NAMA has no B2A3G code)
#   total   <- B1G
# summed over EU_NACE_BENCH (A01 + A03).  To keep the capital identity valid,
# only (iso3c, year, nace) cells carrying ALL THREE of {B1G, D1, D29X39} are
# kept before summing across divisions; a division missing a component (e.g.
# A03 for a landlocked country) drops out, so the benchmark degrades to whatever
# complete divisions remain (typically A01).  EUR millions -> USD via the same
# Germany SLC rate the BioSAMs use.  Returns NULL (with a warning) if the staged
# CSV is missing or unreadable, so the figures still draw, just without the
# reference line.
load_eurostat_benchmark <- function(eur_per_usd, nace = EU_NACE_BENCH) {
  if (!file.exists(EUROSTAT_NAMA_PATH)) {
    warning("Eurostat NAMA not staged (", EUROSTAT_NAMA_PATH, ") — strand ",
            "figures will have no reference line.  Run FABIO's ",
            "R/00_9_prep_value_added.R to stage it.")
    return(NULL)
  }
  message(sprintf("\nReading staged Eurostat benchmark (%s, nace %s) ...",
                  EU_NAMA_TABLE, paste(nace, collapse = "+")))
  
  nama <- tryCatch(as.data.table(fread(EUROSTAT_NAMA_PATH)),
                   error = function(e) {
                     warning("Reading staged Eurostat NAMA failed (", EUROSTAT_NAMA_PATH, "): ",
                             conditionMessage(e)); NULL })
  if (is.null(nama)) {
    message("  No Eurostat data read — skipping the strand reference line.")
    return(NULL)
  }
  
  if (!"TIME_PERIOD" %in% names(nama) && "time" %in% names(nama))
    setnames(nama, "time", "TIME_PERIOD")
  nama <- nama[na_item %in% c(EU_TOTAL, EU_LAB, EU_TLS) &
                 nace_r2 %in% nace & unit == EU_NAMA_UNIT & !is.na(values)]
  nama[, `:=`(iso3c = unname(EU_ISO2_TO_ISO3[toupper(trimws(geo))]),
              year  = as.integer(TIME_PERIOD))]
  nama <- nama[!is.na(iso3c) & year %in% YEARS]
  if (nrow(nama) == 0L) {
    message("  No usable Eurostat rows for the validation years/countries.")
    return(NULL)
  }
  
  # Keep only (iso3c, year, nace) cells with all three na_items so the capital
  # identity B1G - D1 - D29X39 is well defined, THEN sum across divisions.
  nama[, n_items := uniqueN(na_item), by = .(iso3c, year, nace_r2)]
  nama <- nama[n_items == 3L]
  if (nrow(nama) == 0L) {
    message("  No Eurostat division carried all of {B1G, D1, D29X39}.")
    return(NULL)
  }
  
  a <- nama[, .(meur = sum(values, na.rm = TRUE)), by = .(iso3c, year, na_item)]
  a[, rate := eur_per_usd[as.character(year)]]
  a[, usd := fifelse(is.finite(rate) & rate > 0, meur * 1e6 / rate, NA_real_)]
  w <- dcast(a, iso3c + year ~ na_item, value.var = "usd")
  g <- function(col) if (col %in% names(w)) w[[col]] else rep(NA_real_, nrow(w))
  tot <- g(EU_TOTAL); lab <- g(EU_LAB); tx <- g(EU_TLS)
  out <- data.table(iso3c = w$iso3c, year = w$year,
                    wages = lab, capital = tot - lab - tx,
                    tls   = tx,  total   = tot)
  long <- melt(out, id.vars = c("iso3c", "year"),
               measure.vars = c("wages", "capital", "tls", "total"),
               variable.name = "strand", value.name = "bench_usd")
  long[, strand := as.character(strand)]
  long[is.finite(bench_usd)]
}


# ── Agreement statistics ─────────────────────────────────────────────────────
#
# Two metric tables quantify how closely each source reproduces a reference,
# scored across the BioSAM-covered countries x the two validation years.  Both
# carry one row per (measure, source), where the measures are the TOTAL
# value-added and its three strands (wages, capital, tls):
#
#   metrics_vs_nationalaccounts.csv — all five sources (BioSAMs included) against
#       the Eurostat A01+A03 national-accounts line.  ISIC-A scope only: the
#       A01+A03 reference is primary agriculture, with no counterpart to the
#       ISIC-C processing sub-stack, so each source is summed over category
#       within ISIC-A before the comparison.
#   metrics_biosam_vs_fabio.csv     — the four FABIOv2 variants against the raw
#       BioSAMs reference, at the full ISIC A+C scope (summed over isic and
#       category).
#   metrics_biosam_vs_fabio_by_item.csv — the BioSAMs comparison resolved within
#       each BioSAM category (summed over isic only), so item-level agreement can
#       be read directly instead of only through the national aggregate.
#
# n counts the country-years with finite values on both sides and a non-zero
# reference.  The metric set depends on the measure:
#   total / wages / capital — strictly-positive measures, computed on the
#   country-years where BOTH source and reference are > 0 (NA if fewer than 3):
#       med_ratio   median(source / reference)
#       bias_dex    median(log10(source / reference))       (dex = log10 units)
#       RMSLE_dex   sqrt(mean(log10(source / reference)^2))
#       within_2x   share of pairs with 0.5 <= source/reference <= 2
#   tls — net-negative (subsidies exceed taxes), so ratios/logs on the signed
#   values are undefined; scored sign-robustly on the magnitudes instead:
#       sign_agree     share of country-years with sign(source) == sign(reference)
#       med_ratio_mag  median(|source| / |reference|) on same-sign, non-zero pairs
#       RMSLE_dex      sqrt(mean(log10(|source|/|reference|)^2)) on those pairs
# The columns not applicable to a measure are left NA — the ratio columns
# (med_ratio, bias_dex, within_2x) for tls, the sign columns (sign_agree,
# med_ratio_mag) for the positive measures.  Country-years flagged as erroneous
# in the raw BioSAMs (BIOSAM_EXCLUDE) are dropped from both tables.

#' Collapse a long source table to one value per (iso3c, year, source[, category],
#' strand) within an ISIC scope, and append a derived `total` strand summing the
#' strands present in each cell.
#'   isic_keep   = "A"  -> ISIC-A (primary agriculture) only (national-accounts cmp)
#'   isic_keep   = NULL -> full ISIC A+C scope               (BioSAMs comparison)
#'   by_category = TRUE -> retain the BioSAM category as a grouping key (per-item)
#' A strand absent from a cell counts as zero in that cell's total; at the
#' aggregate scopes every cell carries all three, so the total is their full sum.
aggregate_measures <- function(dat, isic_keep = NULL, by_category = FALSE) {
  d   <- if (is.null(isic_keep)) dat else dat[isic == isic_keep]
  lhs <- c("iso3c", "year", "source", if (by_category) "category")
  s   <- d[is.finite(value_usd),
           .(value_usd = sum(value_usd, na.rm = TRUE)),
           by = c(lhs, "strand")]
  w   <- dcast(s, as.formula(paste(paste(lhs, collapse = " + "), "~ strand")),
               value.var = "value_usd")
  for (col in STRANDS) if (!col %in% names(w)) w[, (col) := NA_real_]
  w[, total := rowSums(.SD, na.rm = TRUE), .SDcols = STRANDS]
  long <- melt(w, id.vars = lhs, measure.vars = MEASURES,
               variable.name = "strand", value.name = "value_usd")
  long[, strand := as.character(strand)][is.finite(value_usd)]
}

#' One metric row for a single (measure, source).  `cmp` holds that pair's
#' matched country-years with columns `src` (source value) and `ref` (reference
#' value); n counts those with finite values on both sides and a non-zero
#' reference.  tls is scored sign-robustly, the other measures on positive pairs.
agreement_row <- function(cmp, measure, source_label) {
  ok  <- cmp[is.finite(src) & is.finite(ref) & ref != 0]
  out <- data.table(
    measure = measure, source = source_label, n = nrow(ok),
    med_ratio = NA_real_, bias_dex = NA_real_, RMSLE_dex = NA_real_,
    within_2x = NA_real_, sign_agree = NA_real_, med_ratio_mag = NA_real_)
  if (measure == "tls") {
    if (nrow(ok))
      out[, sign_agree := mean(sign(ok$src) == sign(ok$ref))]
    sm <- ok[src != 0 & sign(src) == sign(ref)]
    if (nrow(sm)) {
      r <- abs(sm$src) / abs(sm$ref)
      out[, `:=`(med_ratio_mag = median(r),
                 RMSLE_dex     = sqrt(mean(log10(r)^2)))]
    }
  } else {
    pos <- ok[src > 0 & ref > 0]
    if (nrow(pos) >= 3L) {
      r <- pos$src / pos$ref
      out[, `:=`(med_ratio = median(r),
                 bias_dex  = median(log10(r)),
                 RMSLE_dex = sqrt(mean(log10(r)^2)),
                 within_2x = mean(r >= 0.5 & r <= 2))]
    }
  }
  out[]
}

#' Score every (measure, source) of `src_long` (iso3c, year, source, strand,
#' value_usd) against `ref_long` (iso3c, year, strand, ref).  Returns the metric
#' table in MEASURES x `sources` order, one row per (measure, source); with
#' by_category = TRUE the comparison is keyed on the BioSAM category too, giving
#' a leading `category` column and one row per (category, measure, source).
score_against <- function(src_long, ref_long, sources, by_category = FALSE) {
  keys <- c("iso3c", "year", "strand", if (by_category) "category")
  cmp  <- merge(src_long, ref_long, by = keys, all = FALSE)
  setnames(cmp, "value_usd", "src")
  groups <- if (by_category) sort(unique(cmp$category)) else NA_character_
  res <- rbindlist(lapply(groups, function(g) {
    cg  <- if (by_category) cmp[category == g] else cmp
    out <- rbindlist(lapply(MEASURES, function(m)
      rbindlist(lapply(sources, function(s)
        agreement_row(cg[strand == m & source == s], m, s)))))
    if (by_category) out[, category := g]
    out
  }))
  if (by_category) setcolorder(res, c("category", setdiff(names(res), "category")))
  res[]
}


# ── Colour palette ───────────────────────────────────────────────────────────
#
# One distinct, STABLE colour per BioSAM category, shared across every country
# figure and all three source bars so a given category is always the same
# colour.  A 30-colour base palette, interpolated to the number of categories and
# assigned in descending-total order (largest categories get the most separated
# hues).  Colour encodes category only — ISIC is shown by the black frame (below),
# not by colour — so a category that contributes at BOTH ISIC levels stays one
# colour across its A and C segments.
base_pal <- c(
  "#1f77b4","#ff7f0e","#2ca02c","#d62728","#9467bd",
  "#8c564b","#e377c2","#bcbd22","#17becf","#aec7e8",
  "#ffbb78","#98df8a","#ff9896","#c5b0d5","#c49c94",
  "#f7b6d2","#dbdb8d","#9edae5","#393b79","#637939",
  "#8c6d31","#843c39","#7b4173","#3182bd","#e6550d",
  "#31a354","#756bb1","#fd8d3c","#74c476","#9e9ac8"
)

# Linewidth of the black ISIC-C (processing) frame drawn on the top segments of
# every bar.  Colour is mapped to ISIC (A -> NA = no outline, C -> black), so
# this width only affects the visible ISIC-C frames.  Shared by both the
# per-measure figures and the combined panel so the framing is uniform.
ISIC_C_OUTLINE_LW <- 0.6

# ── Per-country figure ───────────────────────────────────────────────────────
#
# One SVG per BioSAM-covered country PER MEASURE (total + the three strands).
# Within a figure:
#   facet = year   (2010 | 2015, side by side)
#   x     = the sources (BioSAMs / GLORIA-agg / COMBINED-GLORIA-agg /
#                         EXIOBASE-agg / COMBINED-EXIOBASE-agg), labelled
#   y     = the measure (USD), stacked by BioSAM category (colour = category)
#   stack order: all ISIC-A segments at the BOTTOM, all ISIC-C segments at the
#                TOP, the latter outlined in black.  Flushing the ISIC-A
#                sub-stack to the bottom is what lets the (primary-agriculture /
#                ISIC-A) reference line be read directly against the bar.
#   reference: one horizontal line per year-panel, supplied by the caller —
#                Eurostat NAMA A01+A03 for the matching measure (total or strand).
#
# `cat_colors`   : named colour vector keyed by category (global, stable).
# `stack_levels` : ordered "<isic>|<category>" keys (A combos first, then C),
#                  used as the stacking group so A is at the bottom regardless
#                  of fill.
# `bench_specs`  : list of hline specs (see hline_spec()); each draws one
#                  horizontal reference line.  Empty list = no reference line.
# `ref_note`     : one-clause description of the reference line(s) for the
#                  subtitle (already includes its leading separator/space).

# hline_spec(): now in va_helpers.R

make_country_chart <- function(iso, dat_iso, measure, bench_specs,
                               cat_colors, stack_levels, ref_note = "") {
  if (!nrow(dat_iso)) {
    message("[", iso, "/", measure, "] no rows; skipping.")
    return(invisible(NULL))
  }
  
  dat <- dat_iso %>%
    mutate(
      source    = factor(source, levels = SOURCE_LEVELS),
      isic      = factor(isic,   levels = c("A", "C")),
      category  = factor(category, levels = names(cat_colors)),
      year      = factor(year,   levels = YEARS),
      stack_grp = factor(paste(isic, category, sep = "|"), levels = stack_levels)
    )
  
  # Strands (esp. TLS) can go negative (net subsidies); when so, allow the
  # y-axis to extend below zero and draw a thin zero baseline.  An all-positive
  # measure keeps a zero floor.
  bench_vals <- unlist(lapply(bench_specs, function(s) s$data$yintercept))
  has_neg    <- any(c(dat$value_usd, bench_vals) < 0, na.rm = TRUE)
  y_expand   <- if (has_neg) expansion(mult = c(0.04, 0.04))
  else          expansion(mult = c(0, 0.04))
  
  p <- ggplot(dat, aes(x = source, y = value_usd,
                       fill = category, colour = isic, group = stack_grp)) +
    # Single stacked layer: positions are computed over all segments together,
    # so the per-segment black frame (ISIC-C) lands in the right place.  A
    # segments get colour = NA (no frame); reverse = TRUE puts the first
    # stack level (an ISIC-A category) at the bottom.
    geom_col(width = 0.8, linewidth = ISIC_C_OUTLINE_LW,
             position = position_stack(reverse = TRUE))
  
  if (has_neg)
    p <- p + geom_hline(yintercept = 0, linewidth = 0.3, colour = "grey70")
  
  # Reference line(s), one horizontal line per year-panel (geom_hline keys off
  # the `year` column so each lands in the matching facet and spans all three
  # source bars).
  for (s in bench_specs) {
    p <- p + geom_hline(data = s$data, aes(yintercept = yintercept),
                        inherit.aes = FALSE, linetype = s$linetype,
                        linewidth = s$linewidth, colour = s$colour)
  }
  
  measure_lead <- paste0(toupper(substring(MEASURE_TITLE[[measure]], 1, 1)),
                         substring(MEASURE_TITLE[[measure]], 2))
  p <- p +
    facet_wrap(~ year, nrow = 1) +
    scale_x_discrete(drop = FALSE) +
    scale_fill_manual(values = cat_colors, name = "BioSAM category",
                      drop = TRUE) +
    # ISIC frame: A = no outline, C = black.  Not shown as its own legend
    # (the framing is described in the subtitle).
    scale_colour_manual(values = c(A = NA, C = "black"), guide = "none",
                        na.value = NA) +
    scale_y_continuous(
      labels = label_number(scale_cut = cut_short_scale()),
      expand = y_expand
    ) +
    labs(
      title    = sprintf("BioSAMs vs FABIOv2 %s — %s",
                         MEASURE_TITLE[[measure]], iso),
      subtitle = paste0(
        measure_lead, " (USD) for the raw JRC BioSAMs and for the GLORIA / ",
        "COMBINED-GLORIA / EXIOBASE / COMBINED-EXIOBASE FABIOv2 variants ",
        "aggregated to BioSAM categories. Bars ",
        "stacked by category; ISIC-C (processing) segments are grouped on top ",
        "and outlined in black, ISIC-A (primary) below.", ref_note,
        " BioSAMs converted EUR->USD via Germany's FAOSTAT SLC rate."),
      x = NULL,
      y = MEASURE_AXIS[[measure]]
    ) +
    theme_minimal(base_size = 10) +
    theme(
      axis.text.x        = element_text(angle = 30, vjust = 1, hjust = 1, size = 8),
      panel.grid.major.x = element_blank(),
      panel.spacing      = unit(1, "lines"),
      strip.text         = element_text(face = "bold"),
      legend.position    = "bottom",
      legend.key.size    = unit(0.35, "cm"),
      legend.text        = element_text(size = 7),
      plot.title         = element_text(face = "bold")
    ) +
    guides(fill = guide_legend(ncol = 4, byrow = TRUE))
  
  n_legend_rows <- ceiling(length(cat_colors) / 4)
  svg_width     <- 14          # up to five source bars per year panel
  svg_height    <- 7 + 0.25 * n_legend_rows
  out_name      <- if (measure == "total") sprintf("%s.svg", iso)
  else                     sprintf("%s_%s.svg", iso, measure)
  out_file      <- file.path(OUT_DIR_COUNTRY, out_name)
  
  ggsave(out_file, p, width = svg_width, height = svg_height,
         limitsize = FALSE, device = "svg")
  message(sprintf("[%s/%s] wrote %s  (%.1f x %.1f in)",
                  iso, measure, out_file, svg_width, svg_height))
  invisible(out_file)
}


# ── Combined four-measure panel for a single country-year ────────────────────
#
# One SVG holding all FOUR measures (TOTAL value-added + the wages / capital /
# tls strands) for a SINGLE country and a SINGLE year, laid out as a 2x2 grid
# (facet = measure).  y-scales are FREE per panel because the four measures
# differ greatly in magnitude and tls can be net-negative.  Per-bar layout is
# identical to make_country_chart: x = sources, bars stacked by BioSAM category,
# ISIC-C (processing) framed in black on top of ISIC-A (primary).  Each
# measure-panel carries its own Eurostat NAMA A01+A03 reference line for the
# matching measure.  Arguments mirror make_country_chart; `dat_total` / `dat_all`
# / `eu_bench` are the global tables assembled in the RUN section.
make_combined_panel <- function(iso, year, dat_total, dat_all, eu_bench,
                                cat_colors, stack_levels) {
  yr <- as.integer(year)
  
  # Pull the four measures for this country-year and tag each with its measure:
  #   total  <- dat_total (already the per-(source,isic,category) strand sum)
  #   strands<- dat_all rows for wages / capital / tls
  total_dt  <- as.data.table(dat_total)[iso3c == iso & year == yr]
  if (nrow(total_dt))  total_dt[,  measure := "total"]
  strand_dt <- as.data.table(dat_all)[iso3c == iso & year == yr &
                                        strand %in% STRANDS]
  if (nrow(strand_dt)) strand_dt[, measure := strand]
  
  keep <- c("iso3c", "year", "source", "isic", "biosam_item_code",
            "category", "measure", "value_usd")
  dat <- rbindlist(list(
    if (nrow(total_dt))  total_dt[,  ..keep],
    if (nrow(strand_dt)) strand_dt[, ..keep]
  ), use.names = TRUE, fill = TRUE)
  
  if (!nrow(dat)) {
    message("[", iso, "/", yr, "/panel] no rows; skipping.")
    return(invisible(NULL))
  }
  
  # Facet strips show the human measure labels, in canonical measure order.
  meas_labs <- unname(MEASURE_TITLE[MEASURES])
  dat <- as_tibble(dat) %>%
    mutate(
      source    = factor(source, levels = SOURCE_LEVELS),
      isic      = factor(isic,   levels = c("A", "C")),
      category  = factor(category, levels = names(cat_colors)),
      measure   = factor(measure, levels = MEASURES, labels = meas_labs),
      stack_grp = factor(paste(isic, category, sep = "|"), levels = stack_levels)
    )
  
  # Per-measure Eurostat reference line for this country-year, tagged with the
  # same measure factor so each line lands in its own panel.
  bench_dt <- NULL
  if (!is.null(eu_bench)) {
    bench_dt <- as.data.table(eu_bench)[iso3c == iso & year == yr &
                                          strand %in% MEASURES &
                                          is.finite(bench_usd)]
    if (nrow(bench_dt))
      bench_dt[, measure := factor(strand, levels = MEASURES, labels = meas_labs)]
    else bench_dt <- NULL
  }
  
  has_neg  <- any(c(dat$value_usd,
                    if (!is.null(bench_dt)) bench_dt$bench_usd) < 0, na.rm = TRUE)
  y_expand <- if (has_neg) expansion(mult = c(0.04, 0.04))
  else          expansion(mult = c(0, 0.04))
  
  p <- ggplot(dat, aes(x = source, y = value_usd,
                       fill = category, colour = isic, group = stack_grp)) +
    geom_col(width = 0.8, linewidth = ISIC_C_OUTLINE_LW,
             position = position_stack(reverse = TRUE))
  
  if (has_neg)
    p <- p + geom_hline(yintercept = 0, linewidth = 0.3, colour = "grey70")
  
  if (!is.null(bench_dt))
    p <- p + geom_hline(data = bench_dt, aes(yintercept = bench_usd),
                        inherit.aes = FALSE, linetype = "solid",
                        linewidth = 0.6, colour = "black")
  
  p <- p +
    facet_wrap(~ measure, nrow = 2, scales = "free_y") +
    scale_x_discrete(drop = FALSE) +
    scale_fill_manual(values = cat_colors, name = "BioSAM category", drop = TRUE) +
    scale_colour_manual(values = c(A = NA, C = "black"), guide = "none",
                        na.value = NA) +
    scale_y_continuous(
      labels = label_number(scale_cut = cut_short_scale()),
      expand = y_expand
    ) +
    labs(
      title    = sprintf("BioSAMs vs FABIOv2 — %s, %d", iso, yr),
      subtitle = paste0(
        "Total value-added and its wages / capital / taxes-less-subsidies ",
        "strands (USD) for the raw JRC BioSAMs and the GLORIA / COMBINED-GLORIA / ",
        "EXIOBASE / COMBINED-EXIOBASE FABIOv2 variants aggregated to BioSAM ",
        "categories. Bars stacked by category; ISIC-C (processing) framed in ",
        "black on top, ISIC-A (primary) below. Black line = Eurostat NAMA ",
        "A01+A03 for each measure (primary-agriculture / ISIC-A reference, read ",
        "against the lower sub-stack). Free y-scale per panel; BioSAMs converted ",
        "EUR->USD via Germany's FAOSTAT SLC rate."),
      x = NULL,
      y = "Value (current US$)"
    ) +
    theme_minimal(base_size = 10) +
    theme(
      axis.text.x        = element_text(angle = 30, vjust = 1, hjust = 1, size = 8),
      panel.grid.major.x = element_blank(),
      panel.spacing      = unit(1, "lines"),
      strip.text         = element_text(face = "bold"),
      legend.position    = "bottom",
      legend.key.size    = unit(0.35, "cm"),
      legend.text        = element_text(size = 7),
      plot.title         = element_text(face = "bold")
    ) +
    guides(fill = guide_legend(ncol = 4, byrow = TRUE))
  
  n_legend_rows <- ceiling(length(cat_colors) / 4)
  svg_width     <- 14
  svg_height    <- 10 + 0.25 * n_legend_rows   # 2 facet rows -> taller than the singles
  out_file      <- file.path(OUT_DIR_COUNTRY, sprintf("%s_%d_panel.svg", iso, yr))
  
  ggsave(out_file, p, width = svg_width, height = svg_height,
         limitsize = FALSE, device = "svg")
  message(sprintf("[%s/%d/panel] wrote %s  (%.1f x %.1f in)",
                  iso, yr, out_file, svg_width, svg_height))
  invisible(out_file)
}


# ============================================================================
# RUN
# ============================================================================

message("Loading concordances ...")
item_conc_a <- load_item_conc(ITEM_CONC_PATH, "A", "BioSAM_item_code", "BioSAM_item", out_code = "biosam_item_code", out_item = "biosam_item", keep_code_class_char = FALSE)
item_conc_c <- load_item_conc(ITEM_CONC_PATH, "C", "BioSAM_item_code", "BioSAM_item", out_code = "biosam_item_code", out_item = "biosam_item", keep_code_class_char = FALSE)
# ISIC-C keeps only FABIO items not also tagged at A (drop double-mapped items).
item_conc_c <- item_conc_c[!fabio_item_code %in% item_conc_a$fabio_item_code]
area_conc   <- load_area_conc(AREA_CONC_PATH, "BioSAM_area_code", "FABIO_iso3c", out_code = "biosam_area_code", out_fabio = "iso3c", fabio_as_integer = FALSE)
item_isic   <- build_biosam_item_isic(ITEM_CONC_PATH)
message(sprintf("  %d ISIC-A and %d ISIC-C item mappings; %d area mappings; %d categories.",
                nrow(item_conc_a), nrow(item_conc_c), nrow(area_conc),
                nrow(item_isic)))

message("Loading raw BioSAMs + exchange rate ...")
va_long     <- load_biosam_va(BIOSAM_FILES)
eur_per_usd <- faostat_rate_vector(EXCHANGE_RATE_PATH, GERMANY_AREA_CODE, element = EXCHANGE_ELEMENT)

message("Building per-source long tables ...")
src_biosam   <- build_biosam_source(va_long, area_conc, item_isic, eur_per_usd)
src_gloria            <- build_fabio_source("GLORIA-FABIOv2 (agg.)",
                                            GLORIA_VA_PATH,            item_conc_a, item_conc_c)
src_combined_gloria   <- build_fabio_source("COMBINED-GLORIA-FABIOv2 (agg.)",
                                            COMBINED_GLORIA_VA_PATH,   item_conc_a, item_conc_c)
src_exiobase          <- build_fabio_source("EXIOBASE-FABIOv2 (agg.)",
                                            EXIOBASE_VA_PATH,          item_conc_a, item_conc_c)
src_combined_exiobase <- build_fabio_source("COMBINED-EXIOBASE-FABIOv2 (agg.)",
                                            COMBINED_EXIOBASE_VA_PATH, item_conc_a, item_conc_c)

dat_all <- rbindlist(
  list(src_biosam, src_gloria, src_combined_gloria,
       src_exiobase, src_combined_exiobase),
  use.names = TRUE, fill = TRUE
)[, .(iso3c, year, source, isic, biosam_item_code, category = biosam_item,
      strand, value_usd)]
dat_all <- dat_all[is.finite(value_usd)]

# Restrict EVERYTHING to the countries the BioSAMs actually cover — GLORIA /
# COMBINED span the full FABIO country set, but a BioSAM validation figure (and
# its comparison table) is only meaningful where there is a BioSAMs column.
biosam_countries <- sort(unique(src_biosam$iso3c))
dat_all <- dat_all[iso3c %in% biosam_countries]

# Keep only the source bars that actually produced rows, in the canonical order.
# A missing EXIOBASE pipeline therefore yields the figure without those bars
# (no empty x slots), the graceful-degradation behaviour of script 01.
SOURCE_LEVELS <- intersect(SOURCE_LEVELS, unique(dat_all$source))
message(sprintf("BioSAMs cover %d country(ies).", length(biosam_countries)))

# TOTAL = sum of the three strands per (iso3c, year, source, isic, category).
# For every source the total equals wages + capital + tls by construction
# (BioSAMs: the three retained accounts; GLORIA/COMBINED: the derived total).
dat_total <- dat_all[, .(value_usd = sum(value_usd, na.rm = TRUE)),
                     by = .(iso3c, year, source, isic, biosam_item_code,
                            category)]

message("Loading Eurostat A01+A03 benchmark ...")
eu_bench <- load_eurostat_benchmark(eur_per_usd)        # may be NULL (skipped)

# Tidy comparison CSV behind the figures (BioSAM-covered countries only), now at
# strand granularity.  The Eurostat benchmark (if any) is written alongside.
comparison_path <- file.path(OUT_DIR, "biosam_vs_fabio_comparison.csv")
fwrite(dat_all, comparison_path)
message("Comparison table -> ", comparison_path)
if (!is.null(eu_bench)) {
  eu_bench_path <- file.path(OUT_DIR, "eurostat_A01_A03_benchmark.csv")
  fwrite(eu_bench[iso3c %in% biosam_countries], eu_bench_path)
  message("Eurostat benchmark -> ", eu_bench_path)
}

# Agreement statistics behind the figures: two metric tables scoring the sources
# across the BioSAM-covered countries x the two validation years, written next to
# the comparison CSV and echoed to the console.  NAs are written explicitly so a
# downstream reader sees which columns apply to which measure.  Known-erroneous
# BioSAM country-years (BIOSAM_EXCLUDE — Romania 2010) are dropped here, so the
# metrics reflect only the trustworthy comparison; the figures and comparison CSV
# keep them.
dat_metrics <- dat_all[!BIOSAM_EXCLUDE, on = .(iso3c, year)]

# Analysis 1 — all sources vs the Eurostat A01+A03 national-accounts line, at the
# ISIC-A scope that line measures (primary agriculture).  Needs the benchmark, so
# it degrades gracefully when the benchmark is unavailable.
if (!is.null(eu_bench)) {
  src_na     <- aggregate_measures(dat_metrics, isic_keep = "A")
  ref_na     <- eu_bench[iso3c %in% biosam_countries,
                         .(iso3c, year, strand, ref = bench_usd)]
  metrics_na <- score_against(src_na, ref_na, SOURCE_LEVELS)
  metrics_na_path <- file.path(OUT_DIR, "metrics_vs_nationalaccounts.csv")
  fwrite(metrics_na, metrics_na_path, na = "NA")
  message("National-accounts metrics -> ", metrics_na_path)
  message("\nAgreement vs Eurostat A01+A03 national accounts (ISIC-A):")
  print(metrics_na)
} else {
  message("Eurostat benchmark unavailable — skipping national-accounts metrics.")
}

# Analysis 2 — the four FABIOv2 variants vs the raw BioSAMs reference, at the full
# ISIC A+C scope.
src_bs     <- aggregate_measures(dat_metrics, isic_keep = NULL)
ref_bs     <- src_bs[source == "BioSAMs", .(iso3c, year, strand, ref = value_usd)]
fab_srcs   <- setdiff(SOURCE_LEVELS, "BioSAMs")
metrics_bs <- score_against(src_bs[source %in% fab_srcs], ref_bs, fab_srcs)
metrics_bs_path <- file.path(OUT_DIR, "metrics_biosam_vs_fabio.csv")
fwrite(metrics_bs, metrics_bs_path, na = "NA")
message("BioSAMs-reference metrics -> ", metrics_bs_path)
message("\nAgreement vs raw BioSAMs (full ISIC A+C):")
print(metrics_bs)

# Analysis 3 — Analysis 2 resolved per BioSAM category: each FABIOv2 variant vs the
# raw BioSAMs reference within every category, at the full ISIC A+C scope.
src_bs_item     <- aggregate_measures(dat_metrics, isic_keep = NULL,
                                      by_category = TRUE)
ref_bs_item     <- src_bs_item[source == "BioSAMs",
                               .(iso3c, year, category, strand, ref = value_usd)]
metrics_bs_item <- score_against(src_bs_item[source %in% fab_srcs],
                                 ref_bs_item, fab_srcs, by_category = TRUE)
metrics_bs_item_path <- file.path(OUT_DIR, "metrics_biosam_vs_fabio_by_item.csv")
fwrite(metrics_bs_item, metrics_bs_item_path, na = "NA")
message("Per-item BioSAMs-reference metrics -> ", metrics_bs_item_path)

# Global, stable category palette + stacking order (A combos first, then C, each
# by descending TOTAL) so colours and stack positions match across every country
# figure AND every measure (a category is one colour everywhere).  Computed on
# the totals.
cat_tot    <- dat_total[, .(tot = sum(abs(value_usd), na.rm = TRUE)),
                        by = category][order(-tot)]
cat_levels <- cat_tot$category
cat_colors <- setNames(colorRampPalette(base_pal)(length(cat_levels)), cat_levels)

combos <- unique(dat_total[, .(isic, category)])
combos[, tot := cat_tot$tot[match(category, cat_tot$category)]]
setorder(combos, isic, -tot)                      # "A" before "C"; within, tot desc
stack_levels <- paste(combos$isic, combos$category, sep = "|")

# Per-measure reference-line + subtitle-note builders.  Every measure (total and
# each strand) draws the Eurostat NAMA A01+A03 line for the matching strand
# (solid black); the Eurostat loader emits a "total" row (B1G) alongside the
# three strands, so the total figure is handled by the same path.
build_bench_specs <- function(iso, measure) {
  if (is.null(eu_bench)) return(list())
  Filter(Negate(is.null), list(hline_spec(
    eu_bench[iso3c == iso & strand == measure & year %in% YEARS],
    "bench_usd", "solid", "black")))
}

ref_note_for <- function(measure) {
  if (is.null(eu_bench))
    " (Eurostat reference unavailable — no reference line.)"
  else
    paste0(" Black line = Eurostat NAMA A01+A03 (nama_10_a64, current prices) ",
           "for this measure — a primary-agriculture (ISIC-A) reference, read ",
           "against the lower sub-stack; converted EUR->USD on the same rate.")
}

# One figure per BioSAM-covered country PER MEASURE (total + three strands).
countries <- intersect(sort(unique(dat_all$iso3c)), biosam_countries)
message(sprintf("Building %d countries x %d measures = %d figures ...",
                length(countries), length(MEASURES),
                length(countries) * length(MEASURES)))
for (iso in countries) {
  for (measure in MEASURES) {
    dm <- if (measure == "total") dat_total[iso3c == iso]
    else                    dat_all[iso3c == iso & strand == measure]
    make_country_chart(iso, as_tibble(dm), measure,
                       build_bench_specs(iso, measure),
                       cat_colors, stack_levels,
                       ref_note = ref_note_for(measure))
  }
}

# Combined four-measure panel (total VA + the wages / capital / tls strands) for
# Spain in 2015 only — the four per-measure views laid out as one 2x2 grid for an
# at-a-glance look at that country-year.  Drawn in addition to the per-measure
# figures above.
if ("ESP" %in% countries && 2015L %in% YEARS) {
  message("Building combined ESP 2015 four-measure panel ...")
  make_combined_panel("ESP", 2015L, dat_total, dat_all, eu_bench,
                      cat_colors, stack_levels)
} else {
  message("Skipping combined ESP 2015 panel (ESP not covered, or 2015 not in YEARS).")
}

message("\nDone.")