# config.R
# Settings for the Kingston population project. Edit this file to change the
# study area, the focus places, or the data years. Nothing else needs to change.

# ---- Geography --------------------------------------------------------------

state_fips <- "36"   # New York

# Counties whose towns and cities are mapped and compared.
# Names are used for labels; values are county FIPS codes.
study_counties <- c(Ulster = "111", Dutchess = "027", Greene = "039")

# County used for the births / deaths / migration breakdown
home_county <- "Ulster"

# Counties compared on components of change (births, deaths, migration)
comparison_counties <- c(Ulster = "111", Dutchess = "027", Greene = "039",
                         Columbia = "021", Orange = "071", Sullivan = "105",
                         Delaware = "025")

# Kingston and the towns around it. County must be one of study_counties, and
# the name must match Census spelling exactly ("Kingston city", "Ulster town").
# In New York, cities and towns are both county subdivisions; villages sit
# inside towns and are not listed separately here.
focus_places <- tibble::tribble(
  ~county,    ~name,
  "Ulster",   "Kingston city",
  "Ulster",   "Kingston town",
  "Ulster",   "Ulster town",
  "Ulster",   "Esopus town",
  "Ulster",   "Hurley town",
  "Ulster",   "Saugerties town",
  "Ulster",   "Woodstock town",
  "Ulster",   "Rosendale town",
  "Ulster",   "Marbletown town",
  "Dutchess", "Rhinebeck town"
)

# ---- Data years -------------------------------------------------------------

# Population Estimates Program (PEP) vintage. Each May the Census Bureau
# releases a new vintage of city and town estimates (Vintage 2026 is due in
# May 2027). Change this number, then knit once with refresh_data: true.
pep_vintage <- 2025

# End years of non-overlapping ACS 5-year periods: 2010-14, 2015-19, 2020-24.
# The Census Bureau advises comparing only non-overlapping 5-year periods.
acs_years <- c(2014, 2019, 2024)

# Boundary year for maps (cartographic boundary files)
shapes_year <- 2024

# Projected coordinate system for maps: NAD83 / New York East (meters)
map_crs <- 32115

# ---- Source files -----------------------------------------------------------

popest_url <- "https://www2.census.gov/programs-surveys/popest/datasets"

vintage_label <- paste("Vintage", pep_vintage)

# City and town (subcounty) population estimates. Later files take priority
# over earlier ones where years overlap.
pep_files <- list(
  list(source = "Intercensal 2000-2010",
       url    = paste0(popest_url, "/2000-2010/intercensal/cities/sub-est00int.csv")),
  list(source = "Intercensal 2010-2020",
       url    = paste0(popest_url, "/2010-2020/intercensal/cities/sub-est2020int.csv")),
  list(source = vintage_label,
       url    = sprintf("%s/2020-%d/cities/totals/sub-est%d_%s.csv",
                        popest_url, pep_vintage, pep_vintage, as.integer(state_fips)))
)

# Order of preference when the same year appears in more than one file
source_order <- c(vintage_label, "Intercensal 2010-2020", "Intercensal 2000-2010")

# County components of change (births, deaths, migration).
# keep_years drops the partial-year periods at the start of each file.
components_files <- list(
  list(source = "Vintage 2020",
       url    = paste0(popest_url, "/2010-2020/counties/totals/co-est2020-alldata.csv"),
       keep_years = 2011:2020),
  list(source = vintage_label,
       url    = sprintf("%s/2020-%d/counties/totals/co-est%d-alldata.csv",
                        popest_url, pep_vintage, pep_vintage),
       keep_years = 2021:pep_vintage)
)

# Decennial census: total population, housing units, occupied housing units
decennial_specs <- tibble::tribble(
  ~year, ~sumfile, ~population, ~housing_units, ~occupied,
  2000,  "sf1",    "P001001",   "H001001",      "H003002",
  2010,  "sf1",    "P001001",   "H001001",      "H003002",
  2020,  "pl",     "P1_001N",   "H1_001N",      "H1_002N"
)

# ACS 5-year tables used for population characteristics
acs_tables <- c(
  "B01001",  # sex by age
  "B01002",  # median age
  "B07003",  # geographic mobility in the past year
  "B11001",  # households
  "B19013",  # median household income
  "B25001",  # housing units
  "B25002",  # occupancy status
  "B25003",  # tenure
  "B25004",  # vacancy status (includes seasonal homes)
  "B25064",  # median gross rent
  "B25077"   # median home value
)
