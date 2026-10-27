# config_city.R
# Settings for Kingston_Neighborhoods.Rmd (block groups and wards inside the
# city). The county and data settings in config.R still apply.

# The city to analyse. Must be a city or town in study_counties (config.R),
# spelled as the Census Bureau spells it.
city_name   <- "Kingston city"
city_county <- "Ulster"

# ACS 5-year period for block-group characteristics (2020 boundaries)
bg_acs_year <- 2024

# ACS tables published at block-group level
bg_acs_tables <- c(
  "B01001",  # sex by age
  "B01002",  # median age
  "B19013",  # median household income
  "B25001",  # housing units
  "B25002",  # occupancy status
  "B25003",  # tenure (owner / renter)
  "B25038",  # tenure by year householder moved into unit
  "B25064",  # median gross rent
  "B25077"   # median home value
)

# Block groups whose 2020 population is mostly outside the city are left out
# of the ACS section (ACS figures describe the whole block group).
bg_min_share_in_city <- 0.5

# ---- Ward boundaries ---------------------------------------------------------
# By default the Ulster County election districts are downloaded and merged
# into wards (in New York cities, election districts are numbered within
# wards). To use a ward map of your own instead, set ward_file to its path
# (shapefile or GeoJSON) and ward_field to the column holding the ward number.

ward_source_url <- paste0(
  "https://www.ulstercountyny.gov/files/assets/countysite/v/1/",
  "information-services/documents/uc-local-election-districts.zip"
)
ward_file  <- NULL   # e.g. here::here("data", "my_wards.geojson")
ward_field <- NULL   # NULL = find the ward column automatically
