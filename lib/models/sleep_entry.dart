import 'package:json_annotation/json_annotation.dart';

part 'sleep_entry.g.dart';

@JsonSerializable()
class SleepEntry {
  final int? id;
  final DateTime startTime;
  final DateTime? endTime;
  final DateTime lastModified;
  final String modifiedBy;

  SleepEntry({
    this.id,
    required this.startTime,
    this.endTime,
    DateTime? lastModified,
    String? modifiedBy,
  })  : lastModified = lastModified ?? DateTime.now(),
        modifiedBy = modifiedBy ?? 'local';

  factory SleepEntry.fromJson(Map<String, dynamic> json) => _$SleepEntryFromJson(json);
  Map<String, dynamic> toJson() => _$SleepEntryToJson(this);

  SleepEntry copyWith({
    int? id,
    DateTime? startTime,
    DateTime? endTime,
    DateTime? lastModified,
    String? modifiedBy,
  }) {
    return SleepEntry(
      id: id ?? this.id,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      lastModified: lastModified ?? this.lastModified,
      modifiedBy: modifiedBy ?? this.modifiedBy,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime?.toIso8601String(),
      'lastModified': lastModified.toIso8601String(),
      'modifiedBy': modifiedBy,
    };
  }

  static SleepEntry fromMap(Map<String, dynamic> map) {
    return SleepEntry(
      id: map['id'],
      startTime: DateTime.parse(map['startTime']),
      endTime: map['endTime'] != null ? DateTime.parse(map['endTime']) : null,
      lastModified: DateTime.parse(map['lastModified']),
      modifiedBy: map['modifiedBy'],
    );
  }
}