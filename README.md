# Kingston, NY population trends

An R Project that downloads Census Bureau data for the City of Kingston and the
surrounding towns and knits it into two reports (HTML or PDF):

- `Kingston_Population.Rmd`: Kingston and the surrounding towns and counties
- `Kingston_Neighborhoods.Rmd`: inside the city, by block group and by ward

## Before the first knit

1. **System libraries** (for the maps; skip any you already have):

   ```bash
   sudo apt install libgdal-dev libgeos-dev libproj-dev libudunits2-dev
   ```

2. **Census API key.** Free from <https://api.census.gov/data/key_signup.html>.
   Recent versions of tidycensus require one for every request. If you already
   set one up for your COVID tracker it is in `~/.Renviron` and nothing more is
   needed; otherwise run once in R, then restart R:

   ```r
   tidycensus::census_api_key("YOUR KEY", install = TRUE)
   ```

3. Open `kingston-population.Rproj` in RStudio and click **Knit**.
   `R/load_packages.R` installs any missing packages.

The first knit downloads several Census files and queries the Census API, so
it takes a few minutes. Everything is saved in `data/`, and later knits use the
saved copies and run in seconds.

## Files

| File | What it does |
|---|---|
| `Kingston_Population.Rmd` | Report: Kingston and the surrounding area |
| `Kingston_Neighborhoods.Rmd` | Report: block groups and wards inside the city |
| `R/config.R` | **The file to edit**: counties, focus towns, data years, source URLs |
| `R/config_city.R` | Settings for the neighborhoods report: city, ACS year, ward source |
| `R/load_packages.R` | Installs and loads packages |
| `R/get_data.R` | Downloads data and saves local copies in `data/` |
| `R/get_data_city.R` | Downloads blocks, block counts, block-group ACS data and ward boundaries |
| `R/process.R` | Cleans the Census files; computes growth rates, migration rates, ACS shares and margins of error |
| `R/process_city.R` | Adds blocks up into block groups and wards; builds wards from election districts |
| `R/theme.R` | Colors (Okabe-Ito palette) and chart theme |
| `styles.css` | Page styling |
| `data/raw/` | Census CSV files as downloaded (created on first knit) |
| `data/cache/` | Saved API results and map boundaries (created on first knit) |

## What the report covers

- Annual population, 2000 to the latest estimate, for each focus place
- Kingston against Ulster, Dutchess and Greene counties and New York State, indexed to 2010
- Average annual growth 2010-2020 vs. since 2020, as a table and a map of every town
- Ulster County's births, deaths, domestic and international migration, 2011 onward
- Domestic and international migration rates for seven Hudson Valley and Catskill counties, before and after 2020
- Housing-unit growth vs. population growth (decennial census)
- Age structure, recent arrivals, seasonal homes, and median income, rent and home value (ACS 5-year, with 90% margins of error and significance tests)

## What the neighborhoods report covers

- Population and housing units by block group, 2010 and 2020, with a map of change
- Children and residents 65+ by block group, 2010 and 2020
- Block-group characteristics from the ACS (2020-2024): median household income,
  renters, residents 65+, recent movers, each with its margin of error and a
  reliability flag
- The same population, housing and age figures by ward

Both scales are built from census blocks, so 2010 and 2020 are compared on
today's boundaries. Ward boundaries come from the Ulster County election
districts file, merged into wards automatically. If the report says it could
not find the ward column, it lists the file's columns; set `ward_field` in
`R/config_city.R` to the right one. To use a ward map of your own, set
`ward_file` instead.

## Data sources

| Source | Geography | Years |
|---|---|---|
| Population Estimates Program, city and town totals | State, counties, cities and towns | 2000-2025, annual |
| Population Estimates Program, county components of change | Counties | 2011-2025, annual |
| Decennial Census (SF1 2000 and 2010; PL 94-171 2020) | Cities and towns | 2000, 2010, 2020 |
| American Community Survey, 5-year | Cities and towns | 2010-14, 2015-19, 2020-24 |
| TIGER/Line cartographic boundaries | Cities and towns, counties | 2024 |
| Decennial Census (SF1 2010; DHC 2020) | Census blocks | 2010, 2020 |
| American Community Survey, 5-year | Block groups | 2020-24 |
| TIGER/Line blocks and city boundary | Blocks, City of Kingston | 2010, 2020 |
| Ulster County election districts | Wards | current |

## Changing things

- **Different towns:** edit `focus_places` in `R/config.R`. Names must match
  Census spelling, e.g. `"New Paltz town"`. A misspelled name produces a
  warning naming it.
- **More counties on the maps:** add to `study_counties` (name = FIPS code).
  Then knit once with `refresh_data: true` so the API data is fetched for them.
- **New data each year:**
  - City and town estimates arrive each May. Set `pep_vintage <- 2026` in May 2027.
  - New ACS 5-year data arrives each winter. A new non-overlapping period
    comes every five years; the next is 2025-2029.
  - After changing either, knit once with `refresh_data: true` (in the YAML
    header, or Knit > Knit with Parameters).
- **Start fresh:** delete the `data/` folder.

## Caveats

- Estimates for cities and towns are modelled from housing-unit changes, not
  counted, and have no margin of error. Each new vintage revises all years back to 2020.
- Births, deaths and migration exist only at the county level.
- The 2000 decennial endpoint has moved before. If it fails, the report uses
  2010 and 2020 only and says so in the knit log.
- ACS figures for small towns have wide margins of error. Read the error bars
  before reading anything into a difference.
