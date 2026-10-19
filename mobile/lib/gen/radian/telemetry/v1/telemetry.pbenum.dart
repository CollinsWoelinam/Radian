// This is a generated file - do not edit.
//
// Generated from radian/telemetry/v1/telemetry.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

class JobStatus extends $pb.ProtobufEnum {
  static const JobStatus JOB_STATUS_UNSPECIFIED =
      JobStatus._(0, _omitEnumNames ? '' : 'JOB_STATUS_UNSPECIFIED');
  static const JobStatus JOB_STATUS_PENDING =
      JobStatus._(1, _omitEnumNames ? '' : 'JOB_STATUS_PENDING');
  static const JobStatus JOB_STATUS_ASSIGNED =
      JobStatus._(2, _omitEnumNames ? '' : 'JOB_STATUS_ASSIGNED');
  static const JobStatus JOB_STATUS_EN_ROUTE_PICKUP =
      JobStatus._(3, _omitEnumNames ? '' : 'JOB_STATUS_EN_ROUTE_PICKUP');
  static const JobStatus JOB_STATUS_ON_SITE =
      JobStatus._(4, _omitEnumNames ? '' : 'JOB_STATUS_ON_SITE');
  static const JobStatus JOB_STATUS_EN_ROUTE_DROPOFF =
      JobStatus._(5, _omitEnumNames ? '' : 'JOB_STATUS_EN_ROUTE_DROPOFF');
  static const JobStatus JOB_STATUS_COMPLETED =
      JobStatus._(6, _omitEnumNames ? '' : 'JOB_STATUS_COMPLETED');
  static const JobStatus JOB_STATUS_CANCELLED =
      JobStatus._(7, _omitEnumNames ? '' : 'JOB_STATUS_CANCELLED');

  static const $core.List<JobStatus> values = <JobStatus>[
    JOB_STATUS_UNSPECIFIED,
    JOB_STATUS_PENDING,
    JOB_STATUS_ASSIGNED,
    JOB_STATUS_EN_ROUTE_PICKUP,
    JOB_STATUS_ON_SITE,
    JOB_STATUS_EN_ROUTE_DROPOFF,
    JOB_STATUS_COMPLETED,
    JOB_STATUS_CANCELLED,
  ];

  static final $core.List<JobStatus?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 7);
  static JobStatus? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const JobStatus._(super.value, super.name);
}

class VehicleStatus extends $pb.ProtobufEnum {
  static const VehicleStatus VEHICLE_STATUS_UNSPECIFIED =
      VehicleStatus._(0, _omitEnumNames ? '' : 'VEHICLE_STATUS_UNSPECIFIED');
  static const VehicleStatus VEHICLE_STATUS_OFFLINE =
      VehicleStatus._(1, _omitEnumNames ? '' : 'VEHICLE_STATUS_OFFLINE');
  static const VehicleStatus VEHICLE_STATUS_IDLE =
      VehicleStatus._(2, _omitEnumNames ? '' : 'VEHICLE_STATUS_IDLE');
  static const VehicleStatus VEHICLE_STATUS_EN_ROUTE =
      VehicleStatus._(3, _omitEnumNames ? '' : 'VEHICLE_STATUS_EN_ROUTE');
  static const VehicleStatus VEHICLE_STATUS_ON_JOB =
      VehicleStatus._(4, _omitEnumNames ? '' : 'VEHICLE_STATUS_ON_JOB');

  static const $core.List<VehicleStatus> values = <VehicleStatus>[
    VEHICLE_STATUS_UNSPECIFIED,
    VEHICLE_STATUS_OFFLINE,
    VEHICLE_STATUS_IDLE,
    VEHICLE_STATUS_EN_ROUTE,
    VEHICLE_STATUS_ON_JOB,
  ];

  static final $core.List<VehicleStatus?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 4);
  static VehicleStatus? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const VehicleStatus._(super.value, super.name);
}

class GeofenceKind extends $pb.ProtobufEnum {
  static const GeofenceKind GEOFENCE_KIND_UNSPECIFIED =
      GeofenceKind._(0, _omitEnumNames ? '' : 'GEOFENCE_KIND_UNSPECIFIED');
  static const GeofenceKind GEOFENCE_KIND_DEPOT =
      GeofenceKind._(1, _omitEnumNames ? '' : 'GEOFENCE_KIND_DEPOT');
  static const GeofenceKind GEOFENCE_KIND_SERVICE_AREA =
      GeofenceKind._(2, _omitEnumNames ? '' : 'GEOFENCE_KIND_SERVICE_AREA');
  static const GeofenceKind GEOFENCE_KIND_RESTRICTED =
      GeofenceKind._(3, _omitEnumNames ? '' : 'GEOFENCE_KIND_RESTRICTED');

  static const $core.List<GeofenceKind> values = <GeofenceKind>[
    GEOFENCE_KIND_UNSPECIFIED,
    GEOFENCE_KIND_DEPOT,
    GEOFENCE_KIND_SERVICE_AREA,
    GEOFENCE_KIND_RESTRICTED,
  ];

  static final $core.List<GeofenceKind?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static GeofenceKind? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const GeofenceKind._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
