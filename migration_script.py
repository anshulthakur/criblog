import csv
import json
from datetime import datetime

# Constants
INPUT_CSV = 'source.csv'
OUTPUT_CSV = 'sync_output.csv'
MODIFIED_BY = 'anshulthakurjourneyendless@gmail.com'

def parse_source_type(table_field):
    if '(' in table_field and ')' in table_field:
        return table_field.split('(')[-1].strip(' )')
    return table_field.strip().lower()

def to_iso8601(dt):
    return dt.strftime('%Y-%m-%dT%H:%M:%S.%f')[:-3] + 'Z'

def to_epoch(dt):
    return int(dt.timestamp() * 1000)

def process_row(row, entry_id):
    start_dt = datetime.strptime(f"{row['start_date']} {row['start_time'].strip()}", "%Y-%m-%d %H:%M")
    end_dt = datetime.strptime(f"{row['end_date']} {row['end_time'].strip()}", "%Y-%m-%d %H:%M")
    source = parse_source_type(row['table (source)'])

    entry = {
        "Sync ID": to_epoch(end_dt),
        "Timestamp": to_iso8601(end_dt),
        "Operation": "insert",
        "Table": "feeding_entries",
        "Data JSON": json.dumps({
            "id": str(entry_id),
            "start_date": row['start_date'],
            "start_time": start_dt.strftime("%H:%M:%S"),
            "end_date": row['end_date'],
            "end_time": end_dt.strftime("%H:%M:%S"),
            "source": source,
            "lastModified": to_iso8601(end_dt),
            "modifiedBy": MODIFIED_BY
        })
    }

    return entry

def convert_csv():
    with open(INPUT_CSV, newline='') as infile:
        reader = csv.DictReader(infile)
        sorted_rows = sorted(reader, key=lambda r: datetime.strptime(
            f"{r['start_date']} {r['start_time'].strip()}", "%Y-%m-%d %H:%M"))

    with open(OUTPUT_CSV, 'w', newline='') as outfile:
        fieldnames = ["Sync ID", "Timestamp", "Operation", "Table", "Data JSON"]
        writer = csv.DictWriter(outfile, fieldnames=fieldnames)
        writer.writeheader()

        for idx, row in enumerate(sorted_rows, start=1):
            entry = process_row(row, idx)
            writer.writerow(entry)

if __name__ == "__main__":
    convert_csv()
