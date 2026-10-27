# process.R
# Turn the downloaded Census files into tidy tables for the report.

# ---- Reading the Census CSV files ---------------------------------------------

# Census flat files are Latin-1 encoded. Everything is read as text first so
# FIPS codes keep their leading zeros.
read_census_csv <- function(path) {
  raw <- readr::read_csv(path, col_types = readr::cols(.default = readr::col_character()),
                         locale = readr::locale(encoding = "latin1"), progress = FALSE)
  names(raw) <- toupper(names(raw))
  raw %>%
    mutate(
      SUMLEV = str_pad(SUMLEV, 3, pad = "0"),
      STATE  = str_pad(STATE, 2, pad = "0"),
      COUNTY = str_pad(COUNTY, 3, pad = "0"),
      across(any_of("COUSUB"), ~ str_pad(.x, 5, pad = "0"))
    )
}

# One PEP city-and-town file -> long table, New York only.
# Keeps the state (040), counties (050) and minor civil divisions (061);
# in New York the MCDs are the cities and towns.
read_pep_file <- function(path, source_label) {
  raw <- read_census_csv(path)
  id_cols <- c("SUMLEV", "STATE", "COUNTY", "COUSUB", "NAME")

  raw %>%
    filter(STATE == state_fips, SUMLEV %in% c("040", "050", "061")) %>%
    select(all_of(id_cols),
           matches("^(POPESTIMATE\\d{4}|ESTIMATESBASE\\d{4}|CENSUS\\d{4}POP)$")) %>%
    pivot_longer(-all_of(id_cols), names_to = "series", values_to = "population") %>%
    mutate(
      kind = case_when(
        str_starts(series, "POPESTIMATE")   ~ "estimate",  # July 1
        str_starts(series, "ESTIMATESBASE") ~ "base",      # April 1
        TRUE                                ~ "census"     # April 1
      ),
      year = as.integer(str_extract(series, "\\d{4}")),
      date = if_else(kind == "estimate", make_date(year, 7, 1), make_date(year, 4, 1)),
      population = as.numeric(population),
      geoid = case_when(
        SUMLEV == "040" ~ STATE,
        SUMLEV == "050" ~ paste0(STATE, COUNTY),
        TRUE            ~ paste0(STATE, COUNTY, COUSUB)
      ),
      source = source_label
    ) %>%
    filter(!is.na(population)) %>%
    transmute(geoid, sumlev = SUMLEV, county = COUNTY, name = NAME,
              source, kind, year, date, population)
}

# One county components-of-change file -> long table, New York only.
# Older files call natural change NATURALINC; it is renamed NATURALCHG.
read_components_file <- function(path) {
  raw <- read_census_csv(path)
  pattern <- "^(POPESTIMATE|NPOPCHG|BIRTHS|DEATHS|NATURALINC|NATURALCHG|INTERNATIONALMIG|DOMESTICMIG|NETMIG|RESIDUAL)_?(\\d{4})$"

  raw %>%
    filter(STATE == state_fips, SUMLEV %in% c("040", "050")) %>%
    select(SUMLEV, STATE, COUNTY, CTYNAME, matches(pattern)) %>%
    pivot_longer(-c(SUMLEV, STATE, COUNTY, CTYNAME),
                 names_to = c("component", "year"), names_pattern = pattern,
                 values_to = "value") %>%
    mutate(
      component = recode(component, NATURALINC = "NATURALCHG"),
      year  = as.integer(year),
      value = as.numeric(value),
      geoid = if_else(SUMLEV == "040", STATE, paste0(STATE, COUNTY)),
      name  = if_else(SUMLEV == "040", "New York State", CTYNAME)
    ) %>%
    select(geoid, name, component, year, value)
}

# ---- Place names ---------------------------------------------------------------

# "Kingston city" -> "Kingston (city)", "Ulster town" -> "Ulster".
# A town that shares its name with a city keeps "(town)".
short_place_name <- function(name) {
  base <- str_remove(name, " (town|city)$")
  type <- str_extract(name, "(town|city)$")
  dup  <- base %in% base[duplicated(base)]
  if_else(!is.na(type) & (type == "city" | dup),
          paste0(base, " (", type, ")"), base)
}

# All cities and towns in the study counties, with short labels and a flag
# for the focus places listed in config.R.
make_place_lookup <- function(pep_long) {
  county_names <- tibble(county = unname(study_counties),
                         county_name = names(study_counties))
  focus_key <- paste(focus_places$county, focus_places$name)

  places <- pep_long %>%
    filter(sumlev == "061", county %in% study_counties) %>%
    arrange(match(source, source_order)) %>%
    distinct(geoid, .keep_all = TRUE) %>%
    select(geoid, county, name) %>%
    left_join(county_names, by = "county") %>%
    mutate(label = short_place_name(name),
           focus = paste(county_name, name) %in% focus_key)

  unmatched <- setdiff(focus_key, paste(places$county_name, places$name))
  if (length(unmatched) > 0) {
    warning("These focus places were not found in the Census files (check spelling ",
            "in config.R): ", paste(unmatched, collapse = "; "), call. = FALSE)
  }
  places
}

# Labels for every geography in the PEP files: places, counties, the state
make_geo_labels <- function(pep_long, places) {
  pep_long %>%
    arrange(match(source, source_order)) %>%
    distinct(geoid, .keep_all = TRUE) %>%
    select(geoid, sumlev, name) %>%
    left_join(select(places, geoid, place_label = label), by = "geoid") %>%
    mutate(label = case_when(
      sumlev == "040" ~ "New York State",
      sumlev == "050" ~ name,
      TRUE            ~ coalesce(place_label, name)
    )) %>%
    select(geoid, sumlev, label)
}

# ---- Population series -----------------------------------------------------------

# July 1 estimates, one value per place and year. Where files overlap, the
# newest series wins (see source_order in config.R).
build_annual <- function(pep_long) {
  pep_long %>%
    filter(kind == "estimate") %>%
    mutate(rank = match(source, source_order)) %>%
    group_by(geoid, year) %>%
    slice_min(rank, n = 1, with_ties = FALSE) %>%
    ungroup() %>%
    select(-rank)
}

# April 1 benchmarks for 2000, 2010 and 2020: the census count where the file
# has one, otherwise the estimates base (the census count with corrections).
build_benchmarks <- function(pep_long) {
  pep_long %>%
    filter(kind %in% c("census", "base"), year %in% c(2000, 2010, 2020)) %>%
    mutate(rank = case_when(
      kind == "census"                 ~ 1L,
      str_starts(source, "Intercensal") ~ 2L,
      TRUE                             ~ 3L
    )) %>%
    group_by(geoid, year) %>%
    slice_min(rank, n = 1, with_ties = FALSE) %>%
    ungroup() %>%
    select(-rank)
}

# Average annual (compound) growth before and after the 2020 census.
#   2010-2020: April 2010 estimates base to April 2020 census count (10 years)
#   2020-latest: April 2020 estimates base to the latest July 1 estimate.
# Each period uses one consistent series, so the 2020 switch between series
# does not create artificial growth or decline.
build_growth <- function(pep_long, vintage = pep_vintage) {
  value_of <- function(source_pattern, kind_wanted, year_wanted, new_name) {
    pep_long %>%
      filter(str_detect(source, source_pattern), kind == kind_wanted,
             year == year_wanted) %>%
      distinct(geoid, .keep_all = TRUE) %>%
      select(geoid, population) %>%
      rename(!!new_name := population)
  }
  years_post <- (vintage - 2020) + 0.25

  value_of("^Intercensal 2010", "base", 2010, "pop_2010") %>%
    full_join(value_of("^Intercensal 2010", "census", 2020, "census_2020"), by = "geoid") %>%
    full_join(value_of("^Vintage", "base", 2020, "base_2020"), by = "geoid") %>%
    full_join(value_of("^Vintage", "estimate", vintage, "pop_latest"), by = "geoid") %>%
    mutate(
      cagr_2010_2020   = 100 * ((census_2020 / pop_2010)^(1 / 10) - 1),
      cagr_2020_latest = 100 * ((pop_latest / base_2020)^(1 / years_post) - 1),
      pct_2020_latest  = 100 * (pop_latest / base_2020 - 1)
    )
}

# County components of change, one row per county and year, with rates per
# 1,000 residents.
build_components <- function(components) {
  components %>%
    select(-source) %>%
    pivot_wider(names_from = component, values_from = value) %>%
    mutate(across(c(NATURALCHG, DOMESTICMIG, INTERNATIONALMIG, NETMIG),
                  ~ 1000 * .x / POPESTIMATE, .names = "rate_{.col}"))
}

# ---- Decennial census -----------------------------------------------------------

build_decennial <- function(dec_raw) {
  if (is.null(dec_raw) || nrow(dec_raw) == 0) return(NULL)
  dec_raw %>%
    filter(!str_detect(NAME, "not defined")) %>%
    select(geoid = GEOID, year, variable, value) %>%
    pivot_wider(names_from = variable, values_from = value) %>%
    mutate(persons_per_occupied = population / occupied)
}

# ---- ACS margins of error ---------------------------------------------------------
# Formulas from the Census Bureau's ACS handbook. ACS MOEs are 90% intervals.

moe_sum2 <- function(moe) sqrt(sum(moe^2, na.rm = TRUE))

# MOE of a proportion num / den where num is a subset of den. Falls back to
# the ratio formula when the term under the square root is negative.
moe_prop2 <- function(num, den, moe_num, moe_den) {
  p   <- num / den
  rad <- moe_num^2 - p^2 * moe_den^2
  ifelse(rad < 0, sqrt(moe_num^2 + p^2 * moe_den^2), sqrt(rad)) / den
}

# Is the change between two ACS estimates statistically significant at 90%?
# Equivalent to |z| > 1.645 with z = diff / sqrt(se1^2 + se2^2).
sig_change <- function(est1, est2, moe1, moe2) {
  abs(est2 - est1) > sqrt(moe1^2 + moe2^2)
}

# ---- ACS indicators ---------------------------------------------------------------

age_groups <- c("Under 18", "18 to 34", "35 to 64", "65 and over")

# Split a Census label like "Estimate!!Total:!!Male:!!5 to 9 years" into its
# meaningful parts: c("Male", "5 to 9 years").
label_parts <- function(label) {
  label %>%
    str_remove_all(":") %>%
    str_split("!!") %>%
    purrr::map(~ setdiff(str_trim(.x), c("Estimate", "Total", "")))
}

# From raw ACS rows to one row per place, year and indicator, each with an
# estimate and a 90% margin of error.
build_acs_indicators <- function(acs_raw) {
  if (is.null(acs_raw) || nrow(acs_raw) == 0) return(NULL)

  acs <- acs_raw %>%
    filter(!str_detect(NAME, "not defined")) %>%
    mutate(
      estimate = if_else(estimate < 0, NA_real_, as.numeric(estimate)),
      moe      = if_else(moe < 0, NA_real_, as.numeric(moe)),
      table    = str_sub(variable, 1, 6),
      parts    = label_parts(label),
      n_parts  = lengths(parts),
      part1    = purrr::map_chr(parts, ~ if (length(.x) >= 1) .x[1] else NA_character_),
      part2    = purrr::map_chr(parts, ~ if (length(.x) >= 2) .x[2] else NA_character_)
    ) %>%
    rename(geoid = GEOID)

  denominator <- function(var) {
    acs %>% filter(variable == var) %>%
      select(geoid, year, den = estimate, den_moe = moe)
  }
  as_share <- function(df, den_var, indicator) {
    df %>%
      left_join(denominator(den_var), by = c("geoid", "year")) %>%
      transmute(geoid, year, indicator = indicator, unit = "share",
                estimate = num / den, moe = moe_prop2(num, den, num_moe, den_moe))
  }
  single <- function(var, indicator, unit) {
    acs %>% filter(variable == var) %>%
      transmute(geoid, year, indicator = indicator, unit = unit, estimate, moe)
  }

  # Age groups from B01001 (sex by age): sum the male and female rows
  age <- acs %>%
    filter(table == "B01001", n_parts == 2, part1 %in% c("Male", "Female")) %>%
    mutate(
      age_start = if_else(str_detect(part2, "^Under"), 0,
                          as.numeric(str_extract(part2, "\\d+"))),
      age_group = cut(age_start, c(-Inf, 17, 34, 64, Inf), labels = age_groups)
    ) %>%
    group_by(geoid, year, age_group) %>%
    summarise(num = sum(estimate), num_moe = moe_sum2(moe), .groups = "drop") %>%
    left_join(denominator("B01001_001"), by = c("geoid", "year")) %>%
    transmute(geoid, year, indicator = paste0("Age: ", age_group), unit = "share",
              estimate = num / den, moe = moe_prop2(num, den, num_moe, den_moe))

  # Where people lived a year ago (B07003), as a share of residents age 1+
  mobility <- acs %>%
    filter(table == "B07003", n_parts == 1) %>%
    mutate(indicator = case_when(
      str_detect(part1, "different county") ~ "Moved from another NY county",
      str_detect(part1, "different state")  ~ "Moved from another state",
      str_detect(part1, "abroad")           ~ "Moved from abroad"
    )) %>%
    filter(!is.na(indicator)) %>%
    select(geoid, year, indicator, num = estimate, num_moe = moe) %>%
    left_join(denominator("B07003_001"), by = c("geoid", "year")) %>%
    transmute(geoid, year, indicator, unit = "share",
              estimate = num / den, moe = moe_prop2(num, den, num_moe, den_moe))

  # Seasonal, recreational or occasional-use homes (B25004) per housing unit
  seasonal <- acs %>%
    filter(table == "B25004", n_parts == 1, str_detect(part1, "[Ss]easonal")) %>%
    select(geoid, year, num = estimate, num_moe = moe) %>%
    as_share("B25001_001", "Seasonal homes (share of housing units)")

  vacant <- acs %>%
    filter(variable == "B25002_003") %>%
    select(geoid, year, num = estimate, num_moe = moe) %>%
    as_share("B25002_001", "Vacant (share of housing units)")

  owner <- acs %>%
    filter(variable == "B25003_002") %>%
    select(geoid, year, num = estimate, num_moe = moe) %>%
    as_share("B25003_001", "Owner-occupied (share of households)")

  bind_rows(
    single("B01001_001", "Total population", "count"),
    single("B11001_001", "Households", "count"),
    single("B25001_001", "Housing units", "count"),
    single("B01002_001", "Median age", "years"),
    single("B19013_001", "Median household income", "dollars"),
    single("B25064_001", "Median gross rent", "dollars"),
    single("B25077_001", "Median home value", "dollars"),
    age, mobility, seasonal, vacant, owner
  ) %>%
    mutate(period = period_label(year))
}

# Change in one ACS indicator between two 5-year periods, with a 90%
# significance flag.
acs_change <- function(acs_ind, indicator_name, from_year, to_year) {
  acs_ind %>%
    filter(indicator == indicator_name, year %in% c(from_year, to_year)) %>%
    mutate(when = if_else(year == from_year, "from", "to")) %>%
    select(geoid, when, estimate, moe) %>%
    pivot_wider(names_from = when, values_from = c(estimate, moe)) %>%
    mutate(
      change      = estimate_to - estimate_from,
      moe_change  = sqrt(moe_from^2 + moe_to^2),
      significant = sig_change(estimate_from, estimate_to, moe_from, moe_to)
    )
}
