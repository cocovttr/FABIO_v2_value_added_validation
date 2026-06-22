# ==============================================================================
# US SUT validation chart — per-year VA comparison at BEA detail-industry level
#
# US analog of 02_validation_BioSAMs.R.  Produces, for the USA, FOUR figures:
# a TOTAL value-added figure and one each for the value-added strands WAGES,
# CAPITAL and TLS (taxes less subsidies), all sharing the same three-source /
# stacked-by-category layout of script 02.  The strands are intrinsic to all
# three sources:
#     • The BEA Use (SUT) tables carry them as three value-added rows
#           V00100  Compensation of employees        -> wages
#           T00OTOP Other taxes on production        -> tls
#           V00300  Gross operating surplus          -> capital
#       (VABAS = V00100 + T00OTOP + V00300 holds exactly for every industry
#       column in both years — verified — so the TOTAL figure is their sum,
#       same construction as script 02.)
#     • GLORIA / COMBINED carry them as the component-split columns written by
#       scripts 14_1 / 14_4:  value_added_wages|capital|tls [USD].
#
#   Reference data — the BEA Detail Use tables under the Supply-Use framework,
#   taken from the `useeior` package data objects (2017 NAICS schema, so the
#   two years are directly comparable):
#       Detail_Use_SUT_2012_17sch   |   Detail_Use_SUT_2017_17sch
#   Industry columns are BEA detail codes (e.g. 1111A0, 311210) — the SAME
#   codes the concordance's USA_SUT_code column uses, so no concordance
#   re-coding is needed (the script validates this and reports any mismatch;
#   a trailing "/US" suffix, if a useeior build carries one, is stripped).
#   Values are MILLION USD -> multiplied by 1e6.  NO currency conversion
#   anywhere in this script: BEA and the FABIO VA outputs are both USD, and
#   the OECD benchmark for the US is reported in USD as well.
#
#   Benchmark — OECD for all four figures.  Every figure (total and each
#   strand) draws a horizontal reference line per year-panel built from the
#   SAME OECD SUT download script 14_4 consumes for its A02 forestry / A03
#   fishing overlays: table T1600 "Use, Value added and its components by
#   activity" (dataflow OECD.SDD.NAD : DSD_NASU@DF_USEVA_T1600, written by
#   crafting.R / import_oecd_sut_useva.R) — no new download needed.  The
#   benchmark sums ISIC divisions A01 (crop & animal production) + A03
#   (fishing & aquaculture); A02 (forestry) is simply NOT in the sum, so the
#   agriculture+fishery total is the FABIO-comparable primary-agriculture
#   figure directly, with no deduction step (this replaces script 01's
#   reduced-WB construction).  Strand mapping — IDENTICAL to script 14_4's
#   loader (T1600 publishes the full GVA identity directly):
#       wages   <- D1                  (compensation of employees)
#       capital <- B2A3G (or B2G+B3G)  (gross operating surplus + mixed income)
#       tls     <- D29X39              (other taxes less subsidies on prod.)
#       total   <- B1G  == wages + capital + tls
#   Any SINGLE missing strand is recovered from the identity (script 14_4's
#   rule); cells still incomplete are dropped, and an activity dropping out
#   degrades the benchmark to the remaining divisions (reported).  No FX step:
#   T1600's "XDC" national currency is USD for the USA.  Same dimension
#   filters as script 14_4 (T1600 / _T / V / S1 / _Z / XDC), so both scripts
#   read the same slice of the file.  If the file is missing or unusable the
#   figures are still drawn, just without the reference line (same graceful
#   degradation as scripts 01 / 02).
#
#   The three sources are made comparable as follows:
#     • US SUT (BEA) is the RAW reference, at BEA detail industries directly:
#       the three VA rows are read off the mapped industry columns.
#     • GLORIA-FABIOv2 and COMBINED-FABIOv2 are the 14_1 / 14_4 VA
#       outputs (USA rows), DISAGGREGATED down to BEA detail industries via
#       the SUT<->FABIO item concordance, separately per ISIC level.  Unlike
#       the BioSAMs concordance, the US mapping is NOT clean within ISIC-C:
#       52 FABIO items map to several SUT industries each (e.g. FABIO 2511
#       "Wheat and products" feeds flour milling 311210, breakfast cereals
#       311230 AND all-other-food 311990), so a plain join would replicate —
#       and double-count — their value-added.  Instead, each FABIO item's VA
#       is SPLIT across its mapped SUT industries proportionally to US TOTAL
#       INDUSTRY OUTPUT (row T018 of the same Use table, year-specific), so
#       the split sums back to the item's VA exactly (conservation is checked
#       and reported).  Items whose mapped industries all have zero/missing
#       output fall back to an equal split.  ISIC-A needs no such split (its
#       mapping is 1:1 per item) but runs through the same weighting code,
#       where the weights are simply 1.
#
#   ISIC assignment of the RAW SUT bars is direct: in this concordance no SUT
#   industry appears at both ISIC levels (verified; the script enforces it),
#   so each industry carries the single ISIC level of its concordance rows —
#   no majority rule needed.  For GLORIA/COMBINED the ISIC level is intrinsic
#   (which of the two ISIC-level RDS files the FABIO item came from), as in
#   script 02.
#
#   Colours / layout: identical to script 02 — one stable colour per SUT
#   category, ISIC-C segments grouped on top and outlined in black, ISIC-A
#   below, facet per year (2012 | 2017), up to five source bars per panel
#   (the EXIOBASE pure + combined pair is omitted where its output is absent).
#
# Outputs (sibling of script 02's biosam_validation/):
#   output/usa_sut_validation/by_country/USA.svg            (TOTAL value-added)
#   output/usa_sut_validation/by_country/USA_wages.svg
#   output/usa_sut_validation/by_country/USA_capital.svg
#   output/usa_sut_validation/by_country/USA_tls.svg
#       — every figure carries the OECD A01+A03 reference line for its measure
#       (total or the matching strand), if the OECD export is available.
#   output/usa_sut_validation/by_country/USA_panel4.svg
#       the SAME four measures combined into ONE 2x2 panel, with a single year
#       (PANEL_YEAR) per panel so all four fit, a shared industry legend, and
#       the per-measure OECD reference line.  The four figures above are kept.
#   output/usa_sut_validation/usa_sut_vs_fabio_comparison.csv
#       tidy long table behind the figures
#       (iso3c, year, source, isic, usa_sut_code, category, strand, value_usd)
#   output/usa_sut_validation/oecd_A01_A03_benchmark.csv
#       the OECD A01+A03 benchmark behind every reference line
#       (iso3c, year, strand, bench_usd) — written only if the load succeeded.
#   output/usa_sut_validation/fabio_item_to_sut_output_weights.csv
#       diagnostic: the year-specific output weights used to split each FABIO
#       item's VA across its mapped SUT industries
#       (year, isic, fabio_item_code, usa_sut_code, output_usd, weight).
#
# Companion to: 02_validation_BioSAMs.R (EU, JRC BioSAMs reference)
# ==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(dplyr)
  library(tidyr)
  library(readr)
  library(ggplot2)
  library(scales)
  library(useeior)     # provides Detail_Use_SUT_<year>_17sch
})

# ── FABIO + validation-repo integration ──────────────────────────────────────
# The value-added pipeline is now folded into FABIO (lives in ~/fabio). Rather
# than re-deriving paths here, we source the pipeline's single source of truth,
# R/00_value_added_config.R, which (a) sources R/00_value_added_helpers.R — so
# load_item_conc comes into scope — and (b) exports the canonical path constants
# this validator reads from:
#   VA_VALUE_ADDED_OUTPUT_DIR  FABIOv2_*_value_added_ISIC-*.rds  (14_1 / 14_4)
#   VA_VALUE_ADDED_INPUT_DIR   input/value_added/  (oecd_sut_use_valueadded.csv)
# This validator is USA-only (XDC == USD), so it needs no FAOSTAT FX step.
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

# This validation repo ships its OWN reference inputs (the USA-SUT<->FABIO
# concordance) and receives the validation figures/CSVs. Anchor those on the
# validation-repo root — the directory holding input/ and output/. Defaults to
# the working directory (the .Rproj root); override with VALIDATION_ROOT.
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


# ── Configuration ────────────────────────────────────────────────────────────

# Validation-only concordance. The FABIO pipeline keeps ITS shared concordances
# in inst/value_added/ (VA_CONCORDANCE_DIR); the USA-SUT<->FABIO concordance is
# validation-specific and ships inside this repo under input/concordances/.
INPUT_DIR      <- VALIDATION_CONC_DIR
ITEM_CONC_PATH <- file.path(INPUT_DIR, "concordance_items_usa_sut_fabio.csv")

# FABIOv2 VA outputs (already USD). FOUR variants: the two pure bases written
# by 14_1 (GLORIA / EXIOBASE) and the two synthesis bases written by 14_4
# (COMBINED-GLORIA / COMBINED-EXIOBASE). They live in FABIO's output/value_added/
# (= VA_VALUE_ADDED_OUTPUT_DIR from the config; filenames unchanged). EXIOBASE
# may be absent on a given machine; those sources then drop out rather than fail.
VA_OUTPUT_DIR  <- VA_VALUE_ADDED_OUTPUT_DIR
GLORIA_VA_PATH            <- function(suffix)
  file.path(VA_OUTPUT_DIR, sprintf("FABIOv2_GLORIA_value_added_ISIC-%s.rds",            suffix))
COMBINED_GLORIA_VA_PATH   <- function(suffix)
  file.path(VA_OUTPUT_DIR, sprintf("FABIOv2_COMBINED_GLORIA_value_added_ISIC-%s.rds",   suffix))
EXIOBASE_VA_PATH          <- function(suffix)
  file.path(VA_OUTPUT_DIR, sprintf("FABIOv2_EXIOBASE_value_added_ISIC-%s.rds",          suffix))
COMBINED_EXIOBASE_VA_PATH <- function(suffix)
  file.path(VA_OUTPUT_DIR, sprintf("FABIOv2_COMBINED_EXIOBASE_value_added_ISIC-%s.rds", suffix))

# Reference data: useeior package data objects, both on the 2017 NAICS schema.
# Keyed by validation year.
USE_TABLE_OBJECTS <- c(
  `2012` = "Detail_Use_SUT_2012_17sch",
  `2017` = "Detail_Use_SUT_2017_17sch"
)

# OECD benchmark: the SAME OECD SUT cache the synthesis (14_4) consumes for its
# A02 forestry / A03 fishing overlays — table T1600 "Use, Value added and its
# components by activity" (dataflow OECD.SDD.NAD : DSD_NASU@DF_USEVA_T1600).
# FABIO's 00_9_prep_value_added.R stages it into input/value_added/
# (= VA_VALUE_ADDED_INPUT_DIR), the same path 14_4 reads. No new download needed.
OECD_SUT_PATH <- file.path(VA_VALUE_ADDED_INPUT_DIR, "oecd_sut_use_valueadded.csv")

# ISIC divisions summed for the benchmark: agriculture + fishery, forestry-free
# by construction (A02 simply not in the sum).  Per script 14_4's loader, a
# country that does not report a division simply yields no rows for it; the
# benchmark then degrades to whatever complete divisions remain (reported).
OECD_ACTIVITIES <- c("A01", "A03")

# Dimension filters isolating the VA-by-activity block — IDENTICAL to script
# 05's OECD_SUT_FILTERS, so the two scripts read the same slice of the file.
# UNIT_MEASURE "XDC" is national currency; for the USA that IS USD, so this
# script needs no FX step (script 14_4's SLC join would multiply by 1 here).
OECD_SUT_FILTERS <- list(
  TABLE_IDENTIFIER = "T1600",
  PRODUCT          = "_T",
  PRICE_BASE       = "V",          # current prices
  SECTOR           = "S1",         # total economy (avoid sub-sector double count)
  VALUATION        = "_Z",         # not applicable (VA is valuation-neutral)
  UNIT_MEASURE     = "XDC"         # national currency == USD for the USA
)

# Transaction codes for the four VA strands — IDENTICAL to script 14_4's
# OECD_SUT_TX: capital is B2A3G directly (T1600 publishes the full GVA
# identity), falling back to B2G + B3G, then to the identity for any SINGLE
# missing strand.  D29/D39 are deliberately not split (subsidy-sign ambiguity).
OECD_SUT_TX <- c(total = "B1G", wages = "D1", capital = "B2A3G",
                 capital_os = "B2G", capital_mi = "B3G", tls = "D29X39")

# Output locations: this validator's figures/CSVs live in the validation repo's
# own output/ tree (VALIDATION_OUTPUT_DIR). The oecd benchmark CSV written below
# is read back by 01 — both sides resolve it from VALIDATION_OUTPUT_DIR.
OUT_DIR         <- file.path(VALIDATION_OUTPUT_DIR, "usa_sut_validation")
OUT_DIR_COUNTRY <- file.path(OUT_DIR, "by_country")
dir.create(OUT_DIR_COUNTRY, recursive = TRUE, showWarnings = FALSE)

# BEA Use-table row codes: the three VA strand rows, their total, and the
# total-industry-output row used for the disaggregation weights.
SUT_ROW_TO_STRAND <- c(V00100 = "wages", T00OTOP = "tls", V00300 = "capital")
SUT_VA_TOTAL_ROW  <- "VABAS"   # identity check only
SUT_OUTPUT_ROW    <- "T018"    # total industry output (basic value) -> weights
SUT_MILLIONS      <- 1e6       # BEA tables are in million USD

# The two validation years (== the BEA SUT benchmark years on the 2017 schema).
YEARS <- c(2012L, 2017L)

# The single country this validation covers.
ISO3 <- "USA"

# Measures plotted, one figure each (same as script 02).
STRANDS  <- c("wages", "capital", "tls")
MEASURES <- c("total", STRANDS)

# Single year shown in every panel of the combined 2x2 figure (USA_panel4.svg);
# must be one of YEARS.  The four single-measure figures keep BOTH years; only
# the combined panel collapses to one year so all four measures fit at once.
PANEL_YEAR <- 2017L

MEASURE_TITLE <- c(total   = "value-added",
                   wages   = "wages",
                   capital = "capital",
                   tls     = "taxes less subsidies")
MEASURE_AXIS  <- c(total   = "Value-added (current US$)",
                   wages   = "Wages — compensation of employees (current US$)",
                   capital = "Capital — gross operating surplus (current US$)",
                   tls     = "Other taxes less subsidies on production (current US$)")

# Source ordering / display labels (x-axis order within each year panel).
# Base-grouped to match script 01 (each base's pure output then its COMBINED
# version).  EXIOBASE entries that produced no rows are dropped after the data
# are assembled (see RUN), so a machine without the EXIOBASE pipeline still
# draws the BEA / GLORIA / COMBINED-GLORIA bars.
SOURCE_LEVELS <- c("US SUT (BEA)",
                   "GLORIA-FABIOv2 (disagg.)",
                   "COMBINED-GLORIA-FABIOv2 (disagg.)",
                   "EXIOBASE-FABIOv2 (disagg.)",
                   "COMBINED-EXIOBASE-FABIOv2 (disagg.)")


# ── Concordance loading ──────────────────────────────────────────────────────

# load_item_conc(): now in va_helpers.R

#' Per-SUT-industry ISIC level + canonical label for the RAW SUT bars.  The US
#' concordance has no industry straddling both levels, so the assignment is
#' direct — enforced here (an industry at both levels would silently corrupt
#' the stacking, so it is an error, not a majority vote as in script 02).
build_sut_item_isic <- function(item_conc_a, item_conc_c) {
  both <- intersect(item_conc_a$usa_sut_code, item_conc_c$usa_sut_code)
  if (length(both) > 0L)
    stop("SUT industries mapped at BOTH ISIC levels (unexpected for the US ",
         "concordance): ", paste(both, collapse = ", "),
         "\n  Resolve them to one level in ", ITEM_CONC_PATH, ".")
  rbindlist(list(
    unique(item_conc_a[, .(usa_sut_code, usa_sut_item)])[, isic := "A"],
    unique(item_conc_c[, .(usa_sut_code, usa_sut_item)])[, isic := "C"]
  ))
}


# ── BEA Use (SUT) tables from useeior ────────────────────────────────────────

#' Fetch one useeior Detail_Use_SUT object by name, as a numeric matrix with
#' NA -> 0 and any "/US" location suffix stripped from the dimnames (the raw
#' BEA data objects carry plain detail codes; the strip is defensive in case a
#' useeior build suffixes them like its model objects).
load_use_table <- function(object_name) {
  obj <- tryCatch(get(object_name), error = function(e) NULL)
  if (is.null(obj)) {
    ok <- tryCatch({
      data(list = object_name, package = "useeior",
           envir = environment()); TRUE
    }, warning = function(w) FALSE, error = function(e) FALSE)
    if (ok) obj <- get(object_name, envir = environment())
  }
  if (is.null(obj))
    stop("useeior object '", object_name, "' not found.  Is useeior ",
         "installed and does this version ship the SUT-framework detail ",
         "tables (Detail_Use_SUT_<year>_17sch)?")
  m <- as.matrix(obj)
  mode(m) <- "numeric"
  m[is.na(m)] <- 0
  rownames(m) <- sub("/US$", "", trimws(rownames(m)))
  colnames(m) <- sub("/US$", "", trimws(colnames(m)))
  m
}

#' Raw US SUT source: read the three VA strand rows off the mapped industry
#' columns of each year's Use table.  Returns the same long shape as script
#' 07's build_biosam_source(): (iso3c, year, usa_sut_code, usa_sut_item, isic,
#' strand, value_usd, source).  Also runs the strand identity check
#' (V00100 + T00OTOP + V00300 == VABAS) on the mapped columns as a guard
#' against schema drift in future useeior releases.
build_sut_source <- function(use_tables, sut_isic) {
  per_year <- lapply(names(use_tables), function(yr) {
    m <- use_tables[[yr]]
    
    need_rows <- c(names(SUT_ROW_TO_STRAND), SUT_VA_TOTAL_ROW)
    miss_rows <- setdiff(need_rows, rownames(m))
    if (length(miss_rows) > 0L)
      stop("Use table for ", yr, " is missing VA row(s): ",
           paste(miss_rows, collapse = ", "))
    
    miss_cols <- setdiff(sut_isic$usa_sut_code, colnames(m))
    if (length(miss_cols) > 0L)
      stop("Use table for ", yr, " has no industry column for mapped SUT ",
           "code(s): ", paste(miss_cols, collapse = ", "),
           "\n  Either the concordance codes or the useeior schema changed.")
    
    cols <- sut_isic$usa_sut_code
    va   <- m[names(SUT_ROW_TO_STRAND), cols, drop = FALSE]
    
    # Identity check (tolerance: $1m absolute or 0.1% relative per column).
    tot  <- m[SUT_VA_TOTAL_ROW, cols]
    gap  <- abs(colSums(va) - tot)
    bad  <- gap > pmax(1, 0.001 * abs(tot))
    if (any(bad))
      warning("Year ", yr, ": strand identity V00100+T00OTOP+V00300 != VABAS ",
              "for: ", paste(cols[bad], collapse = ", "))
    
    long <- as.data.table(as.table(va))
    setnames(long, c("row_code", "usa_sut_code", "value"))
    long[, `:=`(
      iso3c     = ISO3,
      year      = as.integer(yr),
      strand    = unname(SUT_ROW_TO_STRAND[as.character(row_code)]),
      value_usd = as.numeric(value) * SUT_MILLIONS
    )][, c("row_code", "value") := NULL]
    long
  })
  out <- rbindlist(per_year)
  out <- sut_isic[out, on = "usa_sut_code", nomatch = NULL]
  out[, source := "US SUT (BEA)"]
  out[, .(iso3c, year, usa_sut_code, usa_sut_item, isic, strand,
          value_usd, source)]
}

#' Year-specific total-industry-output (row T018) per mapped SUT industry, in
#' USD.  These are the disaggregation weights' raw material.
build_output_table <- function(use_tables, sut_codes) {
  rbindlist(lapply(names(use_tables), function(yr) {
    m <- use_tables[[yr]]
    if (!SUT_OUTPUT_ROW %in% rownames(m))
      stop("Use table for ", yr, " has no '", SUT_OUTPUT_ROW,
           "' (total industry output) row — needed for the VA split weights.")
    data.table(
      year         = as.integer(yr),
      usa_sut_code = sut_codes,
      output_usd   = as.numeric(m[SUT_OUTPUT_ROW, sut_codes]) * SUT_MILLIONS
    )
  }))
}


# ── FABIO sources: output-weighted disaggregation to SUT industries ─────────

#' Year-specific weight table for one ISIC level: for each (year,
#' fabio_item_code), the share of each mapped SUT industry in the summed total
#' output of ALL its mapped industries.  Items whose mapped industries all
#' have zero/missing output fall back to an EQUAL split.  Weights sum to 1 per
#' (year, item) by construction, so splitting VA by them conserves the item
#' total exactly — no duplication.  For ISIC-A (1 industry per item) every
#' weight is 1 and the code is a no-op.
build_split_weights <- function(conc, out_tbl, isic_level) {
  w <- merge(
    conc[, .(fabio_item_code, usa_sut_code, usa_sut_item)],
    out_tbl, by = "usa_sut_code", allow.cartesian = TRUE
  )
  w[!is.finite(output_usd) | output_usd < 0, output_usd := 0]
  w[, tot_out := sum(output_usd), by = .(year, fabio_item_code)]
  w[, weight := fifelse(tot_out > 0, output_usd / tot_out, 1 / .N),
    by = .(year, fabio_item_code)]
  n_eq <- uniqueN(w[tot_out <= 0, .(year, fabio_item_code)])
  if (n_eq > 0L)
    message(sprintf(
      "  ISIC-%s: %d (year, item) cell(s) fell back to an equal split ",
      isic_level, n_eq), "(all mapped industries have zero output).")
  w[, isic := isic_level]
  w[, .(year, isic, fabio_item_code, usa_sut_code, usa_sut_item,
        output_usd, weight)]
}

#' GLORIA / COMBINED: melt the strand columns of one ISIC level's VA RDS (USA
#' rows, validation years), split each FABIO item's strand VA across its
#' mapped SUT industries by the output weights, and aggregate to (year, SUT
#' industry, strand).  Conservation (post-split total == pre-split total of
#' the MAPPED items) is checked per level and reported.
build_fabio_source <- function(source_label, va_path_fun, weights_a, weights_c) {
  strand_cols <- c(wages   = "value_added_wages [USD]",
                   capital = "value_added_capital [USD]",
                   tls     = "value_added_tls [USD]")
  one_level <- function(suffix, weights) {
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
    va <- raw[iso3c == ISO3 & year %in% YEARS,
              .(iso3c           = as.character(iso3c),
                year            = as.integer(year),
                fabio_item_code = as.integer(fabio_item_code),
                wages           = `value_added_wages [USD]`,
                capital         = `value_added_capital [USD]`,
                tls             = `value_added_tls [USD]`)]
    if (!nrow(va)) {
      message("  NOTE: ", source_label, " ISIC-", suffix,
              " has no USA rows for ", paste(YEARS, collapse = "/"), ".")
      return(NULL)
    }
    va <- melt(va, id.vars = c("iso3c", "year", "fabio_item_code"),
               measure.vars = names(strand_cols),
               variable.name = "strand", value.name = "value_usd")
    va[, strand := as.character(strand)]
    
    # Pre-split control total over the items that HAVE a SUT mapping (items
    # without one are outside the US SUT agricultural scope and drop out, as
    # unmapped items did in script 02).
    mapped_items <- unique(weights$fabio_item_code)
    pre_tot <- va[fabio_item_code %in% mapped_items,
                  sum(value_usd, na.rm = TRUE)]
    
    out <- weights[va, on = c("year", "fabio_item_code"),
                   nomatch = NULL, allow.cartesian = TRUE]
    out[, value_usd := value_usd * weight]
    
    post_tot <- out[, sum(value_usd, na.rm = TRUE)]
    if (is.finite(pre_tot) && abs(pre_tot) > 0 &&
        abs(post_tot - pre_tot) > 1e-6 * abs(pre_tot))
      warning(source_label, " ISIC-", suffix, ": split does not conserve VA (",
              format(pre_tot, big.mark = ","), " -> ",
              format(post_tot, big.mark = ","), ").")
    message(sprintf(
      "  %s ISIC-%s: %s USD across %d mapped item(s) split onto %d industries (conserved).",
      source_label, suffix,
      label_number(scale_cut = cut_short_scale())(pre_tot),
      length(mapped_items), uniqueN(out$usa_sut_code)))
    
    out[, .(value_usd = sum(value_usd, na.rm = TRUE)),
        by = .(iso3c, year, usa_sut_code, usa_sut_item, strand)][
          , isic := suffix][]
  }
  res <- rbindlist(list(one_level("A", weights_a),
                        one_level("C", weights_c)),
                   use.names = TRUE, fill = TRUE)
  if (nrow(res)) res[, source := source_label]
  res
}


# ── Reference: OECD SUT A01+A03, per measure (all four figures) ──────────────
#
# USA specialization of script 14_4's load_oecd_sut_activity(): same file, same
# dimension filters, same transaction codes and strand construction —
#   wages   <- D1
#   capital <- B2A3G  (or B2G + B3G)     T1600 publishes the GVA identity
#   tls     <- D29X39                    directly, so the identity is only a
#   total   <- B1G                       FALLBACK for one missing strand
# — restricted to REF_AREA == USA, run per activity in OECD_ACTIVITIES (A01 +
# A03 -> forestry-free by construction) and summed across them.  Only
# (activity, year) cells with all four strands finite AFTER identity recovery
# enter the sum (script 14_4's completeness rule); an activity with no usable
# rows drops out and the benchmark degrades to what remains (reported).  No FX
# step: UNIT_MEASURE "XDC" is national currency, which for the USA is USD.
# Returns a long (iso3c, year, strand, bench_usd) table, or NULL (with a
# message) when the file is missing/unusable — figures then draw without the
# reference line, as in scripts 01 / 02.
load_oecd_benchmark <- function(path = OECD_SUT_PATH,
                                activities = OECD_ACTIVITIES) {
  if (!file.exists(path)) {
    message("NOTE: OECD SUT CSV not found at\n  ", path,
            "\n  Figures will be drawn WITHOUT a reference line.  Run ",
            "crafting.R / import_oecd_sut_useva.R first to enable it.")
    return(NULL)
  }
  s <- as.data.table(fread(path))
  
  need <- c("REF_AREA", "ACTIVITY", "TRANSACTION", "PRODUCT", "PRICE_BASE",
            "SECTOR", "VALUATION", "UNIT_MEASURE", "TABLE_IDENTIFIER",
            "TIME_PERIOD", "OBS_VALUE", "UNIT_MULT")
  miss <- setdiff(need, names(s))
  if (length(miss) > 0L) {
    message("NOTE: OECD SUT CSV is missing column(s): ",
            paste(miss, collapse = ", "),
            " — is this the crafting.R download?  Reference line skipped.")
    return(NULL)
  }
  
  # Core dimension filters (script 14_4's, plus REF_AREA and the activity set).
  s <- s[TABLE_IDENTIFIER == OECD_SUT_FILTERS$TABLE_IDENTIFIER &
           PRODUCT      == OECD_SUT_FILTERS$PRODUCT       &
           PRICE_BASE   == OECD_SUT_FILTERS$PRICE_BASE    &
           SECTOR       == OECD_SUT_FILTERS$SECTOR        &
           VALUATION    == OECD_SUT_FILTERS$VALUATION     &
           UNIT_MEASURE == OECD_SUT_FILTERS$UNIT_MEASURE  &
           trimws(as.character(REF_AREA)) == ISO3         &
           ACTIVITY %in% activities]
  if (nrow(s) == 0L) {
    message("NOTE: no OECD SUT rows for USA x {",
            paste(activities, collapse = ", "), "} after filtering — the US ",
            "may not report these divisions in T1600, or a filter code ",
            "differs from your download.  Reference line skipped.")
    return(NULL)
  }
  
  # National-currency (== USD for the USA) absolute value; UNIT_MULT is a
  # power of ten (millions = 6).
  s[, `:=`(value_usd = suppressWarnings(as.numeric(OBS_VALUE)) *
             10^suppressWarnings(as.integer(UNIT_MULT)),
           year = as.integer(substr(trimws(as.character(TIME_PERIOD)), 1, 4)))]
  s <- s[is.finite(value_usd) & year %in% YEARS]
  if (nrow(s) == 0L) {
    message("NOTE: no finite OECD SUT values for USA in ",
            paste(YEARS, collapse = "/"), " — reference line skipped.")
    return(NULL)
  }
  
  # One value per (activity, year, TRANSACTION); warn-and-sum on duplicates
  # (script 14_4's rule — duplicates mean a filter dimension is off).
  tx_all <- unname(OECD_SUT_TX)
  dup <- s[TRANSACTION %in% tx_all, .N,
           by = .(ACTIVITY, year, TRANSACTION)][N > 1L]
  if (nrow(dup) > 0L)
    warning(sprintf("%d (activity, year, transaction) cell(s) had >1 OECD SUT ",
                    nrow(dup)),
            "row after filtering and were summed — check OECD_SUT_FILTERS.")
  s <- s[TRANSACTION %in% tx_all,
         .(value_usd = sum(value_usd, na.rm = TRUE)),
         by = .(activity = as.character(ACTIVITY), year, TRANSACTION)]
  w <- dcast(s, activity + year ~ TRANSACTION, value.var = "value_usd")
  
  gettx <- function(dt, code) {
    if (code %in% names(dt)) suppressWarnings(as.numeric(dt[[code]]))
    else rep(NA_real_, nrow(dt))
  }
  capB2A3G <- gettx(w, OECD_SUT_TX[["capital"]])
  capB2G   <- gettx(w, OECD_SUT_TX[["capital_os"]])
  capB3G   <- gettx(w, OECD_SUT_TX[["capital_mi"]])
  w[, `:=`(
    wages   = gettx(w, OECD_SUT_TX[["wages"]]),
    tls     = gettx(w, OECD_SUT_TX[["tls"]]),
    total   = gettx(w, OECD_SUT_TX[["total"]]),
    capital = fcase(is.finite(capB2A3G),                   capB2A3G,
                    is.finite(capB2G) & is.finite(capB3G), capB2G + capB3G,
                    default = NA_real_))]
  
  # Recover one missing strand from the identity B1G = D1 + B2A3G + D29X39
  # (same recovery order as script 14_4).
  w[!is.finite(capital) & is.finite(total) & is.finite(wages)   & is.finite(tls),
    capital := total - wages - tls]
  w[!is.finite(tls)     & is.finite(total) & is.finite(wages)   & is.finite(capital),
    tls     := total - wages - capital]
  w[!is.finite(wages)   & is.finite(total) & is.finite(capital) & is.finite(tls),
    wages   := total - capital - tls]
  w[!is.finite(total)   & is.finite(wages) & is.finite(capital) & is.finite(tls),
    total   := wages + capital + tls]
  
  # Identity residual where all four were published (sanity, not enforced).
  full <- w[is.finite(wages) & is.finite(capital) &
              is.finite(tls) & is.finite(total)]
  if (nrow(full) > 0L) {
    rr <- full[, abs(total - (wages + capital + tls)) / pmax(abs(total), 1)]
    message(sprintf(
      "  OECD SUT GVA identity (USA %s): max |residual| = %.2e (rel) over %d cell(s).",
      paste(activities, collapse = "+"), max(rr, na.rm = TRUE), nrow(full)))
  }
  
  # Completeness rule: only (activity, year) cells with all four strands
  # finite after recovery enter the cross-activity sum.
  n_pre <- nrow(w)
  w <- w[is.finite(wages) & is.finite(capital) &
           is.finite(tls) & is.finite(total)]
  if (nrow(w) < n_pre)
    message(sprintf("  %d OECD SUT cell(s) dropped for incomplete VA components.",
                    n_pre - nrow(w)))
  if (nrow(w) == 0L) {
    message("NOTE: no complete OECD SUT cells left — reference line skipped.")
    return(NULL)
  }
  kept <- w[, sort(unique(activity))]
  if (!setequal(kept, activities))
    message("  OECD benchmark degrades to activity set {",
            paste(kept, collapse = ", "), "} (incomplete divisions dropped).")
  
  out <- w[, .(wages = sum(wages), capital = sum(capital),
               tls = sum(tls), total = sum(total)), by = year]
  out[, iso3c := ISO3]
  long <- melt(out, id.vars = c("iso3c", "year"),
               measure.vars = c("wages", "capital", "tls", "total"),
               variable.name = "strand", value.name = "bench_usd")
  long[, strand := as.character(strand)]
  long[is.finite(bench_usd)]
}


# ── Colour palette (same base as scripts 01 / 02) ────────────────────────────
base_pal <- c(
  "#1f77b4","#ff7f0e","#2ca02c","#d62728","#9467bd",
  "#8c564b","#e377c2","#bcbd22","#17becf","#aec7e8",
  "#ffbb78","#98df8a","#ff9896","#c5b0d5","#c49c94",
  "#f7b6d2","#dbdb8d","#9edae5","#393b79","#637939",
  "#8c6d31","#843c39","#7b4173","#3182bd","#e6550d",
  "#31a354","#756bb1","#fd8d3c","#74c476","#9e9ac8"
)

# ── Figure (same layout as script 02's make_country_chart) ───────────────────

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
  
  bench_vals <- unlist(lapply(bench_specs, function(s) s$data$yintercept))
  has_neg    <- any(c(dat$value_usd, bench_vals) < 0, na.rm = TRUE)
  y_expand   <- if (has_neg) expansion(mult = c(0.04, 0.04))
  else          expansion(mult = c(0, 0.04))
  
  p <- ggplot(dat, aes(x = source, y = value_usd,
                       fill = category, colour = isic, group = stack_grp)) +
    geom_col(width = 0.8, linewidth = 0.35,
             position = position_stack(reverse = TRUE))
  
  if (has_neg)
    p <- p + geom_hline(yintercept = 0, linewidth = 0.3, colour = "grey70")
  
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
    scale_fill_manual(values = cat_colors, name = "US SUT industry",
                      drop = TRUE) +
    scale_colour_manual(values = c(A = NA, C = "black"), guide = "none",
                        na.value = NA) +
    scale_y_continuous(
      labels = label_number(scale_cut = cut_short_scale()),
      expand = y_expand
    ) +
    labs(
      title    = sprintf("US SUT vs FABIOv2 %s — %s",
                         MEASURE_TITLE[[measure]], iso),
      subtitle = paste0(
        measure_lead, " (USD) for the BEA detail Use (SUT) tables and for the ",
        "GLORIA / COMBINED-GLORIA / EXIOBASE / COMBINED-EXIOBASE FABIOv2 ",
        "variants disaggregated to BEA industries by US ",
        "output shares. Bars stacked by industry; ISIC-C (processing) ",
        "segments are grouped on top and outlined in black, ISIC-A (primary) ",
        "below.", ref_note),
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


# ── Figure: all four measures as ONE 2x2 panel (single year) ─────────────────
# Same stacking / colours / ISIC-C black outlines as make_country_chart(), but
# the year facet is dropped (one chosen year, PANEL_YEAR) and the four MEASURES
# become the facets, so the four single-measure figures also exist combined in
# one panel.  One shared industry legend; each measure keeps its own y-scale
# (free_y) because the magnitudes — and the TLS sign — differ.  TOTAL is read
# from dat_total (strand-summed), the three strands from dat_all.
make_panel_of_4 <- function(iso, panel_year, dat_total, dat_all,
                            cat_colors, stack_levels, oecd_bench = NULL) {
  if (!panel_year %in% YEARS)
    stop("PANEL_YEAR (", panel_year, ") is not one of the benchmark years: ",
         paste(YEARS, collapse = ", "))
  
  # Capitalised facet labels: "Value-added", "Wages", "Capital", "Taxes ...".
  measure_label <- vapply(MEASURE_TITLE[MEASURES], function(x)
    paste0(toupper(substring(x, 1, 1)), substring(x, 2)), character(1))
  names(measure_label) <- MEASURES
  
  # One long table tagged by measure.
  dat_panel <- rbindlist(list(
    dat_total[iso3c == iso & year == panel_year][, measure := "total"],
    dat_all  [iso3c == iso & year == panel_year & strand %in% STRANDS][
      , measure := strand]
  ), use.names = TRUE, fill = TRUE)
  
  if (!nrow(dat_panel)) {
    message("[", iso, "/panel4] no rows for year ", panel_year, "; skipping.")
    return(invisible(NULL))
  }
  
  dat_panel <- dat_panel %>%
    mutate(
      source    = factor(source,   levels = SOURCE_LEVELS),
      isic      = factor(isic,     levels = c("A", "C")),
      category  = factor(category, levels = names(cat_colors)),
      stack_grp = factor(paste(isic, category, sep = "|"), levels = stack_levels),
      measure   = factor(measure,  levels = MEASURES,
                         labels = measure_label[MEASURES])
    )
  
  # Per-measure OECD reference line — tagged by measure so it lands in its panel.
  bench_panel <- NULL
  if (!is.null(oecd_bench)) {
    bp <- as.data.table(oecd_bench)[iso3c == iso & year == panel_year &
                                      strand %in% MEASURES & is.finite(bench_usd)]
    if (nrow(bp)) {
      bp[, measure := factor(strand, levels = MEASURES,
                             labels = measure_label[MEASURES])]
      bench_panel <- bp
    }
  }
  
  has_neg  <- any(c(dat_panel$value_usd, bench_panel$bench_usd) < 0, na.rm = TRUE)
  y_expand <- if (has_neg) expansion(mult = c(0.04, 0.04))
  else          expansion(mult = c(0,    0.04))
  
  p <- ggplot(dat_panel, aes(x = source, y = value_usd,
                             fill = category, colour = isic, group = stack_grp)) +
    geom_col(width = 0.8, linewidth = 0.35,
             position = position_stack(reverse = TRUE))
  
  if (has_neg)
    p <- p + geom_hline(yintercept = 0, linewidth = 0.3, colour = "grey70")
  
  if (!is.null(bench_panel))
    p <- p + geom_hline(data = bench_panel, aes(yintercept = bench_usd),
                        inherit.aes = FALSE, linetype = "solid",
                        linewidth = 0.5, colour = "black")
  
  ref_note <- if (is.null(bench_panel))
    " (OECD reference unavailable — no reference line.)"
  else
    paste0(" Black line = OECD SUT T1600 A01+A03 (agriculture + fishery, ",
           "current prices, USD) for each measure.")
  
  p <- p +
    facet_wrap(~ measure, nrow = 2, scales = "free_y") +
    scale_x_discrete(drop = FALSE) +
    scale_fill_manual(values = cat_colors, name = "US SUT industry", drop = TRUE) +
    scale_colour_manual(values = c(A = NA, C = "black"), guide = "none",
                        na.value = NA) +
    scale_y_continuous(labels = label_number(scale_cut = cut_short_scale()),
                       expand = y_expand) +
    labs(
      title    = sprintf("US SUT vs FABIOv2 — %s (%d)", iso, panel_year),
      subtitle = paste0(
        "All four value-added measures for the BEA detail Use (SUT) tables and ",
        "the GLORIA / COMBINED-GLORIA / EXIOBASE / COMBINED-EXIOBASE FABIOv2 ",
        "variants disaggregated to BEA industries by US output shares. Bars ",
        "stacked by industry; ISIC-C (processing) on top and outlined in black, ",
        "ISIC-A (primary) below. Single year (", panel_year, ") per panel.",
        ref_note),
      x = NULL,
      y = "Value-added components (current US$)"
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
  svg_height    <- 11 + 0.25 * n_legend_rows
  out_file      <- file.path(OUT_DIR_COUNTRY, sprintf("%s_panel4.svg", iso))
  
  ggsave(out_file, p, width = svg_width, height = svg_height,
         limitsize = FALSE, device = "svg")
  message(sprintf("[%s/panel4] wrote %s  (%.1f x %.1f in, year %d)",
                  iso, out_file, svg_width, svg_height, panel_year))
  invisible(out_file)
}


# ============================================================================
# RUN
# ============================================================================

message("Loading concordance ...")
item_conc_a <- load_item_conc(ITEM_CONC_PATH, "A", "USA_SUT_code", "USA_SUT_item", out_code = "usa_sut_code", out_item = "usa_sut_item", keep_code_class_char = FALSE)
item_conc_c <- load_item_conc(ITEM_CONC_PATH, "C", "USA_SUT_code", "USA_SUT_item", out_code = "usa_sut_code", out_item = "usa_sut_item", keep_code_class_char = FALSE)
# ISIC-C keeps only FABIO items not also tagged at ISIC-A (drop double-mapped items).
item_conc_c <- item_conc_c[!fabio_item_code %in% item_conc_a$fabio_item_code]
sut_isic    <- build_sut_item_isic(item_conc_a, item_conc_c)
message(sprintf("  %d ISIC-A and %d ISIC-C item mappings onto %d SUT industries (%d A / %d C).",
                nrow(item_conc_a), nrow(item_conc_c), nrow(sut_isic),
                sum(sut_isic$isic == "A"), sum(sut_isic$isic == "C")))

message("Loading useeior Use (SUT) tables ...")
use_tables <- lapply(USE_TABLE_OBJECTS, load_use_table)
names(use_tables) <- names(USE_TABLE_OBJECTS)

message("Building per-source long tables ...")
src_sut <- build_sut_source(use_tables, sut_isic)

out_tbl   <- build_output_table(use_tables, sut_isic$usa_sut_code)
weights_a <- build_split_weights(item_conc_a, out_tbl, "A")
weights_c <- build_split_weights(item_conc_c, out_tbl, "C")
fwrite(rbindlist(list(weights_a, weights_c)),
       file.path(OUT_DIR, "fabio_item_to_sut_output_weights.csv"))

src_gloria            <- build_fabio_source("GLORIA-FABIOv2 (disagg.)",
                                            GLORIA_VA_PATH,            weights_a, weights_c)
src_combined_gloria   <- build_fabio_source("COMBINED-GLORIA-FABIOv2 (disagg.)",
                                            COMBINED_GLORIA_VA_PATH,   weights_a, weights_c)
src_exiobase          <- build_fabio_source("EXIOBASE-FABIOv2 (disagg.)",
                                            EXIOBASE_VA_PATH,          weights_a, weights_c)
src_combined_exiobase <- build_fabio_source("COMBINED-EXIOBASE-FABIOv2 (disagg.)",
                                            COMBINED_EXIOBASE_VA_PATH, weights_a, weights_c)

dat_all <- rbindlist(
  list(src_sut, src_gloria, src_combined_gloria,
       src_exiobase, src_combined_exiobase),
  use.names = TRUE, fill = TRUE
)[, .(iso3c, year, source, isic, usa_sut_code, category = usa_sut_item,
      strand, value_usd)]
dat_all <- dat_all[is.finite(value_usd)]

# Keep only the source bars that actually produced rows, in the canonical order
# (graceful degradation when the EXIOBASE pipeline is absent — no empty slots).
SOURCE_LEVELS <- intersect(SOURCE_LEVELS, unique(dat_all$source))

# TOTAL = sum of the three strands per (year, source, isic, industry) — exact
# for the SUT source by the VABAS identity, by construction for GLORIA/COMBINED.
dat_total <- dat_all[, .(value_usd = sum(value_usd, na.rm = TRUE)),
                     by = .(iso3c, year, source, isic, usa_sut_code, category)]

message("Loading OECD A01+A03 benchmark ...")
oecd_bench <- load_oecd_benchmark()                     # may be NULL (skipped)

comparison_path <- file.path(OUT_DIR, "usa_sut_vs_fabio_comparison.csv")
fwrite(dat_all, comparison_path)
message("Comparison table -> ", comparison_path)
if (!is.null(oecd_bench)) {
  oecd_bench_path <- file.path(OUT_DIR, "oecd_A01_A03_benchmark.csv")
  fwrite(oecd_bench, oecd_bench_path)
  message("OECD benchmark -> ", oecd_bench_path)
}

# Agreement metrics behind the figures, scoring every FABIOv2 source against the
# RAW US SUT (BEA) reference — the same comparison the thesis text reports, now
# written out rather than read off the bars.  Three CSVs (see
# write_reference_metrics() in 00_validation_helpers.R):
#   usa_sut_by_strand_by_year.csv      per-year aggregate ratios per ISIC level
#       and measure (total + wages/capital/tls) — the per-year totals and the
#       per-year strand ratios, TLS kept signed.
#   usa_sut_item_ratios.csv            the pre-aggregation item frame: one
#       aggregate ratio per (isic, BEA category, year, source, measure).
#   metrics_usa_sut_pooled_items.csv   pooled item-level metrics per
#       (isic, source, measure): med ratio, the three dex dispersions, within-2x.
# Scored on the two SUT benchmark years that dat_all already carries.
write_reference_metrics(
  dat       = dat_all,
  reference = "US SUT (BEA)",
  sources   = SOURCE_LEVELS,
  out_dir   = OUT_DIR,
  prefix    = "usa_sut")

# Global, stable category palette + stacking order (A combos first, then C,
# each by descending TOTAL) — same construction as script 02.
cat_tot    <- dat_total[, .(tot = sum(abs(value_usd), na.rm = TRUE)),
                        by = category][order(-tot)]
cat_levels <- cat_tot$category
cat_colors <- setNames(colorRampPalette(base_pal)(length(cat_levels)), cat_levels)

combos <- unique(dat_total[, .(isic, category)])
combos[, tot := cat_tot$tot[match(category, cat_tot$category)]]
setorder(combos, isic, -tot)
stack_levels <- paste(combos$isic, combos$category, sep = "|")

build_bench_specs <- function(iso, measure) {
  if (is.null(oecd_bench)) return(list())
  Filter(Negate(is.null), list(hline_spec(
    oecd_bench[iso3c == iso & strand == measure & year %in% YEARS],
    "bench_usd", "solid", "black")))
}

ref_note_for <- function(measure) {
  if (is.null(oecd_bench))
    " (OECD reference unavailable — no reference line.)"
  else
    paste0(" Black line = OECD SUT T1600 A01+A03 (agriculture + fishery, ",
           "current prices, USD) for this measure — a primary-agriculture ",
           "(ISIC-A) reference, read against the lower sub-stack.")
}

message(sprintf("Building 1 country x %d measures = %d figures ...",
                length(MEASURES), length(MEASURES)))
for (measure in MEASURES) {
  dm <- if (measure == "total") dat_total[iso3c == ISO3]
  else                    dat_all[iso3c == ISO3 & strand == measure]
  make_country_chart(ISO3, as_tibble(dm), measure,
                     build_bench_specs(ISO3, measure),
                     cat_colors, stack_levels,
                     ref_note = ref_note_for(measure))
}

message(sprintf("Building combined 2x2 panel (year %d) ...", PANEL_YEAR))
make_panel_of_4(ISO3, PANEL_YEAR, dat_total, dat_all,
                cat_colors, stack_levels, oecd_bench)

message("\nDone.")