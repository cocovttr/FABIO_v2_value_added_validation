# ==============================================================================
# National supply-use / input-output validation — VA agreement against a
# country's own published tables
#
# One validator per national reference table, driven by COUNTRY_SPECS.  Each
# country supplies an ingestion function; everything downstream — the
# output-weighted disaggregation of the FABIOv2 items, the OECD A01+A03
# reference, the metric cascade and the shared scatter panels — is generic.
# Cells are scored at L3 (country x year x industry, components summed) and L4
# (x component); the L1 / L2 cells number one per benchmark year, so no national
# rows are emitted and the industries supply the sample size instead.
#
#   To add a country, write a load_<iso3>() returning
#       conc    list(A =, C =)  per-year concordances, columns
#                               (year, fabio_item_code, code, item)
#       isic    (year, code, item, isic)   one ISIC section per industry
#       va      the raw reference in USD, long over
#               (iso3c, year, code, item, isic, component, value_usd, source)
#       output  (year, code, output_usd)   the disaggregation weights' base
#   and add a spec.  Nothing else in this file needs to change.
#
#   The components are intrinsic to both sides of every comparison: the national
#   table carries them as value-added rows, and GLORIA / COMBINED carry them as
#   the component-split columns written by scripts 14_1 / 14_4
#   (value_added_wages|capital|tls [USD]).  Their sum is the total.
#
#   Disaggregation.  The national classifications are finer than FABIO's, and
#   the mappings are NOT clean: many FABIO items map to several industries each
#   (e.g. FABIO 2511 "Wheat and products" feeds US flour milling 311210,
#   breakfast cereals 311230 AND all-other-food 311990; FABIO 2960 "Grazing"
#   feeds four Japanese grassland/feed sectors in 2020), so a plain join would
#   replicate — and double-count — their value-added.  Instead each FABIO item's
#   VA is SPLIT across its mapped industries proportionally to that industry's
#   total output in the same table and year, so the split sums back to the
#   item's VA exactly (conservation is checked and reported).  Items whose
#   mapped industries all have zero/missing output fall back to an equal split.
#
#   ISIC assignment of the raw national rows is direct: no industry appears at
#   both ISIC levels in these concordances (enforced per country and year), so
#   each industry carries the single level of its concordance rows.  For
#   GLORIA/COMBINED the level is intrinsic — which of the two ISIC-level RDS
#   files the FABIO item came from.  A FABIO ITEM, unlike an industry, routinely
#   appears at both levels (wheat farming / flour milling, dairy farming /
#   cheese manufacturing — around 35 items per concordance).  That is correct
#   and both rows are kept: the two levels read their value added from two
#   different files, so nothing is double-counted, and the C-side processing
#   industries have no other source of mappings.
#
#   OECD reference — table T1600 "Use, Value added and its components by
#   activity" (dataflow OECD.SDD.NAD : DSD_NASU@DF_USEVA_T1600), the same OECD
#   SUT download script 14_4 consumes for its A02 forestry / A03 fishing
#   overlays, staged by FABIO's 00_9_prep_value_added.R — no new download
#   needed.  It sums ISIC divisions A01 (crop & animal production) + A03
#   (fishing & aquaculture); A02 (forestry) is simply NOT in the sum, so the
#   agriculture+fishery total is the FABIO-comparable primary-agriculture
#   figure directly.  Component mapping — IDENTICAL to script 14_4's loader
#   (T1600 publishes the full GVA identity directly):
#       wages   <- D1                  (compensation of employees)
#       capital <- B2A3G (or B2G+B3G)  (gross operating surplus + mixed income)
#       tls     <- D29X39              (other taxes less subsidies on prod.)
#       total   <- B1G  == wages + capital + tls
#   Any SINGLE missing component is recovered from the identity (script 14_4's
#   rule); cells still incomplete are dropped, and an activity dropping out
#   degrades the reference to the remaining divisions (reported).  UNIT_MEASURE
#   "XDC" is national currency, so it passes through the same FX vector as the
#   country's own table.  The USA export is read back by 03; Japan is typically
#   absent from the download, which costs nothing here.
#
# Outputs, per country, under output/<subdir>/:
#   <prefix>_vs_fabio_comparison.csv
#       tidy long table behind everything else
#       (iso3c, year, source, isic, <code column>, category, component,
#       value_usd)
#   metrics_<prefix>.csv
#       agreement of each FABIOv2 variant with the national reference, L3 / L4
#       down the `level` column.
#   <prefix>_by_component_by_year.csv / <prefix>_item_ratios.csv
#       aggregate ratios per (year, ISIC level, source, measure), and the same
#       resolved per industry.
#   fabio_item_to_<prefix>_output_weights.csv
#       diagnostic: the year-specific output weights used to split each FABIO
#       item's VA across its mapped industries.
#   oecd_A01_A03_benchmark.csv
#       the OECD A01+A03 reference — written only where the load succeeded.
#
# and once, across countries:
#   output/national_sut_validation/national_sut_symlog_<source>_<level>.svg
#       the symlog scatter figures, every country on one pair of axes, split
#       into one panel per ISIC section.
#
# Companion to: 01_validation_BioSAMs.R (EU, JRC BioSAMs reference)
# ==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(readxl)
  library(ggplot2)
  library(scales)
  library(useeior)     # provides Detail_Use_SUT_<year>_17sch
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
# the per-country concordances) and receives the validation figures/CSVs. Anchor
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
# element, require_years) was consolidated into faostat_rate_table(path,
# element), which now returns an all-areas data.table (fabio_area_code, year,
# rate_lcu_per_usd). Re-derive the old year-named vector for one area so the
# call sites below are unchanged; require_years hard-fails on any missing year.
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

# FABIOv2 VA outputs (already USD). FOUR variants: the two pure bases written
# by 14_1 (GLORIA / EXIOBASE) and the two synthesis bases written by 14_4
# (COMBINED-GLORIA / COMBINED-EXIOBASE). They live in FABIO's output/value_added/
# (= VA_VALUE_ADDED_OUTPUT_DIR from the config; filenames unchanged). EXIOBASE
# may be absent on a given machine; those sources then drop out rather than fail.
VA_OUTPUT_DIR <- VA_VALUE_ADDED_OUTPUT_DIR
va_path       <- function(base) function(suffix)
  file.path(VA_OUTPUT_DIR,
            sprintf("FABIOv2_%s_value_added_ISIC-%s.rds", base, suffix))

# Source labels -> the RDS family each reads.  Base-grouped to match script 03:
# each base's pure output then its COMBINED (FSDN-overlaid) version.
FABIO_VA_SOURCES <- list(
  `GLORIA-FABIOv2 (disagg.)`            = va_path("GLORIA"),
  `COMBINED-GLORIA-FABIOv2 (disagg.)`   = va_path("COMBINED_GLORIA"),
  `EXIOBASE-FABIOv2 (disagg.)`          = va_path("EXIOBASE"),
  `COMBINED-EXIOBASE-FABIOv2 (disagg.)` = va_path("COMBINED_EXIOBASE"))

# The scored measures: the three components and their sum.
COMPONENTS <- c("wages", "capital", "tls")
MEASURES   <- c("total", COMPONENTS)

# The scatter panels put every country on one pair of axes, so they get their
# own directory rather than any one country's.
NATIONAL_OUT_DIR <- file.path(VALIDATION_OUTPUT_DIR, "national_sut_validation")
dir.create(NATIONAL_OUT_DIR, recursive = TRUE, showWarnings = FALSE)

# OECD reference: the SAME OECD SUT cache the synthesis (14_4) consumes, staged
# by FABIO's 00_9_prep_value_added.R into input/value_added/
# (= VA_VALUE_ADDED_INPUT_DIR), the same path 14_4 reads.
OECD_SUT_PATH <- file.path(VA_VALUE_ADDED_INPUT_DIR, "oecd_sut_use_valueadded.csv")

# ISIC divisions summed: agriculture + fishery, forestry-free by construction
# (A02 simply not in the sum).  A country that does not report a division
# yields no rows for it; the reference then degrades to whatever complete
# divisions remain (reported).
OECD_ACTIVITIES <- c("A01", "A03")

# Dimension filters isolating the VA-by-activity block — IDENTICAL to script
# 14_4's, so the two read the same slice of the file.
OECD_SUT_FILTERS <- list(
  TABLE_IDENTIFIER = "T1600",
  PRODUCT          = "_T",
  PRICE_BASE       = "V",          # current prices
  SECTOR           = "S1",         # total economy (avoid sub-sector double count)
  VALUATION        = "_Z",         # not applicable (VA is valuation-neutral)
  UNIT_MEASURE     = "XDC"         # national currency
)

# Transaction codes for the four VA components — IDENTICAL to script 14_4's
# OECD_SUT_TX: capital is B2A3G directly (T1600 publishes the full GVA
# identity), falling back to B2G + B3G, then to the identity for any SINGLE
# missing component.  D29/D39 are deliberately not split (subsidy-sign
# ambiguity).
OECD_SUT_TX <- c(total = "B1G", wages = "D1", capital = "B2A3G",
                 capital_os = "B2G", capital_mi = "B3G", tls = "D29X39")


# ── Generic: concordances ────────────────────────────────────────────────────

#' Per-(year, industry) ISIC level + canonical label for the raw national rows.
#' An industry at both levels would silently corrupt the comparison, so it is
#' an error rather than a majority vote (unlike the BioSAM concordance, which
#' has no industry dimension to be unambiguous about).
concordance_isic <- function(conc_a, conc_c, where) {
  both <- intersect(conc_a$code, conc_c$code)
  if (length(both) > 0L)
    stop(where, ": industries mapped at BOTH ISIC levels: ",
         paste(both, collapse = ", "), "\n  Resolve them to one level in the ",
         "concordance.")
  rbindlist(list(
    unique(conc_a[, .(code, item)])[, isic := "A"],
    unique(conc_c[, .(code, item)])[, isic := "C"]))
}

#' Both ISIC levels keep every mapping the concordance gives them, including the
#' C row of a FABIO item also tagged at A.  A cross-level item is the normal
#' case here, not an anomaly: 2511 "Wheat and products" is wheat farming at A and
#' flour milling at C, 2848 "Milk - Excluding Butter" is dairy farming at A and
#' cheese manufacturing at C, and so on for ~35 items per concordance.  The two
#' levels draw their value added from two different files (ISIC-A vs ISIC-C), so
#' carrying the item at both double-counts nothing, and a FABIO item feeding
#' several industries WITHIN a level is exactly what build_split_weights()
#' exists to apportion.  An earlier version dropped the C row of any item also
#' tagged at A; because concordance_isic() is built from the filtered C table and
#' `cols` then selects which reference rows to read, that silently removed 12-14
#' processing industries per country from BOTH sides of the comparison (US flour
#' milling, cheese, canning, seafood, tobacco, fiber mills; Japan's five seafood
#' sectors, grain milling, condiments, tobacco, fiber yarns) and stripped part of
#' the mapping from several more (Dairy farm products, Tea and roasted coffee,
#' Starch, Wet corn milling, Fluid milk and butter).  No filter is applied now.
#' The one thing that WOULD corrupt the comparison — an industry appearing at
#' both ISIC levels — is caught by concordance_isic() below.


# ── Generic: output-weighted disaggregation ──────────────────────────────────

#' Year-specific weight table for one ISIC level: for each (year,
#' fabio_item_code), the share of each mapped industry in the summed output of
#' ALL its mapped industries.  Items whose mapped industries all have
#' zero/missing output fall back to an EQUAL split.  Weights sum to 1 per
#' (year, item) by construction, so splitting VA by them conserves the item
#' total exactly — no duplication.  Where a mapping is 1:1 every weight is 1
#' and the code is a no-op.
build_split_weights <- function(conc_by_year, out_tbl, isic_level, years) {
  w <- rbindlist(lapply(years, function(yr) {
    conc <- conc_by_year[[as.character(yr)]]
    if (is.null(conc) || nrow(conc) == 0L) return(NULL)
    merge(conc[, .(fabio_item_code, code, item)], out_tbl[year == yr],
          by = "code", allow.cartesian = TRUE)
  }))
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
  w[, .(year, isic, fabio_item_code, code, item, output_usd, weight)]
}

#' GLORIA / COMBINED: melt the component columns of one ISIC level's VA RDS
#' (this country's rows, benchmark years), split each FABIO item's component VA
#' across its mapped industries by the output weights, and aggregate to (year,
#' industry, component).  The mapped item set is year-specific, so conservation
#' (post-split total == pre-split total of the mapped cells) is checked per
#' level and reported.
build_fabio_source <- function(source_label, va_path_fun, weights_a, weights_c,
                               iso3, years) {
  component_cols <- c(wages   = "value_added_wages [USD]",
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
    miss <- setdiff(unname(component_cols), names(raw))
    if (length(miss))
      stop("VA file ", path, " is missing component column(s): ",
           paste(miss, collapse = ", "), ".\n  The metrics need the ",
           "COMPONENT-SPLIT output of scripts 14_1 / 14_4 (value_added_wages|",
           "capital|tls [USD]).  Re-run those to generate it.")
    va <- raw[iso3c == iso3 & year %in% years,
              .(iso3c           = as.character(iso3c),
                year            = as.integer(year),
                fabio_item_code = as.integer(fabio_item_code),
                wages           = `value_added_wages [USD]`,
                capital         = `value_added_capital [USD]`,
                tls             = `value_added_tls [USD]`)]
    if (!nrow(va)) {
      message("  NOTE: ", source_label, " ISIC-", suffix, " has no ", iso3,
              " rows for ", paste(years, collapse = "/"), ".")
      return(NULL)
    }
    va <- melt(va, id.vars = c("iso3c", "year", "fabio_item_code"),
               measure.vars = names(component_cols),
               variable.name = "component", value.name = "value_usd")
    va[, component := as.character(component)]
    
    mapped  <- unique(weights[, .(year, fabio_item_code)])
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
      "  %s ISIC-%s: %s USD across %d mapped (year, item) cell(s) split onto %d industries (conserved).",
      source_label, suffix,
      label_number(scale_cut = cut_short_scale())(pre_tot),
      nrow(mapped), uniqueN(out$code)))
    
    out[, .(value_usd = sum(value_usd, na.rm = TRUE)),
        by = .(iso3c, year, code, item, component)][, isic := suffix][]
  }
  res <- rbindlist(list(one_level("A", weights_a),
                        one_level("C", weights_c)),
                   use.names = TRUE, fill = TRUE)
  if (nrow(res)) res[, source := source_label]
  res
}


# ── Generic: OECD SUT A01+A03 reference ──────────────────────────────────────
#
# Specialization of script 14_4's load_oecd_sut_activity() to one REF_AREA:
# same file, same dimension filters, same transaction codes and component
# construction, run per activity in OECD_ACTIVITIES and summed across them.
# Only (activity, year) cells with all four components finite AFTER identity
# recovery enter the sum (script 14_4's completeness rule).  `lcu_per_usd` is
# the same year -> rate vector the country's own table uses, since XDC is
# national currency.  Returns a long (iso3c, year, component, bench_usd) table,
# or NULL (with a message) when the file is missing or the country is absent.
load_oecd_benchmark <- function(iso3, years, lcu_per_usd,
                                path = OECD_SUT_PATH,
                                activities = OECD_ACTIVITIES) {
  if (!file.exists(path)) {
    message("NOTE: OECD SUT CSV not found at\n  ", path,
            "\n  The A01+A03 export will be skipped.  Run ",
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
            " — is this the crafting.R download?  Export skipped.")
    return(NULL)
  }
  
  s <- s[TABLE_IDENTIFIER == OECD_SUT_FILTERS$TABLE_IDENTIFIER &
           PRODUCT      == OECD_SUT_FILTERS$PRODUCT       &
           PRICE_BASE   == OECD_SUT_FILTERS$PRICE_BASE    &
           SECTOR       == OECD_SUT_FILTERS$SECTOR        &
           VALUATION    == OECD_SUT_FILTERS$VALUATION     &
           UNIT_MEASURE == OECD_SUT_FILTERS$UNIT_MEASURE  &
           trimws(as.character(REF_AREA)) == iso3         &
           ACTIVITY %in% activities]
  if (nrow(s) == 0L) {
    message("NOTE: no OECD SUT rows for ", iso3, " x {",
            paste(activities, collapse = ", "), "} after filtering — the ",
            "country may not report these divisions in T1600.  Export skipped.")
    return(NULL)
  }
  
  # National-currency absolute value; UNIT_MULT is a power of ten (millions = 6).
  s[, `:=`(value_lcu = suppressWarnings(as.numeric(OBS_VALUE)) *
             10^suppressWarnings(as.integer(UNIT_MULT)),
           year = as.integer(substr(trimws(as.character(TIME_PERIOD)), 1, 4)))]
  s <- s[is.finite(value_lcu) & year %in% years]
  s[, value_usd := value_lcu / lcu_per_usd[as.character(year)]]
  s <- s[is.finite(value_usd)]
  if (nrow(s) == 0L) {
    message("NOTE: no finite OECD SUT values for ", iso3, " in ",
            paste(years, collapse = "/"), " — export skipped.")
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
  
  # Recover one missing component from the identity B1G = D1 + B2A3G + D29X39
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
      "  OECD SUT GVA identity (%s %s): max |residual| = %.2e (rel) over %d cell(s).",
      iso3, paste(activities, collapse = "+"), max(rr, na.rm = TRUE), nrow(full)))
  }
  
  n_pre <- nrow(w)
  w <- w[is.finite(wages) & is.finite(capital) &
           is.finite(tls) & is.finite(total)]
  if (nrow(w) < n_pre)
    message(sprintf("  %d OECD SUT cell(s) dropped for incomplete VA components.",
                    n_pre - nrow(w)))
  if (nrow(w) == 0L) {
    message("NOTE: no complete OECD SUT cells left for ", iso3,
            " — export skipped.")
    return(NULL)
  }
  kept <- w[, sort(unique(activity))]
  if (!setequal(kept, activities))
    message("  OECD reference degrades to activity set {",
            paste(kept, collapse = ", "), "} (incomplete divisions dropped).")
  
  out <- w[, .(wages = sum(wages), capital = sum(capital),
               tls = sum(tls), total = sum(total)), by = year]
  out[, iso3c := iso3]
  long <- melt(out, id.vars = c("iso3c", "year"),
               measure.vars = c("wages", "capital", "tls", "total"),
               variable.name = "component", value.name = "bench_usd")
  long[, component := as.character(component)]
  long[is.finite(bench_usd)]
}


# ── USA: BEA Detail Use (SUT) tables from useeior ────────────────────────────
#
# Reference data on the 2017 NAICS schema, so the two years are directly
# comparable.  Industry columns are BEA detail codes (e.g. 1111A0, 311210) —
# the SAME codes the concordance's USA_SUT_code column uses, so no re-coding is
# needed (validated below; a trailing "/US" suffix, if a useeior build carries
# one, is stripped).  Values are MILLION USD.  XDC is USD for the USA, so the
# FX vector is 1 and the OECD reference needs no conversion.

USA_CONC_PATH <- file.path(VALIDATION_CONC_DIR,
                           "concordance_items_usa_sut_fabio.csv")
USE_TABLE_OBJECTS <- c(`2012` = "Detail_Use_SUT_2012_17sch",
                       `2017` = "Detail_Use_SUT_2017_17sch")

# BEA Use-table row codes: the three VA component rows, their total, and the
# total-industry-output row used for the disaggregation weights.
SUT_ROW_TO_COMPONENT <- c(V00100 = "wages", T00OTOP = "tls",
                          V00300 = "capital")
SUT_VA_TOTAL_ROW     <- "VABAS"   # identity check only
SUT_OUTPUT_ROW       <- "T018"    # total industry output (basic) -> weights
SUT_MILLIONS         <- 1e6       # BEA tables are in million USD

#' Fetch one useeior Detail_Use_SUT object by name, as a numeric matrix with
#' NA -> 0 and any "/US" location suffix stripped from the dimnames.
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

load_usa <- function(years) {
  conc_a <- load_item_conc(USA_CONC_PATH, "A", "USA_SUT_code", "USA_SUT_item",
                           out_code = "code", out_item = "item",
                           keep_code_class_char = FALSE)
  conc_c <- load_item_conc(USA_CONC_PATH, "C", "USA_SUT_code", "USA_SUT_item",
                           out_code = "code", out_item = "item",
                           keep_code_class_char = FALSE)
  isic <- concordance_isic(conc_a, conc_c, "USA")
  message(sprintf(
    "  %d ISIC-A and %d ISIC-C item mappings onto %d SUT industries (%d A / %d C).",
    nrow(conc_a), nrow(conc_c), nrow(isic),
    sum(isic$isic == "A"), sum(isic$isic == "C")))
  
  message("  Loading useeior Use (SUT) tables ...")
  tables <- setNames(lapply(USE_TABLE_OBJECTS, load_use_table),
                     names(USE_TABLE_OBJECTS))
  
  cols <- isic$code
  per_year <- lapply(years, function(yr) {
    m <- tables[[as.character(yr)]]
    need_rows <- c(names(SUT_ROW_TO_COMPONENT), SUT_VA_TOTAL_ROW,
                   SUT_OUTPUT_ROW)
    miss_rows <- setdiff(need_rows, rownames(m))
    if (length(miss_rows) > 0L)
      stop("Use table for ", yr, " is missing row(s): ",
           paste(miss_rows, collapse = ", "))
    miss_cols <- setdiff(cols, colnames(m))
    if (length(miss_cols) > 0L)
      stop("Use table for ", yr, " has no industry column for mapped SUT ",
           "code(s): ", paste(miss_cols, collapse = ", "),
           "\n  Either the concordance codes or the useeior schema changed.")
    
    va  <- m[names(SUT_ROW_TO_COMPONENT), cols, drop = FALSE]
    # Identity check (tolerance: $1m absolute or 0.1% relative per column).
    tot <- m[SUT_VA_TOTAL_ROW, cols]
    bad <- abs(colSums(va) - tot) > pmax(1, 0.001 * abs(tot))
    if (any(bad))
      warning("Year ", yr, ": component identity V00100+T00OTOP+V00300 != ",
              "VABAS for: ", paste(cols[bad], collapse = ", "))
    
    long <- as.data.table(as.table(va))
    setnames(long, c("row_code", "code", "value"))
    long[, `:=`(iso3c     = "USA",
                year      = as.integer(yr),
                component = unname(SUT_ROW_TO_COMPONENT[as.character(row_code)]),
                value_usd = as.numeric(value) * SUT_MILLIONS)]
    list(va = long[, .(iso3c, year, code, component, value_usd)],
         output = data.table(year = as.integer(yr), code = cols,
                             output_usd = as.numeric(m[SUT_OUTPUT_ROW, cols]) *
                               SUT_MILLIONS))
  })
  
  va <- isic[rbindlist(lapply(per_year, `[[`, "va")), on = "code",
             nomatch = NULL]
  va[, source := "US SUT (BEA)"]
  list(
    # The US concordance is not year-specific; replicating it per year lets the
    # generic weighting code treat every country the same way.
    conc = list(
      A = setNames(rep(list(conc_a), length(years)), as.character(years)),
      C = setNames(rep(list(conc_c), length(years)), as.character(years))),
    isic   = isic,
    va     = va[, .(iso3c, year, code, item, isic, component, value_usd,
                    source)],
    output = rbindlist(lapply(per_year, `[[`, "output")))
}


# ── Japan: e-Stat Input Table workbooks ──────────────────────────────────────
#
# The Input Tables (basic sector, English edition) carry the VA components as
# component rows, the published GVA as row 9600000 and domestic production as
# row 9700000 — the output tables are NOT needed.  Each workbook is a LONG
# table (Column Code | Row Code | ... | Producers Price); row 1 is the sheet
# title, row 2 the header, and columns are taken by POSITION because the 2011
# header misspells "Producers Price".  The classification changes between
# benchmarks (397 / 391 / 391 industry columns), so the concordances are
# per-year; sectors are keyed by LABEL, since labels are stable across years
# while codes occasionally are not.

JPN_IOT_DIR   <- validation_path("input", "Japan_IOTs")
JPN_IOT_PATH  <- function(yr) file.path(JPN_IOT_DIR,
                                        sprintf("Japan_%d_input_table.xlsx", yr))
JPN_CONC_PATH <- function(yr) file.path(
  VALIDATION_CONC_DIR, sprintf("concordance_items_japan_iot%d_fabio.csv", yr))

# Yen unit of each workbook's Producers Price column: the 2011 and 2015 tables
# are published in MILLION yen, the 2020 table in BILLION yen (domestic
# production totals 939,674,856 m / 1,017,818,388 m / 1,026,154 bn yen
# respectively — verified at load time against row 9700000, column 970000).
JPY_UNIT <- c(`2011` = 1e6, `2015` = 1e6, `2020` = 1e9)

# JPY -> USD: Japan's SLC row from the FAOSTAT exchange-rate file (same file,
# loader and direction as script 14_4).  The SLC element carries one annual
# row per country; the LCU element also has monthly rows.
JPN_AREA_CODE <- 110L   # not in the config (only Germany is named there)

# Add consumption expenditure outside households (rows 7111001-003, a
# quasi-labour cost that is part of GVA in the Japanese tables) to WAGES.
# Either way it stays inside TOTAL, so only the wages/total split — never the
# GVA identity — depends on this flag.
INCLUDE_CEOH <- TRUE

IOT_ROW_TO_COMPONENT <- c(`9111000` = "wages", `9112000` = "wages",
                          `9113000` = "wages",
                          `9211000` = "capital", `9311000` = "capital",
                          `9321000` = "capital",
                          `9411000` = "tls", `9511000` = "tls")
IOT_CEOH_ROWS    <- c("7111001", "7111002", "7111003")
IOT_VA_TOTAL_ROW <- "9600000"   # gross value added — identity check only
IOT_OUTPUT_ROW   <- "9700000"   # domestic production -> weights
IOT_TOTAL_COLS   <- c("700000", "970000")  # all-industry / grand-total columns

#' Read one year's Input Table workbook into a long (col_code, row_code,
#' value_jpy) table, keeping only the VA / CEOH / GVA / production rows.
load_iot_table <- function(yr) {
  path <- JPN_IOT_PATH(yr)
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
  keep_rows <- c(names(IOT_ROW_TO_COMPONENT), IOT_CEOH_ROWS,
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

load_jpn <- function(years) {
  read_conc <- function(yr, lvl)
    load_item_conc(JPN_CONC_PATH(yr), lvl,
                   sprintf("JPN_IOT%d_code", yr), sprintf("JPN_IOT%d_item", yr),
                   out_code = "code", out_item = "item",
                   keep_code_class_char = FALSE)
  conc_a <- setNames(lapply(years, read_conc, lvl = "A"), as.character(years))
  conc_c <- setNames(lapply(years, read_conc, lvl = "C"), as.character(years))
  isic <- rbindlist(lapply(years, function(yr) {
    x <- concordance_isic(conc_a[[as.character(yr)]],
                          conc_c[[as.character(yr)]], paste("JPN", yr))
    x[, year := as.integer(yr)][]
  }))
  for (yr in years)
    message(sprintf(
      "  %d: %d ISIC-A and %d ISIC-C item mappings onto %d IOT sectors (%d A / %d C).",
      yr, nrow(conc_a[[as.character(yr)]]), nrow(conc_c[[as.character(yr)]]),
      nrow(isic[year == yr]), isic[year == yr, sum(isic == "A")],
      isic[year == yr, sum(isic == "C")]))
  
  message("  Loading Japan Input Tables ...")
  jpy_per_usd <- faostat_rate_vector(VA_EXCHANGE_RATE_CSV, JPN_AREA_CODE,
                                     element = VA_FX_ELEMENT_CODE,
                                     require_years = years)
  tables <- setNames(lapply(years, load_iot_table), as.character(years))
  
  per_year <- lapply(years, function(yr) {
    dt     <- tables[[as.character(yr)]]
    codes  <- isic[year == yr, code]
    to_usd <- JPY_UNIT[[as.character(yr)]] / jpy_per_usd[[as.character(yr)]]
    
    miss_rows <- setdiff(c(names(IOT_ROW_TO_COMPONENT), IOT_VA_TOTAL_ROW,
                           IOT_OUTPUT_ROW), unique(dt$row_code))
    if (length(miss_rows) > 0L)
      stop("Input Table for ", yr, " is missing row(s): ",
           paste(miss_rows, collapse = ", "))
    miss_cols <- setdiff(codes, unique(dt$col_code))
    if (length(miss_cols) > 0L)
      stop("Input Table for ", yr, " has no industry column for mapped IOT ",
           "code(s): ", paste(miss_cols, collapse = ", "),
           "\n  Either the concordance codes or the e-Stat layout changed.")
    
    sec <- dt[col_code %in% codes]
    # CEOH is routed into wages (or dropped from the components but NOT from the
    # identity check) per INCLUDE_CEOH.
    sec[, component := IOT_ROW_TO_COMPONENT[row_code]]
    sec[row_code %in% IOT_CEOH_ROWS,
        component := if (INCLUDE_CEOH) "wages" else "ceoh_excluded"]
    
    # Per-sector GVA identity: components must reproduce row 9600000 within
    # rounding of the source's last published digit.
    comp <- sec[!row_code %in% c(IOT_VA_TOTAL_ROW, IOT_OUTPUT_ROW),
                .(components_jpy = sum(value_jpy)), by = col_code]
    pub  <- sec[row_code == IOT_VA_TOTAL_ROW, .(col_code, gva_jpy = value_jpy)]
    chk  <- merge(comp, pub, by = "col_code")
    tol  <- if (JPY_UNIT[[as.character(yr)]] >= 1e9) 0.5 else 2  # last digit
    bad  <- chk[abs(components_jpy - gva_jpy) > pmax(tol, 1e-4 * abs(gva_jpy))]
    if (nrow(bad) > 0L)
      warning("Year ", yr, ": GVA identity (CEOH+wages+capital+tls != ",
              "9600000) fails for: ", paste(bad$col_code, collapse = ", "))
    message(sprintf(
      "  %d: GVA identity max |dev| = %s yen over %d mapped sector(s).",
      yr, format(chk[, max(abs(components_jpy - gva_jpy))] *
                   JPY_UNIT[[as.character(yr)]], big.mark = ","), nrow(chk)))
    
    out <- sec[row_code == IOT_OUTPUT_ROW,
               .(code = col_code, output_usd = value_jpy * to_usd)]
    miss <- setdiff(codes, out$code)
    if (length(miss) > 0L)
      out <- rbind(out, data.table(code = miss, output_usd = 0))
    
    list(va = sec[component %in% COMPONENTS,
                  .(iso3c = "JPN", year = as.integer(yr),
                    value_usd = sum(value_jpy) * to_usd),
                  by = .(code = col_code, component)],
         output = out[, .(year = as.integer(yr), code, output_usd)])
  })
  
  va <- isic[rbindlist(lapply(per_year, `[[`, "va")),
             on = c("year", "code"), nomatch = NULL]
  va[, source := "Japan IOT (MIC)"]
  list(conc   = list(A = conc_a, C = conc_c),
       isic   = isic,
       va     = va[, .(iso3c, year, code, item, isic, component, value_usd,
                       source)],
       output = rbindlist(lapply(per_year, `[[`, "output")),
       fx     = jpy_per_usd)
}


# ── The countries ────────────────────────────────────────────────────────────
#
# `fx` is the year -> national-currency-per-USD vector the OECD T1600 rows pass
# through; the country's own table has already been converted by its loader.

COUNTRY_SPECS <- list(
  list(iso3       = "USA",
       years      = c(2012L, 2017L),
       reference  = "US SUT (BEA)",
       subdir     = "usa_sut_validation",
       prefix     = "usa_sut",
       code_col   = "usa_sut_code",
       load       = load_usa,
       fx         = function(ing, years)
         setNames(rep(1, length(years)), as.character(years))),
  list(iso3       = "JPN",
       years      = c(2011L, 2015L, 2020L),
       reference  = "Japan IOT (MIC)",
       subdir     = "japan_iot_validation",
       prefix     = "japan_iot",
       code_col   = "jpn_iot_code",
       load       = load_jpn,
       fx         = function(ing, years) ing$fx))


# ── Driver ───────────────────────────────────────────────────────────────────

#' Ingest one country, disaggregate the FABIOv2 sources onto its industries,
#' and write its comparison table, metrics, ratio frames and OECD export.
#' Returns the comparison table for the shared scatter panels.
run_country <- function(spec) {
  message("\n=== ", spec$iso3, " (", spec$reference, ") ===")
  out_dir <- file.path(VALIDATION_OUTPUT_DIR, spec$subdir)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  
  ing       <- spec$load(spec$years)
  weights_a <- build_split_weights(ing$conc$A, ing$output, "A", spec$years)
  weights_c <- build_split_weights(ing$conc$C, ing$output, "C", spec$years)
  fwrite(rbindlist(list(weights_a, weights_c)),
         file.path(out_dir,
                   sprintf("fabio_item_to_%s_output_weights.csv", spec$prefix)))
  
  fabio <- lapply(names(FABIO_VA_SOURCES), function(lab)
    build_fabio_source(lab, FABIO_VA_SOURCES[[lab]], weights_a, weights_c,
                       spec$iso3, spec$years))
  
  dat_all <- rbindlist(c(list(ing$va), fabio), use.names = TRUE, fill = TRUE)[
    , .(iso3c, year, source, isic, code, category = item, component, value_usd)]
  dat_all <- dat_all[is.finite(value_usd)]
  
  # Keep only the sources that actually produced rows, in the canonical order —
  # a machine without the EXIOBASE pipeline still scores the GLORIA pair.
  sources <- intersect(c(spec$reference, names(FABIO_VA_SOURCES)),
                       unique(dat_all$source))
  fab     <- setdiff(sources, spec$reference)
  
  comparison <- copy(dat_all)
  setnames(comparison, "code", spec$code_col)
  comparison_path <- file.path(out_dir,
                               sprintf("%s_vs_fabio_comparison.csv", spec$prefix))
  fwrite(comparison, comparison_path)
  message("Comparison table -> ", comparison_path)
  
  oecd <- load_oecd_benchmark(spec$iso3, spec$years, spec$fx(ing, spec$years))
  if (!is.null(oecd)) {
    oecd_path <- file.path(out_dir, "oecd_A01_A03_benchmark.csv")
    fwrite(oecd, oecd_path)
    message("OECD reference -> ", oecd_path)
  }
  
  # L3 / L4 only: the L1 / L2 cells number one per benchmark year, and a
  # per-item breakout would too, so the industries are the sample here.
  matched <- va_matched_levels(dat_all, spec$reference, c("L3", "L4"))
  metrics <- va_metrics_table(matched, fab)
  metrics_path <- file.path(out_dir, sprintf("metrics_%s.csv", spec$prefix))
  fwrite(metrics, metrics_path, na = "NA")
  message("Metrics -> ", metrics_path)
  print(metrics)
  
  va_write_ratio_frames(dat_all, spec$reference, sources, out_dir, spec$prefix)
  
  invisible(list(dat = dat_all, reference = spec$reference, sources = fab))
}


# ============================================================================
# RUN
# ============================================================================

national <- lapply(COUNTRY_SPECS, run_country)

message("\nBuilding shared symlog scatter panels ...")
LEVELS  <- c("L3", "L4")
matched <- setNames(lapply(LEVELS, function(lv)
  rbindlist(lapply(national, function(x)
    va_match_source(va_level_cells(x$dat, lv), x$reference)),
    use.names = TRUE)), LEVELS)

va_write_symlog_plots(
  matched,
  sources      = Reduce(union, lapply(national, `[[`, "sources")),
  out_dir      = NATIONAL_OUT_DIR,
  prefix       = "national_sut",
  dataset      = paste(vapply(COUNTRY_SPECS, `[[`, character(1), "iso3"),
                       collapse = " + "),
  reference    = "National SUT / IOT",
  fill_country = TRUE)

message("\nDone.")