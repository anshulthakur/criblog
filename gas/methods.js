const SHEET_ID = '<sheet_id>';
const API_KEY = '<key>';

function doPost(e) {
  try {
    // Validate API key
    if (!e.parameter.key || e.parameter.key !== API_KEY) {
      return ContentService.createTextOutput(JSON.stringify({
        status: 'error',
        message: 'Invalid API key',
        deltas: [],
        lastSyncTimestamp: new Date(0).toISOString(),
        version: '1.0.0'
      })).setMimeType(ContentService.MimeType.JSON);
    }

    const request = JSON.parse(e.postData.contents);
    const lastSyncId = parseInt(request.lastSyncId || '0', 10);
    const sheet = SpreadsheetApp.openById(SHEET_ID).getActiveSheet();

    // Initialize Sheet headers
    if (sheet.getLastRow() === 0) {
      sheet.appendRow(['Sync ID', 'Timestamp', 'Operation', 'Table', 'Data JSON']);
    }

    // Get all rows (skip header)
    const data = sheet.getDataRange().getValues().slice(1);
    // Sort by Sync ID (timestamp) for LWW
    const sortedData = data.sort((a, b) => parseInt(a[0]) - parseInt(b[0]));
    const serverLastSyncId = data.length > 0 ? parseInt(sortedData[sortedData.length - 1][0]) : 0;

    if (request.action === 'check_sync') {
      // Case 1: Sync OK
      if (lastSyncId >= serverLastSyncId && serverLastSyncId !== 0) {
        return ContentService.createTextOutput(JSON.stringify({
          status: 'sync_ok',
          lastSyncId: serverLastSyncId.toString(),
          deltas: [],
          lastSyncTimestamp: new Date().toISOString(),
          version: '1.0.0'
        })).setMimeType(ContentService.MimeType.JSON);
      }

      // Case 2: Updates Needed
      const newerDeltas = sortedData
        .filter(row => parseInt(row[0]) > lastSyncId)
        .map(row => ({
          timestamp: parseInt(row[0]).toString(),
          operation: row[2],
          table: row[3] === 'feeding_entries' ? 'feeding' : 'sleeping',
          data: JSON.parse(row[4])
        }));

      if (newerDeltas.length > 0) {
        return ContentService.createTextOutput(JSON.stringify({
          status: 'updates_needed',
          lastSyncId: serverLastSyncId.toString(),
          deltas: newerDeltas,
          lastSyncTimestamp: new Date().toISOString(),
          version: '1.0.0'
        })).setMimeType(ContentService.MimeType.JSON);
      }

      // Case 3: Push Needed
      return ContentService.createTextOutput(JSON.stringify({
        status: 'push_needed',
        lastSyncId: serverLastSyncId.toString(),
        deltas: [],
        lastSyncTimestamp: new Date().toISOString(),
        version: '1.0.0'
      })).setMimeType(ContentService.MimeType.JSON);
    }

    if (request.action === 'push_deltas') {
      // Handle new deltas with LWW
      const existingSyncIds = sortedData.map(row => parseInt(row[0]));
      request.deltas.forEach(delta => {
        const syncId = parseInt(delta.timestamp, 10);
        const existingRowIndex = existingSyncIds.indexOf(syncId);
        const table = delta.table === 'feeding' ? 'feeding_entries' : 'sleep_entries';
        const dataJson = JSON.stringify(delta.data);

        if (existingRowIndex !== -1) {
          // LWW: Update if new timestamp is more recent
          const existingRow = sortedData[existingRowIndex];
          const existingTimestamp = parseInt(existingRow[0]);
          if (syncId >= existingTimestamp) {
            sheet.getRange(existingRowIndex + 2, 1, 1, 5).setValues([[
              syncId.toString(),
              new Date(syncId).toISOString(),
              delta.operation,
              table,
              dataJson
            ]]);
          }
        } else {
          // Append new delta
          sheet.appendRow([
            syncId.toString(),
            new Date(syncId).toISOString(),
            delta.operation,
            table,
            dataJson
          ]);
        }
      });

      // Update serverLastSyncId
      const updatedData = sheet.getDataRange().getValues().slice(1);
      const newServerLastSyncId = updatedData.length > 0 ? parseInt(updatedData.sort((a, b) => parseInt(b[0]) - parseInt(a[0]))[0][0]) : 0;

      return ContentService.createTextOutput(JSON.stringify({
        status: 'ack',
        lastSyncId: newServerLastSyncId.toString(),
        deltas: [],
        lastSyncTimestamp: new Date().toISOString(),
        version: '1.0.0'
      })).setMimeType(ContentService.MimeType.JSON);
    }

    return ContentService.createTextOutput(JSON.stringify({
      status: 'error',
      message: 'Invalid action',
      deltas: [],
      lastSyncTimestamp: new Date(0).toISOString(),
      version: '1.0.0'
    })).setMimeType(ContentService.MimeType.JSON);
  } catch (error) {
    return ContentService.createTextOutput(JSON.stringify({
      status: 'error',
      message: error.toString(),
      deltas: [],
      lastSyncTimestamp: new Date(0).toISOString(),
      version: '1.0.0'
    })).setMimeType(ContentService.MimeType.JSON);
  }
}

function doGet(e) {
  return ContentService.createTextOutput('CribLog Sync API - Use POST for sync operations').setMimeType(ContentService.MimeType.TEXT);
}