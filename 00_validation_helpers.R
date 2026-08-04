# ==============================================================================
# 00_validation_helpers.R — shared agreement metrics and IHS scatter panels for
#                           the FABIO value-added validators (01 global
#                           agricultural GDP, 02 BioSAMs, 03 USA SUTs,
#                           04 Japan IOTs).
#
# Sourced via the validation-repo anchor so it resolves regardless of working
# directory:  source(validation_path("00_validation_helpers.R"))
#
# Expects data.table, ggplot2 and scales to be attached by the caller.
# Everything except va_metrics() also expects the caller's measure ordering,
#     MEASURES = c("total", "wages", "capital", "tls")
# ==============================================================================


# ── Cells ────────────────────────────────────────────────────────────────────
#
# A comparison table is long over (iso3c, year, source, isic, category, strand,
# value_usd).  Three cell resolutions are scored:
#
#   L1  (iso3c, year)                            items and ISIC sections summed
#   L2  (iso3c, year, isic, category)            strands summed
#   L3  (iso3c, year, isic, category, strand)
#
# `total` is a cell value only where the resolution sums the strands away — at
# L1 alongside the three strand rows, at L2 as the only row.  The item key
# carries its ISIC section because a category can contribute at both levels.

VA_LEVEL_KEYS <- list(L1 = c("iso3c", "year"),
                      L2 = c("iso3c", "year", "isic", "category"),
                      L3 = c("iso3c", "year", "isic", "category"))

VA_LEVEL_DESC <- c(L1 = "country x year",
                   L2 = "country x year x item, strands summed",
                   L3 = "country x year x item x strand")

#' One value per (source, cell, strand) at the resolution `keys`.  `strands`
#' keeps the three VA strands as separate rows; `total` appends their sum, where
#' a strand absent from a cell counts as zero.
va_cells <- function(dat, keys, strands = TRUE, total = TRUE) {
  s <- dat[is.finite(value_usd),
           .(value = sum(value_usd, na.rm = TRUE)),
           by = c("source", keys, "strand")]
  rbindlist(list(
    if (strands) s,
    if (total)   s[, .(strand = "total", value = sum(value)), by = c("source", keys)]
  ), use.names = TRUE)
}

va_level_cells <- function(dat, level) {
  keys <- VA_LEVEL_KEYS[[level]]
  switch(level,
         L1 = va_cells(dat, keys),
         L2 = va_cells(dat, keys, strands = FALSE),
         L3 = va_cells(dat, keys, total   = FALSE))
}


# ── Matching ─────────────────────────────────────────────────────────────────

#' Pair every source in `cells` against the reference table `ref` (the cell keys
#' plus a `ref` column).  With `expand`, the cell universe is the union of the
#' two sides and an absent row is carried as a structural zero, so a source that
#' simply does not populate a cell registers as a coverage failure rather than
#' vanishing from the comparison.  Without it the pairing is an inner join.
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
# reported alongside, over all cells in the group:
#
#   n          cells in the group
#   n_used     cells surviving the non-zero + same-sign filter
#   coverage   share of cells non-zero on both sides
#   sign_agree share of same-sign cells, among cells non-zero on both sides
#
# sign_agree conditions on the non-zero cells so that a structural zero reads as
# missing coverage rather than as a sign flip; coverage carries that information.

VA_MIN_USED <- 10L

va_metrics <- function(ref, src) {
  nz  <- ref != 0 & src != 0
  use <- nz & sign(ref) == sign(src)
  l   <- log10(abs(src[use]) / abs(ref[use]))
  ok  <- length(l) >= VA_MIN_USED
  data.table(
    n          = length(ref),
    n_used     = length(l),
    coverage   = if (length(ref)) mean(nz) else NA_real_,
    sign_agree = if (any(nz)) sum(use) / sum(nz) else NA_real_,
    med_ratio  = if (ok) 10^median(l) else NA_real_,
    mad_fold   = if (ok) 10^median(abs(l - median(l))) else NA_real_,
    rmsle_dex  = if (ok) sqrt(mean(l^2)) else NA_real_)
}

#' One metric row per (strand, source) pooling all cells of `matched`, plus —
#' with `by_item` — the same rows resolved within each item.
va_score <- function(matched, sources, level, by_item = FALSE) {
  m    <- matched[source %in% sources]
  rows <- m[, va_metrics(ref, src), by = .(strand, source)]
  rows[, item := NA_character_]
  if (by_item)
    rows <- rbindlist(list(
      rows, m[, va_metrics(ref, src), by = .(strand, source, item = category)]),
      use.names = TRUE)
  set(rows, j = "level", value = level)
  setcolorder(rows, c("level", "item", "strand", "source", "n", "n_used",
                      "coverage", "sign_agree", "med_ratio", "mad_fold",
                      "rmsle_dex"))
  rows[order(match(strand, MEASURES), match(source, sources), item)]
}

#' The tidy metrics table for a level cascade: va_score() down the levels of
#' `matched`, stacked, with the `level` column carrying the resolution.  The
#' per-item breakout needs an item key, so it applies below L1 only.
va_metrics_table <- function(matched, sources, by_item = FALSE) {
  rbindlist(lapply(names(matched), function(lv)
    va_score(matched[[lv]], sources, lv, by_item = by_item && lv != "L1")))
}

#' The aggregate ratio frames behind the metrics: one row per (cell, source,
#' measure) with both sides and their signed ratio, at per-ISIC national scope
#' and at item scope.  Inner-joined, so only cells both sides populate appear.
va_write_ratio_frames <- function(dat, reference, sources, out_dir, prefix) {
  fab <- setdiff(sources, reference)
  frame <- function(keys, file) {
    m <- copy(va_match_source(va_cells(dat, keys), reference,
                              expand = FALSE)[source %in% fab])
    setnames(m, c("src", "ref", "strand"), c("source_usd", "ref_usd", "measure"))
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
                    paste0(prefix, "_by_strand_by_year.csv")),
    items   = frame(c("iso3c", "year", "isic", "category"),
                    paste0(prefix, "_item_ratios.csv"))))
}


# ── IHS scatter panels ───────────────────────────────────────────────────────
#
# One panel per (source, level), every cell of that resolution on shared axes:
# reference on x, source on y, both as asinh(value / theta).  theta is a single
# per-dataset scale, so the panel stays coherent across strands and ISIC
# sections; the transform is near-linear inside a typical cell and logarithmic
# beyond it, which keeps zero and the sign-crossing cells on the plot.

VA_STRAND_COLOURS <- c(wages = "#1f77b4", capital = "#d62728",
                       tls   = "#2ca02c", total   = "#4d4d4d")
VA_ISIC_SHAPES    <- c(A = 21, C = 24, `A+C` = 21)

#' Neutral interior fills: the outline already carries the strand, so countries
#' separate by lightness alone.  Legible to about six.
va_country_fills <- function(countries) {
  countries <- sort(unique(as.character(countries)))
  setNames(grey(seq(1, 0.3, length.out = length(countries))), countries)
}

#' The panel scale: the median magnitude of a non-zero reference cell.
va_theta <- function(v) {
  v <- abs(v[is.finite(v) & v != 0])
  if (length(v)) median(v) else 1
}

#' Decade ticks either side of zero, labelled in the untransformed unit.
va_ihs_axis <- function(v, theta) {
  hi  <- max(abs(v[is.finite(v)]), theta)
  dec <- theta * 10^(0:ceiling(log10(hi / theta)))
  at  <- sort(unique(c(-rev(dec), 0, dec)))
  list(breaks = asinh(at / theta),
       labels = label_number(scale_cut = cut_short_scale())(at))
}

va_ihs_plot <- function(matched, theta, title, subtitle, reference,
                        fill_country = FALSE) {
  d <- copy(matched[is.finite(ref) & is.finite(src)])
  if (!"isic" %in% names(d)) d[, isic := "A+C"]
  d[, `:=`(xt     = asinh(ref / theta),
           yt     = asinh(src / theta),
           strand = factor(strand, levels = MEASURES),
           isic   = factor(isic,   levels = names(VA_ISIC_SHAPES)))]
  ax  <- va_ihs_axis(c(d$ref, d$src), theta)
  sz  <- if (nrow(d) > 2000L) 1.2 else 2.0     # L3 panels run to thousands of cells
  
  p <- ggplot(d, aes(x = xt, y = yt)) +
    geom_hline(yintercept = 0, linewidth = 0.3, colour = "grey75") +
    geom_vline(xintercept = 0, linewidth = 0.3, colour = "grey75") +
    geom_abline(slope = 1, intercept = 0, linetype = "dashed",
                linewidth = 0.4, colour = "black") +
    (if (fill_country)
      geom_point(aes(colour = strand, shape = isic, fill = iso3c),
                 size = sz, stroke = 0.45, alpha = 0.8)
     else
       geom_point(aes(colour = strand, shape = isic),
                  fill = NA, size = sz, stroke = 0.45, alpha = 0.8)) +
    scale_x_continuous(breaks = ax$breaks, labels = ax$labels) +
    scale_y_continuous(breaks = ax$breaks, labels = ax$labels) +
    scale_colour_manual(values = VA_STRAND_COLOURS, name = "VA strand") +
    scale_shape_manual(values = VA_ISIC_SHAPES, name = "ISIC section") +
    labs(title = title, subtitle = subtitle,
         x = sprintf("%s (current US$, asinh scale)", reference),
         y = "FABIOv2 source (current US$, asinh scale)") +
    theme_minimal(base_size = 10) +
    theme(
      aspect.ratio        = 1,
      panel.grid.minor    = element_blank(),
      panel.grid.major    = element_line(colour = "grey90", linewidth = 0.25),
      legend.position     = "bottom",
      legend.box          = "vertical",
      plot.title.position = "plot",
      plot.title          = element_text(face = "bold", size = 12),
      plot.subtitle       = element_text(size = 8.5, lineheight = 1.2)
    ) +
    guides(colour = guide_legend(override.aes = list(shape = 21, fill = NA, size = 2.8)),
           shape  = guide_legend(override.aes = list(colour = "black", fill = NA, size = 2.8)))
  
  if (fill_country)
    p <- p + scale_fill_manual(values = va_country_fills(d$iso3c),
                               name = "Country") +
    guides(fill = guide_legend(override.aes = list(shape = 21, colour = "black",
                                                   size = 2.8)))
  p
}

va_slug <- function(x) gsub("(^-|-$)", "", tolower(gsub("[^A-Za-z0-9]+", "-", x)))

#' One SVG per (source, level) of `matched` into `out_dir`.
va_write_ihs_plots <- function(matched, theta, sources, out_dir, prefix,
                               dataset, reference, fill_country = FALSE) {
  scale_note <- sprintf(
    paste0("Both axes asinh(value / theta), theta = %s = median |reference| ",
           "across all strands and both ISIC sections. Dashed line = identity; ",
           "grey lines mark zero, so sign disagreement reads off the ",
           "off-diagonal quadrants."),
    label_number(scale_cut = cut_short_scale())(theta))
  for (lv in names(matched)) {
    for (s in sources) {
      d <- matched[[lv]][source == s]
      if (!nrow(d)) next
      p <- va_ihs_plot(
        d, theta, reference = reference, fill_country = fill_country,
        title    = sprintf("%s vs %s — %s", dataset, s, lv),
        subtitle = paste0("One point per ", VA_LEVEL_DESC[[lv]], " cell. ",
                          scale_note))
      out_file <- file.path(out_dir,
                            sprintf("%s_ihs_%s_%s.svg", prefix, va_slug(s), lv))
      ggsave(out_file, p, width = 8, height = 9, limitsize = FALSE, device = "svg")
      message(sprintf("[ihs/%s/%s] wrote %s  (n=%d)", lv, s, out_file, nrow(d)))
    }
  }
}