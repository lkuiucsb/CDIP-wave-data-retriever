# CDIP Wave Data Downloader

This R script provides a function to download wave data from the Coastal Data Information Program (CDIP) for a list of sites specified in a CSV file.

## Features

-   Retrieves wave data for multiple sites from a single CSV file.
-   Fetches CDIP station metadata automatically from the CDIP website.
-   Finds the nearest CDIP station for each site.
-   Downloads hindcast wave data (significant wave height) in parallel.
-   Returns a single data frame with the combined hourly wave data for all sites.

## Dependencies

The script requires the following R packages:

-   `tidyverse`
-   `lubridate`
-   `ncdf4`
-   `httr`
-   `purrr`
-   `furrr`
-   `future`
-   `FNN`
-   `geosphere`
-   `xml2`

You can install these packages using the following command in R:

```R
install.packages(c("tidyverse", "lubridate", "ncdf4", "httr", "purrr", "furrr", "future", "FNN", "geosphere", "xml2"))
```

## Usage

1.  **Fill in the `sites.csv` file:**

    Open the `sites.csv` file and fill in the site information. The file must have the following columns:

    -   `site`: The name of the site.
    -   `lat`: The latitude of the site.
    -   `long`: The longitude of the site.

    **Example `sites.csv`:**

    ```csv
    site,lat,long
    SBC,34.4140,-119.8489
    SFB,37.7749,-122.4194
    ```

2.  **Source the script:**

    ```R
    source("wave_CDIP.R")
    ```

3.  **Call the `process_cdip_data_for_sites` function:**

    ```R
    wave_data <- process_cdip_data_for_sites(
      sites_file_path = "sites.csv",
      start_date = "2023-09-01",
      end_date = "2023-09-05"
    )
    ```

    This will download the wave data for the sites in `sites.csv` for the specified time period and store it in the `wave_data` variable.

    The output will be a data frame with the following columns:

    -   `site`: The name of the site.
    -   `time_utc`: The timestamp in UTC.
    -   `Hs_m`: The significant wave height in meters.

## Example

Please see the `run_example.R` script for an example of how to use the `process_cdip_data_for_sites` function.


## License

This project is licensed under the MIT License. See the `LICENSE` file for details.
