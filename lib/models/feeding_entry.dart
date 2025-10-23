class FeedingEntry {
  final int? id;
  final DateTime time;

  FeedingEntry({
    this.id,
    required this.time,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'time': time.toIso8601String(),
    };
  }

  static FeedingEntry fromMap(Map<String, dynamic> map) {
    return FeedingEntry(
      id: map['id'],
      time: DateTime.parse(map['time']),
    );
  }
}