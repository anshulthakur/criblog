import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/database.dart';
import '../services/sync_service.dart';
import '../models/sleep_entry.dart';
import '../models/feeding_entry.dart';

class EntriesScreen extends StatefulWidget {
  const EntriesScreen({super.key});

  @override
  State<EntriesScreen> createState() => _EntriesScreenState();
}

class _EntriesScreenState extends State<EntriesScreen> {
  bool _showSleep = true;
  bool _showFeeding = true;
  DateTime? _fromDate;
  DateTime? _toDate;
  TimeOfDay? _fromTime;
  TimeOfDay? _toTime;
  List<dynamic> _entries = [];
  int _currentPage = 0;
  final int _itemsPerPage = 20;
  int _totalCount = 0;

  final DatabaseService _dbService = DatabaseService();
  final SyncService _syncService = SyncService();

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  Future<void> _loadEntries() async {
    final entries = await _dbService.getCombinedEntries(
      fromDate: _fromDate,
      toDate: _toDate,
      fromTime: _fromTime,
      toTime: _toTime,
      showSleep: _showSleep,
      showFeeding: _showFeeding,
      limit: _itemsPerPage,
      offset: _currentPage * _itemsPerPage,
    );
    final count = await _dbService.getCombinedCount(
      fromDate: _fromDate,
      toDate: _toDate,
      fromTime: _fromTime,
      toTime: _toTime,
      showSleep: _showSleep,
      showFeeding: _showFeeding,
    );

    setState(() {
      _entries = entries;
      _totalCount = count;
    });
  }

  void _nextPage() {
    if ((_currentPage + 1) * _itemsPerPage < _totalCount) {
      setState(() {
        _currentPage++;
      });
      _loadEntries();
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      setState(() {
        _currentPage--;
      });
      _loadEntries();
    }
  }

  Future<void> _showFilterDialog() async {
    DateTime? tempFromDate = _fromDate;
    DateTime? tempToDate = _toDate;
    TimeOfDay? tempFromTime = _fromTime;
    TimeOfDay? tempToTime = _toTime;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Filter Entries'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton(
                onPressed: () async {
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) {
                    setDialogState(() {
                      tempFromDate = picked.start;
                      tempToDate = picked.end.add(const Duration(days: 1)).subtract(const Duration(seconds: 1));
                    });
                  }
                },
                child: Text(
                  tempFromDate == null
                      ? 'Select Date Range'
                      : '${DateFormat('yyyy-MM-dd').format(tempFromDate!)} to ${DateFormat('yyyy-MM-dd').format(tempToDate!)}',
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: tempFromTime ?? TimeOfDay.now(),
                        );
                        if (picked != null) {
                          setDialogState(() {
                            tempFromTime = picked;
                          });
                        }
                      },
                      child: Text(tempFromTime == null ? 'From Time' : tempFromTime!.format(context)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: tempToTime ?? TimeOfDay.now(),
                        );
                        if (picked != null) {
                          setDialogState(() {
                            tempToTime = picked;
                          });
                        }
                      },
                      child: Text(tempToTime == null ? 'To Time' : tempToTime!.format(context)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () {
                  setDialogState(() {
                    tempFromDate = null;
                    tempToDate = null;
                    tempFromTime = null;
                    tempToTime = null;
                  });
                },
                child: const Text('Clear Filters'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _fromDate = tempFromDate;
                  _toDate = tempToDate;
                  _fromTime = tempFromTime;
                  _toTime = tempToTime;
                  _currentPage = 0;
                });
                _loadEntries();
                Navigator.pop(context);
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editEntry(dynamic entry) async {
    if (entry is SleepEntry) {
      await _showEditSleepDialog(entry);
    } else if (entry is FeedingEntry) {
      await _showEditFeedingDialog(entry);
    }
    _loadEntries();
  }

  Future<void> _showEditSleepDialog(SleepEntry entry) async {
    DateTime startTime = entry.startTime;
    DateTime? endTime = entry.endTime;
    bool isOngoing = endTime == null;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Sleep Entry'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton(
                onPressed: () async {
                  final pickedDate = await showDatePicker(
                    context: context,
                    initialDate: startTime,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                  );
                  if (pickedDate != null) {
                    final pickedTime = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(startTime),
                    );
                    if (pickedTime != null) {
                      setDialogState(() {
                        startTime = DateTime(
                          pickedDate.year,
                          pickedDate.month,
                          pickedDate.day,
                          pickedTime.hour,
                          pickedTime.minute,
                        );
                      });
                    }
                  }
                },
                child: Text('Start: ${DateFormat('yyyy-MM-dd HH:mm').format(startTime)}'),
              ),
              if (!isOngoing)
                ElevatedButton(
                  onPressed: () async {
                    final pickedDate = await showDatePicker(
                      context: context,
                      initialDate: endTime!,
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now(),
                    );
                    if (pickedDate != null) {
                      final pickedTime = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.fromDateTime(endTime!),
                      );
                      if (pickedTime != null) {
                        setDialogState(() {
                          endTime = DateTime(
                            pickedDate.year,
                            pickedDate.month,
                            pickedDate.day,
                            pickedTime.hour,
                            pickedTime.minute,
                          );
                        });
                      }
                    }
                  },
                  child: Text('End: ${DateFormat('yyyy-MM-dd HH:mm').format(endTime!)}'),
                ),
              CheckboxListTile(
                title: const Text('Ongoing'),
                value: isOngoing,
                onChanged: (value) {
                  setDialogState(() {
                    isOngoing = value!;
                    endTime = isOngoing ? null : (endTime ?? DateTime.now());
                  });
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                if (!isOngoing && endTime!.isBefore(startTime)) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('End time must be after start time')));
                  return;
                }
                final updated = SleepEntry(
                  id: entry.id,
                  startTime: startTime,
                  endTime: isOngoing ? null : endTime,
                  lastModified: DateTime.now(),
                  modifiedBy: 'local', // Will be updated by SyncService
                );
                _syncService.logSleepUpdate(updated);
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showEditFeedingDialog(FeedingEntry entry) async {
    DateTime startTime = entry.startTime;
    DateTime? endTime = entry.endTime;
    bool isOngoing = endTime == null;
    FeedingSource source = entry.source;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Feeding Entry'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton(
                onPressed: () async {
                  final pickedDate = await showDatePicker(
                    context: context,
                    initialDate: startTime,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                  );
                  if (pickedDate != null) {
                    final pickedTime = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(startTime),
                    );
                    if (pickedTime != null) {
                      setDialogState(() {
                        startTime = DateTime(
                          pickedDate.year,
                          pickedDate.month,
                          pickedDate.day,
                          pickedTime.hour,
                          pickedTime.minute,
                        );
                      });
                    }
                  }
                },
                child: Text('Start: ${DateFormat('yyyy-MM-dd HH:mm').format(startTime)}'),
              ),
              if (!isOngoing)
                ElevatedButton(
                  onPressed: () async {
                    final pickedDate = await showDatePicker(
                      context: context,
                      initialDate: endTime!,
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now(),
                    );
                    if (pickedDate != null) {
                      final pickedTime = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.fromDateTime(endTime!),
                      );
                      if (pickedTime != null) {
                        setDialogState(() {
                          endTime = DateTime(
                            pickedDate.year,
                            pickedDate.month,
                            pickedDate.day,
                            pickedTime.hour,
                            pickedTime.minute,
                          );
                        });
                      }
                    }
                  },
                  child: Text('End: ${DateFormat('yyyy-MM-dd HH:mm').format(endTime!)}'),
                ),
              CheckboxListTile(
                title: const Text('Ongoing'),
                value: isOngoing,
                onChanged: (value) {
                  setDialogState(() {
                    isOngoing = value!;
                    endTime = isOngoing ? null : (endTime ?? DateTime.now());
                  });
                },
              ),
              DropdownButton<FeedingSource>(
                value: source,
                items: FeedingSource.values
                    .map((s) => DropdownMenuItem(value: s, child: Text(s.name.capitalize())))
                    .toList(),
                onChanged: (value) {
                  setDialogState(() {
                    source = value!;
                  });
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                if (!isOngoing && endTime!.isBefore(startTime)) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('End time must be after start time')));
                  return;
                }
                final updated = FeedingEntry(
                  id: entry.id,
                  startTime: startTime,
                  endTime: isOngoing ? null : endTime,
                  source: source,
                  lastModified: DateTime.now(),
                  modifiedBy: 'local', // Will be updated by SyncService
                );
                _syncService.logFeedingUpdate(updated);
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteEntry(dynamic entry) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Entry'),
        content: const Text('Are you sure you want to delete this entry?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (entry is SleepEntry) {
        await _syncService.logSleepDelete(entry.id!);
      } else if (entry is FeedingEntry) {
        await _syncService.logFeedingDelete(entry.id!);
      }
      _loadEntries();
    }
  }

  String _formatDuration(DateTime start, DateTime? end) {
    if (end == null) return 'Ongoing';
    final duration = end.difference(start);
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    return '${hours}h ${minutes}m';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ToggleButtons(
          isSelected: [_showSleep, _showFeeding],
          onPressed: (index) {
            setState(() {
              if (index == 0) _showSleep = !_showSleep;
              if (index == 1) _showFeeding = !_showFeeding;
              _currentPage = 0;
            });
            _loadEntries();
          },
          children: const [
            Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Sleep')),
            Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Feeding')),
          ],
        ),
        Expanded(
          child: _entries.isEmpty
              ? const Center(child: Text('No entries found'))
              : ListView.builder(
                  itemCount: _entries.length,
                  itemBuilder: (context, index) {
                    final entry = _entries[index];
                    final startStr = DateFormat('yyyy-MM-dd HH:mm').format(entry.startTime);
                    final endStr = entry.endTime != null ? DateFormat('HH:mm').format(entry.endTime) : 'Ongoing';
                    final duration = _formatDuration(entry.startTime, entry.endTime);

                    return Card(
                      child: ListTile(
                        title: entry is SleepEntry
                            ? Text('Sleep: $startStr - $endStr')
                            : Text('Feeding (${(entry as FeedingEntry).source.name}): $startStr - $endStr'),
                        subtitle: Text('Duration: $duration'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () => _editEntry(entry),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete),
                              onPressed: () => _deleteEntry(entry),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        if (_totalCount > _itemsPerPage)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _currentPage > 0 ? _previousPage : null,
                ),
                Text('Page ${_currentPage + 1} of ${(_totalCount / _itemsPerPage).ceil()}'),
                IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: (_currentPage + 1) * _itemsPerPage < _totalCount ? _nextPage : null,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

extension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${substring(1)}";
  }
}