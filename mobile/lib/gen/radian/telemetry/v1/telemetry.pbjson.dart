// This is a generated file - do not edit.
//
// Generated from radian/telemetry/v1/telemetry.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports
// ignore_for_file: unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use jobStatusDescriptor instead')
const JobStatus$json = {
  '1': 'JobStatus',
  '2': [
    {'1': 'JOB_STATUS_UNSPECIFIED', '2': 0},
    {'1': 'JOB_STATUS_PENDING', '2': 1},
    {'1': 'JOB_STATUS_ASSIGNED', '2': 2},
    {'1': 'JOB_STATUS_EN_ROUTE_PICKUP', '2': 3},
    {'1': 'JOB_STATUS_ON_SITE', '2': 4},
    {'1': 'JOB_STATUS_EN_ROUTE_DROPOFF', '2': 5},
    {'1': 'JOB_STATUS_COMPLETED', '2': 6},
    {'1': 'JOB_STATUS_CANCELLED', '2': 7},
  ],
};

/// Descriptor for `JobStatus`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List jobStatusDescriptor = $convert.base64Decode(
    'CglKb2JTdGF0dXMSGgoWSk9CX1NUQVRVU19VTlNQRUNJRklFRBAAEhYKEkpPQl9TVEFUVVNfUE'
    'VORElORxABEhcKE0pPQl9TVEFUVVNfQVNTSUdORUQQAhIeChpKT0JfU1RBVFVTX0VOX1JPVVRF'
    'X1BJQ0tVUBADEhYKEkpPQl9TVEFUVVNfT05fU0lURRAEEh8KG0pPQl9TVEFUVVNfRU5fUk9VVE'
    'VfRFJPUE9GRhAFEhgKFEpPQl9TVEFUVVNfQ09NUExFVEVEEAYSGAoUSk9CX1NUQVRVU19DQU5D'
    'RUxMRUQQBw==');

@$core.Deprecated('Use vehicleStatusDescriptor instead')
const VehicleStatus$json = {
  '1': 'VehicleStatus',
  '2': [
    {'1': 'VEHICLE_STATUS_UNSPECIFIED', '2': 0},
    {'1': 'VEHICLE_STATUS_OFFLINE', '2': 1},
    {'1': 'VEHICLE_STATUS_IDLE', '2': 2},
    {'1': 'VEHICLE_STATUS_EN_ROUTE', '2': 3},
    {'1': 'VEHICLE_STATUS_ON_JOB', '2': 4},
  ],
};

/// Descriptor for `VehicleStatus`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List vehicleStatusDescriptor = $convert.base64Decode(
    'Cg1WZWhpY2xlU3RhdHVzEh4KGlZFSElDTEVfU1RBVFVTX1VOU1BFQ0lGSUVEEAASGgoWVkVISU'
    'NMRV9TVEFUVVNfT0ZGTElORRABEhcKE1ZFSElDTEVfU1RBVFVTX0lETEUQAhIbChdWRUhJQ0xF'
    'X1NUQVRVU19FTl9ST1VURRADEhkKFVZFSElDTEVfU1RBVFVTX09OX0pPQhAE');

@$core.Deprecated('Use geofenceKindDescriptor instead')
const GeofenceKind$json = {
  '1': 'GeofenceKind',
  '2': [
    {'1': 'GEOFENCE_KIND_UNSPECIFIED', '2': 0},
    {'1': 'GEOFENCE_KIND_DEPOT', '2': 1},
    {'1': 'GEOFENCE_KIND_SERVICE_AREA', '2': 2},
    {'1': 'GEOFENCE_KIND_RESTRICTED', '2': 3},
  ],
};

/// Descriptor for `GeofenceKind`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List geofenceKindDescriptor = $convert.base64Decode(
    'CgxHZW9mZW5jZUtpbmQSHQoZR0VPRkVOQ0VfS0lORF9VTlNQRUNJRklFRBAAEhcKE0dFT0ZFTk'
    'NFX0tJTkRfREVQT1QQARIeChpHRU9GRU5DRV9LSU5EX1NFUlZJQ0VfQVJFQRACEhwKGEdFT0ZF'
    'TkNFX0tJTkRfUkVTVFJJQ1RFRBAD');

@$core.Deprecated('Use locationPointDescriptor instead')
const LocationPoint$json = {
  '1': 'LocationPoint',
  '2': [
    {'1': 'seq', '3': 1, '4': 1, '5': 3, '10': 'seq'},
    {'1': 'latitude', '3': 2, '4': 1, '5': 1, '10': 'latitude'},
    {'1': 'longitude', '3': 3, '4': 1, '5': 1, '10': 'longitude'},
    {'1': 'recorded_at_ms', '3': 4, '4': 1, '5': 3, '10': 'recordedAtMs'},
    {
      '1': 'speed_kmh',
      '3': 5,
      '4': 1,
      '5': 2,
      '9': 0,
      '10': 'speedKmh',
      '17': true
    },
    {
      '1': 'heading_deg',
      '3': 6,
      '4': 1,
      '5': 2,
      '9': 1,
      '10': 'headingDeg',
      '17': true
    },
    {
      '1': 'accuracy_m',
      '3': 7,
      '4': 1,
      '5': 2,
      '9': 2,
      '10': 'accuracyM',
      '17': true
    },
    {
      '1': 'altitude_m',
      '3': 8,
      '4': 1,
      '5': 2,
      '9': 3,
      '10': 'altitudeM',
      '17': true
    },
    {
      '1': 'battery_pct',
      '3': 9,
      '4': 1,
      '5': 5,
      '9': 4,
      '10': 'batteryPct',
      '17': true
    },
  ],
  '8': [
    {'1': '_speed_kmh'},
    {'1': '_heading_deg'},
    {'1': '_accuracy_m'},
    {'1': '_altitude_m'},
    {'1': '_battery_pct'},
  ],
};

/// Descriptor for `LocationPoint`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List locationPointDescriptor = $convert.base64Decode(
    'Cg1Mb2NhdGlvblBvaW50EhAKA3NlcRgBIAEoA1IDc2VxEhoKCGxhdGl0dWRlGAIgASgBUghsYX'
    'RpdHVkZRIcCglsb25naXR1ZGUYAyABKAFSCWxvbmdpdHVkZRIkCg5yZWNvcmRlZF9hdF9tcxgE'
    'IAEoA1IMcmVjb3JkZWRBdE1zEiAKCXNwZWVkX2ttaBgFIAEoAkgAUghzcGVlZEttaIgBARIkCg'
    'toZWFkaW5nX2RlZxgGIAEoAkgBUgpoZWFkaW5nRGVniAEBEiIKCmFjY3VyYWN5X20YByABKAJI'
    'AlIJYWNjdXJhY3lNiAEBEiIKCmFsdGl0dWRlX20YCCABKAJIA1IJYWx0aXR1ZGVNiAEBEiQKC2'
    'JhdHRlcnlfcGN0GAkgASgFSARSCmJhdHRlcnlQY3SIAQFCDAoKX3NwZWVkX2ttaEIOCgxfaGVh'
    'ZGluZ19kZWdCDQoLX2FjY3VyYWN5X21CDQoLX2FsdGl0dWRlX21CDgoMX2JhdHRlcnlfcGN0');

@$core.Deprecated('Use telemetryBatchDescriptor instead')
const TelemetryBatch$json = {
  '1': 'TelemetryBatch',
  '2': [
    {
      '1': 'points',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.radian.telemetry.v1.LocationPoint',
      '10': 'points'
    },
    {'1': 'is_backfill', '3': 2, '4': 1, '5': 8, '10': 'isBackfill'},
  ],
};

/// Descriptor for `TelemetryBatch`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List telemetryBatchDescriptor = $convert.base64Decode(
    'Cg5UZWxlbWV0cnlCYXRjaBI6CgZwb2ludHMYASADKAsyIi5yYWRpYW4udGVsZW1ldHJ5LnYxLk'
    'xvY2F0aW9uUG9pbnRSBnBvaW50cxIfCgtpc19iYWNrZmlsbBgCIAEoCFIKaXNCYWNrZmlsbA==');

@$core.Deprecated('Use heartbeatDescriptor instead')
const Heartbeat$json = {
  '1': 'Heartbeat',
  '2': [
    {'1': 'client_time_ms', '3': 1, '4': 1, '5': 3, '10': 'clientTimeMs'},
  ],
};

/// Descriptor for `Heartbeat`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List heartbeatDescriptor = $convert.base64Decode(
    'CglIZWFydGJlYXQSJAoOY2xpZW50X3RpbWVfbXMYASABKANSDGNsaWVudFRpbWVNcw==');

@$core.Deprecated('Use clientMessageDescriptor instead')
const ClientMessage$json = {
  '1': 'ClientMessage',
  '2': [
    {
      '1': 'batch',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.radian.telemetry.v1.TelemetryBatch',
      '9': 0,
      '10': 'batch'
    },
    {
      '1': 'heartbeat',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.radian.telemetry.v1.Heartbeat',
      '9': 0,
      '10': 'heartbeat'
    },
    {
      '1': 'job_status',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.radian.telemetry.v1.JobStatusUpdate',
      '9': 0,
      '10': 'jobStatus'
    },
  ],
  '8': [
    {'1': 'payload'},
  ],
};

/// Descriptor for `ClientMessage`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List clientMessageDescriptor = $convert.base64Decode(
    'Cg1DbGllbnRNZXNzYWdlEjsKBWJhdGNoGAEgASgLMiMucmFkaWFuLnRlbGVtZXRyeS52MS5UZW'
    'xlbWV0cnlCYXRjaEgAUgViYXRjaBI+CgloZWFydGJlYXQYAiABKAsyHi5yYWRpYW4udGVsZW1l'
    'dHJ5LnYxLkhlYXJ0YmVhdEgAUgloZWFydGJlYXQSRQoKam9iX3N0YXR1cxgDIAEoCzIkLnJhZG'
    'lhbi50ZWxlbWV0cnkudjEuSm9iU3RhdHVzVXBkYXRlSABSCWpvYlN0YXR1c0IJCgdwYXlsb2Fk');

@$core.Deprecated('Use batchAckDescriptor instead')
const BatchAck$json = {
  '1': 'BatchAck',
  '2': [
    {'1': 'acked_seq', '3': 1, '4': 1, '5': 3, '10': 'ackedSeq'},
  ],
};

/// Descriptor for `BatchAck`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List batchAckDescriptor = $convert
    .base64Decode('CghCYXRjaEFjaxIbCglhY2tlZF9zZXEYASABKANSCGFja2VkU2Vx');

@$core.Deprecated('Use trackingConfigDescriptor instead')
const TrackingConfig$json = {
  '1': 'TrackingConfig',
  '2': [
    {
      '1': 'moving_interval_ms',
      '3': 1,
      '4': 1,
      '5': 5,
      '10': 'movingIntervalMs'
    },
    {'1': 'distance_filter_m', '3': 2, '4': 1, '5': 5, '10': 'distanceFilterM'},
    {'1': 'max_accuracy_m', '3': 3, '4': 1, '5': 2, '10': 'maxAccuracyM'},
    {
      '1': 'stationary_speed_kmh',
      '3': 4,
      '4': 1,
      '5': 2,
      '10': 'stationarySpeedKmh'
    },
  ],
};

/// Descriptor for `TrackingConfig`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List trackingConfigDescriptor = $convert.base64Decode(
    'Cg5UcmFja2luZ0NvbmZpZxIsChJtb3ZpbmdfaW50ZXJ2YWxfbXMYASABKAVSEG1vdmluZ0ludG'
    'VydmFsTXMSKgoRZGlzdGFuY2VfZmlsdGVyX20YAiABKAVSD2Rpc3RhbmNlRmlsdGVyTRIkCg5t'
    'YXhfYWNjdXJhY3lfbRgDIAEoAlIMbWF4QWNjdXJhY3lNEjAKFHN0YXRpb25hcnlfc3BlZWRfa2'
    '1oGAQgASgCUhJzdGF0aW9uYXJ5U3BlZWRLbWg=');

@$core.Deprecated('Use serverMessageDescriptor instead')
const ServerMessage$json = {
  '1': 'ServerMessage',
  '2': [
    {
      '1': 'ack',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.radian.telemetry.v1.BatchAck',
      '9': 0,
      '10': 'ack'
    },
    {
      '1': 'config',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.radian.telemetry.v1.TrackingConfig',
      '9': 0,
      '10': 'config'
    },
    {
      '1': 'job_offer',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.radian.telemetry.v1.JobOffer',
      '9': 0,
      '10': 'jobOffer'
    },
    {
      '1': 'job_cancelled',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.radian.telemetry.v1.JobCancelled',
      '9': 0,
      '10': 'jobCancelled'
    },
  ],
  '8': [
    {'1': 'payload'},
  ],
};

/// Descriptor for `ServerMessage`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List serverMessageDescriptor = $convert.base64Decode(
    'Cg1TZXJ2ZXJNZXNzYWdlEjEKA2FjaxgBIAEoCzIdLnJhZGlhbi50ZWxlbWV0cnkudjEuQmF0Y2'
    'hBY2tIAFIDYWNrEj0KBmNvbmZpZxgCIAEoCzIjLnJhZGlhbi50ZWxlbWV0cnkudjEuVHJhY2tp'
    'bmdDb25maWdIAFIGY29uZmlnEjwKCWpvYl9vZmZlchgDIAEoCzIdLnJhZGlhbi50ZWxlbWV0cn'
    'kudjEuSm9iT2ZmZXJIAFIIam9iT2ZmZXISSAoNam9iX2NhbmNlbGxlZBgEIAEoCzIhLnJhZGlh'
    'bi50ZWxlbWV0cnkudjEuSm9iQ2FuY2VsbGVkSABSDGpvYkNhbmNlbGxlZEIJCgdwYXlsb2Fk');

@$core.Deprecated('Use geoPointDescriptor instead')
const GeoPoint$json = {
  '1': 'GeoPoint',
  '2': [
    {'1': 'latitude', '3': 1, '4': 1, '5': 1, '10': 'latitude'},
    {'1': 'longitude', '3': 2, '4': 1, '5': 1, '10': 'longitude'},
  ],
};

/// Descriptor for `GeoPoint`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List geoPointDescriptor = $convert.base64Decode(
    'CghHZW9Qb2ludBIaCghsYXRpdHVkZRgBIAEoAVIIbGF0aXR1ZGUSHAoJbG9uZ2l0dWRlGAIgAS'
    'gBUglsb25naXR1ZGU=');

@$core.Deprecated('Use jobOfferDescriptor instead')
const JobOffer$json = {
  '1': 'JobOffer',
  '2': [
    {'1': 'job_id', '3': 1, '4': 1, '5': 9, '10': 'jobId'},
    {
      '1': 'pickup',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.radian.telemetry.v1.GeoPoint',
      '10': 'pickup'
    },
    {'1': 'pickup_address', '3': 3, '4': 1, '5': 9, '10': 'pickupAddress'},
    {
      '1': 'dropoff',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.radian.telemetry.v1.GeoPoint',
      '9': 0,
      '10': 'dropoff',
      '17': true
    },
    {
      '1': 'dropoff_address',
      '3': 5,
      '4': 1,
      '5': 9,
      '9': 1,
      '10': 'dropoffAddress',
      '17': true
    },
    {'1': 'priority', '3': 6, '4': 1, '5': 5, '10': 'priority'},
    {'1': 'eta_seconds', '3': 7, '4': 1, '5': 5, '10': 'etaSeconds'},
    {'1': 'notes', '3': 8, '4': 1, '5': 9, '10': 'notes'},
    {'1': 'expires_at_ms', '3': 9, '4': 1, '5': 3, '10': 'expiresAtMs'},
    {'1': 'number', '3': 10, '4': 1, '5': 3, '10': 'number'},
  ],
  '8': [
    {'1': '_dropoff'},
    {'1': '_dropoff_address'},
  ],
};

/// Descriptor for `JobOffer`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List jobOfferDescriptor = $convert.base64Decode(
    'CghKb2JPZmZlchIVCgZqb2JfaWQYASABKAlSBWpvYklkEjUKBnBpY2t1cBgCIAEoCzIdLnJhZG'
    'lhbi50ZWxlbWV0cnkudjEuR2VvUG9pbnRSBnBpY2t1cBIlCg5waWNrdXBfYWRkcmVzcxgDIAEo'
    'CVINcGlja3VwQWRkcmVzcxI8Cgdkcm9wb2ZmGAQgASgLMh0ucmFkaWFuLnRlbGVtZXRyeS52MS'
    '5HZW9Qb2ludEgAUgdkcm9wb2ZmiAEBEiwKD2Ryb3BvZmZfYWRkcmVzcxgFIAEoCUgBUg5kcm9w'
    'b2ZmQWRkcmVzc4gBARIaCghwcmlvcml0eRgGIAEoBVIIcHJpb3JpdHkSHwoLZXRhX3NlY29uZH'
    'MYByABKAVSCmV0YVNlY29uZHMSFAoFbm90ZXMYCCABKAlSBW5vdGVzEiIKDWV4cGlyZXNfYXRf'
    'bXMYCSABKANSC2V4cGlyZXNBdE1zEhYKBm51bWJlchgKIAEoA1IGbnVtYmVyQgoKCF9kcm9wb2'
    'ZmQhIKEF9kcm9wb2ZmX2FkZHJlc3M=');

@$core.Deprecated('Use jobCancelledDescriptor instead')
const JobCancelled$json = {
  '1': 'JobCancelled',
  '2': [
    {'1': 'job_id', '3': 1, '4': 1, '5': 9, '10': 'jobId'},
    {'1': 'reason', '3': 2, '4': 1, '5': 9, '10': 'reason'},
  ],
};

/// Descriptor for `JobCancelled`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List jobCancelledDescriptor = $convert.base64Decode(
    'CgxKb2JDYW5jZWxsZWQSFQoGam9iX2lkGAEgASgJUgVqb2JJZBIWCgZyZWFzb24YAiABKAlSBn'
    'JlYXNvbg==');

@$core.Deprecated('Use jobStatusUpdateDescriptor instead')
const JobStatusUpdate$json = {
  '1': 'JobStatusUpdate',
  '2': [
    {'1': 'job_id', '3': 1, '4': 1, '5': 9, '10': 'jobId'},
    {
      '1': 'status',
      '3': 2,
      '4': 1,
      '5': 14,
      '6': '.radian.telemetry.v1.JobStatus',
      '10': 'status'
    },
    {'1': 'occurred_at_ms', '3': 3, '4': 1, '5': 3, '10': 'occurredAtMs'},
  ],
};

/// Descriptor for `JobStatusUpdate`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List jobStatusUpdateDescriptor = $convert.base64Decode(
    'Cg9Kb2JTdGF0dXNVcGRhdGUSFQoGam9iX2lkGAEgASgJUgVqb2JJZBI2CgZzdGF0dXMYAiABKA'
    '4yHi5yYWRpYW4udGVsZW1ldHJ5LnYxLkpvYlN0YXR1c1IGc3RhdHVzEiQKDm9jY3VycmVkX2F0'
    'X21zGAMgASgDUgxvY2N1cnJlZEF0TXM=');

@$core.Deprecated('Use boundingBoxDescriptor instead')
const BoundingBox$json = {
  '1': 'BoundingBox',
  '2': [
    {'1': 'min_lon', '3': 1, '4': 1, '5': 1, '10': 'minLon'},
    {'1': 'min_lat', '3': 2, '4': 1, '5': 1, '10': 'minLat'},
    {'1': 'max_lon', '3': 3, '4': 1, '5': 1, '10': 'maxLon'},
    {'1': 'max_lat', '3': 4, '4': 1, '5': 1, '10': 'maxLat'},
  ],
};

/// Descriptor for `BoundingBox`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List boundingBoxDescriptor = $convert.base64Decode(
    'CgtCb3VuZGluZ0JveBIXCgdtaW5fbG9uGAEgASgBUgZtaW5Mb24SFwoHbWluX2xhdBgCIAEoAV'
    'IGbWluTGF0EhcKB21heF9sb24YAyABKAFSBm1heExvbhIXCgdtYXhfbGF0GAQgASgBUgZtYXhM'
    'YXQ=');

@$core.Deprecated('Use dashboardSubscribeDescriptor instead')
const DashboardSubscribe$json = {
  '1': 'DashboardSubscribe',
  '2': [
    {
      '1': 'viewport',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.radian.telemetry.v1.BoundingBox',
      '10': 'viewport'
    },
  ],
};

/// Descriptor for `DashboardSubscribe`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List dashboardSubscribeDescriptor = $convert.base64Decode(
    'ChJEYXNoYm9hcmRTdWJzY3JpYmUSPAoIdmlld3BvcnQYASABKAsyIC5yYWRpYW4udGVsZW1ldH'
    'J5LnYxLkJvdW5kaW5nQm94Ugh2aWV3cG9ydA==');

@$core.Deprecated('Use dashboardClientMessageDescriptor instead')
const DashboardClientMessage$json = {
  '1': 'DashboardClientMessage',
  '2': [
    {
      '1': 'subscribe',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.radian.telemetry.v1.DashboardSubscribe',
      '9': 0,
      '10': 'subscribe'
    },
  ],
  '8': [
    {'1': 'payload'},
  ],
};

/// Descriptor for `DashboardClientMessage`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List dashboardClientMessageDescriptor = $convert.base64Decode(
    'ChZEYXNoYm9hcmRDbGllbnRNZXNzYWdlEkcKCXN1YnNjcmliZRgBIAEoCzInLnJhZGlhbi50ZW'
    'xlbWV0cnkudjEuRGFzaGJvYXJkU3Vic2NyaWJlSABSCXN1YnNjcmliZUIJCgdwYXlsb2Fk');

@$core.Deprecated('Use vehicleDeltaDescriptor instead')
const VehicleDelta$json = {
  '1': 'VehicleDelta',
  '2': [
    {'1': 'vehicle_id', '3': 1, '4': 1, '5': 9, '10': 'vehicleId'},
    {'1': 'latitude', '3': 2, '4': 1, '5': 1, '10': 'latitude'},
    {'1': 'longitude', '3': 3, '4': 1, '5': 1, '10': 'longitude'},
    {'1': 'heading_deg', '3': 4, '4': 1, '5': 2, '10': 'headingDeg'},
    {'1': 'speed_kmh', '3': 5, '4': 1, '5': 2, '10': 'speedKmh'},
    {
      '1': 'status',
      '3': 6,
      '4': 1,
      '5': 14,
      '6': '.radian.telemetry.v1.VehicleStatus',
      '10': 'status'
    },
    {'1': 'recorded_at_ms', '3': 7, '4': 1, '5': 3, '10': 'recordedAtMs'},
  ],
};

/// Descriptor for `VehicleDelta`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List vehicleDeltaDescriptor = $convert.base64Decode(
    'CgxWZWhpY2xlRGVsdGESHQoKdmVoaWNsZV9pZBgBIAEoCVIJdmVoaWNsZUlkEhoKCGxhdGl0dW'
    'RlGAIgASgBUghsYXRpdHVkZRIcCglsb25naXR1ZGUYAyABKAFSCWxvbmdpdHVkZRIfCgtoZWFk'
    'aW5nX2RlZxgEIAEoAlIKaGVhZGluZ0RlZxIbCglzcGVlZF9rbWgYBSABKAJSCHNwZWVkS21oEj'
    'oKBnN0YXR1cxgGIAEoDjIiLnJhZGlhbi50ZWxlbWV0cnkudjEuVmVoaWNsZVN0YXR1c1IGc3Rh'
    'dHVzEiQKDnJlY29yZGVkX2F0X21zGAcgASgDUgxyZWNvcmRlZEF0TXM=');

@$core.Deprecated('Use fleetUpdateDescriptor instead')
const FleetUpdate$json = {
  '1': 'FleetUpdate',
  '2': [
    {
      '1': 'deltas',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.radian.telemetry.v1.VehicleDelta',
      '10': 'deltas'
    },
    {
      '1': 'removed_vehicle_ids',
      '3': 2,
      '4': 3,
      '5': 9,
      '10': 'removedVehicleIds'
    },
    {'1': 'server_time_ms', '3': 3, '4': 1, '5': 3, '10': 'serverTimeMs'},
    {'1': 'is_snapshot', '3': 4, '4': 1, '5': 8, '10': 'isSnapshot'},
  ],
};

/// Descriptor for `FleetUpdate`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List fleetUpdateDescriptor = $convert.base64Decode(
    'CgtGbGVldFVwZGF0ZRI5CgZkZWx0YXMYASADKAsyIS5yYWRpYW4udGVsZW1ldHJ5LnYxLlZlaG'
    'ljbGVEZWx0YVIGZGVsdGFzEi4KE3JlbW92ZWRfdmVoaWNsZV9pZHMYAiADKAlSEXJlbW92ZWRW'
    'ZWhpY2xlSWRzEiQKDnNlcnZlcl90aW1lX21zGAMgASgDUgxzZXJ2ZXJUaW1lTXMSHwoLaXNfc2'
    '5hcHNob3QYBCABKAhSCmlzU25hcHNob3Q=');

@$core.Deprecated('Use jobsChangedDescriptor instead')
const JobsChanged$json = {
  '1': 'JobsChanged',
  '2': [
    {'1': 'job_ids', '3': 1, '4': 3, '5': 9, '10': 'jobIds'},
  ],
};

/// Descriptor for `JobsChanged`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List jobsChangedDescriptor = $convert
    .base64Decode('CgtKb2JzQ2hhbmdlZBIXCgdqb2JfaWRzGAEgAygJUgZqb2JJZHM=');

@$core.Deprecated('Use geofenceEventDescriptor instead')
const GeofenceEvent$json = {
  '1': 'GeofenceEvent',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 3, '10': 'id'},
    {'1': 'geofence_id', '3': 2, '4': 1, '5': 9, '10': 'geofenceId'},
    {'1': 'geofence_name', '3': 3, '4': 1, '5': 9, '10': 'geofenceName'},
    {
      '1': 'kind',
      '3': 4,
      '4': 1,
      '5': 14,
      '6': '.radian.telemetry.v1.GeofenceKind',
      '10': 'kind'
    },
    {'1': 'vehicle_id', '3': 5, '4': 1, '5': 9, '10': 'vehicleId'},
    {'1': 'license_plate', '3': 6, '4': 1, '5': 9, '10': 'licensePlate'},
    {'1': 'entered', '3': 7, '4': 1, '5': 8, '10': 'entered'},
    {'1': 'occurred_at_ms', '3': 8, '4': 1, '5': 3, '10': 'occurredAtMs'},
    {
      '1': 'position',
      '3': 9,
      '4': 1,
      '5': 11,
      '6': '.radian.telemetry.v1.GeoPoint',
      '10': 'position'
    },
  ],
};

/// Descriptor for `GeofenceEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List geofenceEventDescriptor = $convert.base64Decode(
    'Cg1HZW9mZW5jZUV2ZW50Eg4KAmlkGAEgASgDUgJpZBIfCgtnZW9mZW5jZV9pZBgCIAEoCVIKZ2'
    'VvZmVuY2VJZBIjCg1nZW9mZW5jZV9uYW1lGAMgASgJUgxnZW9mZW5jZU5hbWUSNQoEa2luZBgE'
    'IAEoDjIhLnJhZGlhbi50ZWxlbWV0cnkudjEuR2VvZmVuY2VLaW5kUgRraW5kEh0KCnZlaGljbG'
    'VfaWQYBSABKAlSCXZlaGljbGVJZBIjCg1saWNlbnNlX3BsYXRlGAYgASgJUgxsaWNlbnNlUGxh'
    'dGUSGAoHZW50ZXJlZBgHIAEoCFIHZW50ZXJlZBIkCg5vY2N1cnJlZF9hdF9tcxgIIAEoA1IMb2'
    'NjdXJyZWRBdE1zEjkKCHBvc2l0aW9uGAkgASgLMh0ucmFkaWFuLnRlbGVtZXRyeS52MS5HZW9Q'
    'b2ludFIIcG9zaXRpb24=');

@$core.Deprecated('Use geofencesChangedDescriptor instead')
const GeofencesChanged$json = {
  '1': 'GeofencesChanged',
};

/// Descriptor for `GeofencesChanged`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List geofencesChangedDescriptor =
    $convert.base64Decode('ChBHZW9mZW5jZXNDaGFuZ2Vk');

@$core.Deprecated('Use dashboardServerMessageDescriptor instead')
const DashboardServerMessage$json = {
  '1': 'DashboardServerMessage',
  '2': [
    {
      '1': 'fleet_update',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.radian.telemetry.v1.FleetUpdate',
      '9': 0,
      '10': 'fleetUpdate'
    },
    {
      '1': 'jobs_changed',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.radian.telemetry.v1.JobsChanged',
      '9': 0,
      '10': 'jobsChanged'
    },
    {
      '1': 'geofence_event',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.radian.telemetry.v1.GeofenceEvent',
      '9': 0,
      '10': 'geofenceEvent'
    },
    {
      '1': 'geofences_changed',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.radian.telemetry.v1.GeofencesChanged',
      '9': 0,
      '10': 'geofencesChanged'
    },
  ],
  '8': [
    {'1': 'payload'},
  ],
};

/// Descriptor for `DashboardServerMessage`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List dashboardServerMessageDescriptor = $convert.base64Decode(
    'ChZEYXNoYm9hcmRTZXJ2ZXJNZXNzYWdlEkUKDGZsZWV0X3VwZGF0ZRgBIAEoCzIgLnJhZGlhbi'
    '50ZWxlbWV0cnkudjEuRmxlZXRVcGRhdGVIAFILZmxlZXRVcGRhdGUSRQoMam9ic19jaGFuZ2Vk'
    'GAIgASgLMiAucmFkaWFuLnRlbGVtZXRyeS52MS5Kb2JzQ2hhbmdlZEgAUgtqb2JzQ2hhbmdlZB'
    'JLCg5nZW9mZW5jZV9ldmVudBgDIAEoCzIiLnJhZGlhbi50ZWxlbWV0cnkudjEuR2VvZmVuY2VF'
    'dmVudEgAUg1nZW9mZW5jZUV2ZW50ElQKEWdlb2ZlbmNlc19jaGFuZ2VkGAQgASgLMiUucmFkaW'
    'FuLnRlbGVtZXRyeS52MS5HZW9mZW5jZXNDaGFuZ2VkSABSEGdlb2ZlbmNlc0NoYW5nZWRCCQoH'
    'cGF5bG9hZA==');
