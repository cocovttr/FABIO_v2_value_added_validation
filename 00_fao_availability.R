# ==============================================================================
# 00_fao_availability.R — did the primary source observe this cell at all?
#
# Writes input/fao_availability.rds: one row per (fabio_area_code,
# fabio_item_code, year), with
#
#   fao_status  "reported"        the primary source books a figure above zero
#               "reported_zero"   it books an explicit zero
#               "no_observation"  it books nothing — no row, or a flag saying
#                                 the value is missing / not reported
#
# Items no primary source can speak to carry NO row; readers treat an absent
# row as unknown rather than as an absent observation.  Crops, livestock
# products and animal stocks come from FAOSTAT Production_Crops_Livestock;
# fish from the FAO Global Production quantities, which the crops-and-livestock
# domain does not cover.
#
# Read-only with respect to FABIO: nothing here re-runs or rewrites any part of
# the pipeline.  Run once, commit the rds.
#
#   Rscript 00_fao_availability.R
# ==============================================================================

library(data.table)


# ── Anchors ──────────────────────────────────────────────────────────────────
# Standalone: this script is run on its own, before the validators, so it sets
# its own two roots rather than borrowing theirs.

FABIO_ROOT      <- path.expand(Sys.getenv("FABIO_ROOT",      unset = "~/fabio"))
VALIDATION_ROOT <- path.expand(Sys.getenv("VALIDATION_ROOT", unset = getwd()))
fabio_path      <- function(...) file.path(FABIO_ROOT, ...)
validation_path <- function(...) file.path(VALIDATION_ROOT, ...)

if (!dir.exists(validation_path("input")))
  stop("VALIDATION_ROOT (", VALIDATION_ROOT, ") has no input/ folder. Run from ",
       "the validation repo root, or set the VALIDATION_ROOT env var.")

FAO_PROD_CSV <- Sys.getenv("FAO_PROD_CSV", unset = fabio_path(
  "input", "fao", "Production_Crops_Livestock_E_All_Data_(Normalized).csv"))
FAO_FISH_CSV <- Sys.getenv("FAO_FISH_CSV", unset = fabio_path(
  "input", "fish", "Global_production_quantity.csv"))
FAO_SUA_CSV  <- Sys.getenv("FAO_SUA_CSV", unset = fabio_path(
  "input", "fao", "SUA_Crops_Livestock_E_All_Data_(Normalized).csv"))

REGIONS_CSV  <- fabio_path("inst", "regions_full.csv")
CROP_CONC    <- fabio_path("inst", "conc_crop-cbs.csv")
BTD_CONC     <- fabio_path("inst", "conc_btd-cbs.csv")
PP_ITEM_CONC <- fabio_path("inst", "value_added",
                           "concordance_items_fao_producer_prices_fabio.csv")
PP_AREA_CONC <- fabio_path("inst", "value_added",
                           "concordance_areas_fao_producer_prices_fabio.csv")

# Where 14_1 / 14_4 leave the extension.  Matches VA_VALUE_ADDED_OUTPUT_DIR in
# R/00_value_added_config.R; only the gap list below reads it.
VA_DIR <- Sys.getenv("VA_VALUE_ADDED_OUTPUT_DIR",
                     unset = fabio_path("data", "value_added"))

OUT_RDS  <- validation_path("input", "fao_availability.rds")
GAPS_CSV <- validation_path("output", "fao_availability_gaps.csv")

YEARS <- as.integer(strsplit(Sys.getenv("FAO_AVAIL_YEARS", unset = "2010:2023"),
                             ":")[[1]])
YEARS <- seq.int(YEARS[1], YEARS[2])

for (p in c(FAO_PROD_CSV, REGIONS_CSV, CROP_CONC, PP_ITEM_CONC, PP_AREA_CONC))
  if (!file.exists(p)) stop("Input not found: ", p)

FISH_ITEM <- 2960L
# FAO flags standing for "no figure": M is FAOSTAT's missing value; N and Q are
# the Global Production codes for not-reported and not-separately-reported,
# both of which arrive carrying a literal 0.
NO_FIGURE_FLAGS <- c("M", "N", "Q")
# SUA element code for Production.  The SUA also carries an F (forecast) flag
# the other two domains do not; a forecast is still a figure, so it is left in.
SUA_PRODUCTION  <- 5510L


# ── Areas ────────────────────────────────────────────────────────────────────
# FABIO's region codes ARE FAOSTAT area codes for 180 of the 181 current
# regions, so the map is identity plus the producer-price concordance's
# redirections (small territories folded into RoW or France, Serbia and
# Montenegro into Montenegro), plus FABIO's own two area merges.  Identity
# first matters: the concordance leaves 16 areas without a FAO code because
# they carry no producer price, and every one of them reports production.

regions <- fread(REGIONS_CSV)[current == TRUE]
areas   <- fread(PP_AREA_CONC, encoding = "UTF-8", na.strings = c("", "NA"))

area_map <- rbindlist(list(
  regions[code != 999L, .(fao_area_code = as.integer(code),
                          fabio_area_code = as.integer(code))],
  areas[!is.na(FAO_area_code),
        .(fao_area_code   = as.integer(FAO_area_code),
          fabio_area_code = as.integer(FABIO_area_code))]))
# The concordance is appended second, so fromLast keeps it where the two differ.
area_map <- unique(area_map, by = "fao_area_code", fromLast = TRUE)

area_map[fao_area_code == 62L,  fabio_area_code := 238L]   # Ethiopia PDR
area_map[fao_area_code == 206L, fabio_area_code := 276L]   # Sudan (former)
area_map <- area_map[fao_area_code != 351L]                # China aggregate
area_map <- area_map[fabio_area_code %in% regions$code]


# ── Items ────────────────────────────────────────────────────────────────────
# Three sources of mapping, unioned: the producer-price concordance (one or
# more FAO items per FABIO item), the crop concordance (which reaches the
# aggregated crop items and fodder), and identity on the live-animal items,
# whose FABIO code is the FAO code and whose quantity is a stock, not a
# production.  Poultry Birds takes its components too, since a country can
# report ducks and geese without the aggregate.

LIVE_ITEMS    <- c(866L, 946L, 976L, 1016L, 1034L, 1096L, 1107L, 1110L,
                   1126L, 1140L, 1150L, 1157L, 2029L)
POULTRY_ITEM  <- 2029L
POULTRY_PARTS <- c(1057L, 1068L, 1072L, 1079L, 1083L)

pp_items <- fread(PP_ITEM_CONC, encoding = "UTF-8", na.strings = c("", "NA"))
crop     <- fread(CROP_CONC,    encoding = "UTF-8", na.strings = c("", "NA"))

item_map <- unique(rbindlist(list(
  pp_items[!is.na(FAO_item_code) & !is.na(FABIO_item_code),
           .(fao_item_code   = as.integer(FAO_item_code),
             fabio_item_code = as.integer(FABIO_item_code),
             element         = "Production")],
  crop[!is.na(crop_item_code) & !is.na(cbs_item_code),
       .(fao_item_code   = as.integer(crop_item_code),
         fabio_item_code = as.integer(cbs_item_code),
         element         = "Production")],
  data.table(fao_item_code   = LIVE_ITEMS,
             fabio_item_code = LIVE_ITEMS,
             element         = "Stocks"),
  data.table(fao_item_code   = POULTRY_PARTS,
             fabio_item_code = POULTRY_ITEM,
             element         = "Stocks"))))


# ── Crops, livestock products, animal stocks ─────────────────────────────────

prod <- fread(FAO_PROD_CSV, encoding = "UTF-8", showProgress = FALSE,
              select = c("Area Code", "Item Code", "Element", "Year",
                         "Value", "Flag"))
setnames(prod, c("fao_area_code", "fao_item_code", "element", "year",
                 "value", "flag"))
prod <- prod[element %chin% c("Production", "Stocks") & year %in% YEARS]
prod[, `:=`(fao_area_code = as.integer(fao_area_code),
            fao_item_code = as.integer(fao_item_code),
            year          = as.integer(year),
            value         = as.numeric(value))]

prod <- merge(prod, item_map, by = c("fao_item_code", "element"),
              allow.cartesian = TRUE)
prod <- merge(prod, area_map, by = "fao_area_code")
prod[, figure := !flag %chin% NO_FIGURE_FLAGS & is.finite(value)]

obs <- prod[, .(n_figure = sum(figure),
                n_above  = sum(figure & value > 0)),
            by = .(fabio_area_code, fabio_item_code, year)]


# ── Processed items (SUA) ────────────────────────────────────────────────────
# The crops-and-livestock domain reports primary production, so nine CBS items
# have no row there and would stay unknown: the two beverage aggregates and
# non-food alcohol, butter and ghee, raw animal fats, hides and skins, edible
# offals, ricebran oil, non-centrifugal sugar.  Their production is in the SUA,
# on the same item codes conc_btd-cbs.csv already maps to CBS (01_1_tidy_fao.R
# uses that mapping for exactly this join).  Only the items the production file
# cannot reach are taken from here, so no verdict reached above can move.
#
# `Value` is read with the flag, NOT as FABIO reads it: 01_1_tidy_fao.R:235
# drops the SUA rows whose value is zero, which is a third place — after the
# CBS fill at :160 and the crop fill at :88 — where a reported zero becomes
# indistinguishable from an absent one.  Reading the raw file sidesteps that.

if (file.exists(FAO_SUA_CSV)) {
  btd <- fread(BTD_CONC, encoding = "UTF-8", na.strings = c("", "NA"))
  sua_map <- unique(btd[!is.na(btd_item_code) & !is.na(cbs_item_code) &
                          !cbs_item_code %in% item_map$fabio_item_code,
                        .(sua_item_code   = as.integer(btd_item_code),
                          fabio_item_code = as.integer(cbs_item_code))])
  # 11.6M rows; `select` keeps this to the six columns that matter.
  sua <- fread(FAO_SUA_CSV, encoding = "UTF-8", showProgress = FALSE,
               select = c("Area Code", "Item Code", "Element Code", "Year",
                          "Value", "Flag"))
  setnames(sua, c("fao_area_code", "sua_item_code", "element_code", "year",
                  "value", "flag"))
  sua[, `:=`(fao_area_code = as.integer(fao_area_code),
             sua_item_code = as.integer(sua_item_code),
             element_code  = as.integer(element_code),
             year          = as.integer(year),
             value         = as.numeric(value))]
  sua <- sua[element_code == SUA_PRODUCTION & year %in% YEARS]
  sua <- merge(sua, sua_map,  by = "sua_item_code", allow.cartesian = TRUE)
  sua <- merge(sua, area_map, by = "fao_area_code")
  sua[, figure := !flag %chin% NO_FIGURE_FLAGS & is.finite(value)]
  obs <- rbindlist(list(obs, sua[, .(n_figure = sum(figure),
                                     n_above  = sum(figure & value > 0)),
                                 by = .(fabio_area_code, fabio_item_code,
                                        year)]),
                   use.names = TRUE)
} else {
  sua_map <- data.table(sua_item_code = integer(), fabio_item_code = integer())
  message("NOTE: ", FAO_SUA_CSV, " not found — processed items stay unknown.")
}


# ── Fish ─────────────────────────────────────────────────────────────────────
# Keyed on the UN M49 code, which regions_full carries as `fish`.  RoW has
# none, so its fishing cells stay unknown rather than being called unobserved.

if (file.exists(FAO_FISH_CSV)) {
  m49_map <- regions[!is.na(fish), .(m49 = as.integer(fish),
                                     fabio_area_code = as.integer(code))]
  fsh <- fread(FAO_FISH_CSV, encoding = "UTF-8", showProgress = FALSE,
               select = c("COUNTRY.UN_CODE", "PERIOD", "VALUE", "STATUS"))
  setnames(fsh, c("m49", "year", "value", "flag"))
  fsh[, `:=`(m49   = as.integer(m49),
             year  = as.integer(year),
             value = as.numeric(value))]
  fsh <- merge(fsh[year %in% YEARS], m49_map, by = "m49")
  fsh[, figure := !flag %chin% NO_FIGURE_FLAGS & is.finite(value)]
  obs <- rbindlist(list(obs, fsh[, .(fabio_item_code = FISH_ITEM,
                                     n_figure = sum(figure),
                                     n_above  = sum(figure & value > 0)),
                                 by = .(fabio_area_code, year)]),
                   use.names = TRUE)
} else {
  message("NOTE: ", FAO_FISH_CSV, " not found — fishing cells stay unknown.")
}


# ── The grid ─────────────────────────────────────────────────────────────────
# Every (region, adjudicable item, year), so the readers can join on the key
# and read an absent row as "no primary source speaks to this item".

adjudicable <- sort(unique(c(item_map$fabio_item_code,
                             sua_map$fabio_item_code,
                             if (any(obs$fabio_item_code == FISH_ITEM))
                               FISH_ITEM)))
out <- CJ(fabio_area_code = sort(regions$code),
          fabio_item_code = adjudicable,
          year            = YEARS)
out <- out[!(fabio_item_code == FISH_ITEM & fabio_area_code == 999L)]

out[obs, `:=`(n_figure = i.n_figure, n_above = i.n_above),
    on = .(fabio_area_code, fabio_item_code, year)]
out[, fao_status := fifelse(!is.na(n_above)  & n_above  > 0L, "reported",
                            fifelse(!is.na(n_figure) & n_figure > 0L, "reported_zero",
                                    "no_observation"))]
out[, c("n_figure", "n_above") := NULL]
out[regions, iso3c := i.iso3c, on = c(fabio_area_code = "code")]
setcolorder(out, c("fabio_area_code", "iso3c", "fabio_item_code", "year",
                   "fao_status"))
setkeyv(out, c("fabio_area_code", "fabio_item_code", "year"))

saveRDS(out, OUT_RDS)
message("FAO availability -> ", OUT_RDS)
print(out[, .N, by = fao_status][order(-N)])
message(sprintf("%d of %d FABIO items adjudicable; the rest stay unknown.",
                length(adjudicable), uniqueN(fread(
                  fabio_path("inst", "items_full_123.csv"))$item_code)))


# ── Gap list ─────────────────────────────────────────────────────────────────
# The cells the extension leaves empty although a primary source reports a
# figure, split by where the chain broke.  Not read by the figures; written so
# the FABIO-side cause can be chased separately.
#
# The split is strand-aware, because 13_3 section 8e builds total_value two
# different ways.  For an item mapped at BOTH ISIC levels the ISIC-C value is
# the SUA/BTD bundle aggregate, price is blanked deliberately and
# total_product_output reflects the ISIC-A primary quantity — so neither column
# says anything about why the ISIC-C value is empty, and reading them as a
# missing price would call a designed asymmetry a failure.  Those rows get one
# cause of their own.  The both-mapped set is the intersection of the item
# codes the two level files carry.

va_files <- Sys.glob(file.path(VA_DIR,
                               "FABIOv2_COMBINED_*_value_added_ISIC-*.rds"))
if (!length(va_files)) {
  message("NOTE: no extension files under ", VA_DIR, " — gap list skipped.")
} else {
  va_tbls <- setNames(lapply(va_files, function(p) as.data.table(readRDS(p))),
                      basename(va_files))
  lvl_of  <- function(f) sub("^.*ISIC-([AC])\\.rds$", "\\1", f)
  items_at <- function(lv) unique(unlist(lapply(
    names(va_tbls)[lvl_of(names(va_tbls)) == lv],
    function(f) va_tbls[[f]]$fabio_item_code)))
  both_items <- intersect(items_at("A"), items_at("C"))
  
  gaps <- rbindlist(lapply(names(va_tbls), function(f) {
    va <- va_tbls[[f]]
    tv <- grep("^total_value \\[",          names(va), value = TRUE)[1]
    to <- grep("^total_product_output \\[", names(va), value = TRUE)[1]
    pc <- grep("^price \\[",                names(va), value = TRUE)[1]
    ta <- grep("^value_added \\[",          names(va), value = TRUE)[1]
    if (anyNA(c(tv, to, pc, ta))) return(NULL)
    g <- va[get(ta) == 0 & (is.na(get(tv)) | get(tv) == 0),
            .(iso3c, fabio_area_code, fabio_item_code, fabio_item, year,
              total_product_output = get(to), price = get(pc), va_source)]
    g[out, fao_status := i.fao_status,
      on = .(fabio_area_code, fabio_item_code, year)]
    g <- g[fao_status == "reported"]
    if (!nrow(g)) return(NULL)
    sua_route <- lvl_of(f) == "C" & g$fabio_item_code %in% both_items
    g[, gap_cause := fifelse(
      sua_route, "no_sua_bundle",
      fifelse(!is.finite(total_product_output) | total_product_output == 0,
              "no_quantity",
              fifelse(!is.finite(price) | price == 0, "no_price",
                      "no_bundle_value")))]
    g[, `:=`(isic = lvl_of(f), file = f)][]
  }), use.names = TRUE)
  if (nrow(gaps)) {
    setorder(gaps, iso3c, fabio_item, year)
    fwrite(gaps, GAPS_CSV)
    message("Gap list -> ", GAPS_CSV, "  (", nrow(gaps), " cell(s))")
    print(gaps[, .N, by = .(file, gap_cause)][order(file, -N)])
  }
}