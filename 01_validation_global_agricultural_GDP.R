# =============================================================================
# FABIO value-added validation chart
#
# Runs for FOUR value-added sources, each written to its own sub-folder under
# output/fabio_validation/:
#   - gloria/            : the pure GLORIA decomposition              (script 14_1, GLORIA base)
#   - combined_gloria/   : GLORIA   + the FSDN/OECD/Eurostat overlay  (synthesis output)
#   - exiobase/          : the pure EXIOBASE decomposition            (script 14_1, EXIOBASE base)
#   - combined_exiobase/ : EXIOBASE + the FSDN/OECD/Eurostat overlay  (synthesis output)
# plus, when both members of a pair are available, COMPARISON versions of
# every chart that put the two bases into ONE figure (section 9):
#   - comparison_base/     : GLORIA vs EXIOBASE                (pure bases)
#   - comparison_combined/ : COMBINED_GLORIA vs COMBINED_EXIOBASE
# In the comparison figures the facet rows are base x ISIC level, ordered so
# the two bases sit DIRECTLY above each other within each ISIC level (GLORIA
# primary / EXIOBASE primary / GLORIA processing / EXIOBASE processing), on
# identical axes, country order, item colours and WB references — the
# remaining differences between adjacent panels are the bases themselves.
# All sources share the same output schema, so one set of chart code drives
# them; item colours are built from the UNION of all sources so the same FABIO
# item is the same colour in every sub-folder's figures — flipping between the
# gloria/ and exiobase/ versions of a chart then reads as "same item, same
# colour", which is the point of having the EXIOBASE branch here at all.
# Sources whose input RDS files don't exist yet are skipped with a message
# (so the script still runs before the EXIOBASE branch has been built).
#
# For each source, two families of outputs are produced:
#
# (A) Per-year cross-country charts (ONE SVG per year)
#     For every year that exists in BOTH the FABIO pipeline RDS files and the
#     World Bank ag-value-added CSV, builds a 100%-stacked column chart per
#     country (ISO3C):
#       - <year>_raw-WB.svg : 100% = full WB ag VA
#     The FABIO-comparable ("reduced") WB — full WB minus seeds (GLORIA share
#     of sector 15) and forestry (the MEASURED ISIC A02 value-added from
#     Eurostat NAMA / OECD SUT written by the synthesis script (14_4) where available, else the
#     GLORIA share of sector 21); see "Reduced WB reference" below — is drawn
#     ON this chart as a per-country grey tick, so it stays visible without a
#     separate SVG.  A coloured square under each country flags which forestry
#     route was used (green = Eurostat, purple = OECD, grey = GLORIA fallback).
#     The standalone <year>_reduced-WB.svg variant is no longer produced.
#     Y axis is clipped to [-100%, 300%] via coord_cartesian — values outside
#     that range are visually capped without dropping bars from the stack.
#
#     Items whose ABSOLUTE share is below `threshold` (default 3%) are
#     grouped as "Other"; the abs() lets heavily-subsidized items with
#     large negative shares keep their identity rather than being lumped
#     in with truly-small contributions.  Each item keeps a fixed colour
#     across years and across the per-country charts (built from a global
#     palette).
#
#     Sign convention.  Countries/years with non-zero WB ag VA are kept,
#     including negative ones (heavy-subsidy regimes occasionally show
#     negative WB values).  share = value_usd / wb_ag_va_usd then divides
#     signed-by-signed:
#       - WB > 0, VA > 0 : share > 0  — bar above zero (covers WB)
#       - WB > 0, VA < 0 : share < 0  — bar below zero (against WB)
#       - WB < 0, VA < 0 : share > 0  — bar above zero (also subsidies,
#                                       contributing in WB's direction)
#       - WB < 0, VA > 0 : share < 0  — bar below zero (counter to WB's
#                                       net-subsidy sign)
#     The dashed y=1 line means "FABIO matches WB in magnitude AND sign"
#     regardless of which sign that is.  Only WB == 0 / NA is dropped, to
#     avoid divide-by-zero.
#
# (B) Per-country time-series charts (one SVG per country)
#     For each country that appears in the pipeline data within `available_years`,
#     builds an *absolute* stacked column chart over time (x = year, y = USD).
#     A black line/points overlay shows the WB ag value-added so the absolute
#     gap to FABIO is visible. Items whose MAX absolute share across years
#     stays below `threshold` (default 3%) are grouped as "Other" for that
#     country (so the legend is stable across the time axis); colours are
#     shared with the per-year item charts so the same item is the same
#     colour everywhere.
#
# (B') Per-country VA sub-account (strand) charts  [do_strand_charts]
#     For every source whose RDS files carry the component-split columns
#     written by scripts 14_1 / 14_4 (value_added_wages|capital|tls [USD]),
#     family (B) is repeated once per strand (WAGES, CAPITAL, TLS), written as
#       by_country/fabio_validation_country_<ISO3>_<strand>.svg
#     next to the TOTAL figure.  These are FABIO-INTERNAL decompositions, not
#     WB validations: the World Bank reference exists only as a TOTAL (no
#     wages/capital/TLS split of agricultural VA is published), so the strand
#     figures carry NO WB line and no reduced-WB reference.  Where scripts 02 /
#     03 have already been run, their exported A01+A03 strand benchmarks
#     (Eurostat NAMA for the EU, OECD SUT T1600 for the USA; both
#     (iso3c, year, strand, bench_usd) CSVs) are stamped into the Primary
#     (ISIC-A) row(s) as a blue reference line — a primary-agriculture,
#     forestry-free anchor for the covered (country, year) cells.  Everything
#     else (item palette, "Other" grouping, facet layout, sizes) is shared
#     with the TOTAL figure: the "Other" grouping in particular is decided
#     ONCE from the TOTAL measure, so a country's four figures show the same
#     items and one consistent legend.  TLS can be net negative (subsidies >
#     taxes); those figures extend below zero and draw a thin zero baseline.
#     The per-year cross-country charts (A) stay TOTAL-only by construction —
#     they are shares of the WB headline, and there is no WB strand
#     denominator to take a share of.  Sources without the component-split
#     columns (older script 14_1 outputs) skip the strand figures with a
#     message; comparison figures (section 9) build them only when BOTH
#     members carry the columns.
#
# Pipeline rows are matched to items.csv on the numeric `item_code`
# (fabio_item_code in the pipeline). Item names are then taken from items.csv
# as the canonical source.
#
# Two facet rows compare the two GLORIA-derived layers on the same axes:
#   - Primary    (ISIC-A) : output of script 14_1 (primary agricultural production)
#   - Processing (ISIC-C) : output of script 14_1 (downstream processing layer)
# Downstream consumers stack these on the same FABIO (area, item, year) cells;
# here they are kept side-by-side so each layer's contribution is visible.
#
# Reduced WB reference.
#   The WB "Agriculture, forestry & fishing, value added" total covers GLORIA
#   primary sectors 1-23, but FABIO has no items mapped to GLORIA sectors 15
#   (Seeds and plant propagation) and 21 (Forestry and logging).  To make the
#   comparison like-for-like, every chart uses (or shows) a REDUCED WB that
#   subtracts those two:
#       reduced_WB = WB - D_seeds - D_forestry
#   - D_seeds    = WB x (GLORIA share of sector 15 within sectors 1-23).  Seeds
#     sits inside ISIC A01 and has NO standalone external counterpart, so this
#     structural share is the only option.
#   - D_forestry = the MEASURED forestry (ISIC A02) value-added written by
#     the synthesis script 14_4 (Eurostat NAMA preferred, OECD SUT fallback, both in USD) where
#     that reference covers the (country, year); ELSE WB x (GLORIA share of
#     sector 21).  Which path was taken is the "forestry route", recorded per
#     (country, year) and FLAGGED ON EVERY CHART by colour (green = Eurostat,
#     purple = OECD, grey = GLORIA-share fallback).
#   Implementation note: D_forestry is folded back into the same multiplicative
#   form the charts already use, via
#       share_non_fabio = share_seeds_gloria +
#                         (forestry_total_usd / WB   if external available
#                          else share_forestry_gloria)
#   so WB x (1 - share_non_fabio) == WB - D_seeds - D_forestry exactly, and the
#   result degrades to the previous GLORIA-only number wherever no external
#   forestry cell exists.  share_non_fabio is still passed through unclamped.
#
#   - Per-year charts (A): one SVG per year, raw WB as the denominator; the
#     reduced WB is drawn as a per-country grey tick, with a coloured square
#     marking the forestry route.  (The standalone reduced-WB SVG is no longer
#     produced.)
#   - Per-country charts (B): raw WB stays the primary line (black, solid)
#     for absolute scaling; reduced WB appears as a grey dashed reference whose
#     open points are coloured by the forestry route.
#
# Colour scheme.
#   The pipeline output carries a `comm_group` column (e.g. "Cereals", "Live
#   animals", "Vegetable oils"). Each comm_group is assigned ONE base hue;
#   items within the group render as evenly-spaced shades of that hue, dark
#   for the heaviest item in the group → light for the smallest. Group base
#   hues are taken from the existing base_pal (interpolated to the number of
#   groups), ordered by total value_added so the largest groups get the most
#   distinct colours. The legend in every chart is reordered group-by-group,
#   so adjacent swatches are always related shades and a "block of greens"
#   reads as "all the cereals" without consulting labels. Item colours are
#   stable across years and across charts (per-year and per-country share the
#   same global palette).
#
# Parallelization.
#   Both output loops fan out via parallel::mclapply (fork-based, shares the
#   in-memory pipelines / WB / palette tables copy-on-write — no per-worker
#   re-read). On Windows the loops fall back to sequential lapply. Number of
#   workers is configurable via `n_cores` and the whole feature can be
#   toggled off with `do_parallel <- FALSE` for easier debugging.
# =============================================================================

# ---- packages ---------------------------------------------------------------
# install.packages(c("readr", "dplyr", "tidyr", "ggplot2", "scales"))
suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(scales)
})

# ── FABIO + validation-repo integration ──────────────────────────────────────
# The value-added / producer-price pipeline is now folded into FABIO and lives
# in ~/fabio. Rather than re-deriving paths here, we source the pipeline's single
# source of truth, R/00_value_added_config.R, which exports the canonical path
# constants this validator reads from:
#   VA_VALUE_ADDED_OUTPUT_DIR  FABIOv2_*_value_added_ISIC-*.rds  (14_1 / 14_4)
#   VA_CONCORDANCE_DIR         inst/value_added/ (concordance_areas_gloria_fabio.csv)
#   VA_GLORIA_README_XLSX / VA_GLORIA_V_DIR   raw GLORIA on the NFS scratch
#   VA_FABIO_V2_DIR            compiled FABIO v2 dir (items.csv)
# Override the repo location with FABIO_ROOT (the raw GLORIA/FABIO scratch with
# FINEPRINT_ROOT). This validator uses none of the moved helpers, but sourcing
# the config keeps its paths in lock-step with the pipeline.
FABIO_ROOT <- path.expand(Sys.getenv("FABIO_ROOT", unset = "~/fabio"))
fabio_path <- function(...) file.path(FABIO_ROOT, ...)

# The config resolves `years` (from R/00_system_variables.R) and sources the
# helpers using paths RELATIVE to the FABIO repo root, so source it with the
# working directory temporarily set there. Its constants land in the global
# environment; the working directory is restored immediately after.
local({
  .old_wd <- getwd(); on.exit(setwd(.old_wd), add = TRUE)
  setwd(FABIO_ROOT)
  sys.source(file.path(FABIO_ROOT, "R", "00_value_added_config.R"),
             envir = globalenv())
})

# This validation repo ships its OWN reference input (World Bank Agri GDP) and
# both writes its figures/CSVs AND reads the benchmark CSVs that 02 / 03 write.
# Anchor those on the validation-repo root — the directory holding input/ and
# output/. Defaults to the working directory (the .Rproj root); override with
# the VALIDATION_ROOT env var when run head-less.
VALIDATION_ROOT <- path.expand(Sys.getenv("VALIDATION_ROOT", unset = getwd()))
if (!dir.exists(file.path(VALIDATION_ROOT, "input")))
  stop("VALIDATION_ROOT (", VALIDATION_ROOT, ") has no input/ folder. Run from ",
       "the validation repo root, or set the VALIDATION_ROOT env var.")
validation_path       <- function(...) file.path(VALIDATION_ROOT, ...)
# Validation outputs default to the repo's own output/; flip via VALIDATION_OUTPUT_DIR.
VALIDATION_OUTPUT_DIR <- path.expand(Sys.getenv("VALIDATION_OUTPUT_DIR",
                                                unset = validation_path("output")))

# VA outputs live in FABIO's output/value_added/ (= VA_VALUE_ADDED_OUTPUT_DIR
# from the config; filenames unchanged; stage-1 producer totals are in
# output/total_value/).
VA_OUTPUT_DIR <- VA_VALUE_ADDED_OUTPUT_DIR

# ---- config -----------------------------------------------------------------
threshold     <- 0.03          # |share| of WB total below which items go to "Other"

# Pipeline RDS inputs.  The full chart set is built for FOUR value-added
# sources, each written to its own sub-folder.  All share the same output
# schema (year, iso3c, fabio_item_code, comm_group, value_added [USD], ...),
# so the same chart code drives them; the COMBINED files' extra provenance
# columns (va_source, fsdn_source_isic) are simply ignored here.  Each source
# contributes its two ISIC levels as the two facet rows of every chart.
# The COMBINED file names follow the synthesis script's <TAG> convention,
# naming the base explicitly: "GLORIA_" for the GLORIA base, "EXIOBASE_"
# otherwise.
sources <- list(
  list(
    name   = "GLORIA",
    subdir = "gloria",
    isic_a = file.path(VA_OUTPUT_DIR, "FABIOv2_GLORIA_value_added_ISIC-A.rds"),     # 14_1 (GLORIA base)
    isic_c = file.path(VA_OUTPUT_DIR, "FABIOv2_GLORIA_value_added_ISIC-C.rds")      # 14_1 (GLORIA base)
  ),
  list(
    name   = "COMBINED_GLORIA",
    subdir = "combined_gloria",
    isic_a = file.path(VA_OUTPUT_DIR, "FABIOv2_COMBINED_GLORIA_value_added_ISIC-A.rds"),  # 14_4 synthesis (GLORIA base)
    isic_c = file.path(VA_OUTPUT_DIR, "FABIOv2_COMBINED_GLORIA_value_added_ISIC-C.rds")   # 14_4 synthesis (GLORIA base)
  ),
  list(
    name   = "EXIOBASE",
    subdir = "exiobase",
    isic_a = file.path(VA_OUTPUT_DIR, "FABIOv2_EXIOBASE_value_added_ISIC-A.rds"),   # 14_1 (EXIOBASE base)
    isic_c = file.path(VA_OUTPUT_DIR, "FABIOv2_EXIOBASE_value_added_ISIC-C.rds")    # 14_1 (EXIOBASE base)
  ),
  list(
    name   = "COMBINED_EXIOBASE",
    subdir = "combined_exiobase",
    isic_a = file.path(VA_OUTPUT_DIR, "FABIOv2_COMBINED_EXIOBASE_value_added_ISIC-A.rds"),  # 14_4 synthesis (EXIOBASE base)
    isic_c = file.path(VA_OUTPUT_DIR, "FABIOv2_COMBINED_EXIOBASE_value_added_ISIC-C.rds")   # 14_4 synthesis (EXIOBASE base)
  )
)

# Keep only sources whose input RDS files all exist.  The EXIOBASE branch may
# not have been produced yet on a given machine; skipping it with a message
# beats a hard failure halfway into the read loop.  (This also means the
# shared palette is built only from the sources actually present — colours
# stay stable as long as the union of items doesn't change between runs.)
.source_paths <- function(src) c(src$isic_a, src$isic_c)
.source_ok    <- vapply(sources,
                        function(src) all(file.exists(.source_paths(src))),
                        logical(1))
if (any(!.source_ok)) {
  for (src in sources[!.source_ok]) {
    .missing <- .source_paths(src)[!file.exists(.source_paths(src))]
    message("NOTE: skipping source ", src$name, " — missing input(s): ",
            paste(.missing, collapse = ", "))
  }
  sources <- sources[.source_ok]
}
if (!length(sources)) {
  stop("No value-added sources found — run the 14_1 / 14_4 (synthesis) scripts first.")
}

wb_path       <- validation_path("input", "World_Bank_Agri_GDP.csv")
# items.csv is a static reference (item_code -> item name) carried with the
# compiled FABIO v2 data on the NFS scratch (= VA_FABIO_V2_DIR from the config).
items_path    <- file.path(VA_FABIO_V2_DIR, "items.csv")

# Base output dir.  Each source gets <out_dir_base>/<subdir>/ with a
# by_country/ sub-folder inside it (created per source in the run driver).
# The source-independent share diagnostic is written once at the base level.
# This validator's outputs live in the validation repo's own output/ tree.
out_dir_base <- file.path(VALIDATION_OUTPUT_DIR, "fabio_validation")
dir.create(out_dir_base, recursive = TRUE, showWarnings = FALSE)

# Toggles — set to FALSE to skip a family of outputs.
do_yearly_charts  <- TRUE
do_country_charts <- TRUE

# Per-country VA sub-account (strand) figures — family (B').  Requires the
# component-split columns of scripts 14_1 / 14_4 in the source RDS files
# (value_added_wages|capital|tls [USD]); sources without them fall back to
# the TOTAL figure only, with a message.  Only family (B) is extended — the
# per-year cross-country charts (A) are shares of the WB headline, which has
# no strand decomposition, so they stay TOTAL-only.
do_strand_charts <- TRUE

STRANDS  <- c("wages", "capital", "tls")
MEASURES <- c("total", STRANDS)

# Strand columns as written by scripts 14_1 / 14_4 (same names scripts 02 / 03
# hard-require).  The TOTAL measure keeps using `value_added [USD]` so the
# existing figures are bit-identical to before.
strand_cols_usd <- c(wages   = "value_added_wages [USD]",
                     capital = "value_added_capital [USD]",
                     tls     = "value_added_tls [USD]")

MEASURE_TITLE <- c(total   = "value-added",
                   wages   = "wages",
                   capital = "capital",
                   tls     = "taxes less subsidies")
MEASURE_AXIS  <- c(total   = "Value-added (current US$)",
                   wages   = "Wages — compensation of employees (current US$)",
                   capital = "Capital — operating surplus etc. (current US$)",
                   tls     = "Taxes less subsidies on production (current US$)")

# External strand benchmarks, REUSED from scripts 02 / 03 rather than
# re-derived: both export an (iso3c, year, strand, bench_usd) CSV of their
# A01+A03 (agriculture + fishery, forestry-free) reference — Eurostat NAMA
# (script 02, EU countries) and OECD SUT T1600 (script 03, USA). They are read
# from VALIDATION_OUTPUT_DIR, where 02 / 03 write them. Where a file is missing
# the strand figures simply draw without a benchmark line. On overlapping cells
# (none expected) the order below is the priority.
STRAND_BENCH_PATHS <- c(
  EUROSTAT_NAMA = file.path(VALIDATION_OUTPUT_DIR, "biosam_validation", "eurostat_A01_A03_benchmark.csv"),
  OECD_SUT      = file.path(VALIDATION_OUTPUT_DIR, "usa_sut_validation", "oecd_A01_A03_benchmark.csv")
)

# Parallelization. Forking is Unix-only; on Windows we silently fall back to
# sequential lapply. Set do_parallel <- FALSE to debug a single chart serially
# (mclapply swallows interactive errors and hides traceback noise).
do_parallel <- TRUE
n_cores     <- min(8L, max(1L, parallel::detectCores(logical = FALSE) - 1L))

# Facet-row order (top to bottom) on every chart.  Kept as a single source
# of truth so the labels and the factor levels stay in sync.
pipeline_levels <- c("Primary (ISIC-A)", "Processing (ISIC-C)")

# Forestry-deduction provenance ("route"): which source supplied the forestry
# component of the reduced-WB reference for each (country, year).  Used to
# colour a per-country route marker on every chart so the figure ITSELF shows
# whether the forestry deduction was measured (Eurostat/OECD A02) or fell back
# to the GLORIA structural share.  Levels are fixed so colours and the legend
# stay stable across all charts even when a level is absent in a given year.
forestry_route_levels <- c("EUROSTAT_NAMA", "OECD_SUT", "GLORIA_share")
forestry_route_labels <- c(EUROSTAT_NAMA = "Eurostat (A02)",
                           OECD_SUT      = "OECD (A02)",
                           GLORIA_share  = "GLORIA (fallback)")
forestry_route_colors <- c(EUROSTAT_NAMA = "#1b9e77",   # green  — measured (EU)
                           OECD_SUT      = "#7570b3",   # purple — measured (OECD)
                           GLORIA_share  = "grey55")    # grey   — structural fallback

# ---- 1. read pipeline outputs (all years) ----------------------------------
# Carry `item_code` (from fabio_item_code) as the join key, plus `comm_group`
# (commodity group label, e.g. "Cereals") which drives the colour scheme. The
# item NAME will be attached later from items.csv so that items.csv is the
# single source of truth for labels.
read_pipeline <- function(path, label) {
  raw <- readRDS(path)
  # Strand columns are OPTIONAL here (unlike scripts 02 / 03, which hard-fail):
  # a source built before the component split simply loses its strand figures,
  # not the whole run.  All-or-nothing per file — a partial set would make the
  # TOTAL ≠ sum-of-strands silently.
  has_strands <- all(unname(strand_cols_usd) %in% names(raw))
  out <- raw %>%
    transmute(
      year,
      iso3c,
      item_code     = fabio_item_code,
      comm_group,
      value_usd     = `value_added [USD]`,
      value_wages   = if (has_strands) `value_added_wages [USD]`   else NA_real_,
      value_capital = if (has_strands) `value_added_capital [USD]` else NA_real_,
      value_tls     = if (has_strands) `value_added_tls [USD]`     else NA_real_,
      pipeline      = label
    ) %>%
    group_by(pipeline, year, iso3c, item_code, comm_group) %>%
    summarise(
      across(c(value_usd, value_wages, value_capital, value_tls),
             ~ if (all(is.na(.x))) NA_real_ else sum(.x, na.rm = TRUE)),
      .groups = "drop"
    )
  attr(out, "has_strands") <- has_strands
  out
}

# Read each source's two ISIC levels into one tibble per source, keyed by the
# source name.  The palette (section 5) is built from the UNION of all sources
# so that a given FABIO item is the SAME colour in the GLORIA, EXIOBASE and
# both COMBINED chart sets — flipping between any two versions of a
# year/country then reads as "same item, same colour", which is the whole
# point of comparing them.
read_source <- function(src) {
  lev_a <- read_pipeline(src$isic_a, "Primary (ISIC-A)")
  lev_c <- read_pipeline(src$isic_c, "Processing (ISIC-C)")
  out <- bind_rows(lev_a, lev_c) %>%
    mutate(pipeline = factor(pipeline, levels = pipeline_levels))
  # Strands are usable for a source only when BOTH ISIC levels carry them —
  # otherwise the two facet rows of a strand figure would not be comparable.
  attr(out, "has_strands") <-
    isTRUE(attr(lev_a, "has_strands")) && isTRUE(attr(lev_c, "has_strands"))
  out
}

pipelines_by_source <- lapply(sources, read_source)
names(pipelines_by_source) <- vapply(sources, `[[`, character(1), "name")

# Which sources can drive strand figures (component-split columns present in
# both ISIC-level files).  Consulted by the run drivers (sections 8 / 9).
strands_by_source <- vapply(pipelines_by_source,
                            function(x) isTRUE(attr(x, "has_strands")),
                            logical(1))
if (do_strand_charts) {
  if (any(strands_by_source)) {
    message("Strand (sub-account) figures enabled for: ",
            paste(names(strands_by_source)[strands_by_source], collapse = ", "))
  }
  if (any(!strands_by_source)) {
    message("NOTE: no component-split columns (value_added_wages|capital|tls",
            " [USD]) for: ",
            paste(names(strands_by_source)[!strands_by_source], collapse = ", "),
            " — TOTAL figures only for those.  Re-run scripts 14_1 / 14_4 ",
            "to generate the split.")
  }
}

# Union across sources — used ONLY to build the shared palette / canonical
# legend order and the shared set of available years.  Never charted directly
# (each source is charted from its own entry in pipelines_by_source).
pipelines_union <- bind_rows(pipelines_by_source, .id = "source")

# ---- 2. World Bank agricultural value added (denominator) ------------------
# WB CSVs have 4 lines of metadata before the header row.
wb_raw <- read_csv(wb_path, skip = 4, show_col_types = FALSE)

# Year columns in the WB file are 4-digit names ("1960", "1961", ...)
wb_years <- suppressWarnings(as.integer(names(wb_raw)))
wb_years <- wb_years[!is.na(wb_years)]

# ---- 3. years available in both pipelines and WB ---------------------------
pipeline_years  <- sort(unique(pipelines_union$year))
available_years <- sort(intersect(pipeline_years, wb_years))

if (!length(available_years)) {
  stop("No overlapping years between the FABIO pipelines and the World Bank file.")
}

message("Building charts for years: ",
        paste(available_years, collapse = ", "))

# ---- 3b. GLORIA non-FABIO sector share per country and year ----------------
# The WB "Agriculture, value added" headline covers GLORIA primary sectors
# 1-23, but FABIO has no items mapped to GLORIA sectors 15 (Seeds and plant
# propagation) and 21 (Forestry and logging).  Build a per-(country, year)
# share that those two sectors hold in raw GLORIA VA across sectors 1-23,
# then use it as the new default reference in the per-year charts (the
# bar denominator is the reduced WB, raw WB drops to a secondary tick).
#
# NOTE (multi-base): this seeds/forestry deduction is a property of the WB
# REFERENCE (which sectors the WB headline covers that FABIO doesn't), not of
# the value-added base, so the same GLORIA-derived structural share is used
# for ALL sources — including the EXIOBASE ones.  That keeps the reduced-WB
# tick / dashed line identical across the gloria/, combined/, exiobase/ and
# combined_exiobase/ figures, so differences between the chart sets are
# attributable to the bases alone.
#
# Computation:
#   - Read V_<year>.qs2 for each `available_year` (only V; X is not needed
#     for a pure VA share).  Mirror script 14_1's collapse_va helper to sum
#     each region's on-diagonal VA block to one VA value per (region,
#     sector).
#   - Map gloria_region → iso3c via concordance_areas_gloria_fabio.csv
#     (the FABIO_iso3c column is the canonical destination).  Both 1:N
#     and N:1 mappings are handled by a single cartesian join + group-by:
#       * 1:N (e.g. XAF → CPV, SWZ, GNB, …): each downstream iso3c
#         inherits XAF's full sector-1-23 totals before the ratio is
#         taken, so all of them get the same XAF share (the "duplication"
#         is a no-op at the ratio level).
#       * N:1 (e.g. XAF, XEU, XAS, BTN, … → ROW): VA is summed across
#         source regions BEFORE the share is computed, so ROW gets the
#         aggregate structural share.  ROW typically has no WB row
#         anyway, but the logic is correct.
#
# Raw gloria_va is used here, not the stage-4-cleaned va_intensity_winsor
# * gloria_x: this is a structural ratio (which sectors dominate within
# the 1-23 group), so cleaning doesn't materially change the answer and
# the raw values keep this block self-contained.

suppressPackageStartupMessages({
  library(data.table)
  library(readxl)
  library(qs2)
})

GLORIA_README_PATH <- VA_GLORIA_README_XLSX
GLORIA_V_DIR       <- VA_GLORIA_V_DIR
# GLORIA<->FABIO area concordance: a SHARED pipeline concordance, in FABIO's
# inst/value_added/ (= VA_CONCORDANCE_DIR), the same file 14_1 reads.
AREA_CONC_PATH     <- file.path(VA_CONCORDANCE_DIR, "concordance_areas_gloria_fabio.csv")

PRIMARY_SECTORS    <- 1:23

# The two GLORIA primary sectors with no FABIO item mapping, kept SEPARATE
# because they deduct differently from the WB headline (see below):
#   - Seeds (15): sits inside ISIC A01, no external (Eurostat/OECD) equivalent,
#                 so it can only ever be deducted via the GLORIA structural share.
#   - Forestry (21): == ISIC/NACE A02, published directly by Eurostat NAMA and
#                 OECD SUT, so the synthesis script (14_4) emits a measured forestry VA we use in
#                 preference to the GLORIA share wherever it exists.
SEEDS_SECTOR    <- 15L
FORESTRY_SECTOR <- 21L

# GLORIA dimension labels (mirrors script 14_1).
.regions_tbl <- as.data.table(read_excel(GLORIA_README_PATH, sheet = "Regions"))
.sectors_tbl <- as.data.table(read_excel(GLORIA_README_PATH, sheet = "Sectors"))
setorder(.sectors_tbl, Lfd_Nr)
.n_va_rows <- nrow(read_excel(GLORIA_README_PATH,
                              sheet = "Value added and final demand"))
.n_regions <- nrow(.regions_tbl)
.n_sectors <- nrow(.sectors_tbl)
.n_cols    <- .n_regions * .n_sectors

.col_idx <- data.table(
  col                = seq_len(.n_cols),
  gloria_region_code = rep(.regions_tbl$Region_acronyms,    each  = .n_sectors),
  gloria_sector_code = rep(as.integer(.sectors_tbl$Lfd_Nr), times = .n_regions)
)

# Sum each region's on-diagonal VA block (off-diagonal blocks are zero).
.collapse_va <- function(V_mat) {
  out <- numeric(.n_cols)
  for (r in seq_len(.n_regions)) {
    cols_r <- ((r - 1L) * .n_sectors + 1L):(r * .n_sectors)
    rows_r <- ((r - 1L) * .n_va_rows + 1L):(r * .n_va_rows)
    out[cols_r] <- colSums(V_mat[rows_r, cols_r, drop = FALSE])
  }
  out
}

.read_gloria_va <- function(yr) {
  v_path <- sprintf("%s/V_%d.qs2", GLORIA_V_DIR, yr)
  if (!file.exists(v_path)) {
    message("[share] year ", yr, ": V_", yr, ".qs2 missing, skipping.")
    return(NULL)
  }
  V_mat  <- as.matrix(qs_read(v_path))
  VA_vec <- .collapse_va(V_mat)
  rm(V_mat); gc(verbose = FALSE)
  dt <- copy(.col_idx)
  dt[, gloria_va := VA_vec]
  dt[, year := yr]
  dt[, col := NULL]
  dt[]
}

message("Computing GLORIA non-FABIO sector share per (country, year) for ",
        length(available_years), " year(s) ...")
gloria_va_dt <- rbindlist(lapply(available_years, .read_gloria_va),
                          use.names = TRUE)
gloria_va_dt <- gloria_va_dt[gloria_sector_code %in% PRIMARY_SECTORS]

# Area concordance: gloria_region_code → iso3c (FABIO_iso3c column is the
# canonical destination).  `unique` collapses any exact-duplicate rows in
# the CSV; the GLORIA → iso3c mapping itself can still be 1:N or N:1.
area_conc <- fread(AREA_CONC_PATH)[
  !is.na(GLORIA_region_code) & GLORIA_region_code != "" &
    !is.na(FABIO_iso3c)      & FABIO_iso3c       != "",
  .(gloria_region_code = as.character(GLORIA_region_code),
    iso3c              = as.character(FABIO_iso3c))
]
area_conc <- unique(area_conc)

# Aggregate VA to (iso3c, year) — handles 1:N (each downstream iso3c
# inherits the source region's full totals, so all get the same share)
# and N:1 (multiple source regions sum into one iso3c, e.g. ROW) in a
# single group-by.
share_by_iso_dt <- gloria_va_dt[
  area_conc, on = "gloria_region_code",
  allow.cartesian = TRUE, nomatch = NULL
][, .(
  va_total    = sum(gloria_va, na.rm = TRUE),
  va_seeds    = sum(gloria_va[gloria_sector_code == SEEDS_SECTOR],    na.rm = TRUE),
  va_forestry = sum(gloria_va[gloria_sector_code == FORESTRY_SECTOR], na.rm = TRUE)
), by = .(iso3c, year)]

# Per-(country, year) GLORIA structural shares of the two non-FABIO sectors,
# kept SEPARATE.  share_seeds_gloria is the ONLY available seeds deduction;
# share_forestry_gloria is the FALLBACK forestry deduction, used only where the
# external A02 reference (below) has no cell.
share_by_iso <- share_by_iso_dt[is.finite(va_total) & va_total > 0] %>%
  as_tibble() %>%
  transmute(
    iso3c, year,
    share_seeds_gloria    = va_seeds    / va_total,
    share_forestry_gloria = va_forestry / va_total
  )

# ============================================================================
# Forestry (ISIC A02) value-added reference  (was R/14_4 SECTION 4 / APPENDIX 2)
# ----------------------------------------------------------------------------
# Benchmark-side artefact: it writes NOTHING into the FABIO VA product, so it is
# built HERE in the validation suite (no synthesis run required) from the shared
# loaders now in R/00_value_added_helpers.R.  Eurostat NAMA A02 wins wherever it
# has a cell; OECD SUT A02 fills the rest; (country, year) cells neither source
# covers are simply absent — those keep the GLORIA structural forestry share
# downstream.  Output (validation-owned, under out_dir_base):
#   FABIOv2_forestry_VA_ISIC-A02.rds / .csv
#   columns: iso3c, year, forestry_{wages,capital,tls,total}_usd, forestry_source
# This carries the `forestry_source` that the per-chart routing turns into the
# per-country route flag.
# ============================================================================
FORESTRY_OECD_ACTIVITY <- "A02"     # OECD SUT activity = Forestry and logging
FORESTRY_EU_NACE       <- "A02"     # Eurostat nace_r2  = Forestry and logging

build_forestry_reference <- function(rates_all, eur_usd, iso_xwalk, out_dir) {
  ref_rds <- file.path(out_dir, "FABIOv2_forestry_VA_ISIC-A02.rds")
  ref_csv <- file.path(out_dir, "FABIOv2_forestry_VA_ISIC-A02.csv")
  message("\n=== Forestry (A02) reference (Eurostat -> OECD) ===")
  
  # OECD SUT A02 -> (iso3c, year, strands + total USD).  Reuses the generic
  # loader; `iso3` it carries IS the iso3c the combined base supplied via
  # iso_xwalk.
  oecd_f  <- load_oecd_sut_activity(iso3_to_area = iso_xwalk, lcu_usd = rates_all,
                                    activity = FORESTRY_OECD_ACTIVITY)
  oecd_dt <- if (!is.null(oecd_f) && nrow(oecd_f) > 0L)
    data.table(iso3c                = oecd_f$iso3,
               year                 = as.integer(oecd_f$year),
               forestry_wages_usd   = oecd_f[[STRAND_TO_COL[["wages"]]]],
               forestry_capital_usd = oecd_f[[STRAND_TO_COL[["capital"]]]],
               forestry_tls_usd     = oecd_f[[STRAND_TO_COL[["tls"]]]],
               forestry_total_usd   = oecd_f[[BASE_TOTAL_COL]],
               forestry_source      = "OECD_SUT")
  else NULL
  
  # Eurostat NAMA A02 -> (iso3c, year, strands + total USD).
  eu_f  <- load_eurostat_nama_activity(eur_usd, FORESTRY_EU_NACE)
  eu_dt <- if (!is.null(eu_f) && nrow(eu_f) > 0L)
    data.table(iso3c                = eu_f$iso3c,
               year                 = as.integer(eu_f$year),
               forestry_wages_usd   = eu_f$wages_usd,
               forestry_capital_usd = eu_f$capital_usd,
               forestry_tls_usd     = eu_f$tls_usd,
               forestry_total_usd   = eu_f$total_usd,
               forestry_source      = "EUROSTAT_NAMA")
  else NULL
  
  ref <- rbindlist(list(eu_dt, oecd_dt), use.names = TRUE, fill = TRUE)
  if (is.null(ref) || nrow(ref) == 0L) {
    warning("No forestry (A02) cells from Eurostat or OECD — this script will fall ",
            "back to the structural forestry share for every country.")
    return(invisible(NULL))
  }
  ref <- ref[is.finite(forestry_total_usd)]
  
  # Eurostat precedence: "EUROSTAT_NAMA" sorts before "OECD_SUT", so keeping the
  # FIRST row per (iso3c, year) keeps Eurostat wherever it exists and falls back
  # to OECD only where it does not — exactly the fishing precedence.
  setorder(ref, iso3c, year, forestry_source)
  ref <- unique(ref, by = c("iso3c", "year"))
  setorderv(ref, c("iso3c", "year"))
  
  saveRDS(ref, ref_rds)
  fwrite(ref,  ref_csv)
  src <- ref[, .N, by = forestry_source][order(-N)]
  message(sprintf("  Forestry reference: %d (iso3c, year) cell(s) -> %s",
                  nrow(ref), ref_rds))
  message("    source mix: ",
          paste(sprintf("%s=%d", src$forestry_source, src$N), collapse = "  "))
  invisible(ref)
}


# Inputs for the reference (all validation-side):
#   .fx_rates_all  per-country FAOSTAT LCU->USD table (helpers::faostat_rate_table)
#   .eur_usd       Germany's EUR/USD row, for the Eurostat EUR->USD conversion
#   .iso_xwalk     iso3c -> fabio_area_code, from the canonical FABIO regions table
#                  (inst/regions_full.csv) — replaces the crosswalk the synthesis
#                  used to lift out of its combined VA table.
# The whole build is guarded: if any required FABIO input (the FAOSTAT FX file,
# the regions table) or both benchmark sources are missing, we degrade to an
# empty reference and the GLORIA structural forestry share is used everywhere —
# exactly the fallback this script had when it read a pre-built RDS.
.empty_forestry <- function()
  tibble(iso3c = character(), year = integer(),
         forestry_total_usd = double(), forestry_source = character())

forestry_ext <- tryCatch({
  if (!file.exists(VA_EXCHANGE_RATE_CSV))
    stop("FAOSTAT exchange-rate file not staged at ", VA_EXCHANGE_RATE_CSV)
  if (!file.exists(VA_FABIO_REGIONS_CSV))
    stop("FABIO regions table not found at ", VA_FABIO_REGIONS_CSV)
  
  .fx_rates_all <- faostat_rate_table(VA_EXCHANGE_RATE_CSV, element = VA_FX_ELEMENT_CODE)
  .eur_usd <- .fx_rates_all[fabio_area_code == VA_GERMANY_AREA_CODE,
                            .(year, rate_eur_per_usd = rate_lcu_per_usd)]
  setkey(.eur_usd, year)
  .regions <- fread(VA_FABIO_REGIONS_CSV)
  .iso_xwalk <- unique(.regions[!is.na(iso3c) & nzchar(as.character(iso3c)) & !is.na(code),
                                .(iso3 = as.character(iso3c),
                                  fabio_area_code = as.integer(code))])
  
  forestry_ref <- build_forestry_reference(.fx_rates_all, .eur_usd, .iso_xwalk,
                                           out_dir = out_dir_base)
  if (is.null(forestry_ref)) .empty_forestry()
  else as_tibble(forestry_ref) %>%
    select(iso3c, year, forestry_total_usd, forestry_source) %>%
    filter(is.finite(forestry_total_usd))
}, error = function(e) {
  message("NOTE: forestry (A02) reference not built (", conditionMessage(e), ") — ",
          "the forestry deduction will use the GLORIA structural share everywhere.")
  .empty_forestry()
})

share_by_iso <- share_by_iso %>%
  left_join(forestry_ext, by = c("iso3c", "year"))

.gloria_combined_share <- share_by_iso$share_seeds_gloria +
  share_by_iso$share_forestry_gloria
.n_ext_forestry <- sum(!is.na(share_by_iso$forestry_source))
message(sprintf(
  "  GLORIA seeds+forestry share for %d (iso3c, year) cells; range %.1f%%–%.1f%%, median %.1f%%.",
  nrow(share_by_iso),
  100 * min(.gloria_combined_share),
  100 * max(.gloria_combined_share),
  100 * median(.gloria_combined_share)
))
message(sprintf(
  "  measured external forestry (A02) covers %d / %d cells (%.0f%%); the rest use the GLORIA forestry share.",
  .n_ext_forestry, nrow(share_by_iso),
  100 * .n_ext_forestry / max(1L, nrow(share_by_iso))
))

# Diagnostic CSV — useful when a chart looks off and you want to inspect
# the share that drove the reduced reference.
fwrite(share_by_iso,
       file.path(out_dir_base, "non_fabio_sector_share_per_country_year.csv"))

# ---- 3c. external strand benchmarks (from scripts 02 / 03) ------------------
# The WB headline has no wages/capital/TLS split, so the strand figures (B')
# have no WB line.  Instead, REUSE the A01+A03 strand benchmarks that scripts
# 07 (Eurostat NAMA, EU) and 08 (OECD SUT T1600, USA) already export as tidy
# (iso3c, year, strand, bench_usd) CSVs — a primary-agriculture, forestry-free
# reference for the (country, year) cells they cover.  Missing files just mean
# no benchmark line; nothing is fetched here.
read_strand_bench <- function(path, source_tag) {
  if (!file.exists(path)) return(NULL)
  out <- tryCatch(read_csv(path, show_col_types = FALSE),
                  error = function(e) NULL)
  need <- c("iso3c", "year", "strand", "bench_usd")
  if (is.null(out) || !all(need %in% names(out))) {
    message("NOTE: strand benchmark '", path, "' unreadable or missing ",
            "column(s) — skipped.")
    return(NULL)
  }
  out %>%
    transmute(iso3c        = as.character(iso3c),
              year         = as.integer(year),
              strand       = as.character(strand),
              bench_usd    = as.numeric(bench_usd),
              bench_source = source_tag) %>%
    filter(is.finite(bench_usd), strand %in% STRANDS)
}

strand_bench <- NULL
if (do_strand_charts) {
  .bench_list <- Filter(Negate(is.null), Map(read_strand_bench,
                                             STRAND_BENCH_PATHS,
                                             names(STRAND_BENCH_PATHS)))
  if (length(.bench_list)) {
    strand_bench <- bind_rows(.bench_list) %>%
      # Priority on (unexpected) overlapping cells = order of STRAND_BENCH_PATHS.
      mutate(.prio = match(bench_source, names(STRAND_BENCH_PATHS))) %>%
      arrange(iso3c, year, strand, .prio) %>%
      distinct(iso3c, year, strand, .keep_all = TRUE) %>%
      select(-.prio)
    message(sprintf(
      "Strand benchmarks loaded: %d (iso3c, year, strand) cells over %d country(ies) [%s].",
      nrow(strand_bench), n_distinct(strand_bench$iso3c),
      paste(sort(unique(strand_bench$bench_source)), collapse = ", ")))
  } else {
    message("NOTE: no strand benchmark CSVs found (run scripts 02 / 03 first ",
            "to enable the A01+A03 reference lines) — strand figures will be ",
            "drawn without a benchmark.")
  }
}

# ---- 4. items.csv -> item_code-to-item mapping -----------------------------
items_map <- read_csv(items_path, show_col_types = FALSE) %>%
  select(item_code, item) %>%
  distinct()

# Sanity-check for item_codes in the pipeline that aren't in items.csv.
unmapped_codes <- setdiff(unique(pipelines_union$item_code), items_map$item_code)
if (length(unmapped_codes)) {
  message("item_codes present in pipeline but missing from items.csv ",
          "(will be labelled '[unmapped:CODE]'): ",
          paste(unmapped_codes, collapse = ", "))
}

# ---- 5. colour palette -----------------------------------------------------
# One base hue per comm_group, with items inside the group rendered as
# evenly-spaced shades of that hue (dark for the heaviest item in the group
# → light for the smallest). The legend in every chart is reordered
# group-by-group so adjacent swatches are always related shades, and a
# "block of greens" reads as "all the cereals" without consulting labels.
#
# The base palette below is the original 30-colour set. We interpolate it to
# the number of comm_groups so that even when the group count drifts (new
# data, schema changes), each group gets a distinct hue without manually
# re-balancing the palette.
base_pal <- c(
  "#1f77b4","#ff7f0e","#2ca02c","#d62728","#9467bd",
  "#8c564b","#e377c2","#bcbd22","#17becf","#aec7e8",
  "#ffbb78","#98df8a","#ff9896","#c5b0d5","#c49c94",
  "#f7b6d2","#dbdb8d","#9edae5","#393b79","#637939",
  "#8c6d31","#843c39","#7b4173","#3182bd","#e6550d",
  "#31a354","#756bb1","#fd8d3c","#74c476","#9e9ac8"
)

# Helpers: lighten/darken a colour by mixing with white/black in RGB. RGB
# mixing isn't perceptually uniform, but for the small intra-group shade
# counts we have here (mostly ≤9 items, max 23) it produces visually
# distinguishable shades that read as "the same hue, different brightness".
.mix_with <- function(col, target, amount) {
  rgb_mat <- col2rgb(col) / 255
  out     <- rgb_mat + amount * (target - rgb_mat)
  rgb(out[1L, ], out[2L, ], out[3L, ])
}
.lighten <- function(col, amount) .mix_with(col, target = 1, amount = amount)
.darken  <- function(col, amount) .mix_with(col, target = 0, amount = amount)

# N evenly-spaced shades of `base`, dark → light. Endpoints (.darken 0.35,
# .lighten 0.55) are tuned so even adjacent shades stay readable on white
# and the lightest shade doesn't disappear into the page.
make_shades <- function(base, n) {
  if (n <= 1L) return(base)
  colorRampPalette(c(.darken(base, 0.35),
                     base,
                     .lighten(base, 0.55)))(n)
}

# Sanity: each item_code should map to exactly one comm_group. If not (data
# issue), warn and fall back to the most common group for that code so we
# don't end up with duplicate item-name rows in the palette.
multi_group <- pipelines_union %>%
  distinct(item_code, comm_group) %>%
  count(item_code) %>%
  filter(n > 1L)
if (nrow(multi_group)) {
  message("WARNING: item_code(s) with multiple comm_groups (using mode): ",
          paste(multi_group$item_code, collapse = ", "))
}
comm_group_lookup <- pipelines_union %>%
  count(item_code, comm_group, name = "n_rows") %>%
  group_by(item_code) %>%
  slice_max(n_rows, n = 1L, with_ties = FALSE) %>%
  ungroup() %>%
  select(item_code, comm_group)

# All items + their canonical name + comm_group + global total. Unmapped
# codes get "[unmapped:CODE]" labels (mirroring the chart functions); items
# missing a comm_group fall into a neutral "[ungrouped]" bucket so the
# palette still has a slot for them.
all_items_meta <- pipelines_union %>%
  group_by(item_code) %>%
  summarise(total = sum(value_usd, na.rm = TRUE), .groups = "drop") %>%
  left_join(items_map,         by = "item_code") %>%
  left_join(comm_group_lookup, by = "item_code") %>%
  mutate(
    item       = if_else(is.na(item),
                         paste0("[unmapped:", item_code, "]"),
                         item),
    comm_group = if_else(is.na(comm_group) | comm_group == "",
                         "[ungrouped]", comm_group)
  )

# Group order: comm_groups by total value_added desc, so the largest groups
# get the most distinct base hues.
group_totals <- all_items_meta %>%
  group_by(comm_group) %>%
  summarise(group_total = sum(total, na.rm = TRUE), .groups = "drop") %>%
  arrange(desc(group_total))

group_base_hues <- setNames(
  colorRampPalette(base_pal)(nrow(group_totals)),
  group_totals$comm_group
)
# "[ungrouped]" goes neutral so it doesn't claim a vivid hue for items we
# couldn't classify.
if ("[ungrouped]" %in% names(group_base_hues)) {
  group_base_hues[["[ungrouped]"]] <- "grey55"
}

# Per-item colour: order items within each group by total desc, then ramp
# shades dark → light in that order so the heaviest item in the group reads
# strongest. Result is a named character vector keyed by item label, used
# directly by scale_fill_manual in both chart functions.
item_palette_df <- all_items_meta %>%
  arrange(comm_group, desc(total)) %>%
  group_by(comm_group) %>%
  mutate(colour = make_shades(group_base_hues[[first(comm_group)]], n())) %>%
  ungroup()

item_colors <- setNames(item_palette_df$colour, item_palette_df$item)
item_colors["Other"] <- "grey70"

# Canonical legend order: comm_groups by total desc, items within each group
# by total desc. Both chart functions sort their per-chart legend against
# this so adjacent swatches in any chart are always shades of the same hue.
canonical_item_order <- all_items_meta %>%
  left_join(group_totals, by = "comm_group") %>%
  arrange(desc(group_total), comm_group, desc(total)) %>%
  pull(item)

# Short helper for axis labels in absolute USD (e.g. "1.2B", "500M", "10K")
usd_axis_labels <- scales::label_number(scale_cut = scales::cut_short_scale())

# ---- 6a. per-year chart builder --------------------------------------------
# Two output variants per year, controlled by the `denominator` argument:
#   * "raw"     — bars are share of full WB ag VA; dashed y=1 line IS the
#                 raw WB; per-country grey tick = where the FABIO-comparable
#                 (reduced) WB sits, at y = 1 - share_non_fabio.
#   * "reduced" — bars are share of FABIO-comparable WB; dashed y=1 line IS
#                 the reduced WB; per-country grey tick = where the FULL WB
#                 sits, at y = 1 / (1 - share_non_fabio).
# share_non_fabio is passed through unclamped, so both ticks can land
# anywhere on the y axis (including outside the clipped window, in which
# case they simply don't render).
# Y-axis is clipped to [-100%, 300%] in both variants via coord_cartesian,
# so values outside that range are visually capped without dropping bars
# from the stack (scale_y_continuous(limits=...) would drop them and
# silently break stacking).
#
# Sign convention.  WB ag VA is allowed to be negative (heavy-subsidy
# regimes occasionally show negative WB).  share = value_usd / wb_ag_va_usd
# then divides signed-by-signed: a negative-VA item in a country with
# negative WB renders as a POSITIVE share (both pulling in the same
# direction) — that's the desired behaviour.  Only zero / NA WB is
# dropped, to avoid divide-by-zero.  Item grouping into "Other" is on
# |share|, so heavily-subsidized items keep their identity rather than
# falling below the threshold from the negative side.
# `pipelines_all`, `out_dir` and `source_name` are passed in by the per-source
# driver (section 7) so the same builder serves every source; everything else
# it references (wb_raw, share_by_iso, items_map, the palette, threshold) is
# source-independent and inherited from the enclosing scope.  `source_name`
# goes into the title so the four chart sets are tellable apart from the
# figure itself, not just the folder it sits in.
make_chart <- function(year_select, denominator = c("raw", "reduced"),
                       pipelines_all, out_dir, source_name) {
  denominator <- match.arg(denominator)
  
  # Attach canonical item name from items.csv via item_code.
  pipelines <- filter(pipelines_all, year == year_select) %>%
    left_join(items_map, by = "item_code") %>%
    mutate(item = if_else(is.na(item),
                          paste0("[unmapped:", item_code, "]"),
                          item))
  
  wb <- wb_raw %>%
    select(iso3c = `Country Code`,
           wb_ag_va_usd = all_of(as.character(year_select))) %>%
    # Drop only NA and exactly-zero WB rows (zero would divide-by-zero);
    # negative WB is kept on purpose so subsidy-dominated countries
    # appear in the chart with shares above the dashed y=1 line when
    # FABIO matches the negative direction.
    filter(!is.na(wb_ag_va_usd), wb_ag_va_usd != 0) %>%
    # Attach the non-FABIO share for this year and derive the reduced WB.
    # Where share is missing — no GLORIA data for this country/year —
    # fall back to share = 0 so reduced equals raw and the country isn't
    # dropped.  Otherwise share_non_fabio is passed through as-is, even
    # when negative or > 1: the reduced WB is then literally WB × (1 -
    # share), with no floor/ceiling, and the chart shows whatever that
    # produces.
    left_join(filter(share_by_iso, year == year_select), by = "iso3c") %>%
    # Forestry deduction routing (see section 3b): use the MEASURED external A02
    # value-added as a share of WB where available, otherwise the GLORIA
    # structural forestry share.  Seeds is always the GLORIA share (no external
    # equivalent).  `forestry_route` records which path was taken so the chart
    # can flag it per country.  share_non_fabio stays unclamped, as before.
    mutate(
      share_seeds_gloria    = coalesce(share_seeds_gloria, 0),
      share_forestry_gloria = coalesce(share_forestry_gloria, 0),
      use_external_forestry = is.finite(forestry_total_usd) & wb_ag_va_usd != 0,
      share_forestry        = if_else(use_external_forestry,
                                      forestry_total_usd / wb_ag_va_usd,
                                      share_forestry_gloria),
      forestry_route        = factor(
        if_else(use_external_forestry,
                coalesce(forestry_source, "EUROSTAT_NAMA"),
                "GLORIA_share"),
        levels = forestry_route_levels),
      share_non_fabio       = share_seeds_gloria + share_forestry,
      wb_ag_va_reduced      = wb_ag_va_usd * (1 - share_non_fabio)
    )
  
  # Pick the denominator for this variant.
  wb <- wb %>%
    mutate(wb_ref = if (denominator == "raw") wb_ag_va_usd else wb_ag_va_reduced)
  
  missing_wb <- setdiff(unique(pipelines$iso3c), wb$iso3c)
  if (length(missing_wb)) {
    message("[", year_select, "/", denominator, "] dropped ",
            length(missing_wb),
            " countries with no non-zero WB ag value-added: ",
            paste(missing_wb, collapse = ", "))
  }
  
  dat <- pipelines %>%
    inner_join(wb, by = "iso3c") %>%
    mutate(share = value_usd / wb_ref)
  
  if (!nrow(dat)) {
    message("[", year_select, "/", denominator,
            "] no joinable rows; skipping.")
    return(invisible(NULL))
  }
  
  # Group small items into "Other" per (pipeline, country).  The test is
  # on |share| so a heavily-subsidized item with share = -0.5 in some
  # country still keeps its identity rather than being lumped in with
  # genuinely small contributions.  Note also that the threshold is
  # measured against the chosen denominator, so the same item may be
  # Other in one variant but named in the other — that's the natural
  # reading ("small relative to which WB?") and consistent with how each
  # chart presents itself.
  dat_grouped <- dat %>%
    mutate(item_grp = if_else(abs(share) < threshold, "Other", item)) %>%
    group_by(pipeline, iso3c, item_grp) %>%
    summarise(share = sum(share, na.rm = TRUE), .groups = "drop") %>%
    rename(item = item_grp)
  
  # Legend order: follow the canonical comm_group order (groups by total
  # value_added desc, items within each group by total desc), intersected
  # with whatever items actually appear in this chart. This keeps adjacent
  # legend swatches as related shades of the same hue. "Other" pinned at
  # end. Defensive append for any item not in canonical (shouldn't happen
  # with current data, but a new item shouldn't crash the chart).
  present_items <- setdiff(unique(as.character(dat_grouped$item)), "Other")
  item_order    <- c(canonical_item_order[canonical_item_order %in% present_items],
                     setdiff(present_items, canonical_item_order))
  
  fill_levels <- c(item_order, "Other")
  dat_grouped <- mutate(dat_grouped, item = factor(item, levels = fill_levels))
  
  # Colour mapping comes from the global item palette so every item gets
  # the same colour across years and across the per-country charts.
  fill_colors <- item_colors[fill_levels]
  
  legend_name <- "FABIO item"
  legend_ncol <- 6
  
  # Variant-specific output filename, title, subtitle, y label.
  variant_tag    <- if (denominator == "raw") "raw-WB" else "reduced-WB"
  variant_title  <- if (denominator == "raw") "(full WB)" else "(FABIO-comparable WB)"
  out_file       <- file.path(
    out_dir, sprintf("fabio_validation_%d_%s.svg", year_select, variant_tag))
  
  y_axis_label <- if (denominator == "raw") {
    "Share of WB agricultural value-added"
  } else {
    "Share of FABIO-comparable WB agricultural value-added"
  }
  
  subtitle_txt <- if (denominator == "raw") {
    sprintf(
      paste0("Stacked items are FABIO value-added as a share of FULL WB ",
             "agricultural VA (black dashed line = 100%%; negative WB rows ",
             "are kept and produce above-the-line bars when FABIO matches ",
             "the negative direction). Grey tick per country = where the ",
             "FABIO-comparable WB sits (= WB minus seeds [GLORIA share of ",
             "sector 15] and forestry [measured A02 where available, else ",
             "GLORIA share of sector 21]). Coloured square under each country ",
             "= forestry deduction route (see legend). Items whose |share| is ",
             "below %.0f%% per country are grouped as \"Other\". Countries ",
             "ordered by full WB agricultural value-added (largest first; ",
             "negatives at the end). Y axis clipped to [-100%%, 300%%]. ",
             "Facet rows as labelled: primary (ISIC-A) vs processing ",
             "(ISIC-C) layers; comparison figures interleave the bases ",
             "within each level."),
      threshold * 100
    )
  } else {
    sprintf(
      paste0("Stacked items are FABIO value-added as a share of FABIO-",
             "comparable WB agricultural VA (= WB minus seeds [GLORIA share ",
             "of sector 15] and forestry [measured A02 from Eurostat/OECD ",
             "where available, else GLORIA share of sector 21]; black dashed ",
             "line = 100%%; negative WB rows are kept). Grey tick per country ",
             "= where the FULL WB sits relative to the reduced one ",
             "(= 1 / (1 - share)). Coloured square under each country = ",
             "forestry deduction route (see legend). Items whose |share| ",
             "is below %.0f%% per country are grouped as \"Other\". ",
             "Countries ordered by full WB agricultural value-added ",
             "(largest first; negatives at the end). Y axis clipped to ",
             "[-100%%, 300%%]. Facet rows as labelled: primary (ISIC-A) vs ",
             "processing (ISIC-C) layers; comparison figures interleave the ",
             "bases within each level."),
      threshold * 100
    )
  }
  
  # Countries ordered by RAW WB ag value-added (largest first) — keeps
  # the "biggest agricultural countries first" intuition independent of
  # which denominator drives the bar shares, so the two variants share
  # the same x-axis order.
  country_order <- wb %>%
    filter(iso3c %in% unique(dat_grouped$iso3c)) %>%
    arrange(desc(wb_ag_va_usd)) %>%
    pull(iso3c)
  
  dat_grouped <- mutate(dat_grouped,
                        iso3c = factor(iso3c, levels = country_order))
  
  # Per-country secondary reference: where the OTHER WB sits relative to
  # the chosen denominator's y=1.  Drawn as a horizontal tick (errorbar
  # with ymin == ymax) over each bar; same factor levels as dat_grouped
  # so positions line up; repeats across both facet rows automatically.
  country_other_ref <- wb %>%
    filter(iso3c %in% country_order) %>%
    mutate(other_ref = if (denominator == "raw") {
      1 - share_non_fabio
    } else {
      wb_ag_va_usd / wb_ag_va_reduced
    },
    iso3c = factor(iso3c, levels = country_order)) %>%
    select(iso3c, other_ref)
  
  # Per-country forestry-deduction ROUTE marker: a coloured square pinned just
  # above the bottom of the clip window under each country, so the figure shows
  # at a glance whether the forestry deduction was measured (Eurostat/OECD A02)
  # or the GLORIA-share fallback.  Country-level (no `pipeline` column), so it is
  # replicated into both facet rows automatically.
  route_tbl <- wb %>%
    filter(iso3c %in% country_order) %>%
    distinct(iso3c, forestry_route) %>%
    mutate(iso3c   = factor(iso3c, levels = country_order),
           route_y = -0.95)
  
  # ---- plot ----------------------------------------------------------------
  p <- ggplot(dat_grouped, aes(x = iso3c, y = share, fill = item)) +
    geom_col(width = 0.85, colour = NA) +
    geom_hline(yintercept = 1, linetype = "dashed", linewidth = 0.4) +
    geom_errorbar(data = country_other_ref,
                  aes(x = iso3c, ymin = other_ref, ymax = other_ref),
                  inherit.aes = FALSE,
                  colour = "grey50", linewidth = 0.4, width = 0.85) +
    geom_point(data = route_tbl,
               aes(x = iso3c, y = route_y, colour = forestry_route),
               inherit.aes = FALSE, shape = 15, size = 1.5) +
    facet_wrap(~ pipeline, ncol = 1, strip.position = "left", axes = "all_x",
               drop = FALSE) +
    scale_y_continuous(
      labels = percent_format(accuracy = 1),
      breaks = seq(-1, 3, by = 0.5),
      expand = expansion(mult = c(0, 0.02))
    ) +
    # Visual clip — DOES NOT drop data points, so stacking stays consistent
    # for bars whose total exceeds 300%.  Tail of any item that pushes the
    # stack past 300% (or below -100%) is simply painted out of frame.
    coord_cartesian(ylim = c(-1, 3)) +
    scale_fill_manual(
      values = fill_colors,
      name   = legend_name,
      drop   = FALSE          # show every level in the legend, even if absent
    ) +
    scale_colour_manual(
      values       = forestry_route_colors,
      labels       = forestry_route_labels,
      name         = "Forestry source",
      drop         = FALSE,
      na.translate = FALSE
    ) +
    labs(
      title    = sprintf(
        "FABIO value-added [%s] vs World Bank agricultural value-added %s, %d",
        source_name, variant_title, year_select),
      subtitle = subtitle_txt,
      x = NULL,
      y = y_axis_label
    ) +
    theme_minimal(base_size = 10) +
    theme(
      axis.text.x        = element_text(angle = 90, vjust = 0.5, hjust = 1, size = 7),
      panel.grid.major.x = element_blank(),
      panel.spacing.y    = unit(1, "lines"),
      strip.text.y.left  = element_text(angle = 0, face = "bold"),
      strip.placement    = "outside",
      legend.position    = "bottom",
      legend.box         = "vertical",   # stack item + route legends, don't compete for width
      legend.key.size    = unit(0.35, "cm"),
      legend.text        = element_text(size = 7),
      plot.title         = element_text(face = "bold")
    ) +
    guides(fill   = guide_legend(ncol = legend_ncol, byrow = TRUE),
           colour = guide_legend(ncol = 3, order = 1,
                                 override.aes = list(size = 3)))
  
  # ---- size & write --------------------------------------------------------
  n_countries   <- n_distinct(dat_grouped$iso3c)
  svg_width     <- max(20, n_countries * 0.18)
  n_legend_rows <- ceiling(length(fill_levels) / legend_ncol)
  # Height scales with the number of facet rows (2 for a single source, 4 for
  # the base-comparison figures) at 4.5in per panel — for 2 panels this
  # reproduces the previous fixed 9in.  +0.5in reserves room for the route
  # legend now stacked under the item legend.
  n_panels      <- nlevels(dat_grouped$pipeline)
  svg_height    <- 4.5 * n_panels + 0.25 * n_legend_rows + 0.5
  
  ggsave(out_file, p,
         width = svg_width, height = svg_height,
         limitsize = FALSE, device = "svg")
  
  message(sprintf("[%d/%s] wrote %s  (%.1f x %.1f in, %d countries)",
                  year_select, denominator, out_file,
                  svg_width, svg_height, n_countries))
}

# ---- 6b. per-country time-series chart builder ------------------------------
# Threshold-based grouping into "Other" using MAX share across years (so the
# legend is stable across the x axis).
#
# Y axis is absolute USD. A black line/points overlay shows the WB ag value-added
# for the same country/years (when available) so absolute over- / undershoot
# is directly readable.
# `pipelines_all`, `out_dir_country` and `source_name` are passed in by the
# per-source driver (section 7); all other inputs are source-independent and
# inherited.  `source_name` goes into the title (see make_chart).
# `primary_panels` names the facet level(s) that represent primary agriculture
# (ISIC-A) — the WB overlay lines are stamped into exactly those panels.  For
# a single source that's the one "Primary (ISIC-A)" row (the default); for the
# base-comparison figures (section 9) it's BOTH bases' primary rows, so each
# base is read against the same WB reference.
# `measure` selects what the bars stack: "total" reproduces the original
# figure exactly (value_added [USD], WB + reduced-WB overlays, original file
# name); "wages"/"capital"/"tls" stack the matching component-split column
# instead, drop the WB overlays (the WB headline has no strand decomposition)
# and stamp the external A01+A03 strand benchmark (section 3c) into the
# primary row(s) where it covers this country.  The "Other" grouping is
# decided from the TOTAL measure for every figure, so a country's four
# figures share one item set and legend.
make_country_chart <- function(iso_select, pipelines_all, out_dir_country,
                               source_name,
                               primary_panels = pipeline_levels[1],
                               measure = "total") {
  
  # Pipeline data for this country, restricted to the WB-overlapping years
  pipelines <- pipelines_all %>%
    filter(iso3c == iso_select, year %in% available_years) %>%
    left_join(items_map, by = "item_code") %>%
    mutate(item = if_else(is.na(item),
                          paste0("[unmapped:", item_code, "]"),
                          item))
  
  if (!nrow(pipelines)) {
    message("[", iso_select, "] no pipeline rows; skipping.")
    return(invisible(NULL))
  }
  
  # Column the bars stack for this measure.  `value_usd` (TOTAL) is also kept
  # around regardless, because the "Other" grouping below is always decided
  # from the TOTAL shares — that keeps a country's four figures on one item
  # set / legend.
  value_col <- if (measure == "total") "value_usd" else paste0("value_", measure)
  pipelines <- mutate(pipelines, value_plot = .data[[value_col]])
  if (measure != "total" &&
      !any(is.finite(pipelines$value_plot) & pipelines$value_plot != 0)) {
    message("[", iso_select, "/", measure, "] no strand data; skipping.")
    return(invisible(NULL))
  }
  
  # External A01+A03 benchmark rows for this (country, strand) — section 3c.
  # NULL/empty for the TOTAL measure (which has the WB overlays instead) and
  # for countries outside the scripts-02/03 coverage.
  bench_iso <- if (measure != "total" && !is.null(strand_bench)) {
    filter(strand_bench, iso3c == iso_select, strand == measure,
           year %in% available_years)
  } else {
    NULL
  }
  
  # WB time series for this country (long form). May be empty.  Drop only
  # NA / zero WB rows; negative values are kept on purpose (the per-country
  # chart's y axis is absolute USD, so a negative WB just dips below zero).
  wb_year_cols <- intersect(as.character(available_years), names(wb_raw))
  wb_country <- wb_raw %>%
    filter(`Country Code` == iso_select) %>%
    select(all_of(wb_year_cols)) %>%
    pivot_longer(everything(),
                 names_to  = "year",
                 values_to = "wb_ag_va_usd") %>%
    mutate(year = as.integer(year)) %>%
    filter(!is.na(wb_ag_va_usd), wb_ag_va_usd != 0)
  
  # Pretty country name from WB if available
  country_name <- wb_raw %>%
    filter(`Country Code` == iso_select) %>%
    pull(`Country Name`) %>%
    {if (length(.)) .[1] else NA_character_}
  title_country <- if (!is.na(country_name) && nzchar(country_name)) {
    sprintf("%s (%s)", country_name, iso_select)
  } else {
    iso_select
  }
  
  # Decide which items to demote to "Other" for this country: demote an
  # item only when we have EVIDENCE its MAX |share| of WB across years
  # stays below `threshold`.  Using |share| means heavily-subsidized
  # items (consistently negative share) keep their identity rather than
  # always passing the test from the negative side.  Items with no WB
  # overlap (so no share computable) stay named — we don't disqualify
  # what we can't evaluate.
  keep_items <- unique(pipelines$item)
  if (nrow(wb_country)) {
    shares <- pipelines %>%
      inner_join(wb_country, by = "year") %>%
      mutate(share = value_usd / wb_ag_va_usd) %>%
      group_by(item) %>%
      summarise(max_abs_share = max(abs(share), na.rm = TRUE),
                .groups = "drop")
    
    drop_items <- shares %>%
      filter(max_abs_share < threshold) %>%
      pull(item)
    
    keep_items <- setdiff(keep_items, drop_items)
  }
  
  dat_grouped <- pipelines %>%
    mutate(item = if_else(item %in% keep_items, item, "Other")) %>%
    group_by(pipeline, year, item) %>%
    summarise(value_plot = sum(value_plot, na.rm = TRUE), .groups = "drop")
  
  # Legend order: same canonical comm_group ordering as the per-year
  # charts (groups by total value_added desc, items within each group by
  # total desc), so the same item is in the same position relative to its
  # group across every chart. "Other" pinned at end.
  present_items <- setdiff(unique(as.character(dat_grouped$item)), "Other")
  item_order    <- c(canonical_item_order[canonical_item_order %in% present_items],
                     setdiff(present_items, canonical_item_order))
  
  fill_levels <- c(item_order, "Other")
  dat_grouped <- mutate(dat_grouped, item = factor(item, levels = fill_levels))
  
  # Same global item palette as the per-year charts.
  fill_colors <- item_colors[fill_levels]
  
  legend_name <- "FABIO item"
  legend_ncol <- 4
  if (measure == "total") {
    out_file    <- file.path(
      out_dir_country,
      sprintf("fabio_validation_country_%s.svg", iso_select)
    )
    title_txt   <- sprintf(
      "FABIO value-added [%s] vs World Bank agricultural value-added — %s",
      source_name, title_country)
    subtitle_txt <- sprintf(
      paste0("FABIO value-added per item for %s; items below %.0f%% max |share| ",
             "of WB across years are grouped as \"Other\". Primary (ISIC-A) ",
             "row(s) only: black line = WB ag VA; grey dashed line = FABIO-",
             "comparable WB (WB minus seeds + forestry), open points coloured ",
             "by forestry source (see legend). Rows as labelled: primary ",
             "(ISIC-A) vs processing (ISIC-C); comparison figures interleave ",
             "the bases within each level."),
      title_country, threshold * 100
    )
  } else {
    out_file    <- file.path(
      out_dir_country,
      sprintf("fabio_validation_country_%s_%s.svg", iso_select, measure)
    )
    title_txt   <- sprintf(
      "FABIO %s [%s] — %s (value-added sub-account)",
      MEASURE_TITLE[[measure]], source_name, title_country)
    bench_note  <- if (!is.null(bench_iso) && nrow(bench_iso)) {
      sprintf(paste0("Blue line/triangles on the Primary (ISIC-A) row(s) = ",
                     "external A01+A03 %s benchmark (%s; exported by scripts ",
                     "02/03), a primary-agriculture, forestry-free reference ",
                     "for the covered years. "),
              MEASURE_TITLE[[measure]],
              paste(sort(unique(bench_iso$bench_source)), collapse = " / "))
    } else {
      "No external strand benchmark covers this country. "
    }
    subtitle_txt <- sprintf(
      paste0("FABIO %s per item for %s — a FABIO-internal decomposition of ",
             "value-added; the World Bank reference exists only as a TOTAL, ",
             "so no WB line is drawn here. %sItems grouped as \"Other\" ",
             "exactly as in the TOTAL figure (below %.0f%% max |share| of WB ",
             "total across years), so the country's figures share one legend. ",
             "Rows as labelled: primary (ISIC-A) vs processing (ISIC-C); ",
             "comparison figures interleave the bases within each level."),
      MEASURE_TITLE[[measure]], title_country, bench_note, threshold * 100
    )
  }
  
  if (!nrow(dat_grouped)) {
    message("[", iso_select, "] no rows after aggregation; skipping.")
    return(invisible(NULL))
  }
  
  # ---- plot ----------------------------------------------------------------
  # Build WB layers only when WB data exists; this keeps geom args clean.
  #
  # We restrict the WB lines to the primary (ISIC-A) facet row(s) by stamping
  # those layers' data with the panel level(s) in `primary_panels`. ggplot's
  # facet_wrap then routes the layer to those panels only. WB Agriculture
  # value-added is conceptually a reference for primary agriculture (ISIC-A);
  # overlaying it on the processing layer (ISIC-C) is apples-to-oranges and
  # was visual clutter. The cross-country yearly charts still show both WB
  # references in both rows because there the y=1 line / grey tick are the
  # comparison itself, not a side overlay.  In the base-comparison figures
  # `primary_panels` holds BOTH bases' primary rows, so the identical WB
  # reference is repeated into each — what differs between the panels is then
  # the bars alone.
  panel_levels   <- levels(pipelines$pipeline)
  .stamp_primary <- function(df) {
    bind_rows(lapply(primary_panels, function(pp)
      mutate(df, pipeline = factor(pp, levels = panel_levels))))
  }
  
  # WB overlays only on the TOTAL figure — the WB headline has no strand
  # decomposition, so on strand figures these layers are simply absent.
  wb_line_layers <- if (measure == "total" && nrow(wb_country)) {
    wb_country_primary <- .stamp_primary(wb_country)
    list(
      geom_line(data = wb_country_primary,
                aes(x = year, y = wb_ag_va_usd),
                inherit.aes = FALSE,
                colour = "black", linewidth = 0.6),
      geom_point(data = wb_country_primary,
                 aes(x = year, y = wb_ag_va_usd),
                 inherit.aes = FALSE,
                 colour = "black", size = 1.2)
    )
  } else {
    list()
  }
  
  # Reduced WB reference: WB × (1 - share_non_fabio).  Built only when both
  # WB data and a share are available for this country.  Grey + dashed +
  # open points to read clearly as a "reference variant" of the black line.
  # Same Primary-only restriction as the raw WB line above.
  wb_country_reduced <- wb_country %>%
    inner_join(filter(share_by_iso, iso3c == iso_select),
               by = "year") %>%
    # Same forestry routing as the per-year charts: measured external A02 as a
    # share of WB where available, else GLORIA forestry share; seeds always
    # GLORIA.  `forestry_route` colours the reduced-WB points so the time series
    # shows, year by year, where the forestry deduction came from.
    mutate(
      share_seeds_gloria    = coalesce(share_seeds_gloria, 0),
      share_forestry_gloria = coalesce(share_forestry_gloria, 0),
      use_external_forestry = is.finite(forestry_total_usd) & wb_ag_va_usd != 0,
      share_forestry        = if_else(use_external_forestry,
                                      forestry_total_usd / wb_ag_va_usd,
                                      share_forestry_gloria),
      forestry_route        = factor(
        if_else(use_external_forestry,
                coalesce(forestry_source, "EUROSTAT_NAMA"),
                "GLORIA_share"),
        levels = forestry_route_levels),
      share_non_fabio       = share_seeds_gloria + share_forestry,
      wb_ag_va_reduced_usd  = wb_ag_va_usd * (1 - share_non_fabio)
    ) %>%
    filter(is.finite(wb_ag_va_reduced_usd))
  
  wb_reduced_layers <- if (measure == "total" && nrow(wb_country_reduced)) {
    wb_country_reduced_primary <- .stamp_primary(wb_country_reduced)
    list(
      geom_line(data = wb_country_reduced_primary,
                aes(x = year, y = wb_ag_va_reduced_usd),
                inherit.aes = FALSE,
                colour = "grey50", linewidth = 0.6, linetype = "dashed"),
      # Open points coloured by the forestry route (green = Eurostat, purple =
      # OECD, grey = GLORIA-share fallback), so the route is readable per year.
      geom_point(data = wb_country_reduced_primary,
                 aes(x = year, y = wb_ag_va_reduced_usd, colour = forestry_route),
                 inherit.aes = FALSE,
                 fill = "white", size = 1.9, shape = 21, stroke = 0.9),
      scale_colour_manual(
        values       = forestry_route_colors,
        labels       = forestry_route_labels,
        name         = "Forestry source",
        drop         = FALSE,
        na.translate = FALSE
      )
    )
  } else {
    list()
  }
  
  # External A01+A03 strand benchmark (section 3c), stamped into the primary
  # row(s) like the WB overlays — it is a primary-agriculture reference.
  # Blue + triangles so it cannot be confused with the TOTAL figure's black
  # WB line; typically only a few covered years (02/03 validation years), so
  # it reads as anchor points rather than a full series.
  bench_layers <- if (!is.null(bench_iso) && nrow(bench_iso)) {
    bench_primary <- .stamp_primary(bench_iso)
    list(
      geom_line(data = bench_primary,
                aes(x = year, y = bench_usd),
                inherit.aes = FALSE,
                colour = "#0072B2", linewidth = 0.6),
      geom_point(data = bench_primary,
                 aes(x = year, y = bench_usd),
                 inherit.aes = FALSE,
                 colour = "#0072B2", shape = 17, size = 1.8)
    )
  } else {
    list()
  }
  
  # TLS (and occasionally other strands) can be net negative where subsidies
  # exceed taxes; give those figures a thin zero baseline and a little bottom
  # expansion instead of pinning the columns to the panel floor.
  has_neg     <- any(dat_grouped$value_plot < 0, na.rm = TRUE)
  zero_layers <- if (has_neg) {
    list(geom_hline(yintercept = 0, linewidth = 0.3, colour = "grey70"))
  } else {
    list()
  }
  
  p <- ggplot(dat_grouped, aes(x = year, y = value_plot, fill = item)) +
    geom_col(width = 0.85, colour = NA) +
    zero_layers +
    wb_line_layers +
    wb_reduced_layers +
    bench_layers +
    facet_wrap(~ pipeline, ncol = 1, strip.position = "left", axes = "all_x",
               drop = FALSE) +
    scale_y_continuous(
      labels = usd_axis_labels,
      expand = expansion(mult = c(if (has_neg) 0.04 else 0, 0.02))
    ) +
    scale_x_continuous(breaks = available_years) +
    scale_fill_manual(
      values = fill_colors,
      name   = legend_name,
      drop   = FALSE
    ) +
    labs(
      title    = title_txt,
      subtitle = subtitle_txt,
      x = NULL,
      y = MEASURE_AXIS[[measure]]
    ) +
    theme_minimal(base_size = 10) +
    theme(
      axis.text.x        = element_text(angle = 90, vjust = 0.5, hjust = 1, size = 7),
      panel.grid.major.x = element_blank(),
      panel.spacing.y    = unit(1, "lines"),
      strip.text.y.left  = element_text(angle = 0, face = "bold"),
      strip.placement    = "outside",
      legend.position    = "bottom",
      legend.box         = "vertical",   # stack item + route legends, don't compete for width
      legend.key.size    = unit(0.35, "cm"),
      legend.text        = element_text(size = 7),
      plot.title         = element_text(face = "bold")
    ) +
    guides(fill   = guide_legend(ncol = legend_ncol, byrow = TRUE),
           colour = guide_legend(ncol = 3, order = 1,
                                 override.aes = list(size = 3, stroke = 0.9)))
  
  # ---- size & write --------------------------------------------------------
  n_years       <- length(available_years)
  svg_width     <- max(10, n_years * 0.4)
  n_legend_rows <- ceiling(length(fill_levels) / legend_ncol)
  # Height scales with the number of facet rows (2 for a single source, 4 for
  # the base-comparison figures) at 4in per panel — for 2 panels this
  # reproduces the previous fixed 8in.  +0.8in reserves room for the route
  # legend stacked under the item legend (the per-country plot is narrow, so
  # legends need explicit vertical budget).
  n_panels      <- length(panel_levels)
  svg_height    <- 4 * n_panels + 0.25 * n_legend_rows + 0.8
  
  ggsave(out_file, p,
         width = svg_width, height = svg_height,
         limitsize = FALSE, device = "svg")
  
  message(sprintf("[%s/%s] wrote %s  (%.1f x %.1f in, %d years)",
                  iso_select, measure, out_file,
                  svg_width, svg_height, n_years))
}

# ---- 7. per-source output driver -------------------------------------------
# Both loops fan out via parallel::mclapply on Unix (fork-based — the big
# shared tables are inherited copy-on-write, no per-worker re-read). Windows
# can't fork, so we silently fall back to sequential lapply. Set
# do_parallel <- FALSE to disable for debugging (mclapply swallows interactive
# errors and hides traceback noise — when something breaks, run serially first).
.par_apply <- if (do_parallel && .Platform$OS.type == "unix" && n_cores > 1L) {
  function(X, FUN, ...) parallel::mclapply(X, FUN, ..., mc.cores = n_cores)
} else {
  function(X, FUN, ...) lapply(X, FUN, ...)
}

if (do_parallel && .Platform$OS.type == "unix" && n_cores > 1L) {
  message(sprintf("Parallelizing chart generation across %d cores.", n_cores))
} else if (do_parallel && .Platform$OS.type != "unix") {
  message("do_parallel = TRUE but platform is not Unix; running sequentially.")
}

# Build the full chart set for ONE source (its two ISIC levels are already the
# two facet rows in `src_pipelines`).  Writes to <out_dir_base>/<subdir>/ and
# .../by_country/.  `primary_panels` is forwarded to make_country_chart; the
# default covers the single-source case, the comparison driver (section 9)
# overrides it with both bases' primary rows.  `measures` lists the per-country
# figures to build ("total" plus, where the source carries the component-split
# columns, the strands) — the per-year charts (A) are TOTAL-only regardless,
# being shares of the strand-less WB headline.
run_source_outputs <- function(src, src_pipelines,
                               primary_panels = pipeline_levels[1],
                               measures = "total") {
  out_dir         <- file.path(out_dir_base, src$subdir)
  out_dir_country <- file.path(out_dir, "by_country")
  dir.create(out_dir,         recursive = TRUE, showWarnings = FALSE)
  dir.create(out_dir_country, recursive = TRUE, showWarnings = FALSE)
  
  message(sprintf("\n=== Source: %s  ->  %s ===", src$name, out_dir))
  
  # (A) per-year cross-country charts — one SVG per year.
  # The "reduced-WB" denominator variant is intentionally NOT produced (set
  # `denoms <- c("raw", "reduced")` to bring it back).  The reduced WB still
  # shows up on the raw charts as the per-country grey tick, so no information
  # is lost — only the second, redundant SVG per year is dropped.
  if (do_yearly_charts) {
    denoms <- "raw"
    yearly_jobs <- expand.grid(
      yr    = available_years,
      denom = denoms,
      stringsAsFactors = FALSE,
      KEEP.OUT.ATTRS   = FALSE
    )
    invisible(.par_apply(seq_len(nrow(yearly_jobs)), function(i) {
      make_chart(yearly_jobs$yr[i], yearly_jobs$denom[i],
                 pipelines_all = src_pipelines, out_dir = out_dir,
                 source_name = src$name)
    }))
  }
  
  # (B) per-country time-series charts — one TOTAL figure per country plus,
  # when `measures` includes them, one figure per VA strand (family B').
  if (do_country_charts) {
    all_countries <- src_pipelines %>%
      filter(year %in% available_years) %>%
      distinct(iso3c) %>%
      arrange(iso3c) %>%
      pull(iso3c)
    
    country_jobs <- expand.grid(
      iso     = all_countries,
      measure = measures,
      stringsAsFactors = FALSE,
      KEEP.OUT.ATTRS   = FALSE
    )
    
    message("Building per-country time-series charts for ",
            length(all_countries), " countries x ",
            length(measures), " measure(s) [",
            paste(measures, collapse = ", "), "].")
    
    invisible(.par_apply(seq_len(nrow(country_jobs)), function(i) {
      make_country_chart(country_jobs$iso[i],
                         pipelines_all   = src_pipelines,
                         out_dir_country = out_dir_country,
                         source_name     = src$name,
                         primary_panels  = primary_panels,
                         measure         = country_jobs$measure[i])
    }))
  }
}

# ---- 8. run every source ---------------------------------------------------
for (src in sources) {
  measures_src <- if (do_strand_charts && isTRUE(strands_by_source[[src$name]])) {
    MEASURES
  } else {
    "total"
  }
  run_source_outputs(src, pipelines_by_source[[src$name]],
                     measures = measures_src)
}

# ---- 9. base-comparison figures (GLORIA vs EXIOBASE in ONE chart) -----------
# For each comparison pair below, the two members' pipelines are stacked into
# a single tibble whose `pipeline` factor becomes base x ISIC level, ordered
# so the two bases sit DIRECTLY above each other within each ISIC level:
#   <GLORIA>  Primary (ISIC-A)
#   <EXIOBASE> Primary (ISIC-A)
#   <GLORIA>  Processing (ISIC-C)
#   <EXIOBASE> Processing (ISIC-C)
# The existing builders then do the rest unchanged: facet_wrap on `pipeline`
# renders one panel per (base, level); the WB references, country order
# (per-year charts) / x axis (country charts), y clipping and the shared item
# palette are identical across panels by construction — so any difference
# between two adjacent panels IS the difference between the bases.  The WB
# overlay of the per-country charts is stamped into BOTH bases' primary rows
# via `primary_panels`.
#
# A pair is only built when both members survived the input-file check above;
# otherwise it is skipped with a message (e.g. before the EXIOBASE branch has
# been produced).
comparisons <- list(
  list(
    name    = "GLORIA vs EXIOBASE",
    subdir  = "comparison_base",
    members = c("GLORIA", "EXIOBASE")
  ),
  list(
    name    = "COMBINED: GLORIA vs EXIOBASE",
    subdir  = "comparison_combined",
    members = c("COMBINED_GLORIA", "COMBINED_EXIOBASE")
  )
)

# Panel label: "<base>\n<ISIC level>" — the newline keeps the left strips
# narrow.  Level order interleaves the bases within each ISIC level (see
# above).
.panel_label <- function(member, level) paste0(member, "\n", level)

build_comparison_pipelines <- function(members) {
  panel_levels <- as.vector(vapply(
    pipeline_levels,
    function(lv) vapply(members, .panel_label, character(1), level = lv),
    character(length(members))
  ))
  dat <- bind_rows(lapply(members, function(m) {
    pipelines_by_source[[m]] %>%
      mutate(pipeline = .panel_label(m, as.character(pipeline)))
  })) %>%
    mutate(pipeline = factor(pipeline, levels = panel_levels))
  list(
    pipelines      = dat,
    # Both bases' primary rows — the WB overlay repeats into each.
    primary_panels = vapply(members, .panel_label, character(1),
                            level = pipeline_levels[1])
  )
}

for (cmp in comparisons) {
  if (!all(cmp$members %in% names(pipelines_by_source))) {
    message("NOTE: skipping comparison '", cmp$name, "' — missing source(s): ",
            paste(setdiff(cmp$members, names(pipelines_by_source)),
                  collapse = ", "))
    next
  }
  cmp_dat <- build_comparison_pipelines(cmp$members)
  # Strand figures for a comparison only when BOTH members carry the
  # component-split columns — half a comparison would be misleading.
  measures_cmp <- if (do_strand_charts && all(strands_by_source[cmp$members])) {
    MEASURES
  } else {
    "total"
  }
  run_source_outputs(list(name = cmp$name, subdir = cmp$subdir),
                     cmp_dat$pipelines,
                     primary_panels = cmp_dat$primary_panels,
                     measures       = measures_cmp)
}

message("\nAll sources done.")