# Load the script
source("wave_cdip.R")

# Process the wave data for the sites in sites.csv
wave_data <- process_cdip_data_for_sites(
  sites_file_path = "sites.csv",
  start_date = "2017-09-01",
  end_date = "2017-09-30"
)

# Print the wave data
print(wave_data)

# Save the wave data to a CSV file
write.csv(wave_data, "wave_data.csv", row.names = FALSE)
