# Load necessary libraries. If any are not installed, you'll need to install them first
# using install.packages("package_name").
library(tidyverse)    # Core data manipulation: dplyr, purrr, readr, tibble, etc.
library(lubridate)    # Date-time extraction (year, month, day, hour, etc.)
library(ncdf4)        # Reading NetCDF files
library(httr)         # File downloading with GET()
library(purrr)        # Functional programming tools
library(furrr)        # Parallel processing using future_map()
library(future)       # Setup for parallel strategy (plan())
library(FNN)          # Fast Nearest Neighbor
library(geosphere)    # For accurate Haversine distance
library(xml2)         # Parsing XML files

#' @title Retrieve CDIP Wave Data for a List of Sites
#'
#' @description
#' This function retrieves wave height (Hs) data from CDIP (Coastal Data Information Program)
#' for a list of geographic locations provided in a CSV file. It finds the nearest CDIP
#' station to each site, downloads the relevant hindcast data, and extracts daily mean wave height.
#'
#' @param sites_file_path A character string representing the file path to the CSV file
#'   containing the site coordinates. The CSV file must have the columns "site", "lat", and "long".
#' @param start_date A character string in "YYYY-MM-DD" format, specifying the
#'   start date for data retrieval (UTC).
#' @param end_date A character string in "YYYY-MM-DD" format, specifying the
#'   end date for data retrieval (UTC).
#' @param output_dir A character string specifying the directory where downloaded
#'   NetCDF files will be saved temporarily. Defaults to "cdip_data/".
#'
#' @return A data frame containing `site`, `date_utc`, and `Mean_Hs_m` for each site.
#'   Returns `NULL` if no data can be retrieved.
#'
#' @examples
#' \dontrun{
#' # Example: Retrieve wave data for a list of sites
#' wave_data <- process_cdip_data_for_sites(
#'   sites_file_path = "sites.csv",
#'   start_date = "2017-09-01",
#'   end_date = "2017-09-30"
#' )
#' print(wave_data)
#' }
#' @export
process_cdip_data_for_sites <- function(sites_file_path, start_date, end_date, output_dir = "cdip_data/") {

  # --- Step 1: Read sites from CSV file ---
  tryCatch({
    sites <- read.csv(sites_file_path, stringsAsFactors = FALSE) %>%
      rename_with(tolower) %>%
      rename(site = site, latitude = lat, longitude = long)
  }, error = function(e) {
    stop("Error reading sites file: ", e$message)
  })

  # --- Step 2: Get CDIP station metadata ---
  get_cdip_stations <- function() {
    metadata_url <- "http://cdip.ucsd.edu/data_access/metadata.xml"
    message("Downloading station metadata from CDIP...")
    tryCatch({
      response <- GET(metadata_url)
      response$raise_for_status()
      metadata_xml <- read_xml(content(response, "text"))
      stations <- xml_find_all(metadata_xml, ".//station")
      station_data <- map_df(stations, function(station) {
        station_id <- xml_attr(station, "name")
        latitude <- as.numeric(xml_attr(station, "latitude"))
        longitude <- as.numeric(xml_attr(station, "longitude"))
        # We are only interested in MOP stations for this script
        if (grepl("MOP", station_id)) {
          tibble(station = station_id, latitude = latitude, longitude = longitude)
        } else {
          NULL
        }
      })
      message("Successfully downloaded and parsed station metadata.")
      return(station_data)
    }, error = function(e) {
      stop("Error downloading or parsing station metadata: ", e$message)
    })
  }

  cdip_stations <- get_cdip_stations()

  if (is.null(cdip_stations) || nrow(cdip_stations) == 0) {
    message("Could not retrieve CDIP station metadata.")
    return(NULL)
  }

  # --- Step 3: Find the closest CDIP station for each site ---
  coords_mat_ori <- cdip_stations[, c("latitude", "longitude", "station")]
  site_mat <- sites[, c("latitude", "longitude", "site")]

  coords_mat <- coords_mat_ori[coords_mat_ori[, 1] >= (min(site_mat[, 1]) - 0.2) & coords_mat_ori[, 1] <= (max(site_mat[, 1]) + 0.2) &
                                 coords_mat_ori[, 2] >= (min(site_mat[, 2]) - 0.2) & coords_mat_ori[, 2] <= (max(site_mat[, 2]) + 0.2), ]

  nn <- get.knnx(data = coords_mat[, c(1, 2)], query = site_mat[, c(1, 2)], algorithm = "kd_tree", k = 1)
  nearest_points <- coords_mat[nn$nn.index, ]
  distances_m <- distHaversine(site_mat[, c(2, 1)], nearest_points[, c(2, 1)])

  colnames(nearest_points) <- c("CDIP_lat", "CDIP_lon", "CDIP_station")
  point_mat <- data.frame(cbind(site_mat, nearest_points, distances_m))

  # --- Step 4: Download hindcast files ---
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }

  url_base <- "https://thredds.cdip.ucsd.edu/thredds/fileServer/cdip/model/MOP_alongshore/"
  cases <- data.frame(station = unique(point_mat$CDIP_station)) %>%
    mutate(
      url = paste0(url_base, station, "_hindcast.nc"),
      file = paste0(output_dir, station, "_hindcast.nc")
    ) %>%
    select(url, file)

  download_site <- function(url, file) {
    cat("Processing file:", file, "\n")
    file_size_kb <- file.info(file)$size / 1024
    if (is.na(file_size_kb) || file_size_kb < 151000) {
      message("File exists but too small (", round(file_size_kb), " KB), redownloading...")
    } else {
      message("File already exists and is large enough (", round(file_size_kb), " KB), skipping.")
      return(file)
    }
    safely_download <- possibly(~GET(.x, write_disk(.y, overwrite = TRUE), timeout(600)), otherwise = NULL)
    result <- safely_download(url, file)
    if (!file.exists(file)) {
      message("Download failed or file missing:", file)
      return(NULL)
    }
    return(file)
  }

  num_cores <- ceiling(future::availableCores() * 0.2)
  plan(multisession, workers = num_cores)
  results <- future_pmap(cases, download_site, .progress = TRUE)

  # --- Step 5: Extract data ---
  stations <- unique(point_mat$CDIP_station)
  wave_data_extract <- function(station) {
    file <- paste0(output_dir, station, "_hindcast.nc")
    print(paste("processing ", file))
    nc <- nc_open(file)
    time <- ncvar_get(nc, "waveTime")
    real_time <- as.data.frame(time) %>%
      mutate(rltime = as.POSIXct(time, origin = "1970-01-01", tz = "UTC")) %>%
      mutate(time_idx = ifelse(rltime >= as.POSIXct(start_date, tz = "UTC") &
                                 rltime <= as.POSIXct(end_date, tz = "UTC"), 1, 0))
    start_index <- min(which(real_time$time_idx == 1))
    count_index <- length(which(real_time$time_idx == 1))
    hs <- ncvar_get(nc, "waveHs", start = c(start_index), count = c(count_index))
    nc_close(nc)
    df <- real_time %>%
      filter(time_idx == 1) %>%
      mutate(Hs = hs)
    daily_df <- df %>%
      mutate(date_utc = as.Date(rltime)) %>%
      group_by(date_utc) %>%
      summarise(
        Mean_Hs_m = mean(Hs, na.rm = TRUE),
        .groups = "drop"
      ) %>%
      mutate(station = station)
    return(daily_df)
  }

  num_cores <- ceiling(future::availableCores() * 0.8)
  plan(multisession, workers = num_cores)
  stationresults <- future_map(stations, wave_data_extract, .progress = TRUE)
  plan(sequential)

  # --- Step 6: Combine results ---
  sitemap <- point_mat %>%
    select(site, CDIP_station) %>%
    rename(station = CDIP_station)

  final_df <- bind_rows(stationresults) %>%
    left_join(sitemap, by = "station") %>%
    dplyr::select(site, date_utc, Mean_Hs_m)

  return(final_df)
}