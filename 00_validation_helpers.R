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