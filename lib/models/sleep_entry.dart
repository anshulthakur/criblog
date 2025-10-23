class SleepEntry {
  final int? id;
  final DateTime startTime;
  final DateTime? endTime;

  SleepEntry({
    this.id,
    required this.startTime,
    this.endTime,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime?.toIso8601String(),
    };
  }

  static SleepEntry fromMap(Map<String, dynamic> map) {
    return SleepEntry(
      id: map['id'],
      startTime: DateTime.parse(map['startTime']),
      endTime: map['endTime'] != null ? DateTime.parse(map['endTime']) : null,
    );
  }
}