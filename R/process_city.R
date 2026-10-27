# process_city.R
# Turn census blocks into block-group and ward tables for
# Kingston_Neighborhoods.Rmd. Uses helpers from process.R (label_parts,
# age_groups, moe_sum2, moe_prop2, build_acs_indicators).

# "36111951800 2" -> "9518-2"; "36111952001 1" -> "9520.01-1"
bg_label <- function(bg) {
  tract <- str_sub(bg, 6, 11)
  base  <- as.character(as.integer(str_sub(tract, 1, 4)))
  tract_lab <- if_else(str_sub(tract, 5, 6) == "00", base,
                       paste0(base, ".", str_sub(tract, 5, 6)))
  paste0(tract_lab, "-", str_sub(bg, 12, 12))
}

# Block-group shapes clipped to the city: the union of each block group's
# 2020 blocks inside the city.
build_bg_shapes <- function(city_geo) {
  city_geo$blocks20 %>%
    mutate(bg = str_sub(block, 1, 12)) %>%
    group_by(bg) %>%
    summarise(.groups = "drop") %>%
    mutate(label = bg_label(bg))
}

# Which unit (block group or ward) each block's internal point falls in
assign_points <- function(points, polygons, id_col) {
  sf::st_join(points, select(polygons, unit = all_of(id_col)), join = sf::st_within) %>%
    sf::st_drop_geometry() %>%
    filter(!is.na(unit)) %>%
    select(block, unit)
}

# Block -> unit assignments for both census years.
# 2020 blocks nest exactly in 2020 block groups; 2010 blocks are placed by
# their internal point, which is accurate except where a 2010 block was split
# by a 2020 boundary.
assign_blocks <- function(city_geo, polygons, id_col, exact_2020_bg = FALSE) {
  a20 <- if (exact_2020_bg) {
    sf::st_drop_geometry(city_geo$points20) %>%
      transmute(block, unit = str_sub(block, 1, 12))
  } else {
    assign_points(city_geo$points20, polygons, id_col)
  }
  bind_rows(
    mutate(assign_points(city_geo$points10, polygons, id_col), year = 2010),
    mutate(a20, year = 2020)
  )
}

# Age group for a Census age label such as "5 to 9 years" or "Under 5 years"
age_group_of <- function(age_text) {
  start <- if_else(str_detect(age_text, "^Under"), 0,
                   as.numeric(str_extract(age_text, "\\d+")))
  cut(start, c(-Inf, 17, 34, 64, Inf), labels = age_groups)
}

# Population and housing units per unit and year
summarise_totals <- function(block_counts, assignment) {
  block_counts %>%
    filter(label %in% c("population", "housing_units")) %>%
    inner_join(assignment, by = c("block", "year")) %>%
    group_by(unit, year, label) %>%
    summarise(value = sum(value), .groups = "drop") %>%
    pivot_wider(names_from = label, values_from = value)
}

# Share of residents in each age group per unit and year
summarise_age <- function(block_counts, assignment) {
  block_counts %>%
    filter(!label %in% c("population", "housing_units")) %>%
    inner_join(assignment, by = c("block", "year")) %>%
    mutate(parts = label_parts(label)) %>%
    filter(lengths(parts) == 2) %>%
    mutate(sex = purrr::map_chr(parts, 1), age = purrr::map_chr(parts, 2)) %>%
    filter(sex %in% c("Male", "Female")) %>%
    mutate(age_group = age_group_of(age)) %>%
    group_by(unit, year, age_group) %>%
    summarise(n = sum(value), .groups = "drop") %>%
    group_by(unit, year) %>%
    mutate(share = n / sum(n)) %>%
    ungroup()
}

# 2010 and 2020 side by side, with change
compare_years <- function(totals) {
  totals %>%
    pivot_wider(names_from = year, values_from = c(population, housing_units)) %>%
    mutate(
      pop_change    = population_2020 - population_2010,
      pop_pct       = 100 * (population_2020 / population_2010 - 1),
      hu_change     = housing_units_2020 - housing_units_2010,
      hu_pct        = 100 * (housing_units_2020 / housing_units_2010 - 1),
      share_of_city = population_2020 / sum(population_2020, na.rm = TRUE)
    )
}

# Share of each block group's 2020 population living inside the city
bg_share_in_city <- function(block_counts, city_geo) {
  block_counts %>%
    filter(year == 2020, label == "population") %>%
    mutate(bg = str_sub(block, 1, 12),
           in_city = block %in% city_geo$points20$block) %>%
    group_by(bg) %>%
    summarise(share_in_city = sum(value[in_city]) / sum(value), .groups = "drop") %>%
    filter(share_in_city > 0)
}

# ACS indicators for block groups: the standard set from process.R plus the
# renter share and householders who moved in during the latest period.
build_bg_acs <- function(acs_raw) {
  base <- build_acs_indicators(acs_raw)

  acs <- acs_raw %>%
    rename(geoid = GEOID) %>%
    mutate(
      estimate = if_else(estimate < 0, NA_real_, as.numeric(estimate)),
      moe      = if_else(moe < 0, NA_real_, as.numeric(moe)),
      parts    = label_parts(label)
    )
  den <- function(var) {
    acs %>% filter(variable == var) %>% select(geoid, year, den = estimate, den_moe = moe)
  }

  renter <- acs %>%
    filter(variable == "B25003_003") %>%
    select(geoid, year, num = estimate, num_moe = moe) %>%
    left_join(den("B25003_001"), by = c("geoid", "year")) %>%
    transmute(geoid, year, indicator = "Renter-occupied (share of households)",
              unit = "share", estimate = num / den,
              moe = moe_prop2(num, den, num_moe, den_moe))

  moved <- acs %>%
    filter(str_starts(variable, "B25038_"), lengths(parts) == 2) %>%
    mutate(when = purrr::map_chr(parts, 2)) %>%
    filter(str_detect(when, "or later")) %>%
    group_by(geoid, year) %>%
    summarise(num = sum(estimate), num_moe = moe_sum2(moe), .groups = "drop") %>%
    left_join(den("B25038_001"), by = c("geoid", "year")) %>%
    transmute(geoid, year, indicator = "Householder moved in recently",
              unit = "share", estimate = num / den,
              moe = moe_prop2(num, den, num_moe, den_moe))

  bind_rows(base, mutate(bind_rows(renter, moved), period = period_label(year))) %>%
    mutate(cv = (moe / 1.645) / estimate)
}

# The text of the most recent move-in category, e.g. "Moved in 2021 or later"
recent_move_label <- function(acs_raw) {
  acs_raw %>%
    filter(str_starts(variable, "B25038_")) %>%
    mutate(parts = label_parts(label)) %>%
    filter(lengths(parts) == 2) %>%
    mutate(when = purrr::map_chr(parts, 2)) %>%
    filter(str_detect(when, "or later")) %>%
    pull(when) %>%
    unique() %>%
    first()
}

# ---- Wards -------------------------------------------------------------------

# Find the column that holds the ward: one named like "ward", or a text
# column whose values mention a ward ("Kingston Ward 3 ED 2", "W3").
detect_ward_field <- function(districts) {
  df <- sf::st_drop_geometry(districts)
  by_name <- names(df)[str_detect(names(df), regex("ward", ignore_case = TRUE))]
  if (length(by_name) > 0) return(by_name[1])
  for (col in names(df)) {
    v <- as.character(df[[col]])
    hits <- str_detect(v, regex("\\bw(ard)?\\s*-?\\s*\\d", ignore_case = TRUE))
    if (mean(hits, na.rm = TRUE) > 0.8) return(col)
  }
  NULL
}

# Ward number from values like 3, "03", "Ward 3", "W3" or "Kingston 3-2"
ward_number <- function(x) {
  x <- as.character(x)
  n <- str_match(x, regex("\\bw(?:ard)?\\s*-?\\s*0*(\\d+)", ignore_case = TRUE))[, 2]
  as.integer(coalesce(n, str_extract(x, "\\d+")))
}

# Keep the districts inside the city and merge them into wards.
# Returns a list: wards (sf, or NULL) and a message explaining any problem.
build_wards <- function(districts, city) {
  inside <- lengths(sf::st_within(sf::st_point_on_surface(districts), city)) > 0
  d <- districts[inside, ]
  if (nrow(d) == 0) {
    return(list(wards = NULL,
                message = "None of the districts in the ward file fall inside the city boundary."))
  }
  field <- if (!is.null(ward_field)) ward_field else detect_ward_field(d)
  if (is.null(field) || !field %in% names(d)) {
    return(list(wards = NULL, message = paste0(
      "Could not tell which column holds the ward number. The district file's columns are: ",
      paste(setdiff(names(d), attr(d, "sf_column")), collapse = ", "),
      ". Set ward_field in R/config_city.R to the right one and knit again.")))
  }
  wards <- d %>%
    mutate(ward = ward_number(.data[[field]])) %>%
    filter(!is.na(ward)) %>%
    group_by(ward) %>%
    summarise(.groups = "drop") %>%
    mutate(label = paste("Ward", ward))
  list(wards = wards,
       message = sprintf("%d election districts merged into %d wards using column '%s'.",
                         nrow(d), nrow(wards), field))
}
