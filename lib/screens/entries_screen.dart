import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/database.dart';
import '../models/sleep_entry.dart';
import '../models/feeding_entry.dart';
import '../widgets/app_drawer.dart';

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
  List<dynamic> _entries = [];

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  Future<void> _loadEntries() async {
    final sleepEntries = _showSleep ? await DatabaseService().getSleepEntries() : [];
    final feedingEntries = _showFeeding ? await DatabaseService().getFeedingEntries() : [];

    final allEntries = [...sleepEntries, ...feedingEntries];
    allEntries.sort((a, b) => b.startTime.compareTo(a.startTime)); // Most recent first

    final filteredEntries = allEntries.where((entry) {
      if (_fromDate != null && entry.startTime.isBefore(_fromDate!)) return false;
      if (_toDate != null && entry.startTime.isAfter(_toDate!)) return false;
      return true;
    }).toList();

    setState(() {
      _entries = filteredEntries;
    });
  }

  Future<void> _pickDateRange() async {
    final pickedRange = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (pickedRange != null) {
      setState(() {
        _fromDate = pickedRange.start;
        _toDate = pickedRange.end.add(const Duration(days: 1)).subtract(const Duration(seconds: 1)); // End of day
      });
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('View Entries'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _pickDateRange,
          ),
        ],
      ),
      drawer: const AppDrawer(),
      body: Column(
        children: [
          ToggleButtons(
            isSelected: [_showSleep, _showFeeding],
            onPressed: (index) {
              setState(() {
                if (index == 0) _showSleep = !_showSleep;
                if (index == 1) _showFeeding = !_showFeeding;
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

                      if (entry is SleepEntry) {
                        return Card(
                          child: ListTile(
                            title: Text('Sleep: $startStr - $endStr'),
                            subtitle: Text('Duration: $duration'),
                          ),
                        );
                      } else if (entry is FeedingEntry) {
                        return Card(
                          child: ListTile(
                            title: Text('Feeding (${entry.source.name}): $startStr - $endStr'),
                            subtitle: Text('Duration: $duration'),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
          ),
        ],
      ),
    );
  }
}