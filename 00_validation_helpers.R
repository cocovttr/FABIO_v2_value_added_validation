# ==============================================================================
# 00_validation_helpers.R — shared agreement metrics and symlog scatter panels
#                           for the FABIO value-added validators, which run in
#                           number order: 01 BioSAMs, 02 national SUTs / IOTs
#                           (USA, Japan), 03 global agricultural GDP.  01 and 02
#                           are independent of each other; 03 reads the A01+A03
#                           benchmark CSVs both of them export.
#
# Sourced via the validation-repo anchor so it resolves regardless of working
# directory:  source(validation_path("00_validation_helpers.R"))
#
# Expects data.table and ggplot2 to be attached by the caller.
# Everything except va_metrics() also expects the caller's measure ordering,
#     MEASURES = c("total", "wages", "capital", "tls")
# ==============================================================================


# ── Display vocabulary ───────────────────────────────────────────────────────
#
# Every figure plots one value-added extension against one reference, so both
# axes name a dataset and the quantity read off it, and both are built from
# va_axis_label().  "value added" is the noun, "value-added" the attributive
# ("value-added component"); the unit and the scale go in one trailing
# parenthetical, the scale named only where it is not linear.

#' Base name of a value-added source, keyed by the script-03 source tags and by
#' the `source`-column values scripts 01 / 02 carry.  An unmapped source falls
#' through to itself.
VA_SOURCE_BASE <- c(
  # script 03 source tags
  GLORIA                              = "GLORIA",
  COMBINED_GLORIA                     = "COMBINED-GLORIA",
  EXIOBASE                            = "EXIOBASE",
  COMBINED_EXIOBASE                   = "COMBINED-EXIOBASE",
  # script 01 `source` values (FABIO items aggregated up to BioSAM categories)
  `GLORIA-FABIOv2 (agg.)`             = "GLORIA",
  `COMBINED-GLORIA-FABIOv2 (agg.)`    = "COMBINED-GLORIA",
  `EXIOBASE-FABIOv2 (agg.)`           = "EXIOBASE",
  `COMBINED-EXIOBASE-FABIOv2 (agg.)`  = "COMBINED-EXIOBASE",
  # script 02 `source` values (reference industries disaggregated to items)
  `GLORIA-FABIOv2 (disagg.)`           = "GLORIA",
  `COMBINED-GLORIA-FABIOv2 (disagg.)`  = "COMBINED-GLORIA",
  `EXIOBASE-FABIOv2 (disagg.)`         = "EXIOBASE",
  `COMBINED-EXIOBASE-FABIOv2 (disagg.)`= "COMBINED-EXIOBASE")

#' Display name for a source: the axis form, "FABIO-v2 value-added extension,
#' GLORIA", names the quantity itself, so the axis template leaves its measure
#' slot empty on total figures; the title form, "GLORIA extension", is what a
#' title needs once the axis carries the rest.
#'
#' The (agg.) / (disagg.) qualifier is a property of the comparison rather than
#' of the extension — 01 aggregates the source up, 02 disaggregates the
#' reference down — so it is stated in the subtitle (`note`) instead.
va_source_label <- function(x, form = c("axis", "title")) {
  form <- match.arg(form)
  base <- unname(VA_SOURCE_BASE[as.character(x)])
  base <- ifelse(is.na(base), as.character(x), base)
  if (form == "axis") sprintf("FABIO-v2 value-added extension, %s", base)
  else                sprintf("%s extension", base)
}

#' The scored measures, for axis titles, figure titles and the component legend
#' alike.  `tls` is the production-side measure throughout (see the header of
#' script 01); the qualifier lives in the subtitles rather than in the name.
VA_MEASURE <- c(total   = "value added",
                wages   = "wages",
                capital = "capital",
                tls     = "taxes less subsidies")

#' Axis title: "<dataset>[, <measure>][, <scope>] (<unit>[, <scale>])".
#' `measure` is left NULL where the dataset name already states the quantity,
#' and `scope` is used only where the figure is scope-restricted — where it
#' facets by scope the strip already says so.  The parenthetical is the unit and
#' the scale alone; the scope belongs to the series, not to the unit.
#'
#' A log10 scale is returned as plotmath so the 10 sets as a true subscript,
#' matching the scientific notation on the ticks.
va_axis_label <- function(dataset, measure = NULL, scope = NULL,
                          unit = "current US$", scale = NULL) {
  txt <- sprintf("%s%s%s (%s)", dataset,
                 if (is.null(measure)) "" else paste0(", ", measure),
                 if (is.null(scope))   "" else paste0(", ", scope),
                 paste(c(unit, scale), collapse = ", "))
  if (!grepl("log10", txt, fixed = TRUE)) return(txt)
  parse(text = sprintf('"%s"[10]*"%s"',
                       sub("log10.*$", "log", txt),
                       sub("^.*log10", "", txt)))[[1]]
}


# ── Cells ────────────────────────────────────────────────────────────────────
#
# A comparison table is long over (iso3c, year, source, isic, category,
# component, value_usd).  Four cell resolutions are scored, disaggregating the
# components first and the items second:
#
#   L1  (iso3c, year)                            items and components summed
#   L2  (iso3c, year, component)                 items summed
#   L3  (iso3c, year, isic, category)            components summed
#   L4  (iso3c, year, isic, category, component)
#
# `total` is the cell value exactly where the resolution sums the components
# away, at L1 and L3; L2 and L4 carry the three components as separate rows
# instead.  The item key carries its ISIC section because a category can
# contribute at both levels.

VA_LEVEL_KEYS <- list(L1 = c("iso3c", "year"),
                      L2 = c("iso3c", "year"),
                      L3 = c("iso3c", "year", "isic", "category"),
                      L4 = c("iso3c", "year", "isic", "category"))

VA_LEVEL_DESC <- c(L1 = "country x year, items and components summed",
                   L2 = "country x year x component, items summed",
                   L3 = "country x year x item, components summed",
                   L4 = "country x year x item x component")

#' One value per (source, cell, component) at the resolution `keys`.
#' `components` keeps the three VA components as separate rows; `total` appends
#' their sum, where a component absent from a cell counts as zero.
va_cells <- function(dat, keys, components = TRUE, total = TRUE) {
  s <- dat[is.finite(value_usd),
           .(value = sum(value_usd, na.rm = TRUE)),
           by = c("source", keys, "component")]
  rbindlist(list(
    if (components) s,
    if (total)      s[, .(component = "total", value = sum(value)),
                      by = c("source", keys)]
  ), use.names = TRUE)
}

va_level_cells <- function(dat, level) {
  keys <- VA_LEVEL_KEYS[[level]]
  switch(level,
         L1 = va_cells(dat, keys, components = FALSE),
         L2 = va_cells(dat, keys, total      = FALSE),
         L3 = va_cells(dat, keys, components = FALSE),
         L4 = va_cells(dat, keys, total      = FALSE))
}


# ── Matching ─────────────────────────────────────────────────────────────────

#' Pair every source in `cells` against the reference table `ref` (the cell keys
#' plus a `ref` column).  With `expand`, the cell universe is the union of the
#' two sides and an absent row is carried as a structural zero, so a source that
#' simply does not populate a cell registers as a coverage failure rather than
#' vanishing from the comparison.  The full grid is returned, empty cells
#' included, so `n` is the designed cell count; va_metrics() decides which of
#' them a given statistic is defined over.  Without `expand` the pairing is an
#' inner join.
va_match <- function(cells, ref, expand = TRUE) {
  keys <- setdiff(names(ref), "ref")
  if (!expand) {
    out <- merge(cells, ref, by = keys)
    setnames(out, "value", "src")
    return(out[])
  }
  srcs <- sort(unique(cells$source))
  univ <- unique(rbindlist(list(ref[, ..keys], cells[, ..keys]), use.names = TRUE))
  grid <- data.table(univ[rep(seq_len(nrow(univ)), length(srcs))],
                     source = rep(srcs, each = nrow(univ)))
  out  <- merge(merge(grid, ref, by = keys, all.x = TRUE),
                cells, by = c(keys, "source"), all.x = TRUE)
  out[is.na(ref),   ref   := 0]
  out[is.na(value), value := 0]
  setnames(out, "value", "src")
  out[]
}

#' va_match() where the reference is one of the sources in `cells`.
va_match_source <- function(cells, reference, expand = TRUE) {
  keys <- setdiff(names(cells), c("source", "value"))
  ref  <- cells[source == reference, c(keys, "value"), with = FALSE]
  setnames(ref, "value", "ref")
  va_match(cells[source != reference], ref, expand = expand)
}

#' The matched frames for a level cascade, named by level.
va_matched_levels <- function(dat, reference, levels) {
  setNames(lapply(levels, function(lv)
    va_match_source(va_level_cells(dat, lv), reference)), levels)
}


# ── Cross-level items ────────────────────────────────────────────────────────
#
# A FABIO item can carry a concordance row at BOTH ISIC levels, because the two
# levels describe different stages of the same commodity: 2848 "Milk -
# Excluding Butter" is raw milk at A and dairy products at C, 2511 "Wheat and
# products" is wheat farming at A and flour milling at C.  The MODEL, however,
# reads one strand per commodity — 35_bcp_value_added_extension.R takes the
# ISIC-A strand for items tagged A and the ISIC-C strand for items tagged C,
# never both — so the ISIC-C value added of an item the model uses at ISIC-A
# never reaches the results.  Validating it would score a quantity the research
# does not use, so those cells are out of scope.
#
# The exclusion has to take the whole ISIC-C mapping unit, on BOTH sides.
# Dropping the source rows alone leaves the reference figure covering items the
# source no longer supplies — the BioSAM dairy category would stand against
# Butter/Ghee alone, reading low by the whole milk strand — which is a worse
# artefact than the one being removed.

#' The ISIC-C mapping units (BioSAM categories, national industries) fed by any
#' FABIO item the concordance also tags at ISIC-A.  `conc` is long over
#' (fabio_item_code, isic, unit); the returned units are dropped from both
#' sides of the comparison.
va_crosslevel_c_units <- function(conc) {
  dual <- conc[isic %in% c("A", "C"), .(lv = uniqueN(isic)),
               by = fabio_item_code][lv > 1L, fabio_item_code]
  sort(unique(conc[isic == "C" & fabio_item_code %in% dual, unit]))
}


# ── Metrics ──────────────────────────────────────────────────────────────────
#
# All dispersion is in log10 units ("dex").  On the cells that are non-zero on
# both sides and of the same sign, with l = log10(|src| / |ref|):
#
#   med_ratio  = 10^median(l)
#   mad_fold   = 10^median(|l - median(l)|)
#   rmsle_dex  = sqrt(mean(l^2))         uncentred, about zero — the identity,
#                                        not the fitted centre, is the target
#
# reported alongside:
#
#   n          cells in the group — the designed grid, matching the cell counts
#              quoted in the write-up (55 country-years, 2,145 item cells)
#   n_pop      cells at least one side populates
#   n_used     cells surviving the non-zero + same-sign filter
#   coverage   share of POPULATED cells non-zero on both sides
#   sign_agree share of same-sign cells, among cells non-zero on both sides
#
# A cell zero on both sides is agreement on an empty cell, not a miss, so it is
# counted by n but by neither coverage nor sign_agree: whether such a cell is in
# the grid at all depends on which other sources populate it, which must not
# move a source's score.  n - n_pop is that empty remainder.
#
# sign_agree conditions on the non-zero cells so that a structural zero reads as
# missing coverage rather than as a sign flip; coverage carries that information.

VA_MIN_USED <- 10L

va_metrics <- function(ref, src) {
  pop <- ref != 0 | src != 0
  nz  <- ref != 0 & src != 0
  use <- nz & sign(ref) == sign(src)
  l   <- log10(abs(src[use]) / abs(ref[use]))
  ok  <- length(l) >= VA_MIN_USED
  data.table(
    n          = length(ref),
    n_pop      = sum(pop),
    n_used     = length(l),
    coverage   = if (any(pop)) sum(nz) / sum(pop) else NA_real_,
    sign_agree = if (any(nz)) sum(use) / sum(nz) else NA_real_,
    med_ratio  = if (ok) 10^median(l) else NA_real_,
    mad_fold   = if (ok) 10^median(abs(l - median(l))) else NA_real_,
    rmsle_dex  = if (ok) sqrt(mean(l^2)) else NA_real_)
}

#' One metric row per (component, source) pooling all cells of `matched`, plus —
#' with `by_item` — the same rows resolved within each item.
va_score <- function(matched, sources, level, by_item = FALSE) {
  m    <- matched[source %in% sources]
  rows <- m[, va_metrics(ref, src), by = .(component, source)]
  rows[, item := NA_character_]
  if (by_item)
    rows <- rbindlist(list(
      rows, m[, va_metrics(ref, src),
              by = .(component, source, item = category)]),
      use.names = TRUE)
  set(rows, j = "level", value = level)
  setcolorder(rows, c("level", "item", "component", "source", "n", "n_pop",
                      "n_used", "coverage", "sign_agree", "med_ratio",
                      "mad_fold", "rmsle_dex"))
  rows[order(match(component, MEASURES), match(source, sources), item)]
}

#' The tidy metrics table for a level cascade: va_score() down the levels of
#' `matched`, stacked, with the `level` column carrying the resolution.  The
#' per-item breakout needs an item key, so it applies to the item levels only.
va_metrics_table <- function(matched, sources, by_item = FALSE) {
  rbindlist(lapply(names(matched), function(lv)
    va_score(matched[[lv]], sources, lv,
             by_item = by_item && "category" %in% names(matched[[lv]]))))
}

#' The aggregate ratio frames behind the metrics: one row per (cell, source,
#' measure) with both sides and their signed ratio, at per-ISIC national scope
#' and at item scope.  Inner-joined, so only cells both sides populate appear.
va_write_ratio_frames <- function(dat, reference, sources, out_dir, prefix) {
  fab <- setdiff(sources, reference)
  frame <- function(keys, file) {
    m <- copy(va_match_source(va_cells(dat, keys), reference,
                              expand = FALSE)[source %in% fab])
    setnames(m, c("src", "ref", "component"),
             c("source_usd", "ref_usd", "measure"))
    m[, ratio := source_usd / ref_usd]
    setcolorder(m, c(keys, "source", "measure", "source_usd", "ref_usd", "ratio"))
    setorderv(m, c("source", "measure", keys))
    path <- file.path(out_dir, file)
    fwrite(m, path, na = "NA")
    message("Ratio frame -> ", path)
    m
  }
  invisible(list(
    by_year = frame(c("iso3c", "year", "isic"),
                    paste0(prefix, "_by_component_by_year.csv")),
    items   = frame(c("iso3c", "year", "isic", "category"),
                    paste0(prefix, "_item_ratios.csv"))))
}


# ── Symlog scatter panels ────────────────────────────────────────────────────
#
# One figure per (source, level), every cell of that resolution on shared axes:
# reference on x, source on y, both symlog, ticked at round powers of ten and
# labelled in scientific notation.  The transform is linear within a dollar of
# zero and logarithmic beyond, which keeps zero and the sign-crossing cells on
# the plot while every decade — and the linear core itself — takes the same
# width, so the axis reads evenly from -10^n through 0 to 10^n.
#
# Wherever the cells resolve the ISIC sections (L3 / L4) the figure splits into
# one panel per section, which stops the two clouds overplotting each other;
# the axes stay shared, so the panels remain directly comparable.  The sections
# therefore never need a shape of their own: at L1 / L2 they are summed into a
# single A+C cell and at L3 / L4 the panel strip already names them.  Points are
# plain filled dots throughout — nothing is ever encoded as filled against
# hollow, so an outlined shape would only invite the reader to look for it.
#
# The component legend is likewise carried only where the component varies, at
# L2 and L4; L1 and L3 sum the components away and score a single `total` per
# cell, so their key would have one entry restating the subtitle.
#
# `panel_country` extends the same treatment to a figure pooling several
# national references (02): the countries take a panel row rather than an
# interior shade, so the point stays a plain dot and each cloud is read against
# its own reference instead of being told apart by lightness.

VA_COMPONENT_COLOURS <- c(wages = "#1f77b4", capital = "#d62728",
                          tls   = "#2ca02c", total   = "#4d4d4d")
VA_ISIC_LEVELS       <- c("A", "C", "A+C")

#' TRUE where the cells carry both ISIC sections, and the figure therefore
#' splits into one panel each.  At L1 / L2 the sections are summed away into a
#' single A+C cell, which stays one panel.
va_facets_isic <- function(d) "isic" %in% names(d) && uniqueN(d$isic) > 1L

#' Mantissa and exponent of `x` in scientific notation, with the mantissa
#' carried to `digits` significant figures.  Rounding can push a mantissa to 10
#' (9.999 -> 10.0), which is carried into the exponent.
va_sci_parts <- function(x, digits = 3) {
  ok <- is.finite(x) & x != 0
  e  <- ifelse(ok, floor(log10(abs(x))), 0)
  m  <- ifelse(ok, signif(x / 10^e, digits), x)
  up <- is.finite(m) & abs(m) >= 10
  e[up] <- e[up] + 1L
  m[up] <- m[up] / 10
  list(mantissa = m, exponent = as.integer(e))
}

#' Axis labels as plotmath, so the exponent sets as a true superscript: 0,
#' 10^9, 1.5 x 10^9.  A mantissa of 1 is left implicit, and NA breaks (ggplot
#' passes them for censored values) label as blank.
va_sci_expr <- function(x, digits = 3) {
  p   <- va_sci_parts(x, digits)
  txt <- ifelse(
    !is.finite(x), "''",
    ifelse(x == 0, "0",
           ifelse(abs(p$mantissa) == 1,
                  sprintf("%s10^%d", ifelse(p$mantissa < 0, "-", ""),
                          p$exponent),
                  sprintf("%s %%*%% 10^%d", sprintf("%g", p$mantissa),
                          p$exponent))))
  parse(text = txt)
}

#' Where the linear core ends: below a dollar a cell is rounding, so nothing
#' under it needs resolving and the log region can start at 10^0.
VA_SYMLOG_LIN <- 1

#' Linear inside the core and logarithmic beyond, joined so that the core and
#' every decade outside it are one unit wide.
va_symlog <- function(x) {
  a <- abs(x) / VA_SYMLOG_LIN
  sign(x) * ifelse(a <= 1, a, 1 + log10(a))
}

#' Decade ticks either side of zero, from the linear core out to the largest
#' decade the data actually reach.  Every decade takes a gridline; on a crowded
#' axis the plotmath would collide, so only every second one is labelled.
va_symlog_axis <- function(v) {
  hi  <- max(abs(v[is.finite(v)]), VA_SYMLOG_LIN)
  lo  <- round(log10(VA_SYMLOG_LIN))
  dec <- 10^(lo:max(lo, floor(log10(hi))))
  at  <- sort(unique(c(-rev(dec), 0, dec)))
  step <- abs(seq_along(at) - (length(at) + 1L) / 2L)
  lab  <- at
  if (max(step) > 8L) lab[step > 0L & step %% 2L == 0L] <- NA
  list(breaks = va_symlog(at),
       labels = va_sci_expr(lab))
}

va_symlog_plot <- function(matched, title, subtitle, reference, source_label,
                           panel_country = FALSE) {
  # Cells empty on both sides sit exactly on the origin and carry no
  # disagreement to read; they are not plotted.
  d <- copy(matched[is.finite(ref) & is.finite(src) & (ref != 0 | src != 0)])
  by_isic <- va_facets_isic(d)
  if (!"isic" %in% names(d)) d[, isic := "A+C"]
  d[, `:=`(xt        = va_symlog(ref),
           yt        = va_symlog(src),
           component = factor(component, levels = MEASURES),
           isic      = factor(isic,      levels = VA_ISIC_LEVELS))]
  ax  <- va_symlog_axis(c(d$ref, d$src))
  sz  <- if (nrow(d) > 2000L) 1.2 else 2.0     # L4 panels run to thousands of cells
  # L1 / L3 sum the components away and leave a single `total` per cell, so
  # their colour key would carry one entry and is dropped.
  one_component <- uniqueN(as.character(d$component)) < 2L
  
  p <- ggplot(d, aes(x = xt, y = yt)) +
    geom_hline(yintercept = 0, linewidth = 0.3, colour = "grey75") +
    geom_vline(xintercept = 0, linewidth = 0.3, colour = "grey75") +
    geom_abline(slope = 1, intercept = 0, linetype = "dashed",
                linewidth = 0.4, colour = "black") +
    geom_point(aes(colour = component), shape = 16, size = sz, alpha = 0.8) +
    scale_x_continuous(breaks = ax$breaks, labels = ax$labels) +
    scale_y_continuous(breaks = ax$breaks, labels = ax$labels) +
    scale_colour_manual(values = VA_COMPONENT_COLOURS,
                        labels = VA_MEASURE, name = "Value-added component") +
    labs(title = title, subtitle = subtitle,
         x = va_axis_label(reference, VA_MEASURE[["total"]],
                           scale = "symlog scale"),
         y = va_axis_label(source_label, scale = "symlog scale")) +
    theme_minimal(base_size = 10) +
    theme(
      aspect.ratio        = 1,
      panel.grid.minor    = element_blank(),
      panel.grid.major    = element_line(colour = "grey90", linewidth = 0.25),
      strip.text          = element_text(face = "bold", size = 9.5),
      legend.position     = "bottom",
      legend.box          = "vertical",
      # Title + subtitle form a left-aligned top band, set off by whitespace so
      # they can be cropped off cleanly when placing the figure in publication.
      plot.title.position = "plot",
      plot.title          = element_text(face = "bold", size = 12,
                                         margin = margin(b = 4)),
      plot.subtitle       = element_text(size = 8.5, lineheight = 1.2,
                                         margin = margin(b = 16))
    ) +
    guides(colour = if (one_component) "none" else
      guide_legend(override.aes = list(shape = 16, size = 2.8)))
  
  # The strips name the sections and the countries, so nothing else has to:
  # sections across, countries down, and the axes shared throughout.
  isic_lab <- as_labeller(function(x) paste("ISIC section", x))
  if (by_isic && panel_country)
    p <- p + facet_grid(iso3c ~ isic, labeller = labeller(isic = isic_lab))
  else if (panel_country)
    p <- p + facet_wrap(~ iso3c, nrow = 1)
  else if (by_isic)
    p <- p + facet_wrap(~ isic, nrow = 1, labeller = isic_lab)
  p
}

va_slug <- function(x) gsub("(^-|-$)", "", tolower(gsub("[^A-Za-z0-9]+", "-", x)))

#' ggplot draws ONE y-axis title centred across stacked facet rows; this
#' replicates it so the label sits next to every row, as the ISIC rows of the
#' per-country time series (03) need.  Returns the untouched grob if the layout
#' is unexpected.  Not needed under coord_flip(), where the value axis is the
#' horizontal one and its title is already drawn once at the foot.
#'
#' gtable and grid are reached through `::` and never through requireNamespace():
#' ggplot2 imports both, so they are always loaded, and a namespace lookup inside
#' a forked worker is one of the things that hangs the fan-out in 03.
va_repeat_facet_ylab <- function(p) {
  g          <- ggplot2::ggplotGrob(p)
  yt         <- which(g$layout$name == "ylab-l")
  panel_rows <- sort(unique(g$layout$t[grepl("^panel", g$layout$name)]))
  if (!length(yt) || length(panel_rows) < 2L) return(g)
  ylab_grob <- g$grobs[[yt]]
  ylab_col  <- g$layout$l[yt]
  g$grobs[[yt]] <- grid::nullGrob()
  for (r in panel_rows) {
    g <- gtable::gtable_add_grob(g, ylab_grob, t = r, b = r, l = ylab_col, r = ylab_col,
                                 clip = "off", name = sprintf("ylab-l-%d", r))
  }
  g
}

#' One SVG per (source, level) of `matched` into `out_dir`.  `note` states what
#' the caller did to make the two sides comparable, and is carried in the
#' subtitle.
va_write_symlog_plots <- function(matched, sources, out_dir, prefix,
                                  reference, scope = NULL, panel_country = FALSE,
                                  note = NULL) {
  scale_note <- sprintf(
    paste0("Both axes symlog: linear within \u00b1US$%g and logarithmic beyond, ",
           "so the linear core and every decade outside it are equally wide ",
           "and the panels share a scale. Dashed line = identity; grey lines ",
           "mark zero, so sign disagreement reads off the off-diagonal ",
           "quadrants. Taxes less subsidies is the production-side measure ",
           "on both sides."),
    VA_SYMLOG_LIN)
  for (lv in names(matched)) {
    for (s in sources) {
      d <- matched[[lv]][source == s]
      if (!nrow(d)) next
      p <- va_symlog_plot(
        d, reference = reference,
        source_label = va_source_label(s, "axis"),
        panel_country = panel_country,
        title    = sprintf("%s vs %s at %s%s",
                           va_source_label(s, "title"), reference, lv,
                           if (is.null(scope)) "" else sprintf(" (%s)", scope)),
        subtitle = paste0("One point per ", VA_LEVEL_DESC[[lv]], " cell. ",
                          if (is.null(note)) "" else paste0(note, " "),
                          scale_note))
      out_file <- file.path(out_dir,
                            sprintf("%s_symlog_%s_%s.svg", prefix, va_slug(s), lv))
      # Two panels side by side need the canvas wide rather than tall; the
      # panels are square, so each country row adds its own height.
      nrow_panel <- if (panel_country) uniqueN(d$iso3c) else 1L
      dim <- if (va_facets_isic(d)) c(10, 3 + 4.5 * nrow_panel) else c(8, 9)
      ggsave(out_file, p, width = dim[1], height = dim[2],
             limitsize = FALSE, device = "svg")
      message(sprintf("[symlog/%s/%s] wrote %s  (n=%d)", lv, s, out_file, nrow(d)))
    }
  }
}