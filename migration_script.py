import csv
import json
import datetime
import pytz
from dateutil.parser import parse
import gspread
from oauth2client.service_account import ServiceAccountCredentials

# Configuration
INPUT_CSV = 'feeding_entries.csv'  # Path to old CSV file
OUTPUT_CSV = 'migrated_data.csv'   # Path for new CSV
SHEET_ID = '138TnlXymuLKEh9HVnqHa4dhuf3p6fns6K0jmGAeqVB0'  # Google Sheet ID
CREDENTIALS_JSON = 'path/to/your/credentials.json'  # Path to Google API credentials
SCOPES = ['https://www.googleapis.com/auth/spreadsheets']
MODIFIED_BY = 'anshulthakurjourneyendless@gmail.com'

def ist_to_utc(date_str, time_str):
    """Convert IST date and time to UTC ISO 8601 and milliseconds."""
    try:
        ist_str = f"{date_str} {time_str}"
        ist_time = parse(ist_str)
        ist_time = ist_time.replace(tzinfo=pytz.timezone('Asia/Kolkata'))
        utc_time = ist_time.astimezone(pytz.UTC)
        sync_id = int(utc_time.timestamp() * 1000)  # Milliseconds since epoch
        timestamp = utc_time.strftime("%Y-%m-%dT%H:%M:%SZ")
        return sync_id, timestamp
    except (ValueError, TypeError) as e:
        print(f"Error parsing {date_str} {time_str}: {e}")
        # Fallback to current time
        utc_time = datetime.datetime.now(pytz.UTC)
        sync_id = int(utc_time.timestamp() * 1000)
        timestamp = utc_time.strftime("%Y-%m-%dT%H:%M:%SZ")
        return sync_id, timestamp

def extract_source(activity):
    """Extract source from Activity(Source) format, e.g., 'Feeding (breast)' -> 'breast'."""
    try:
        return activity.split('(')[1].strip(')')
    except IndexError:
        print(f"Invalid Activity(Source) format: {activity}")
        return ''

def convert_row(row, sync_id_counter):
    """Convert a single CSV row to Google Sheet format."""
    start_date = row.get('startDate', '')
    start_time = row.get('startTime', '')
    end_date = row.get('endDate', '')
    end_time = row.get('endTime', '')
    source = extract_source(row.get('Activity(Source)', ''))

    # Generate Sync ID and Timestamp from startTime
    sync_id, timestamp = ist_to_utc(start_date, start_time) if start_date and start_time else (
        int(datetime.datetime.now(pytz.UTC).timestamp() * 1000) + sync_id_counter,
        datetime.datetime.now(pytz.UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
    )

    # Split startTime into start_date and start_time
    start_date_time = parse(f"{start_date} {start_time}") if start_date and start_time else datetime.datetime.now(pytz.UTC)
    start_date_out = start_date_time.strftime("%Y-%m-%d")
    start_time_out = start_date_time.strftime("%H:%M:%S")

    # Handle endDate and endTime
    end_date_out = end_date if end_date else ''
    end_time_out = end_time if end_time else ''

    # Build Data JSON
    data = {
        'id': str(sync_id_counter),  # Use counter as ID
        'start_date': start_date_out,
        'start_time': start_time_out,
        'source': source,
        'lastModified': timestamp,
        'modifiedBy': MODIFIED_BY
    }
    if end_date_out and end_time_out:
        data['end_date'] = end_date_out
        data['end_time'] = end_time_out

    return [
        str(sync_id),          # Sync ID
        timestamp,            # Timestamp
        'insert',            # Operation
        'feeding_entries',   # Table
        json.dumps(data)     # Data JSON
    ]

def migrate_to_csv():
    """Read old CSV and write to new CSV in Google Sheet format."""
    output_rows = [['Sync ID', 'Timestamp', 'Operation', 'Table', 'Data JSON']]
    sync_id_counter = 1  # Start IDs at 1

    try:
        with open(INPUT_CSV, mode='r', encoding='utf-8') as infile:
            reader = csv.DictReader(infile)
            # Sort entries by startDate and startTime (oldest to newest)
            entries = sorted(
                [row for row in reader],
                key=lambda x: parse(f"{x['startDate']} {x['startTime']}") if x['startDate'] and x['startTime'] else datetime.datetime.now(pytz.UTC)
            )
            for row in entries:
                output_rows.append(convert_row(row, sync_id_counter))
                sync_id_counter += 1

        with open(OUTPUT_CSV, mode='w', encoding='utf-8', newline='') as outfile:
            writer = csv.writer(outfile)
            writer.writerows(output_rows)
        print(f"Migration successful. Output written to {OUTPUT_CSV}")
    except FileNotFoundError:
        print(f"Error: {INPUT_CSV} not found")
    except Exception as e:
        print(f"Error during migration: {e}")

def append_to_google_sheet():
    """Append migrated data to Google Sheet."""
    try:
        creds = ServiceAccountCredentials.from_json_keyfile_name(CREDENTIALS_JSON, SCOPES)
        client = gspread.authorize(creds)
        sheet = client.open_by_key(SHEET_ID).sheet1

        # Read migrated CSV
        with open(OUTPUT_CSV, mode='r', encoding='utf-8') as infile:
            reader = csv.reader(infile)
            next(reader)  # Skip header
            rows = list(reader)

        if rows:
            sheet.append_rows(rows)
            print(f"Successfully appended {len(rows)} rows to Google Sheet")
        else:
            print("No data to append")
    except FileNotFoundError:
        print(f"Error: {OUTPUT_CSV} or {CREDENTIALS_JSON} not found")
    except Exception as e:
        print(f"Error appending to Google Sheet: {e}")

def main():
    # Step 1: Migrate to CSV
    migrate_to_csv()
    # Step 2: Optionally append to Google Sheet
    append_to_google_sheet()

if __name__ == '__main__':
    main()