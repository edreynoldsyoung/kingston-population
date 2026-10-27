# load_packages.R
#
# System libraries needed on Ubuntu (install once, and again after an OS upgrade):
#   sudo apt install libgdal-dev libgeos-dev libproj-dev libudunits2-dev
#
# R packages install as precompiled binaries from Posit Package Manager,
# set in ~/.Rprofile:
#   options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/resolute/latest"))
#
# A Census API key is required (https://api.census.gov/data/key_signup.html).
# Store it once with: tidycensus::census_api_key("YOUR KEY", install = TRUE)

# List of required packages
packages <- c(
  "tidyverse",   # attaches ggplot2, dplyr, tidyr, readr, tibble, lubridate, etc.
  "tidycensus",
  "tigris",
  "sf",
  "scales",
  "ggrepel",
  "knitr",
  "here"
)

# Install any missing packages in one batch, stop with a clear message if
# anything still fails, then load everything.
check_and_load_packages <- function(pkg_list) {
  is_available <- function(pkgs) {
    vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)
  }

  missing <- pkg_list[!is_available(pkg_list)]
  if (length(missing) > 0) {
    message("Installing: ", paste(missing, collapse = ", "))
    install.packages(missing)
  }

  failed <- pkg_list[!is_available(pkg_list)]
  if (length(failed) > 0) {
    stop("Could not install or load: ", paste(failed, collapse = ", "),
         "\nCheck the install log above for a missing system library.",
         call. = FALSE)
  }

  for (pkg in pkg_list) library(pkg, character.only = TRUE)
}

# Run the function
check_and_load_packages(packages)

# Options for `tigris` package
options(tigris_use_cache = TRUE)
