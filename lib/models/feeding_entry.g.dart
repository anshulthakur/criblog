// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'feeding_entry.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FeedingEntry _$FeedingEntryFromJson(Map<String, dynamic> json) => FeedingEntry(
      id: (json['id'] as num?)?.toInt(),
      startTime: DateTime.parse(json['startTime'] as String),
      endTime: json['endTime'] == null
          ? null
          : DateTime.parse(json['endTime'] as String),
      source: $enumDecode(_$FeedingSourceEnumMap, json['source']),
      lastModified: json['lastModified'] == null
          ? null
          : DateTime.parse(json['lastModified'] as String),
      modifiedBy: json['modifiedBy'] as String?,
    );

Map<String, dynamic> _$FeedingEntryToJson(FeedingEntry instance) =>
    <String, dynamic>{
      'id': instance.id,
      'startTime': instance.startTime.toIso8601String(),
      'endTime': instance.endTime?.toIso8601String(),
      'source': _$FeedingSourceEnumMap[instance.source]!,
      'lastModified': instance.lastModified.toIso8601String(),
      'modifiedBy': instance.modifiedBy,
    };

const _$FeedingSourceEnumMap = {
  FeedingSource.breast: 'breast',
  FeedingSource.expressed: 'expressed',
};
