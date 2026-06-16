# ==============================================================================
# Japan IOT validation chart — per-year VA comparison at basic-sector level
#
# Japan analog of 03_validation_USA_SUTs.R (USA).  Produces, for
# JAPAN, FOUR figures: a TOTAL value-added figure and one each for the
# value-added strands WAGES, CAPITAL and TLS (taxes less subsidies), all
# sharing the same three-source / stacked-by-category layout of scripts 02 / 03.
# The strands are intrinsic to all three sources:
#     • The Japanese national Input-Output Tables (basic sector
#       classification) carry them as value-added rows of the Input Table
#       (identical row codes in all three benchmark years):
#           9111000 wages & salaries                      \
#           9112000 employers' social insurance contrib.   > -> wages
#           9113000 other wages & allowances              /
#           7111001-003 consumption expenditure outside households (CEOH,
#                   a quasi-labour cost) -> added to wages if INCLUDE_CEOH
#           9211000 operating surplus                     \
#           9311000 consumption of fixed capital           > -> capital
#           9321000 CFC (social capital)                  /
#           9411000 indirect taxes (excl. customs duties  \
#                   and import commodity taxes)            > -> tls
#           9511000 (less) current subsidies [negative]   /
#       (9600000 gross value added == CEOH + wages + capital + tls holds for
#       every industry column — verified per sector — so the TOTAL figure is
#       their sum, same construction as scripts 02 / 03.)
#     • GLORIA / COMBINED carry them as the component-split columns written by
#       scripts 14_1 / 14_4:  value_added_wages|capital|tls [USD].
#
#   Reference data — the e-Stat Input Table workbooks (basic sector, English
#   edition) for the three benchmark years, expected under IOT_DIR
#   ("input/Japan_IOTs"):
#       Japan_2011_input_table.xlsx    (518 rows x 397 columns, MILLION yen)
#       Japan_2015_input_table.xlsx    (509 rows x 391 columns, MILLION yen)
#       Japan_2020_input_table.xlsx    (445 rows x 391 columns, BILLION yen)
#   Each is a LONG table (Column Code | Row Code | ... | Producers Price);
#   row 1 is the sheet title, row 2 the header.  Values are read by POSITION
#   (col 1 = column code, col 2 = row code, col 4 = producers' price) because
#   the 2011 header carries a "Produders Price" typo.  The year-specific yen
#   unit (JPY_UNIT) and Japan's annual SLC rate from the FAOSTAT
#   exchange-rate file (Exchange_rate_E_All_Data.csv — same file, loader and
#   direction as script 14_4 / the BioSAM validator (02): USD = JPY / rate(year)) convert everything
#   to current USD — unlike script 03, an FX step is unavoidable here because
#   the FABIO VA outputs are USD.  The matching
#   Japan_<year>_output_table.xlsx files are NOT needed and are not read: VA,
#   the GVA check row AND the domestic production used for the split weights
#   (row 9700000) all live in the Input Table.
#
#   Concordance — PER-YEAR files (the basic sector classification changes
#   between benchmarks: 397 / 391 / 391 industry columns), in CONC_DIR —
#   this repo's input/concordances/ folder:
#       concordance_items_japan_iot<year>_fabio.csv
#   with columns JPN_IOT<year>_item | JPN_IOT<year>_code | FABIO_item_code |
#   ISIC (+ extras).  Rows with empty ISIC or FABIO_item_code are unmapped
#   sectors (incl. the 573101P/573201P/681100P dummy placeholders) and drop
#   out at load time, as in script 03.  Industry labels (categories) come
#   from the concordance's item column; since labels are stable across years
#   while codes occasionally are not, the figures stack by LABEL so the same
#   industry keeps one colour across the three panels.
#
#   Benchmark — OECD for all four figures, same construction as script 03:
#   table T1600 "Use, Value added and its components by activity" (dataflow
#   OECD.SDD.NAD : DSD_NASU@DF_USEVA_T1600, written by crafting.R /
#   import_oecd_sut_useva.R), REF_AREA == JPN, ISIC divisions A01 + A03
#   (forestry A02 simply not in the sum).  Strand mapping identical
#   (D1 / B2A3G or B2G+B3G / D29X39 / B1G, single-missing-strand identity
#   recovery).  ONE difference from script 03: UNIT_MEASURE "XDC" national
#   currency is YEN for Japan, so the benchmark runs through the SAME
#   JPY_PER_USD conversion as the IOT bars (script 03 needed no FX because
#   XDC == USD for the USA).
#
#   WB FALLBACK — Japan does not appear in the OECD T1600 download (the
#   loader then returns NULL and, before this fallback, every figure drew
#   without a line).  When — and only when — the OECD load yields nothing,
#   the TOTAL figure instead carries a DASHED black A01+A03 reference built
#   exactly like script 01's reduced-WB construction:
#       bench = WB "Agriculture, forestry & fishing, value added
#               (current US$)"  (covers A01+A02+A03, already USD — no FX)
#             x (1 - share_forestry)
#   where share_forestry per year is, as in script 01,
#       forestry_total_usd / WB   — the MEASURED A02 VA written by script 14_4
#                                   (Eurostat NAMA / OECD SUT), if the cell
#                                   exists for (JPN, year); ELSE
#       share_forestry_gloria     — the GLORIA structural share of sector 21.
#   Both come straight from script 01's diagnostic CSV
#   (non_fabio_sector_share_per_country_year.csv), so no GLORIA matrix is
#   re-read here; years the CSV does not cover keep the raw WB value
#   (share 0) and are flagged.  Script 01's SEEDS deduction is deliberately
#   NOT applied: seeds sit inside A01, and the OECD A01+A03 line this
#   replaces keeps them too.  WB has no wages/capital/tls split, so the
#   three strand figures carry no fallback line (noted in their subtitles).
#
#   The three sources are made comparable as follows:
#     • Japan IOT is the RAW reference, at basic-sector industries directly:
#       the VA strand rows are read off the mapped industry columns and
#       converted to USD.
#     • GLORIA-FABIOv2 and COMBINED-FABIOv2 are the 14_1 / 14_4 VA
#       outputs (JPN rows, already USD), DISAGGREGATED down to basic-sector
#       industries via the per-year concordance.  As in the US, the mapping
#       is NOT clean: many FABIO items map to several IOT sectors each (and —
#       unlike the US — this also happens WITHIN ISIC-A, e.g. FABIO 2960
#       "Grazing" feeds four grassland/feed sectors in 2020), so a plain join
#       would replicate — and double-count — their value-added.  Instead,
#       each FABIO item's VA is SPLIT across its mapped IOT sectors
#       proportionally to DOMESTIC PRODUCTION (row 9700000 of the same Input
#       Table, year-specific), so the split sums back to the item's VA
#       exactly (conservation is checked and reported).  Items whose mapped
#       sectors all have zero/missing output fall back to an equal split.
#       Both ISIC levels run through the same weighting code.
#
#   ISIC assignment of the RAW IOT bars is direct: in these concordances no
#   sector appears at both ISIC levels (verified per year; the script
#   enforces it), so each sector carries the single ISIC level of its
#   concordance rows — no majority rule needed.  For GLORIA/COMBINED the ISIC
#   level is intrinsic (which of the two ISIC-level RDS files the FABIO item
#   came from), as in scripts 02 / 03.
#
#   Colours / layout: identical to scripts 02 / 03 — one stable colour per IOT
#   category, ISIC-C segments grouped on top and outlined in black, ISIC-A
#   below, facet per year (2011 | 2015 | 2020), up to five source bars per
#   panel (the EXIOBASE pure + combined pair is omitted where output is absent).
#
# Outputs (sibling of script 03's usa_sut_validation/):
#   output/japan_iot_validation/by_country/JPN.svg           (TOTAL value-added)
#   output/japan_iot_validation/by_country/JPN_wages.svg
#   output/japan_iot_validation/by_country/JPN_capital.svg
#   output/japan_iot_validation/by_country/JPN_tls.svg
#       — every figure carries the OECD A01+A03 reference line for its measure
#       (total or the matching strand), if the OECD export is available.
#   output/japan_iot_validation/japan_iot_vs_fabio_comparison.csv
#       tidy long table behind the figures
#       (iso3c, year, source, isic, jpn_iot_code, category, strand, value_usd)
#   output/japan_iot_validation/oecd_A01_A03_benchmark.csv
#       the OECD A01+A03 benchmark behind every reference line
#       (iso3c, year, strand, bench_usd) — written only if the load succeeded.
#   output/japan_iot_validation/wb_A01_A03_benchmark.csv
#       the WB-fallback A01+A03 benchmark (iso3c, year, strand, bench_usd,
#       wb_raw_usd, share_forestry, forestry_route) — written only when the
#       OECD load failed AND the WB fallback succeeded.
#   output/japan_iot_validation/fabio_item_to_iot_output_weights.csv
#       diagnostic: the year-specific domestic-production weights used to
#       split each FABIO item's VA across its mapped IOT sectors
#       (year, isic, fabio_item_code, jpn_iot_code, output_usd, weight).
#
# Companion to: 02_validation_BioSAMs.R (EU) and
#               03_validation_USA_SUTs.R (USA)
# ==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(dplyr)
  library(tidyr)
  library(readr)
  library(readxl)
  library(ggplot2)
  library(scales)
})

# ── FABIO + validation-repo integration ──────────────────────────────────────
# The value-added pipeline is now folded into FABIO (lives in ~/fabio). Rather
# than re-deriving paths here, we source the pipeline's single source of truth,
# R/00_value_added_config.R, which (a) sources R/00_value_added_helpers.R — so
# load_item_conc / the FAOSTAT rate readers come into scope — and (b) exports
# the canonical path/constant set this validator reads from:
#   VA_VALUE_ADDED_OUTPUT_DIR  FABIOv2_*_value_added_ISIC-*.rds  (14_1 / 14_4)
#   VA_VALUE_ADDED_INPUT_DIR   input/value_added/  (oecd_sut_use_valueadded.csv)
#   VA_EXCHANGE_RATE_CSV       input/fao/Exchange_rate_…(Normalized).csv
#   VA_FX_ELEMENT_CODE ("SLC")
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

# This validation repo ships its OWN reference inputs (the Japan IOT workbooks,
# the Japan-IOT<->FABIO concordances, World Bank Agri GDP) and receives the
# validation figures/CSVs. Anchor those on the validation-repo root — the
# directory holding input/ and output/. Defaults to the working directory (the
# .Rproj root); override with the VALIDATION_ROOT env var when run head-less.
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
# element, require_years) was consolidated into faostat_rate_table(path,
# element), which now returns an all-areas data.table (fabio_area_code, year,
# rate_lcu_per_usd). Re-derive the old year-named vector for one area so the
# call site below is unchanged; require_years hard-fails on any missing year.
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

# Year-adapter for the shared load_item_conc(): builds the per-year path and
# the dynamic JPN_IOT<yr>_code / _item column names, then defers to the helper.
load_jpn_item_conc <- function(yr, isic_level) {
  load_item_conc(CONC_PATH(yr), isic_level,
                 sprintf("JPN_IOT%d_code", yr),
                 sprintf("JPN_IOT%d_item", yr),
                 out_code = "jpn_iot_code", out_item = "jpn_iot_item",
                 keep_code_class_char = FALSE)
}


# ── Configuration ────────────────────────────────────────────────────────────

# Japan IOT workbooks (Input Tables only — see header). Validation reference
# data, not pipeline-produced; ships inside this repo under input/Japan_IOTs/.
IOT_DIR <- validation_path("input", "Japan_IOTs")

# Validation-only concordances (Japan IOT <-> FABIO, per year). The FABIO
# pipeline keeps ITS shared concordances in inst/value_added/ (VA_CONCORDANCE_DIR);
# these are validation-specific and ship inside this repo under input/concordances/.
CONC_DIR <- VALIDATION_CONC_DIR

# The three Japanese IOT benchmark years validated here.
YEARS <- c(2011L, 2015L, 2020L)

# Per-year input files.
IOT_PATH  <- function(yr) file.path(IOT_DIR,
                                    sprintf("Japan_%d_input_table.xlsx", yr))
CONC_PATH <- function(yr) file.path(CONC_DIR,
                                    sprintf("concordance_items_japan_iot%d_fabio.csv", yr))

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

# Yen unit of each workbook's Producers Price column: the 2011 and 2015
# tables are published in MILLION yen, the 2020 table in BILLION yen
# (domestic production totals 939,674,856 m / 1,017,818,388 m / 1,026,154 bn
# yen respectively — verified at load time against row 9700000, column 970000).
JPY_UNIT <- c(`2011` = 1e6, `2015` = 1e6, `2020` = 1e9)

# JPY -> USD: Japan's SLC row from the FAOSTAT exchange-rate file (same file,
# loader and direction as script 14_4 / the BioSAM validator (02)):  value_USD = value_JPY / rate(year).
# The SLC element carries one annual-value row per country (the LCU element
# also has monthly rows — that is why SLC is used).  Loaded into JPY_PER_USD
# (a year -> rate vector) in the RUN section; it converts the IOT bars AND the
# OECD benchmark (XDC == yen for Japan) to the FABIO outputs' USD.
EXCHANGE_RATE_PATH <- VA_EXCHANGE_RATE_CSV
JAPAN_AREA_CODE    <- 110L   # not in the config (only Germany is named there)
EXCHANGE_ELEMENT   <- VA_FX_ELEMENT_CODE

# Add consumption expenditure outside households (rows 7111001-003, a
# quasi-labour cost that is part of GVA in the Japanese tables) to WAGES.
# Either way it stays inside TOTAL, so only the wages/total split — never the
# GVA identity — depends on this flag.
INCLUDE_CEOH <- TRUE

# OECD benchmark: the SAME OECD SUT cache the synthesis (14_4) and the other
# validators consume — table T1600 "Use, Value added and its components by
# activity" (dataflow OECD.SDD.NAD : DSD_NASU@DF_USEVA_T1600). FABIO's
# 00_9_prep_value_added.R stages it into input/value_added/
# (= VA_VALUE_ADDED_INPUT_DIR). No new download needed.
OECD_SUT_PATH <- file.path(VA_VALUE_ADDED_INPUT_DIR, "oecd_sut_use_valueadded.csv")

# ISIC divisions summed for the benchmark: agriculture + fishery, forestry-free
# by construction (A02 simply not in the sum) — as in script 03.
OECD_ACTIVITIES <- c("A01", "A03")

# Dimension filters isolating the VA-by-activity block — IDENTICAL to script 14_4 /
# the USA validator (03).  UNIT_MEASURE "XDC" is national currency, i.e. YEN for Japan: unlike
# script 03, the benchmark therefore passes through JPY_PER_USD below.
OECD_SUT_FILTERS <- list(
  TABLE_IDENTIFIER = "T1600",
  PRODUCT          = "_T",
  PRICE_BASE       = "V",          # current prices
  SECTOR           = "S1",         # total economy (avoid sub-sector double count)
  VALUATION        = "_Z",         # not applicable (VA is valuation-neutral)
  UNIT_MEASURE     = "XDC"         # national currency == JPY for Japan
)

# Transaction codes for the four VA strands — IDENTICAL to script 14_4 / the USA validator (03).
OECD_SUT_TX <- c(total = "B1G", wages = "D1", capital = "B2A3G",
                 capital_os = "B2G", capital_mi = "B3G", tls = "D29X39")

# WB fallback for the reference line (used ONLY when the OECD T1600 load
# yields nothing for JPN — see header).  Same WB CSV script 01 consumes
# ("Agriculture, forestry & fishing, value added", CURRENT USD — no FX step)
# and script 01's own diagnostic share table for the forestry (A02)
# deduction, so the fallback line is numerically script 01's reduced-WB
# reference, minus the seeds deduction (seeds stay in: they are inside A01,
# matching the OECD A01+A03 line this replaces).  Run script 01 first to
# (re)generate the share CSV; if it is absent the line degrades to the raw
# WB total (A01+A02+A03, forestry not removed) and says so.
WB_AGRI_GDP_PATH    <- validation_path("input", "World_Bank_Agri_GDP.csv")
# Written by 01 to VALIDATION_OUTPUT_DIR/fabio_validation/; this is the 01 -> 04
# hand-off, so it MUST match 01's out_dir_base (both resolve VALIDATION_OUTPUT_DIR).
NONFABIO_SHARE_PATH <- file.path(VALIDATION_OUTPUT_DIR, "fabio_validation",
                                 "non_fabio_sector_share_per_country_year.csv")

# Output locations: this validator's figures/CSVs live in the validation repo's
# own output/ tree (VALIDATION_OUTPUT_DIR).
OUT_DIR         <- file.path(VALIDATION_OUTPUT_DIR, "japan_iot_validation")
OUT_DIR_COUNTRY <- file.path(OUT_DIR, "by_country")
dir.create(OUT_DIR_COUNTRY, recursive = TRUE, showWarnings = FALSE)

# Japan Input Table row codes: the VA strand component rows, the CEOH rows,
# the published-GVA check row, and the domestic-production row used for the
# disaggregation weights.
IOT_ROW_TO_STRAND <- c(`9111000` = "wages", `9112000` = "wages",
                       `9113000` = "wages",
                       `9211000` = "capital", `9311000` = "capital",
                       `9321000` = "capital",
                       `9411000` = "tls", `9511000` = "tls")
IOT_CEOH_ROWS    <- c("7111001", "7111002", "7111003")
IOT_VA_TOTAL_ROW <- "9600000"   # gross value added — identity check only
IOT_OUTPUT_ROW   <- "9700000"   # domestic production -> weights
IOT_TOTAL_COLS   <- c("700000", "970000")  # all-industry / grand-total columns

# The single country this validation covers.
ISO3 <- "JPN"

# Measures plotted, one figure each (same as scripts 02 / 03).
STRANDS  <- c("wages", "capital", "tls")
MEASURES <- c("total", STRANDS)

MEASURE_TITLE <- c(total   = "value-added",
                   wages   = "wages",
                   capital = "capital",
                   tls     = "taxes less subsidies")
MEASURE_AXIS  <- c(total   = "Value-added (current US$, annual-avg FX)",
                   wages   = "Wages — compensation of employees (current US$, annual-avg FX)",
                   capital = "Capital — operating surplus + CFC (current US$, annual-avg FX)",
                   tls     = "Indirect taxes less subsidies (current US$, annual-avg FX)")

# Source ordering / display labels (x-axis order within each year panel).
# Base-grouped to match script 01 (each base's pure output then its COMBINED
# version).  EXIOBASE entries that produced no rows are dropped after the data
# are assembled (see RUN), so a machine without the EXIOBASE pipeline still
# draws the IOT / GLORIA / COMBINED-GLORIA bars.
SOURCE_LEVELS <- c("Japan IOT (MIC)",
                   "GLORIA-FABIOv2 (disagg.)",
                   "COMBINED-GLORIA-FABIOv2 (disagg.)",
                   "EXIOBASE-FABIOv2 (disagg.)",
                   "COMBINED-EXIOBASE-FABIOv2 (disagg.)")


# ── FAOSTAT exchange rate: yen per USD, per year ─────────────────────────────

# load_jpy_per_usd(): now faostat_rate_vector() in va_helpers.R


# ── Concordance loading (per year) ───────────────────────────────────────────

# load_item_conc(): now in va_helpers.R

#' Per-(year, sector) ISIC level + canonical label for the RAW IOT bars.  No
#' sector straddles both levels in these concordances, so the assignment is
#' direct — enforced here per year (a sector at both levels would silently
#' corrupt the stacking, so it is an error, not a majority vote).
build_iot_item_isic <- function(item_conc_a, item_conc_c, yr) {
  both <- intersect(item_conc_a$jpn_iot_code, item_conc_c$jpn_iot_code)
  if (length(both) > 0L)
    stop("Year ", yr, ": IOT sectors mapped at BOTH ISIC levels (unexpected ",
         "for the Japan concordances): ", paste(both, collapse = ", "),
         "\n  Resolve them to one level in ", CONC_PATH(yr), ".")
  out <- rbindlist(list(
    unique(item_conc_a[, .(jpn_iot_code, jpn_iot_item)])[, isic := "A"],
    unique(item_conc_c[, .(jpn_iot_code, jpn_iot_item)])[, isic := "C"]
  ))
  out[, year := as.integer(yr)]
  out
}


# ── Japan Input Tables (e-Stat workbooks) ────────────────────────────────────

#' Read one year's Input Table workbook into a long (col_code, row_code,
#' value_jpy) table.  Row 1 is the sheet title, row 2 the header; columns are
#' taken by POSITION (1 = column code, 2 = row code, 4 = producers' price)
#' because the 2011 header misspells "Producers Price".  Only the VA / CEOH /
#' GVA / domestic-production rows are kept — everything this script needs.
load_iot_table <- function(yr) {
  path <- IOT_PATH(yr)
  if (!file.exists(path))
    stop("Japan Input Table not found: ", path)
  raw <- suppressWarnings(suppressMessages(
    read_excel(path, skip = 1, col_names = TRUE)))
  if (ncol(raw) < 4L)
    stop("Unexpected layout in ", path, " — fewer than 4 columns after skip.")
  dt <- as.data.table(raw[, c(1L, 2L, 4L)])
  setnames(dt, c("col_code", "row_code", "value_jpy"))
  dt[, `:=`(col_code  = trimws(as.character(col_code)),
            row_code  = trimws(as.character(row_code)),
            value_jpy = suppressWarnings(as.numeric(value_jpy)))]
  keep_rows <- c(names(IOT_ROW_TO_STRAND), IOT_CEOH_ROWS,
                 IOT_VA_TOTAL_ROW, IOT_OUTPUT_ROW)
  dt <- dt[row_code %in% keep_rows & !is.na(col_code) & col_code != ""]
  dt[is.na(value_jpy), value_jpy := 0]
  # Unit sanity: the grand-total domestic production must land in the
  # 100-2000 trillion-yen range once the configured unit is applied.
  gt <- dt[col_code %in% IOT_TOTAL_COLS & row_code == IOT_OUTPUT_ROW,
           max(value_jpy, na.rm = TRUE)] * JPY_UNIT[[as.character(yr)]]
  if (!is.finite(gt) || gt < 1e14 || gt > 2e15)
    warning("Year ", yr, ": domestic production grand total = ",
            format(gt, big.mark = ","), " yen looks implausible — check ",
            "JPY_UNIT[\"", yr, "\"] against the workbook's unit.")
  dt
}

#' Raw Japan IOT source: read the VA strand rows off the mapped sector columns
#' of each year's Input Table, in USD.  Returns the same long shape as script
#' 08's build_sut_source(): (iso3c, year, jpn_iot_code, jpn_iot_item, isic,
#' strand, value_usd, source).  Also runs the per-sector GVA identity check
#' (CEOH + wages + capital + tls == 9600000) as a guard against row-code
#' drift in future table revisions.
build_iot_source <- function(iot_tables, iot_isic) {
  per_year <- lapply(YEARS, function(yr) {
    dt   <- iot_tables[[as.character(yr)]]
    isic <- iot_isic[year == yr]
    to_usd <- JPY_UNIT[[as.character(yr)]] / JPY_PER_USD[[as.character(yr)]]
    
    have_rows <- unique(dt$row_code)
    miss_rows <- setdiff(c(names(IOT_ROW_TO_STRAND), IOT_VA_TOTAL_ROW),
                         have_rows)
    if (length(miss_rows) > 0L)
      stop("Input Table for ", yr, " is missing VA row(s): ",
           paste(miss_rows, collapse = ", "))
    
    have_cols <- unique(dt$col_code)
    miss_cols <- setdiff(isic$jpn_iot_code, have_cols)
    if (length(miss_cols) > 0L)
      stop("Input Table for ", yr, " has no industry column for mapped IOT ",
           "code(s): ", paste(miss_cols, collapse = ", "),
           "\n  Either the concordance codes or the e-Stat layout changed.")
    
    sec <- dt[col_code %in% isic$jpn_iot_code]
    
    # Strand assignment, with CEOH routed into wages (or dropped from the
    # strands but NOT from the identity check) per INCLUDE_CEOH.
    sec[, strand := IOT_ROW_TO_STRAND[row_code]]
    sec[row_code %in% IOT_CEOH_ROWS,
        strand := if (INCLUDE_CEOH) "wages" else "ceoh_excluded"]
    
    # Per-sector GVA identity: components must reproduce row 9600000 within
    # rounding of the source's last published digit.
    comp <- sec[row_code != IOT_VA_TOTAL_ROW & row_code != IOT_OUTPUT_ROW,
                .(strands_jpy = sum(value_jpy)), by = col_code]
    pub  <- sec[row_code == IOT_VA_TOTAL_ROW,
                .(col_code, gva_jpy = value_jpy)]
    chk  <- merge(comp, pub, by = "col_code")
    tol  <- if (JPY_UNIT[[as.character(yr)]] >= 1e9) 0.5 else 2  # last digit
    bad  <- chk[abs(strands_jpy - gva_jpy) > pmax(tol, 1e-4 * abs(gva_jpy))]
    if (nrow(bad) > 0L)
      warning("Year ", yr, ": GVA identity (CEOH+wages+capital+tls != ",
              "9600000) fails for: ", paste(bad$col_code, collapse = ", "))
    message(sprintf(
      "  %d: GVA identity max |dev| = %s yen over %d mapped sector(s).",
      yr,
      format(chk[, max(abs(strands_jpy - gva_jpy))] *
               JPY_UNIT[[as.character(yr)]], big.mark = ","),
      nrow(chk)))
    
    long <- sec[strand %in% STRANDS,
                .(value_usd = sum(value_jpy) * to_usd),
                by = .(jpn_iot_code = col_code, strand)]
    long[, `:=`(iso3c = ISO3, year = as.integer(yr))]
    long
  })
  out <- rbindlist(per_year)
  out <- iot_isic[out, on = c("year", "jpn_iot_code"), nomatch = NULL]
  out[, source := "Japan IOT (MIC)"]
  out[, .(iso3c, year, jpn_iot_code, jpn_iot_item, isic, strand,
          value_usd, source)]
}

#' Year-specific domestic production (row 9700000) per mapped IOT sector, in
#' USD.  These are the disaggregation weights' raw material.
build_output_table <- function(iot_tables, iot_isic) {
  rbindlist(lapply(YEARS, function(yr) {
    dt     <- iot_tables[[as.character(yr)]]
    codes  <- iot_isic[year == yr, jpn_iot_code]
    to_usd <- JPY_UNIT[[as.character(yr)]] / JPY_PER_USD[[as.character(yr)]]
    if (!IOT_OUTPUT_ROW %in% dt$row_code)
      stop("Input Table for ", yr, " has no '", IOT_OUTPUT_ROW,
           "' (domestic production) row — needed for the VA split weights.")
    o <- dt[row_code == IOT_OUTPUT_ROW & col_code %in% codes,
            .(jpn_iot_code = col_code, output_usd = value_jpy * to_usd)]
    miss <- setdiff(codes, o$jpn_iot_code)
    if (length(miss) > 0L)
      o <- rbind(o, data.table(jpn_iot_code = miss, output_usd = 0))
    o[, year := as.integer(yr)]
    o[, .(year, jpn_iot_code, output_usd)]
  }))
}


# ── FABIO sources: output-weighted disaggregation to IOT sectors ─────────────

#' Year-specific weight table for one ISIC level: for each (year,
#' fabio_item_code), the share of each mapped IOT sector in the summed
#' domestic production of ALL its mapped sectors.  Items whose mapped sectors
#' all have zero/missing output fall back to an EQUAL split.  Weights sum to
#' 1 per (year, item) by construction, so splitting VA by them conserves the
#' item total exactly — no duplication.  Unlike the US, 1:many mappings occur
#' at BOTH ISIC levels here (e.g. FABIO 2960 "Grazing" -> four sectors in
#' 2020), so neither level is a no-op.
build_split_weights <- function(conc_by_year, out_tbl, isic_level) {
  w <- rbindlist(lapply(YEARS, function(yr) {
    conc <- conc_by_year[[as.character(yr)]]
    if (is.null(conc) || nrow(conc) == 0L) return(NULL)
    merge(conc[, .(fabio_item_code, jpn_iot_code, jpn_iot_item)],
          out_tbl[year == yr], by = "jpn_iot_code",
          allow.cartesian = TRUE)
  }))
  w[!is.finite(output_usd) | output_usd < 0, output_usd := 0]
  w[, tot_out := sum(output_usd), by = .(year, fabio_item_code)]
  w[, weight := fifelse(tot_out > 0, output_usd / tot_out, 1 / .N),
    by = .(year, fabio_item_code)]
  n_eq <- uniqueN(w[tot_out <= 0, .(year, fabio_item_code)])
  if (n_eq > 0L)
    message(sprintf(
      "  ISIC-%s: %d (year, item) cell(s) fell back to an equal split ",
      isic_level, n_eq), "(all mapped sectors have zero output).")
  w[, isic := isic_level]
  w[, .(year, isic, fabio_item_code, jpn_iot_code, jpn_iot_item,
        output_usd, weight)]
}

#' GLORIA / COMBINED: melt the strand columns of one ISIC level's VA RDS (JPN
#' rows, validation years), split each FABIO item's strand VA across its
#' mapped IOT sectors by the output weights, and aggregate to (year, IOT
#' sector, strand).  Conservation (post-split total == pre-split total of the
#' MAPPED items per year — the mapped set is year-specific here) is checked
#' per level and reported.
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
              " has no JPN rows for ", paste(YEARS, collapse = "/"), ".")
      return(NULL)
    }
    va <- melt(va, id.vars = c("iso3c", "year", "fabio_item_code"),
               measure.vars = names(strand_cols),
               variable.name = "strand", value.name = "value_usd")
    va[, strand := as.character(strand)]
    
    # Pre-split control total over (year, item) cells that HAVE a mapping —
    # the mapped item set is YEAR-SPECIFIC here (per-year concordances),
    # unlike script 03's single set.
    mapped <- unique(weights[, .(year, fabio_item_code)])
    pre_tot <- va[mapped, on = c("year", "fabio_item_code"), nomatch = NULL][
      , sum(value_usd, na.rm = TRUE)]
    
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
      "  %s ISIC-%s: %s USD across %d mapped (year, item) cell(s) split onto %d sectors (conserved).",
      source_label, suffix,
      label_number(scale_cut = cut_short_scale())(pre_tot),
      nrow(mapped), uniqueN(out$jpn_iot_code)))
    
    out[, .(value_usd = sum(value_usd, na.rm = TRUE)),
        by = .(iso3c, year, jpn_iot_code, jpn_iot_item, strand)][
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
# Japan specialization of script 03's load_oecd_benchmark(): same file, same
# dimension filters, same transaction codes and strand construction —
#   wages   <- D1
#   capital <- B2A3G  (or B2G + B3G)     T1600 publishes the GVA identity
#   tls     <- D29X39                    directly, so the identity is only a
#   total   <- B1G                       FALLBACK for one missing strand
# — restricted to REF_AREA == JPN, run per activity in OECD_ACTIVITIES (A01 +
# A03 -> forestry-free by construction) and summed across them.  Only
# (activity, year) cells with all four strands finite AFTER identity recovery
# enter the sum; an activity with no usable rows drops out and the benchmark
# degrades to what remains (reported).  ONE departure from script 03:
# UNIT_MEASURE "XDC" national currency is YEN for Japan, so values divide by
# the same JPY_PER_USD annual averages as the IOT bars.  Returns a long
# (iso3c, year, strand, bench_usd) table, or NULL (with a message) when the
# file is missing/unusable — figures then draw without the reference line.
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
  
  s <- s[TABLE_IDENTIFIER == OECD_SUT_FILTERS$TABLE_IDENTIFIER &
           PRODUCT      == OECD_SUT_FILTERS$PRODUCT       &
           PRICE_BASE   == OECD_SUT_FILTERS$PRICE_BASE    &
           SECTOR       == OECD_SUT_FILTERS$SECTOR        &
           VALUATION    == OECD_SUT_FILTERS$VALUATION     &
           UNIT_MEASURE == OECD_SUT_FILTERS$UNIT_MEASURE  &
           trimws(as.character(REF_AREA)) == ISO3         &
           ACTIVITY %in% activities]
  if (nrow(s) == 0L) {
    message("NOTE: no OECD SUT rows for JPN x {",
            paste(activities, collapse = ", "), "} after filtering — Japan ",
            "may not report these divisions in T1600, or a filter code ",
            "differs from your download.  Reference line skipped.")
    return(NULL)
  }
  
  # National-currency (yen) absolute value; UNIT_MULT is a power of ten
  # (millions = 6).  Conversion to USD by the year's FAOSTAT SLC rate
  # happens here — the same JPY_PER_USD applied to the IOT bars above
  # (script 03 had no FX step: XDC == USD for the USA).
  s[, `:=`(value_jpy = suppressWarnings(as.numeric(OBS_VALUE)) *
             10^suppressWarnings(as.integer(UNIT_MULT)),
           year = as.integer(substr(trimws(as.character(TIME_PERIOD)), 1, 4)))]
  s <- s[is.finite(value_jpy) & year %in% YEARS]
  if (nrow(s) == 0L) {
    message("NOTE: no finite OECD SUT values for JPN in ",
            paste(YEARS, collapse = "/"), " — reference line skipped.")
    return(NULL)
  }
  s[, value_usd := value_jpy / JPY_PER_USD[as.character(year)]]
  
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
  
  # Recover one missing strand from the identity B1G = D1 + B2A3G + D29X39.
  w[!is.finite(capital) & is.finite(total) & is.finite(wages)   & is.finite(tls),
    capital := total - wages - tls]
  w[!is.finite(tls)     & is.finite(total) & is.finite(wages)   & is.finite(capital),
    tls     := total - wages - capital]
  w[!is.finite(wages)   & is.finite(total) & is.finite(capital) & is.finite(tls),
    wages   := total - capital - tls]
  w[!is.finite(total)   & is.finite(wages) & is.finite(capital) & is.finite(tls),
    total   := wages + capital + tls]
  
  full <- w[is.finite(wages) & is.finite(capital) &
              is.finite(tls) & is.finite(total)]
  if (nrow(full) > 0L) {
    rr <- full[, abs(total - (wages + capital + tls)) / pmax(abs(total), 1)]
    message(sprintf(
      "  OECD SUT GVA identity (JPN %s): max |residual| = %.2e (rel) over %d cell(s).",
      paste(activities, collapse = "+"), max(rr, na.rm = TRUE), nrow(full)))
  }
  
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


# ── Fallback reference: WB A01+A03 (script 01's reduced-WB construction) ─────
# Called ONLY when load_oecd_benchmark() returned NULL (Japan is absent from
# the OECD T1600 download).  Builds, per validation year,
#     bench_usd = WB_ag_va_usd x (1 - share_forestry)
# with share_forestry resolved exactly as in script 01:
#     forestry_total_usd / WB     if script 14_4's measured A02 cell exists
#     share_forestry_gloria       else (GLORIA structural share of sector 21)
#     0                           if the share CSV is missing / lacks the year
#                                 (raw WB incl. forestry — flagged).
# Both shares come from script 01's diagnostic CSV — no GLORIA matrices are
# touched here.  No seeds deduction and no FX step (see header).  Returns the
# SAME shape as load_oecd_benchmark() restricted to strand == "total" (plus
# provenance columns for the CSV dump), or NULL with a message — figures then
# draw without any line, as before.
load_wb_benchmark <- function(path = WB_AGRI_GDP_PATH,
                              share_path = NONFABIO_SHARE_PATH) {
  if (!file.exists(path)) {
    message("NOTE: World Bank ag-VA CSV not found at\n  ", path,
            "\n  No WB fallback reference line either.")
    return(NULL)
  }
  # WB CSVs carry 4 metadata lines before the header (same as script 01).
  wb <- suppressMessages(read_csv(path, skip = 4, show_col_types = FALSE))
  if (!"Country Code" %in% names(wb)) {
    message("NOTE: WB CSV has no 'Country Code' column — is this the World ",
            "Bank export script 01 reads?  WB fallback skipped.")
    return(NULL)
  }
  yr_cols <- intersect(as.character(YEARS), names(wb))
  if (length(yr_cols) == 0L) {
    message("NOTE: WB CSV has no column for any of ",
            paste(YEARS, collapse = "/"), " — WB fallback skipped.")
    return(NULL)
  }
  jp <- wb[wb$`Country Code` == ISO3, yr_cols, drop = FALSE]
  if (nrow(jp) == 0L) {
    message("NOTE: no '", ISO3, "' row in the WB CSV — WB fallback skipped.")
    return(NULL)
  }
  bench <- data.table(
    year   = as.integer(yr_cols),
    wb_usd = suppressWarnings(as.numeric(unlist(jp[1L, ])))
  )[is.finite(wb_usd) & wb_usd != 0]
  if (nrow(bench) == 0L) {
    message("NOTE: WB ag VA for ", ISO3, " is NA/zero in all of ",
            paste(YEARS, collapse = "/"), " — WB fallback skipped.")
    return(NULL)
  }
  miss_yr <- setdiff(YEARS, bench$year)
  if (length(miss_yr) > 0L)
    message("NOTE: WB ag VA missing for year(s) ",
            paste(miss_yr, collapse = ", "),
            " — those panels carry no fallback line.")
  
  # Forestry (A02) deduction from script 01's diagnostic share table.
  bench[, `:=`(share_forestry = 0, forestry_route = "WB_raw_incl_A02")]
  if (file.exists(share_path)) {
    sh <- as.data.table(fread(share_path))
    need <- c("iso3c", "year", "share_forestry_gloria")
    if (all(need %in% names(sh))) {
      if (!"forestry_total_usd" %in% names(sh))
        sh[, forestry_total_usd := NA_real_]   # 01 ran without script 14_4's file
      sh <- sh[iso3c == ISO3,
               .(year = as.integer(year),
                 share_forestry_gloria = suppressWarnings(as.numeric(share_forestry_gloria)),
                 forestry_total_usd    = suppressWarnings(as.numeric(forestry_total_usd)))]
      sh <- sh[, .SD[1L], by = year]      # one row per year (defensive)
      bench <- merge(bench, sh, by = "year", all.x = TRUE)
      bench[, `:=`(
        share_forestry = fcase(
          is.finite(forestry_total_usd),    forestry_total_usd / wb_usd,
          is.finite(share_forestry_gloria), share_forestry_gloria,
          default = 0),
        forestry_route = fcase(
          is.finite(forestry_total_usd),    "measured_A02",
          is.finite(share_forestry_gloria), "GLORIA_share",
          default = "WB_raw_incl_A02"))]
      bench[, c("share_forestry_gloria", "forestry_total_usd") := NULL]
    } else {
      message("NOTE: share CSV at\n  ", share_path,
              "\n  lacks column(s) ", paste(setdiff(need, names(sh)),
                                            collapse = ", "),
              " — forestry NOT removed (raw WB incl. A02).")
    }
  } else {
    message("NOTE: script 01's share CSV not found at\n  ", share_path,
            "\n  Forestry NOT removed from the WB fallback (raw WB incl. ",
            "A02).  Run 01_validation_global_agricultural_GDP.R to fix.")
  }
  
  bench[, bench_usd := wb_usd * (1 - share_forestry)]
  bench <- bench[is.finite(bench_usd)]
  if (nrow(bench) == 0L) {
    message("NOTE: no finite WB fallback values left — skipped.")
    return(NULL)
  }
  message("  WB A01+A03 fallback (JPN): ",
          paste(sprintf("%d: %.2fbn USD [%s, A02 share %.1f%%]",
                        bench$year, bench$bench_usd / 1e9,
                        bench$forestry_route, 100 * bench$share_forestry),
                collapse = " | "))
  bench[, `:=`(iso3c = ISO3, strand = "total")]
  bench[, .(iso3c, year, strand, bench_usd,
            wb_raw_usd = wb_usd, share_forestry, forestry_route)]
}


# ── Colour palette (same base as scripts 01 / 02 / 03) ───────────────────────
base_pal <- c(
  "#1f77b4","#ff7f0e","#2ca02c","#d62728","#9467bd",
  "#8c564b","#e377c2","#bcbd22","#17becf","#aec7e8",
  "#ffbb78","#98df8a","#ff9896","#c5b0d5","#c49c94",
  "#f7b6d2","#dbdb8d","#9edae5","#393b79","#637939",
  "#8c6d31","#843c39","#7b4173","#3182bd","#e6550d",
  "#31a354","#756bb1","#fd8d3c","#74c476","#9e9ac8"
)

# ── Figure (same layout as scripts 02 / 03) ────────────────────────────────────

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
    scale_fill_manual(values = cat_colors, name = "Japan IOT sector",
                      drop = TRUE) +
    scale_colour_manual(values = c(A = NA, C = "black"), guide = "none",
                        na.value = NA) +
    scale_y_continuous(
      labels = label_number(scale_cut = cut_short_scale()),
      expand = y_expand
    ) +
    labs(
      title    = sprintf("Japan IOT vs FABIOv2 %s — %s",
                         MEASURE_TITLE[[measure]], iso),
      subtitle = paste0(
        measure_lead, " (USD, annual-average JPY/USD) for the Japanese ",
        "Input-Output Tables (basic sector) and for the GLORIA / ",
        "COMBINED-GLORIA / EXIOBASE / COMBINED-EXIOBASE FABIOv2 variants ",
        "disaggregated to IOT sectors by domestic-production ",
        "shares. Bars stacked by sector; ISIC-C (processing) segments are ",
        "grouped on top and outlined in black, ISIC-A (primary) below.",
        ref_note),
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
  svg_width     <- 17          # three year panels x up to five source bars
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


# ============================================================================
# RUN
# ============================================================================

message("Loading FAOSTAT JPY/USD rates ...")
JPY_PER_USD <- faostat_rate_vector(EXCHANGE_RATE_PATH, JAPAN_AREA_CODE, element = EXCHANGE_ELEMENT, require_years = YEARS)
message(sprintf("  %s",
                paste(sprintf("%s: %.3f", as.character(YEARS),
                              JPY_PER_USD[as.character(YEARS)]),
                      collapse = " | ")))

message("Loading per-year concordances ...")
conc_a <- setNames(lapply(YEARS, load_jpn_item_conc, isic_level = "A"),
                   as.character(YEARS))
conc_c <- setNames(lapply(YEARS, load_jpn_item_conc, isic_level = "C"),
                   as.character(YEARS))
iot_isic <- rbindlist(lapply(YEARS, function(yr)
  build_iot_item_isic(conc_a[[as.character(yr)]],
                      conc_c[[as.character(yr)]], yr)))
for (yr in YEARS)
  message(sprintf(
    "  %d: %d ISIC-A and %d ISIC-C item mappings onto %d IOT sectors (%d A / %d C).",
    yr, nrow(conc_a[[as.character(yr)]]), nrow(conc_c[[as.character(yr)]]),
    nrow(iot_isic[year == yr]),
    iot_isic[year == yr, sum(isic == "A")],
    iot_isic[year == yr, sum(isic == "C")]))

message("Loading Japan Input Tables ...")
iot_tables <- setNames(lapply(YEARS, load_iot_table), as.character(YEARS))

message("Building per-source long tables ...")
src_iot <- build_iot_source(iot_tables, iot_isic)

out_tbl   <- build_output_table(iot_tables, iot_isic)
weights_a <- build_split_weights(conc_a, out_tbl, "A")
weights_c <- build_split_weights(conc_c, out_tbl, "C")
fwrite(rbindlist(list(weights_a, weights_c)),
       file.path(OUT_DIR, "fabio_item_to_iot_output_weights.csv"))

src_gloria            <- build_fabio_source("GLORIA-FABIOv2 (disagg.)",
                                            GLORIA_VA_PATH,            weights_a, weights_c)
src_combined_gloria   <- build_fabio_source("COMBINED-GLORIA-FABIOv2 (disagg.)",
                                            COMBINED_GLORIA_VA_PATH,   weights_a, weights_c)
src_exiobase          <- build_fabio_source("EXIOBASE-FABIOv2 (disagg.)",
                                            EXIOBASE_VA_PATH,          weights_a, weights_c)
src_combined_exiobase <- build_fabio_source("COMBINED-EXIOBASE-FABIOv2 (disagg.)",
                                            COMBINED_EXIOBASE_VA_PATH, weights_a, weights_c)

dat_all <- rbindlist(
  list(src_iot, src_gloria, src_combined_gloria,
       src_exiobase, src_combined_exiobase),
  use.names = TRUE, fill = TRUE
)[, .(iso3c, year, source, isic, jpn_iot_code, category = jpn_iot_item,
      strand, value_usd)]
dat_all <- dat_all[is.finite(value_usd)]

# Keep only the source bars that actually produced rows, in the canonical order
# (graceful degradation when the EXIOBASE pipeline is absent — no empty slots).
SOURCE_LEVELS <- intersect(SOURCE_LEVELS, unique(dat_all$source))

# TOTAL = sum of the three strands per (year, source, isic, sector) — exact
# for the IOT source by the 9600000 identity (CEOH included either way), by
# construction for GLORIA/COMBINED.
dat_total <- dat_all[, .(value_usd = sum(value_usd, na.rm = TRUE)),
                     by = .(iso3c, year, source, isic, jpn_iot_code, category)]

message("Loading OECD A01+A03 benchmark ...")
oecd_bench <- load_oecd_benchmark()                     # may be NULL (skipped)

# Japan is typically absent from the T1600 download — fall back to script
# 06's reduced-WB A01+A03 construction (TOTAL figure only; see header).
wb_bench <- NULL
if (is.null(oecd_bench)) {
  message("Loading WB A01+A03 fallback benchmark (script 01 construction) ...")
  wb_bench <- load_wb_benchmark()                       # may be NULL too
}

comparison_path <- file.path(OUT_DIR, "japan_iot_vs_fabio_comparison.csv")
fwrite(dat_all, comparison_path)
message("Comparison table -> ", comparison_path)
if (!is.null(oecd_bench)) {
  oecd_bench_path <- file.path(OUT_DIR, "oecd_A01_A03_benchmark.csv")
  fwrite(oecd_bench, oecd_bench_path)
  message("OECD benchmark -> ", oecd_bench_path)
}
if (!is.null(wb_bench)) {
  wb_bench_path <- file.path(OUT_DIR, "wb_A01_A03_benchmark.csv")
  fwrite(wb_bench, wb_bench_path)
  message("WB fallback benchmark -> ", wb_bench_path)
}

# Global, stable category palette + stacking order (A combos first, then C,
# each by descending TOTAL) — same construction as scripts 02 / 03.  Categories
# are sector LABELS, so a sector renumbered between benchmark years still
# keeps one colour across the three panels.
cat_tot    <- dat_total[, .(tot = sum(abs(value_usd), na.rm = TRUE)),
                        by = category][order(-tot)]
cat_levels <- cat_tot$category
cat_colors <- setNames(colorRampPalette(base_pal)(length(cat_levels)), cat_levels)

combos <- unique(dat_total[, .(isic, category)])
combos[, tot := cat_tot$tot[match(category, cat_tot$category)]]
setorder(combos, isic, -tot)
stack_levels <- paste(combos$isic, combos$category, sep = "|")

build_bench_specs <- function(iso, measure) {
  specs <- list()
  if (!is.null(oecd_bench))
    specs <- c(specs, list(hline_spec(
      oecd_bench[iso3c == iso & strand == measure & year %in% YEARS],
      "bench_usd", "solid", "black")))
  # WB fallback only carries strand == "total", so the strand figures
  # naturally get no line here.  Dashed, to flag the different source.
  if (!is.null(wb_bench))
    specs <- c(specs, list(hline_spec(
      wb_bench[iso3c == iso & strand == measure & year %in% YEARS],
      "bench_usd", "dashed", "black")))
  Filter(Negate(is.null), specs)
}

ref_note_for <- function(measure) {
  if (!is.null(oecd_bench)) {
    paste0(" Black line = OECD SUT T1600 A01+A03 (agriculture + fishery, ",
           "current prices, converted at the same annual-average JPY/USD) ",
           "for this measure — a primary-agriculture (ISIC-A) reference, ",
           "read against the lower sub-stack.")
  } else if (!is.null(wb_bench)) {
    if (measure == "total") {
      paste0(" Dashed black line = World Bank agriculture/forestry/fishery ",
             "value-added (current USD) less its forestry (A02) component ",
             "where script 01's forestry share covers the year — an A01+A03 ",
             "primary-agriculture (ISIC-A) reference, read against the ",
             "lower sub-stack (OECD T1600 has no JPN rows).")
    } else {
      paste0(" (OECD T1600 has no JPN rows and the WB fallback has no ",
             "strand split — no reference line on this figure.)")
    }
  } else {
    " (OECD and WB references unavailable — no reference line.)"
  }
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

message("\nDone.")