# get_data_city.R
# Downloads for Kingston_Neighborhoods.Rmd. Uses fetch_file(), cached() and
# check_census_key() from get_data.R, so source that file first.

city_county_fips <- function() study_counties[[city_county]]

# The internal point of each census block (a point guaranteed to lie inside
# the block), as an sf point layer. Works for 2010 and 2020 block files.
block_points <- function(blocks) {
  nm    <- names(blocks)
  geoid <- nm[str_detect(nm, "^GEOID(10|20)?$")][1]
  lat   <- nm[str_detect(nm, "^INTPTLAT")][1]
  lon   <- nm[str_detect(nm, "^INTPTLON")][1]
  blocks %>%
    sf::st_drop_geometry() %>%
    transmute(block = .data[[geoid]],
              lon = as.numeric(.data[[lon]]),
              lat = as.numeric(.data[[lat]])) %>%
    sf::st_as_sf(coords = c("lon", "lat"), crs = 4269) %>%
    sf::st_transform(map_crs)
}

# City boundary (2020, full resolution) and the 2010 and 2020 census blocks
# that lie inside it.
load_city_geo <- function(refresh = FALSE) {
  cached("city_geo", refresh = refresh, {
    cty <- city_county_fips()

    cousub <- tigris::county_subdivisions(state = state_fips, county = cty,
                                          cb = FALSE, year = 2020)
    city <- cousub %>%
      filter(NAMELSAD == city_name) %>%
      select(GEOID, NAMELSAD) %>%
      sf::st_transform(map_crs)
    if (nrow(city) != 1) {
      stop("Could not find '", city_name, "' in the 2020 boundary file.", call. = FALSE)
    }

    b20 <- tigris::blocks(state = state_fips, county = cty, year = 2020)
    b10 <- tigris::blocks(state = state_fips, county = cty, year = 2010)

    pts20 <- block_points(b20)
    pts10 <- block_points(b10)
    in20  <- lengths(sf::st_within(pts20, city)) > 0
    in10  <- lengths(sf::st_within(pts10, city)) > 0

    geoid20  <- names(b20)[str_detect(names(b20), "^GEOID(20)?$")][1]
    blocks20 <- b20 %>%
      transmute(block = .data[[geoid20]]) %>%
      filter(block %in% pts20$block[in20]) %>%
      sf::st_transform(map_crs)

    list(city = city, blocks20 = blocks20,
         points20 = pts20[in20, ], points10 = pts10[in10, ])
  })
}

# Decennial block counts for the whole county, 2010 and 2020: total
# population, housing units, and sex by age.
load_block_counts <- function(refresh = FALSE) {
  cached("block_counts", refresh = refresh, {
    check_census_key()
    specs <- tibble::tribble(
      ~year, ~sumfile, ~age_pattern,     ~population, ~housing_units,
      2010,  "sf1",    "^P012\\d{3}$",   "P001001",   "H001001",
      2020,  "dhc",    "^P12_\\d{3}N$",  "P1_001N",   "H1_001N"
    )
    purrr::pmap_dfr(specs, function(year, sumfile, age_pattern, population, housing_units) {
      age_vars <- tidycensus::load_variables(year, sumfile, cache = TRUE) %>%
        filter(str_detect(name, age_pattern)) %>%
        select(variable = name, label)
      totals <- tibble(variable = c(population, housing_units),
                       label    = c("population", "housing_units"))
      vars <- bind_rows(totals, age_vars)

      # Two requests, each under the API's 50-variable limit
      purrr::map_dfr(list(totals$variable, age_vars$variable), function(v) {
        tidycensus::get_decennial(
          geography = "block", variables = v, year = year, sumfile = sumfile,
          state = state_fips, county = city_county_fips()
        )
      }) %>%
        left_join(vars, by = "variable") %>%
        transmute(block = GEOID, year = year, variable, label, value)
    })
  })
}

# ACS 5-year estimates for every block group in the county
load_acs_bg <- function(refresh = FALSE) {
  cached(paste0("acs5_bg_", bg_acs_year), refresh = refresh, {
    check_census_key()
    vars <- tidycensus::load_variables(bg_acs_year, "acs5", cache = TRUE) %>%
      filter(str_detect(name, "^B\\d{5}_\\d{3}$"),
             str_sub(name, 1, 6) %in% bg_acs_tables) %>%
      select(variable = name, label)
    tidycensus::get_acs(
      geography = "block group", variables = vars$variable,
      year = bg_acs_year, survey = "acs5",
      state = state_fips, county = city_county_fips()
    ) %>%
      left_join(vars, by = "variable") %>%
      mutate(year = bg_acs_year)
  })
}

# Election districts (or your own ward file) as an sf layer
load_districts <- function(refresh = FALSE) {
  path <- ward_file
  if (is.null(path)) {
    zip   <- fetch_file(ward_source_url, refresh)
    exdir <- file.path(raw_dir, tools::file_path_sans_ext(basename(zip)))
    if (refresh || !dir.exists(exdir)) utils::unzip(zip, exdir = exdir)
    shp <- list.files(exdir, pattern = "\\.shp$", recursive = TRUE, full.names = TRUE)
    if (length(shp) == 0) stop("No shapefile found in ", basename(zip), call. = FALSE)
    if (length(shp) > 1) message("Several shapefiles in ", basename(zip), "; using ", basename(shp[1]))
    path <- shp[1]
  }
  sf::read_sf(path) %>%
    sf::st_make_valid() %>%
    sf::st_transform(map_crs)
}
