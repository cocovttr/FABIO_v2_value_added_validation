# ==============================================================================
# BioSAMs validation — VA agreement against the JRC BioSAMs at BioSAM categories
#
# Compares the FABIOv2 value-added estimates with the raw JRC BioSAMs over the
# two years the BioSAMs cover, at three cell resolutions (L1 country-year, L2
# item, L3 item x strand), and with the Eurostat A01+A03 national accounts at
# L1.  The value-added strands are intrinsic to all sources:
#     • BioSAMs carry them as three VA accounts
#         LABOUR -> wages, CAPITAL -> capital, TLS-A -> tls   (TLS-C excluded)
#     • GLORIA / COMBINED carry them as the component-split columns written by
#       scripts 14_1 / 14_4:  value_added_wages|capital|tls [USD]  (total is
#       their sum).
#
#   Note on the TLS strand: all sources use the PRODUCTION-side taxes less
#   subsidies and exclude the product-side ones — BioSAMs keep TLS-A and drop
#   TLS-C (a tax on products), GLORIA / COMBINED's tls is taxes/subsidies on
#   production, and Eurostat's D29X39 is "other taxes less subsidies on
#   production" (the product-tax code D21X31 is not used).  So the strand is
#   like-for-like across sources and reference.  It is often NET NEGATIVE where
#   subsidies exceed taxes.
#
#   The sources are made comparable as follows:
#     • BioSAMs are the RAW JRC input (the reference data), at BioSAM categories
#       directly.  Their three retained VA accounts (CAPITAL, LABOUR, TLS-A;
#       TLS-C excluded as a tax on products, not VA) are summed per (area, item,
#       year, strand) and CONVERTED EUR -> USD using Germany's SLC series from
#       the FAOSTAT exchange-rate file — the same file and direction script 14_4
#       uses to fold FSDN into COMBINED (value_USD = value_EUR / rate(year)).
#     • GLORIA-FABIOv2 and COMBINED-FABIOv2 are the 14_1 / 14_4 VA outputs
#       (already USD).  Their FABIO-item value-added is AGGREGATED UP to the
#       BioSAM categories via the BioSAM<->FABIO item concordance, separately
#       per ISIC level.  The aggregation is clean: no FABIO item maps to more
#       than one BioSAM category within a single ISIC level, so the sum involves
#       no double-counting.
#
#   ISIC assignment of the RAW BioSAM rows.  BioSAM VA carries no ISIC tag, so
#   each BioSAM item is assigned the ISIC level held by the MAJORITY of its
#   mapped FABIO items in the concordance (ties -> A); a FABIO item tagged at
#   BOTH levels counts only toward A.  All but one category are unambiguous;
#   only A_OANM ("Other animals, live and their products") maps across both
#   levels, and resolves to ISIC-A.  For GLORIA/COMBINED the ISIC level is
#   intrinsic — it is simply which of the two ISIC-level RDS files the FABIO
#   item came from; a category can therefore carry both an A and a C cell.
#
#   Eurostat reference — EUROSTAT National Accounts (nama_10_a64, current
#   prices), summed over NACE A01 (crop & animal production) + A03 (fishing &
#   aquaculture).  A02 (forestry) is not in that sum, so the reference is
#   forestry-free: the Eurostat A01+A03 total is the FABIO-comparable
#   primary-agriculture figure directly.  Strand mapping:
#       wages   <- D1                         (compensation of employees)
#       tls     <- D29X39                     (other taxes less subsidies on prod.)
#       capital <- B1G - D1 - D29X39          (via the GVA identity; NAMA has no
#                                              standalone B2A3G code)
#       total   <- B1G
#   Eurostat is in EUR millions, converted EUR->USD with the SAME Germany SLC
#   rate the BioSAMs use.  Being A01+A03 it is a PRIMARY-agriculture (ISIC-A)
#   reference, so it is scored at ISIC-A scope only.  It is READ from the staged
#   nama_10_a64 CSV (the same one FABIO's pipeline stages and reads); if that
#   CSV is missing the rest of the script still runs.
#
# Outputs:
#   output/biosam_validation/biosam_vs_fabio_comparison.csv
#       tidy long table behind everything else, BioSAM-covered countries only
#       (iso3c, year, source, isic, biosam_item_code, category, strand, value_usd)
#   output/biosam_validation/eurostat_A01_A03_benchmark.csv
#       the Eurostat NAMA A01+A03 reference (iso3c, year, strand, bench_usd) —
#       written only if the staged CSV was readable, and read back by 01.
#   output/biosam_validation/metrics_vs_nationalaccounts.csv
#       agreement of all five sources with the Eurostat A01+A03 line at ISIC-A
#       scope, L1 cells.
#   output/biosam_validation/metrics_biosam_vs_fabio.csv
#       agreement of the four FABIOv2 variants with the raw BioSAMs at full ISIC
#       A+C scope, L1 / L2 / L3 down the `level` column, pooled over items and
#       again resolved per item (`item`).
#   output/biosam_validation/biosam_ihs_<source>_<level>.svg
#       one IHS scatter panel per source and level, at that level's cell
#       resolution.
#
# Author:   Coco Vetter
# ==============================================================================

suppressPackageStartupMessages({
  library(data.table)
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

# Shared metric / plot layer, shipped alongside this script.
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
# the comparison rather than failing (see the RUN section).
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
OUT_DIR <- file.path(VALIDATION_OUTPUT_DIR, "biosam_validation")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

# BioSAM CSV column names + retained VA accounts (matched on CODES).
BIOSAM_VALUE_COL <- "Value (MILLION EUROS)"
BIOSAM_AREA_COL  <- "Country (ISO2)"
BIOSAM_ITEM_COL  <- "Spending Agent (Code)"
BIOSAM_VA_COL    <- "Receiving Agent (Code)"
BIOSAM_YEAR_COL  <- "Year"

# Retained BioSAM VA accounts -> strand.  TLS-C (a tax on products, not VA) is
# excluded by omission.  Each account is carried through as its own strand so the
# per-strand metrics can be built; the total is their sum.
BIOSAM_ACCOUNT_TO_STRAND <- c(CAPITAL = "capital", LABOUR = "wages", `TLS-A` = "tls")
VA_ACCOUNTS <- names(BIOSAM_ACCOUNT_TO_STRAND)   # CAPITAL, LABOUR, TLS-A

# The two validation years (== the years the BioSAMs cover).
YEARS <- c(2010L, 2015L)

# Known-erroneous BioSAM country-years, identified against the Eurostat National
# Accounts and dropped from the agreement statistics (the comparison CSV keeps
# them, so the discrepancy stays visible).  Romania 2010: the raw
# BioSAM VA sub-components are clearly corrupt — net-negative agricultural capital
# and a taxes-less-subsidies figure off by roughly +20 bn USD against Eurostat.
BIOSAM_EXCLUDE <- data.table(iso3c = "ROU", year = 2010L)

# The scored measures: the three strands and their sum.
STRANDS  <- c("wages", "capital", "tls")
MEASURES <- c("total", STRANDS)

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

# Source ordering / display labels.  Base-grouped to match script 01: each
# base's pure output then its COMBINED (FSDN-overlaid) version.  EXIOBASE
# entries that produced no rows are dropped from this vector after the data are
# assembled (see RUN), so a machine without the EXIOBASE pipeline still scores
# the GLORIA pair.
SOURCE_LEVELS <- c("BioSAMs",
                   "GLORIA-FABIOv2 (agg.)",
                   "COMBINED-GLORIA-FABIOv2 (agg.)",
                   "EXIOBASE-FABIOv2 (agg.)",
                   "COMBINED-EXIOBASE-FABIOv2 (agg.)")


# ── Concordance loading ──────────────────────────────────────────────────────

#' Per-BioSAM-item ISIC assignment for the RAW BioSAM rows: the ISIC level held
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
           paste(miss, collapse = ", "), ".\n  The metrics need the ",
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


# ── Reference: Eurostat NAMA A01+A03, per measure ────────────────────────────
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
# CSV is missing or unreadable, so the rest of the script still runs, just
# without the national-accounts comparison.
load_eurostat_benchmark <- function(eur_per_usd, nace = EU_NACE_BENCH) {
  if (!file.exists(EUROSTAT_NAMA_PATH)) {
    warning("Eurostat NAMA not staged (", EUROSTAT_NAMA_PATH, ") — the ",
            "national-accounts comparison will be skipped.  Run FABIO's ",
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
    message("  No Eurostat data read — skipping the national-accounts comparison.")
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
# COMBINED span the full FABIO country set, but the comparison is only
# meaningful where there is a BioSAMs column.
biosam_countries <- sort(unique(src_biosam$iso3c))
dat_all <- dat_all[iso3c %in% biosam_countries]

# Keep only the sources that actually produced rows, in the canonical order.
SOURCE_LEVELS <- intersect(SOURCE_LEVELS, unique(dat_all$source))
message(sprintf("BioSAMs cover %d country(ies).", length(biosam_countries)))

message("Loading Eurostat A01+A03 benchmark ...")
eu_bench <- load_eurostat_benchmark(eur_per_usd)        # may be NULL (skipped)

# Tidy comparison CSV behind everything below (BioSAM-covered countries only),
# at strand granularity.  The Eurostat benchmark (if any) is written alongside.
comparison_path <- file.path(OUT_DIR, "biosam_vs_fabio_comparison.csv")
fwrite(dat_all, comparison_path)
message("Comparison table -> ", comparison_path)
if (!is.null(eu_bench)) {
  eu_bench_path <- file.path(OUT_DIR, "eurostat_A01_A03_benchmark.csv")
  fwrite(eu_bench[iso3c %in% biosam_countries], eu_bench_path)
  message("Eurostat benchmark -> ", eu_bench_path)
}

# Agreement statistics: two metric tables scoring the sources across the
# BioSAM-covered countries x the two validation years.  Known-erroneous BioSAM
# country-years (BIOSAM_EXCLUDE — Romania 2010) are dropped here so the metrics
# reflect only the trustworthy comparison; the comparison CSV keeps them.
dat_metrics <- dat_all[!BIOSAM_EXCLUDE, on = .(iso3c, year)]

# Analysis 1 — all sources vs the Eurostat A01+A03 national-accounts line, at
# the ISIC-A scope that line measures (primary agriculture).  The reference is
# national, so L1 is the only resolution it supports.  BIOSAM_EXCLUDE has to
# drop from the reference as well: a country-year left in on one side only
# would come back as a structural zero on the other, and read as a coverage
# failure rather than the deliberate exclusion it is.
if (!is.null(eu_bench)) {
  cells_na   <- va_cells(dat_metrics[isic == "A"], VA_LEVEL_KEYS$L1)
  ref_na     <- eu_bench[iso3c %in% biosam_countries][
    !BIOSAM_EXCLUDE, on = .(iso3c, year)][
      , .(iso3c, year, strand, ref = bench_usd)]
  metrics_na <- va_score(va_match(cells_na, ref_na), SOURCE_LEVELS, "L1")
  metrics_na_path <- file.path(OUT_DIR, "metrics_vs_nationalaccounts.csv")
  fwrite(metrics_na, metrics_na_path, na = "NA")
  message("National-accounts metrics -> ", metrics_na_path)
  message("\nAgreement vs Eurostat A01+A03 national accounts (ISIC-A):")
  print(metrics_na)
} else {
  message("Eurostat benchmark unavailable — skipping national-accounts metrics.")
}

# Analysis 2 — the four FABIOv2 variants vs the raw BioSAMs reference, at the
# full ISIC A+C scope, down the L1 / L2 / L3 cascade and per BioSAM category.
fab_srcs   <- setdiff(SOURCE_LEVELS, "BioSAMs")
matched    <- va_matched_levels(dat_metrics, "BioSAMs", c("L1", "L2", "L3"))
metrics_bs <- va_metrics_table(matched, fab_srcs, by_item = TRUE)
metrics_bs_path <- file.path(OUT_DIR, "metrics_biosam_vs_fabio.csv")
fwrite(metrics_bs, metrics_bs_path, na = "NA")
message("BioSAMs-reference metrics -> ", metrics_bs_path)
message("\nAgreement vs raw BioSAMs (full ISIC A+C), pooled over items:")
print(metrics_bs[is.na(item)])

message("\nBuilding IHS scatter panels ...")
va_write_ihs_plots(
  matched,
  theta        = va_theta(va_level_cells(dat_metrics[source == "BioSAMs"], "L3")$value),
  sources      = fab_srcs,
  out_dir      = OUT_DIR,
  prefix       = "biosam",
  dataset      = "BioSAMs",
  reference    = "raw JRC BioSAMs")

message("\nDone.")