enum FeedingSource { breast, expressed }

class FeedingEntry {
  final int? id;
  final DateTime startTime;
  final DateTime? endTime;
  final FeedingSource source;

  FeedingEntry({
    this.id,
    required this.startTime,
    this.endTime,
    required this.source,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime?.toIso8601String(),
      'source': source.name, // Store enum as string
    };
  }

  static FeedingEntry fromMap(Map<String, dynamic> map) {
    return FeedingEntry(
      id: map['id'],
      startTime: DateTime.parse(map['startTime']),
      endTime: map['endTime'] != null ? DateTime.parse(map['endTime']) : null,
      source: FeedingSource.values.byName(map['source'] as String),
    );
  }

  FeedingEntry insertWithId(int id) => FeedingEntry(
    id: id,
    startTime: startTime,
    endTime: endTime,
    source: source,
  );

  FeedingEntry copyWith({int? id, DateTime? startTime, DateTime? endTime, FeedingSource? source}) {
    return FeedingEntry(
      id: id ?? this.id,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      source: source ?? this.source,
    );
  }
}