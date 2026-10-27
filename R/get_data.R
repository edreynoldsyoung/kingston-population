# get_data.R
# Download Census data once and keep local copies in data/.
#   data/raw/    the Census Bureau's CSV files, as downloaded
#   data/cache/  results of Census API calls and map boundaries, saved as .rds
# Knit with `refresh_data: true` (or delete files in data/) to download again.

raw_dir   <- here::here("data", "raw")
cache_dir <- here::here("data", "cache")

# Download a file unless a copy is already in data/raw/.
# Downloads to a temporary name first so a failed download never leaves a
# partial file behind.
fetch_file <- function(url, refresh = FALSE) {
  dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
  dest <- file.path(raw_dir, basename(url))
  if (refresh || !file.exists(dest)) {
    message("Downloading ", basename(url), " ...")
    old <- options(timeout = max(600, getOption("timeout")))
    on.exit(options(old), add = TRUE)
    tmp <- paste0(dest, ".part")
    utils::download.file(url, tmp, mode = "wb", quiet = TRUE)
    file.rename(tmp, dest)
  }
  dest
}

# Evaluate `expr` once and save the result; later runs read the saved copy.
cached <- function(name, expr, refresh = FALSE) {
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  path <- file.path(cache_dir, paste0(name, ".rds"))
  if (!refresh && file.exists(path)) return(readRDS(path))
  value <- expr
  saveRDS(value, path)
  value
}

check_census_key <- function() {
  if (!nzchar(Sys.getenv("CENSUS_API_KEY"))) {
    stop("No Census API key found. Run\n",
         "  tidycensus::census_api_key('YOUR KEY', install = TRUE)\n",
         "then restart R. Keys are free at https://api.census.gov/data/key_signup.html",
         call. = FALSE)
  }
}

# ---- Population Estimates Program: cities and towns --------------------------

load_pep <- function(refresh = FALSE) {
  purrr::map_dfr(pep_files, function(f) {
    path <- tryCatch(
      fetch_file(f$url, refresh),
      error = function(e) {
        warning("Could not download ", basename(f$url), ": ",
                conditionMessage(e), call. = FALSE)
        NULL
      }
    )
    if (is.null(path)) return(NULL)
    read_pep_file(path, f$source)
  })
}

# ---- Population Estimates Program: county components of change ---------------

load_components <- function(refresh = FALSE) {
  purrr::map_dfr(components_files, function(f) {
    path <- tryCatch(
      fetch_file(f$url, refresh),
      error = function(e) {
        warning("Could not download ", basename(f$url), ": ",
                conditionMessage(e), call. = FALSE)
        NULL
      }
    )
    if (is.null(path)) return(NULL)
    read_components_file(path) %>%
      filter(year %in% f$keep_years) %>%
      mutate(source = f$source)
  })
}

# ---- Map boundaries ----------------------------------------------------------

load_shapes <- function(refresh = FALSE) {
  cached(paste0("shapes_", shapes_year), refresh = refresh, {
    cousub <- tigris::county_subdivisions(state = state_fips, cb = TRUE,
                                          year = shapes_year)
    counties <- tigris::counties(state = state_fips, cb = TRUE,
                                 year = shapes_year)
    list(
      cousub = cousub %>%
        filter(COUNTYFP %in% study_counties) %>%
        select(GEOID, NAME, COUNTYFP) %>%
        sf::st_transform(map_crs),
      counties = counties %>%
        filter(COUNTYFP %in% study_counties) %>%
        select(GEOID, NAME, COUNTYFP) %>%
        sf::st_transform(map_crs)
    )
  })
}

# ---- Decennial census (2000, 2010, 2020) -------------------------------------

# One call per year and county. A year that fails (the 2000 endpoint has been
# moved by the Census Bureau before) is skipped with a message.
load_decennial <- function(refresh = FALSE) {
  cached("decennial_cousub", refresh = refresh, {
    check_census_key()
    purrr::pmap_dfr(decennial_specs, function(year, sumfile, population,
                                              housing_units, occupied) {
      vars <- c(population = population, housing_units = housing_units,
                occupied = occupied)
      tryCatch(
        purrr::map_dfr(unname(study_counties), function(cty) {
          tidycensus::get_decennial(
            geography = "county subdivision", variables = vars,
            year = year, sumfile = sumfile, state = state_fips, county = cty
          )
        }) %>%
          mutate(year = year),
        error = function(e) {
          message("Decennial ", year, " not retrieved: ", conditionMessage(e))
          NULL
        }
      )
    })
  })
}

# ---- American Community Survey, 5-year ---------------------------------------

# Pulls every variable in acs_tables for each county subdivision, with the
# Census Bureau's variable labels attached so the processing code can find
# categories by name (e.g. "Moved from different state") rather than by code.
load_acs <- function(refresh = FALSE) {
  purrr::map_dfr(acs_years, function(yr) {
    cached(paste0("acs5_cousub_", yr), refresh = refresh, {
      check_census_key()
      vars <- tidycensus::load_variables(yr, "acs5", cache = TRUE) %>%
        filter(str_detect(name, "^B\\d{5}_\\d{3}$"),
               str_sub(name, 1, 6) %in% acs_tables) %>%
        select(variable = name, label)
      purrr::map_dfr(unname(study_counties), function(cty) {
        tidycensus::get_acs(
          geography = "county subdivision", variables = vars$variable,
          year = yr, survey = "acs5", state = state_fips, county = cty
        )
      }) %>%
        left_join(vars, by = "variable") %>%
        mutate(year = yr)
    })
  })
}
