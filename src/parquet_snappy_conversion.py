# ZSTD-compressed Parquet file could not be read by the linked service so converting it to snappy parquet file and saving it to the same location with a different name. The original ZSTD-compressed Parquet file will be deleted after the conversion.
import pyarrow.parquet as pq

input_file = "dataset/yellow_tripdata_2024-03.parquet"
output_file = "dataset/yellow_tripdata_2024-03_snappy.parquet"

# Read the existing Parquet file
table = pq.read_table(input_file)

# Write it back using Snappy compression
pq.write_table(
    table,
    output_file,
    compression="snappy"
)

print(f"Converted successfully: {output_file}")