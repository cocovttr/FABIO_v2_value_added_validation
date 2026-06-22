# ==============================================================================
# 00_validation_helpers.R — small shared helpers for the FABIO value-added
#                           VALIDATION scripts (02_BioSAMs, 03_USA_SUTs,
#                           04_Japan_IOTs).
#
# Why this file exists
# --------------------
# When the value-added pipeline was folded into FABIO, the *data* helpers the
# validators use (load_item_conc, load_area_conc, faostat_rate_table,
# read_faostat_exchange_long) were kept in R/00_value_added_helpers.R. The
# *plotting / path-closure* helpers were deliberately dropped from that file
# (see its header: "removed plotting / path-closure helpers") because the
# validators moved to their own repo. hline_spec() is the one such helper the
# validators still call — its definition went with the deleted local helper.
# This file restores it. The data helpers are NOT redefined here; they still
# come from the pipeline helper.
#
# How to load it
# --------------
# 02 / 03 / 04 source this right after sourcing the FABIO value-added config,
# via the validation-repo anchor so it resolves regardless of working directory:
#     source(validation_path("00_validation_helpers.R"))
# (The data helpers — load_item_conc etc. — come from the pipeline's
# R/00_value_added_helpers.R, which the config sources; they are NOT redefined
# here.) 01 does not use hline_spec and so does not source this file.
#
# Base R only — no extra dependencies.
# ==============================================================================

#' Build one horizontal benchmark-line spec for make_country_chart().
#'
#' Call sites (02/03/04, inside build_bench_specs()):
#'   hline_spec(bench[iso3c == iso & strand == measure & year %in% YEARS],
#'              "bench_usd", "solid",  "black")   # OECD / Eurostat
#'   hline_spec(wb_bench[...],          "bench_usd", "dashed", "black")  # WB fb
#'
#' Consumer contract (make_country_chart):
#'   bench_vals <- unlist(lapply(bench_specs, function(s) s$data$yintercept))
#'   for (s in bench_specs)
#'     p <- p + geom_hline(data = s$data, aes(yintercept = yintercept),
#'                         inherit.aes = FALSE, linetype = s$linetype,
#'                         linewidth = s$linewidth, colour = s$colour)
#' so each spec must expose $data (a data.frame with `year` + `yintercept`,
#' one row per faceted year), $linetype, $linewidth and $colour.
#'
#' @param df        benchmark rows ALREADY filtered to one iso3c + one strand +
#'                  the plotted YEARS. Needs a `year` column (the facet var) and
#'                  the value column named by `value_col`. May be empty / NULL.
#' @param value_col name of the column holding the line's y position
#'                  (the benchmark loaders write "bench_usd").
#' @param linetype  ggplot2 linetype (callers pass "solid", or "dashed" for the
#'                  World-Bank fallback line). Required, no default.
#' @param colour    line colour (callers pass "black"). Required, no default.
#' @param linewidth line width (default 0.45).
#' @param years     factor levels to pin `year` to, so the line maps to the same
#'                  facet panels the chart uses (it builds factor(year, YEARS)).
#'                  Defaults to the script-level YEARS via get0().
#'
#' @return NULL when there is nothing to draw (no rows, or every value is
#'   NA / non-finite) — the callers wrap this in Filter(Negate(is.null), ...),
#'   so a NULL simply omits the line and the figure is still produced (the same
#'   graceful degradation the scripts document when a benchmark is unavailable).
#'   Otherwise a list(data, linetype, colour, linewidth) as described above.
hline_spec <- function(df, value_col, linetype, colour, linewidth = 0.45,
                       years = get0("YEARS", ifnotfound = NULL)) {
  if (is.null(df)) return(NULL)
  d <- as.data.frame(df)
  if (!nrow(d) || !value_col %in% names(d)) return(NULL)
  d$yintercept <- d[[value_col]]
  d <- d[is.finite(d$yintercept), , drop = FALSE]
  if (!nrow(d)) return(NULL)
  # The chart builds its facet variable as factor(year, levels = YEARS), so the
  # benchmark line's `year` must be the SAME factor or geom_hline won't land in
  # the right year panel. `years` defaults to the script-level YEARS.
  if (!is.null(years)) d$year <- factor(d$year, levels = years)
  list(data = d[, c("year", "yintercept")],
       linetype = linetype, colour = colour, linewidth = linewidth)
}

# ==============================================================================
# Agreement scoring for the reference-comparison validators (03 / 04).
#
# Why this lives here now
# -----------------------
# 02_validation_BioSAMs.R grew an inline metrics layer (aggregate_measures /
# agreement_row / score_against) that turns a long (iso3c, year, source, isic,
# category, strand, value_usd) comparison table into tidy metric CSVs — med
# ratio, RMSLE (dex), within-2x, plus sign-robust columns for the net-signed
# TLS strand.  03 (USA SUTs) and 04 (Japan IOTs) report the SAME statistics in
# the thesis text but previously wrote only the raw comparison CSV, so the
# numbers cited there had to be read back off the figures.  These helpers let
# 03 / 04 emit the metrics directly, in the BioSAM idiom.
#
# Difference from 02's inline copy: one extra dispersion column, `med_abs_dex`
# = median|log10(ratio)| (the "median absolute residual in dex"), reported
# alongside the RMSLE because the USA item-level comparison is summarised with
# the median-absolute residual rather than the RMSLE.  02 is untouched and
# keeps its own inline definitions; nothing here overrides them.
#
# Requires data.table (loaded by 03 / 04) and two globals the caller defines:
#   STRANDS  = c("wages","capital","tls")
#   MEASURES = c("total", STRANDS)
# ==============================================================================

#' Collapse a long source table to one value per (`group_keys`, strand) within
#' an ISIC scope, appending a derived `total` strand summing the strands present
#' in each cell.  `group_keys` always begins with iso3c/year/source and may add
#' `isic` and/or `category` depending on the granularity the caller wants
#' (national totals, per-ISIC, or per-item).  A strand absent from a cell counts
#' as zero in that cell's total.
va_aggregate <- function(dat, group_keys) {
  stopifnot(all(c(STRANDS, MEASURES) %in% c("total", STRANDS)))
  s <- dat[is.finite(value_usd),
           .(value_usd = sum(value_usd, na.rm = TRUE)),
           by = c(group_keys, "strand")]
  w <- data.table::dcast(
    s, stats::as.formula(paste(paste(group_keys, collapse = " + "), "~ strand")),
    value.var = "value_usd")
  for (col in STRANDS) if (!col %in% names(w)) w[, (col) := NA_real_]
  w[, total := rowSums(.SD, na.rm = TRUE), .SDcols = STRANDS]
  long <- data.table::melt(w, id.vars = group_keys, measure.vars = MEASURES,
                           variable.name = "strand", value.name = "value_usd")
  long[, strand := as.character(strand)][is.finite(value_usd)]
}

#' One metric row for a single (measure, source).  `ok_all` holds that pair's
#' matched cells with columns `src` (source value) and `ref` (reference value).
#' n counts cells finite on both sides with a non-zero reference.  tls is scored
#' sign-robustly (sign agreement + magnitude ratio); the positive measures
#' (total / wages / capital) on cells positive on both sides.  Dispersion is
#' reported three ways so any of the thesis conventions is reproducible:
#'   bias_dex    = median(log10 ratio)        signed central tendency
#'   med_abs_dex = median|log10 ratio|        median absolute residual
#'   RMSLE_dex   = sqrt(mean(log10 ratio^2))  root-mean-square log error
va_agreement_row <- function(ok_all, measure, source_label) {
  ok  <- ok_all[is.finite(src) & is.finite(ref) & ref != 0]
  out <- data.table::data.table(
    measure = measure, source = source_label, n = nrow(ok),
    med_ratio = NA_real_, bias_dex = NA_real_, med_abs_dex = NA_real_,
    RMSLE_dex = NA_real_, within_2x = NA_real_,
    sign_agree = NA_real_, med_ratio_mag = NA_real_)
  if (measure == "tls") {
    if (nrow(ok))
      out[, sign_agree := mean(sign(ok$src) == sign(ok$ref))]
    sm <- ok[src != 0 & sign(src) == sign(ref)]
    if (nrow(sm)) {
      r <- abs(sm$src) / abs(sm$ref)
      out[, `:=`(med_ratio_mag = stats::median(r),
                 med_abs_dex   = stats::median(abs(log10(r))),
                 RMSLE_dex     = sqrt(mean(log10(r)^2)))]
    }
  } else {
    pos <- ok[src > 0 & ref > 0]
    if (nrow(pos) >= 3L) {
      r <- pos$src / pos$ref
      out[, `:=`(med_ratio   = stats::median(r),
                 bias_dex    = stats::median(log10(r)),
                 med_abs_dex = stats::median(abs(log10(r))),
                 RMSLE_dex   = sqrt(mean(log10(r)^2)),
                 within_2x   = mean(r >= 0.5 & r <= 2))]
    }
  }
  out[]
}

#' Pooled agreement metrics.  `cmp` is an already-merged table carrying columns
#' `source`, `strand`, `src`, `ref` (and, if `report_col` is given, that column
#' too).  Returns one row per (measure, source), or per (`report_col`, measure,
#' source) when `report_col` is set — e.g. report_col = "isic" gives separate
#' ISIC-A and ISIC-C blocks.  Cells are pooled across whatever else is in `cmp`
#' (typically item x year).
va_score <- function(cmp, sources, report_col = NULL) {
  grp <- if (is.null(report_col)) NA_character_ else sort(unique(cmp[[report_col]]))
  res <- data.table::rbindlist(lapply(grp, function(g) {
    cg  <- if (is.null(report_col)) cmp else cmp[get(report_col) == g]
    out <- data.table::rbindlist(lapply(MEASURES, function(m)
      data.table::rbindlist(lapply(sources, function(s)
        va_agreement_row(cg[strand == m & source == s], m, s)))))
    if (!is.null(report_col)) out[, (report_col) := g]
    out
  }))
  if (!is.null(report_col))
    data.table::setcolorder(res, c(report_col, setdiff(names(res), report_col)))
  res[]
}

#' Convenience wrapper used by 03 / 04.  Given the long comparison table `dat`
#' (cols iso3c, year, source, isic, category, strand, value_usd), the reference
#' source label, and the source labels to score, write three CSVs into `out_dir`
#' under the given `prefix`, and return them invisibly as a named list:
#'
#'   <prefix>_by_strand_by_year.csv  AGGREGATE ratio per (isic, year, source,
#'       measure): source_usd, ref_usd, ratio.  ratio keeps its sign, so the net
#'       TLS strand shows up signed.  Reproduces the per-year totals, the
#'       per-year strand ratios, and (Japan) the per-year capture shares.
#'   <prefix>_item_ratios.csv        the PRE-AGGREGATION frame: AGGREGATE ratio
#'       per (isic, category, year, source, measure).  One row per mapped item x
#'       year x source; reproduces any single-item or per-year item ratio.
#'   metrics_<prefix>_pooled_items.csv  per (isic, source, measure): pooled
#'       item-level metrics (n, med_ratio, bias/med_abs/RMSLE dex, within_2x,
#'       and the sign columns for TLS), pooling item x year cells.
#'
#' All ratios are source / reference.  NAs are written explicitly.
write_reference_metrics <- function(dat, reference, sources, out_dir, prefix) {
  ref_lab <- reference
  fab     <- setdiff(sources, ref_lab)
  
  ## (1) aggregate by (isic, year[, category]) -------------------------------
  agg_src  <- va_aggregate(dat[source %in% fab],     c("iso3c","year","isic","source"))
  agg_ref  <- va_aggregate(dat[source == ref_lab],   c("iso3c","year","isic"))
  by_year  <- merge(agg_src,
                    agg_ref[, .(iso3c, year, isic, strand, ref_usd = value_usd)],
                    by = c("iso3c","year","isic","strand"))
  data.table::setnames(by_year, "value_usd", "source_usd")
  by_year[, ratio := source_usd / ref_usd]
  data.table::setnames(by_year, "strand", "measure")
  data.table::setcolorder(by_year,
                          c("iso3c","year","isic","source","measure","source_usd","ref_usd","ratio"))
  data.table::setorder(by_year, isic, source, measure, year)
  p1 <- file.path(out_dir, paste0(prefix, "_by_strand_by_year.csv"))
  data.table::fwrite(by_year, p1, na = "NA")
  
  ## (2) item-level pre-aggregation frame ------------------------------------
  it_src <- va_aggregate(dat[source %in% fab],   c("iso3c","year","isic","category","source"))
  it_ref <- va_aggregate(dat[source == ref_lab], c("iso3c","year","isic","category"))
  items  <- merge(it_src,
                  it_ref[, .(iso3c, year, isic, category, strand, ref_usd = value_usd)],
                  by = c("iso3c","year","isic","category","strand"))
  data.table::setnames(items, "value_usd", "source_usd")
  items[, ratio := source_usd / ref_usd]
  data.table::setnames(items, "strand", "measure")
  data.table::setcolorder(items,
                          c("iso3c","year","isic","category","source","measure","source_usd","ref_usd","ratio"))
  data.table::setorder(items, isic, source, measure, category, year)
  p2 <- file.path(out_dir, paste0(prefix, "_item_ratios.csv"))
  data.table::fwrite(items, p2, na = "NA")
  
  ## (3) pooled item-level metrics per (isic, source, measure) ----------------
  cmp <- merge(it_src[, .(iso3c, year, isic, category, source, strand, src = value_usd)],
               it_ref[, .(iso3c, year, isic, category, strand, ref = value_usd)],
               by = c("iso3c","year","isic","category","strand"))
  metrics <- va_score(cmp, fab, report_col = "isic")
  p3 <- file.path(out_dir, paste0("metrics_", prefix, "_pooled_items.csv"))
  data.table::fwrite(metrics, p3, na = "NA")
  
  message("Reference metrics -> ", p1)
  message("Reference metrics -> ", p2)
  message("Reference metrics -> ", p3)
  invisible(list(by_year = by_year, item_ratios = items, pooled = metrics))
}