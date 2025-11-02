import 'package:json_annotation/json_annotation.dart';

part 'feeding_entry.g.dart';

enum FeedingSource { breast, expressed }

@JsonSerializable()
class FeedingEntry {
  final int? id;
  final DateTime startTime;
  final DateTime? endTime;
  final FeedingSource source;
  final DateTime lastModified;
  final String modifiedBy;

  FeedingEntry({
    this.id,
    required this.startTime,
    this.endTime,
    required this.source,
    DateTime? lastModified,
    String? modifiedBy,
  })  : lastModified = lastModified ?? DateTime.now(),
        modifiedBy = modifiedBy ?? 'local';

  factory FeedingEntry.fromJson(Map<String, dynamic> json) => _$FeedingEntryFromJson(json);
  Map<String, dynamic> toJson() => _$FeedingEntryToJson(this);

  FeedingEntry copyWith({
    int? id,
    DateTime? startTime,
    DateTime? endTime,
    FeedingSource? source,
    DateTime? lastModified,
    String? modifiedBy,
  }) {
    return FeedingEntry(
      id: id ?? this.id,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      source: source ?? this.source,
      lastModified: lastModified ?? this.lastModified,
      modifiedBy: modifiedBy ?? this.modifiedBy,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime?.toIso8601String(),
      'source': source.name,
      'lastModified': lastModified.toIso8601String(),
      'modifiedBy': modifiedBy,
    };
  }

  static FeedingEntry fromMap(Map<String, dynamic> map) {
    return FeedingEntry(
      id: map['id'],
      startTime: DateTime.parse(map['startTime']),
      endTime: map['endTime'] != null ? DateTime.parse(map['endTime']) : null,
      source: FeedingSource.values.byName(map['source'] as String),
      modifiedBy: map['modifiedBy'],
      lastModified: DateTime.parse(map['lastModified']),
    );
  }
}