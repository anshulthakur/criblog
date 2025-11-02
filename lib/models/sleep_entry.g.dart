// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sleep_entry.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SleepEntry _$SleepEntryFromJson(Map<String, dynamic> json) => SleepEntry(
      id: (json['id'] as num?)?.toInt(),
      startTime: DateTime.parse(json['startTime'] as String),
      endTime: json['endTime'] == null
          ? null
          : DateTime.parse(json['endTime'] as String),
      lastModified: json['lastModified'] == null
          ? null
          : DateTime.parse(json['lastModified'] as String),
      modifiedBy: json['modifiedBy'] as String?,
    );

Map<String, dynamic> _$SleepEntryToJson(SleepEntry instance) =>
    <String, dynamic>{
      'id': instance.id,
      'startTime': instance.startTime.toIso8601String(),
      'endTime': instance.endTime?.toIso8601String(),
      'lastModified': instance.lastModified.toIso8601String(),
      'modifiedBy': instance.modifiedBy,
    };
