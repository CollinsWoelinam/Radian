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

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'telemetry.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'telemetry.pbenum.dart';

class LocationPoint extends $pb.GeneratedMessage {
  factory LocationPoint({
    $fixnum.Int64? seq,
    $core.double? latitude,
    $core.double? longitude,
    $fixnum.Int64? recordedAtMs,
    $core.double? speedKmh,
    $core.double? headingDeg,
    $core.double? accuracyM,
    $core.double? altitudeM,
    $core.int? batteryPct,
  }) {
    final result = LocationPoint._();
    if (seq != null) result.seq = seq;
    if (latitude != null) result.latitude = latitude;
    if (longitude != null) result.longitude = longitude;
    if (recordedAtMs != null) result.recordedAtMs = recordedAtMs;
    if (speedKmh != null) result.speedKmh = speedKmh;
    if (headingDeg != null) result.headingDeg = headingDeg;
    if (accuracyM != null) result.accuracyM = accuracyM;
    if (altitudeM != null) result.altitudeM = altitudeM;
    if (batteryPct != null) result.batteryPct = batteryPct;
    return result;
  }

  LocationPoint._();

  factory LocationPoint.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      LocationPoint()..mergeFromBuffer(data, registry);
  factory LocationPoint.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      LocationPoint()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LocationPoint',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'radian.telemetry.v1'),
      createEmptyInstance: LocationPoint.$_createMessage)
    ..aInt64(1, _omitFieldNames ? '' : 'seq')
    ..aD(2, _omitFieldNames ? '' : 'latitude')
    ..aD(3, _omitFieldNames ? '' : 'longitude')
    ..aInt64(4, _omitFieldNames ? '' : 'recordedAtMs')
    ..aD(5, _omitFieldNames ? '' : 'speedKmh', fieldType: $pb.PbFieldType.OF)
    ..aD(6, _omitFieldNames ? '' : 'headingDeg', fieldType: $pb.PbFieldType.OF)
    ..aD(7, _omitFieldNames ? '' : 'accuracyM', fieldType: $pb.PbFieldType.OF)
    ..aD(8, _omitFieldNames ? '' : 'altitudeM', fieldType: $pb.PbFieldType.OF)
    ..aI(9, _omitFieldNames ? '' : 'batteryPct')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LocationPoint clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LocationPoint copyWith(void Function(LocationPoint) updates) =>
      super.copyWith((message) => updates(message as LocationPoint))
          as LocationPoint;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use LocationPoint() / LocationPoint.new instead')
  static LocationPoint create() => LocationPoint._();
  static $pb.GeneratedMessage $_createMessage() => LocationPoint._();
  @$core.override
  LocationPoint createEmptyInstance() => LocationPoint._();
  @$core.pragma('dart2js:noInline')
  static LocationPoint getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LocationPoint>(
          LocationPoint.$_createMessage);
  static LocationPoint? _defaultInstance;

  /// Per-device monotonic counter; lets the server ack and the client prune its buffer.
  @$pb.TagNumber(1)
  $fixnum.Int64 get seq => $_getI64(0);
  @$pb.TagNumber(1)
  set seq($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSeq() => $_has(0);
  @$pb.TagNumber(1)
  void clearSeq() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.double get latitude => $_getN(1);
  @$pb.TagNumber(2)
  set latitude($core.double value) => $_setDouble(1, value);
  @$pb.TagNumber(2)
  $core.bool hasLatitude() => $_has(1);
  @$pb.TagNumber(2)
  void clearLatitude() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.double get longitude => $_getN(2);
  @$pb.TagNumber(3)
  set longitude($core.double value) => $_setDouble(2, value);
  @$pb.TagNumber(3)
  $core.bool hasLongitude() => $_has(2);
  @$pb.TagNumber(3)
  void clearLongitude() => $_clearField(3);

  /// Device GPS time, Unix epoch milliseconds. The server orders by this, not arrival.
  @$pb.TagNumber(4)
  $fixnum.Int64 get recordedAtMs => $_getI64(3);
  @$pb.TagNumber(4)
  set recordedAtMs($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasRecordedAtMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearRecordedAtMs() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.double get speedKmh => $_getN(4);
  @$pb.TagNumber(5)
  set speedKmh($core.double value) => $_setFloat(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSpeedKmh() => $_has(4);
  @$pb.TagNumber(5)
  void clearSpeedKmh() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.double get headingDeg => $_getN(5);
  @$pb.TagNumber(6)
  set headingDeg($core.double value) => $_setFloat(5, value);
  @$pb.TagNumber(6)
  $core.bool hasHeadingDeg() => $_has(5);
  @$pb.TagNumber(6)
  void clearHeadingDeg() => $_clearField(6);

  /// Horizontal accuracy radius in meters. Fixes worse than the server threshold are dropped.
  @$pb.TagNumber(7)
  $core.double get accuracyM => $_getN(6);
  @$pb.TagNumber(7)
  set accuracyM($core.double value) => $_setFloat(6, value);
  @$pb.TagNumber(7)
  $core.bool hasAccuracyM() => $_has(6);
  @$pb.TagNumber(7)
  void clearAccuracyM() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.double get altitudeM => $_getN(7);
  @$pb.TagNumber(8)
  set altitudeM($core.double value) => $_setFloat(7, value);
  @$pb.TagNumber(8)
  $core.bool hasAltitudeM() => $_has(7);
  @$pb.TagNumber(8)
  void clearAltitudeM() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.int get batteryPct => $_getIZ(8);
  @$pb.TagNumber(9)
  set batteryPct($core.int value) => $_setSignedInt32(8, value);
  @$pb.TagNumber(9)
  $core.bool hasBatteryPct() => $_has(8);
  @$pb.TagNumber(9)
  void clearBatteryPct() => $_clearField(9);
}

class TelemetryBatch extends $pb.GeneratedMessage {
  factory TelemetryBatch({
    $core.Iterable<LocationPoint>? points,
    $core.bool? isBackfill,
  }) {
    final result = TelemetryBatch._();
    if (points != null) result.points.addAll(points);
    if (isBackfill != null) result.isBackfill = isBackfill;
    return result;
  }

  TelemetryBatch._();

  factory TelemetryBatch.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      TelemetryBatch()..mergeFromBuffer(data, registry);
  factory TelemetryBatch.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      TelemetryBatch()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TelemetryBatch',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'radian.telemetry.v1'),
      createEmptyInstance: TelemetryBatch.$_createMessage)
    ..pPM<LocationPoint>(1, _omitFieldNames ? '' : 'points',
        subBuilder: LocationPoint.$_createMessage)
    ..aOB(2, _omitFieldNames ? '' : 'isBackfill')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TelemetryBatch clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TelemetryBatch copyWith(void Function(TelemetryBatch) updates) =>
      super.copyWith((message) => updates(message as TelemetryBatch))
          as TelemetryBatch;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use TelemetryBatch() / TelemetryBatch.new instead')
  static TelemetryBatch create() => TelemetryBatch._();
  static $pb.GeneratedMessage $_createMessage() => TelemetryBatch._();
  @$core.override
  TelemetryBatch createEmptyInstance() => TelemetryBatch._();
  @$core.pragma('dart2js:noInline')
  static TelemetryBatch getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TelemetryBatch>(
          TelemetryBatch.$_createMessage);
  static TelemetryBatch? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<LocationPoint> get points => $_getList(0);

  /// True when flushing the offline SQLite buffer. Backfill is persisted but
  /// not broadcast as "live" unless it is newer than the last known fix.
  @$pb.TagNumber(2)
  $core.bool get isBackfill => $_getBF(1);
  @$pb.TagNumber(2)
  set isBackfill($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasIsBackfill() => $_has(1);
  @$pb.TagNumber(2)
  void clearIsBackfill() => $_clearField(2);
}

class Heartbeat extends $pb.GeneratedMessage {
  factory Heartbeat({
    $fixnum.Int64? clientTimeMs,
  }) {
    final result = Heartbeat._();
    if (clientTimeMs != null) result.clientTimeMs = clientTimeMs;
    return result;
  }

  Heartbeat._();

  factory Heartbeat.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Heartbeat()..mergeFromBuffer(data, registry);
  factory Heartbeat.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Heartbeat()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Heartbeat',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'radian.telemetry.v1'),
      createEmptyInstance: Heartbeat.$_createMessage)
    ..aInt64(1, _omitFieldNames ? '' : 'clientTimeMs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Heartbeat clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Heartbeat copyWith(void Function(Heartbeat) updates) =>
      super.copyWith((message) => updates(message as Heartbeat)) as Heartbeat;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Heartbeat() / Heartbeat.new instead')
  static Heartbeat create() => Heartbeat._();
  static $pb.GeneratedMessage $_createMessage() => Heartbeat._();
  @$core.override
  Heartbeat createEmptyInstance() => Heartbeat._();
  @$core.pragma('dart2js:noInline')
  static Heartbeat getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Heartbeat>(Heartbeat.$_createMessage);
  static Heartbeat? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get clientTimeMs => $_getI64(0);
  @$pb.TagNumber(1)
  set clientTimeMs($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasClientTimeMs() => $_has(0);
  @$pb.TagNumber(1)
  void clearClientTimeMs() => $_clearField(1);
}

enum ClientMessage_Payload { batch, heartbeat, jobStatus, notSet }

class ClientMessage extends $pb.GeneratedMessage {
  factory ClientMessage({
    TelemetryBatch? batch,
    Heartbeat? heartbeat,
    JobStatusUpdate? jobStatus,
  }) {
    final result = ClientMessage._();
    if (batch != null) result.batch = batch;
    if (heartbeat != null) result.heartbeat = heartbeat;
    if (jobStatus != null) result.jobStatus = jobStatus;
    return result;
  }

  ClientMessage._();

  factory ClientMessage.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ClientMessage()..mergeFromBuffer(data, registry);
  factory ClientMessage.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ClientMessage()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, ClientMessage_Payload>
      _ClientMessage_PayloadByTag = {
    1: ClientMessage_Payload.batch,
    2: ClientMessage_Payload.heartbeat,
    3: ClientMessage_Payload.jobStatus,
    0: ClientMessage_Payload.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ClientMessage',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'radian.telemetry.v1'),
      createEmptyInstance: ClientMessage.$_createMessage)
    ..oo(0, [1, 2, 3])
    ..aOM<TelemetryBatch>(1, _omitFieldNames ? '' : 'batch',
        subBuilder: TelemetryBatch.$_createMessage)
    ..aOM<Heartbeat>(2, _omitFieldNames ? '' : 'heartbeat',
        subBuilder: Heartbeat.$_createMessage)
    ..aOM<JobStatusUpdate>(3, _omitFieldNames ? '' : 'jobStatus',
        subBuilder: JobStatusUpdate.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ClientMessage clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ClientMessage copyWith(void Function(ClientMessage) updates) =>
      super.copyWith((message) => updates(message as ClientMessage))
          as ClientMessage;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ClientMessage() / ClientMessage.new instead')
  static ClientMessage create() => ClientMessage._();
  static $pb.GeneratedMessage $_createMessage() => ClientMessage._();
  @$core.override
  ClientMessage createEmptyInstance() => ClientMessage._();
  @$core.pragma('dart2js:noInline')
  static ClientMessage getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ClientMessage>(
          ClientMessage.$_createMessage);
  static ClientMessage? _defaultInstance;

  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  ClientMessage_Payload whichPayload() =>
      _ClientMessage_PayloadByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  void clearPayload() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  TelemetryBatch get batch => $_getN(0);
  @$pb.TagNumber(1)
  set batch(TelemetryBatch value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasBatch() => $_has(0);
  @$pb.TagNumber(1)
  void clearBatch() => $_clearField(1);
  @$pb.TagNumber(1)
  TelemetryBatch ensureBatch() => $_ensure(0);

  @$pb.TagNumber(2)
  Heartbeat get heartbeat => $_getN(1);
  @$pb.TagNumber(2)
  set heartbeat(Heartbeat value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasHeartbeat() => $_has(1);
  @$pb.TagNumber(2)
  void clearHeartbeat() => $_clearField(2);
  @$pb.TagNumber(2)
  Heartbeat ensureHeartbeat() => $_ensure(1);

  @$pb.TagNumber(3)
  JobStatusUpdate get jobStatus => $_getN(2);
  @$pb.TagNumber(3)
  set jobStatus(JobStatusUpdate value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasJobStatus() => $_has(2);
  @$pb.TagNumber(3)
  void clearJobStatus() => $_clearField(3);
  @$pb.TagNumber(3)
  JobStatusUpdate ensureJobStatus() => $_ensure(2);
}

/// Acknowledges every point with seq <= acked_seq as durably queued.
class BatchAck extends $pb.GeneratedMessage {
  factory BatchAck({
    $fixnum.Int64? ackedSeq,
  }) {
    final result = BatchAck._();
    if (ackedSeq != null) result.ackedSeq = ackedSeq;
    return result;
  }

  BatchAck._();

  factory BatchAck.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      BatchAck()..mergeFromBuffer(data, registry);
  factory BatchAck.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      BatchAck()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'BatchAck',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'radian.telemetry.v1'),
      createEmptyInstance: BatchAck.$_createMessage)
    ..aInt64(1, _omitFieldNames ? '' : 'ackedSeq')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BatchAck clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BatchAck copyWith(void Function(BatchAck) updates) =>
      super.copyWith((message) => updates(message as BatchAck)) as BatchAck;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use BatchAck() / BatchAck.new instead')
  static BatchAck create() => BatchAck._();
  static $pb.GeneratedMessage $_createMessage() => BatchAck._();
  @$core.override
  BatchAck createEmptyInstance() => BatchAck._();
  @$core.pragma('dart2js:noInline')
  static BatchAck getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<BatchAck>(BatchAck.$_createMessage);
  static BatchAck? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get ackedSeq => $_getI64(0);
  @$pb.TagNumber(1)
  set ackedSeq($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAckedSeq() => $_has(0);
  @$pb.TagNumber(1)
  void clearAckedSeq() => $_clearField(1);
}

/// Server-controlled tracking profile so the fleet's battery/precision tradeoff
/// can be tuned without shipping an app update.
class TrackingConfig extends $pb.GeneratedMessage {
  factory TrackingConfig({
    $core.int? movingIntervalMs,
    $core.int? distanceFilterM,
    $core.double? maxAccuracyM,
    $core.double? stationarySpeedKmh,
  }) {
    final result = TrackingConfig._();
    if (movingIntervalMs != null) result.movingIntervalMs = movingIntervalMs;
    if (distanceFilterM != null) result.distanceFilterM = distanceFilterM;
    if (maxAccuracyM != null) result.maxAccuracyM = maxAccuracyM;
    if (stationarySpeedKmh != null)
      result.stationarySpeedKmh = stationarySpeedKmh;
    return result;
  }

  TrackingConfig._();

  factory TrackingConfig.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      TrackingConfig()..mergeFromBuffer(data, registry);
  factory TrackingConfig.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      TrackingConfig()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TrackingConfig',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'radian.telemetry.v1'),
      createEmptyInstance: TrackingConfig.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'movingIntervalMs')
    ..aI(2, _omitFieldNames ? '' : 'distanceFilterM')
    ..aD(3, _omitFieldNames ? '' : 'maxAccuracyM',
        fieldType: $pb.PbFieldType.OF)
    ..aD(4, _omitFieldNames ? '' : 'stationarySpeedKmh',
        fieldType: $pb.PbFieldType.OF)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TrackingConfig clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TrackingConfig copyWith(void Function(TrackingConfig) updates) =>
      super.copyWith((message) => updates(message as TrackingConfig))
          as TrackingConfig;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use TrackingConfig() / TrackingConfig.new instead')
  static TrackingConfig create() => TrackingConfig._();
  static $pb.GeneratedMessage $_createMessage() => TrackingConfig._();
  @$core.override
  TrackingConfig createEmptyInstance() => TrackingConfig._();
  @$core.pragma('dart2js:noInline')
  static TrackingConfig getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TrackingConfig>(
          TrackingConfig.$_createMessage);
  static TrackingConfig? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get movingIntervalMs => $_getIZ(0);
  @$pb.TagNumber(1)
  set movingIntervalMs($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMovingIntervalMs() => $_has(0);
  @$pb.TagNumber(1)
  void clearMovingIntervalMs() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get distanceFilterM => $_getIZ(1);
  @$pb.TagNumber(2)
  set distanceFilterM($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDistanceFilterM() => $_has(1);
  @$pb.TagNumber(2)
  void clearDistanceFilterM() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.double get maxAccuracyM => $_getN(2);
  @$pb.TagNumber(3)
  set maxAccuracyM($core.double value) => $_setFloat(2, value);
  @$pb.TagNumber(3)
  $core.bool hasMaxAccuracyM() => $_has(2);
  @$pb.TagNumber(3)
  void clearMaxAccuracyM() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.double get stationarySpeedKmh => $_getN(3);
  @$pb.TagNumber(4)
  set stationarySpeedKmh($core.double value) => $_setFloat(3, value);
  @$pb.TagNumber(4)
  $core.bool hasStationarySpeedKmh() => $_has(3);
  @$pb.TagNumber(4)
  void clearStationarySpeedKmh() => $_clearField(4);
}

enum ServerMessage_Payload { ack, config, jobOffer, jobCancelled, notSet }

class ServerMessage extends $pb.GeneratedMessage {
  factory ServerMessage({
    BatchAck? ack,
    TrackingConfig? config,
    JobOffer? jobOffer,
    JobCancelled? jobCancelled,
  }) {
    final result = ServerMessage._();
    if (ack != null) result.ack = ack;
    if (config != null) result.config = config;
    if (jobOffer != null) result.jobOffer = jobOffer;
    if (jobCancelled != null) result.jobCancelled = jobCancelled;
    return result;
  }

  ServerMessage._();

  factory ServerMessage.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ServerMessage()..mergeFromBuffer(data, registry);
  factory ServerMessage.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ServerMessage()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, ServerMessage_Payload>
      _ServerMessage_PayloadByTag = {
    1: ServerMessage_Payload.ack,
    2: ServerMessage_Payload.config,
    3: ServerMessage_Payload.jobOffer,
    4: ServerMessage_Payload.jobCancelled,
    0: ServerMessage_Payload.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ServerMessage',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'radian.telemetry.v1'),
      createEmptyInstance: ServerMessage.$_createMessage)
    ..oo(0, [1, 2, 3, 4])
    ..aOM<BatchAck>(1, _omitFieldNames ? '' : 'ack',
        subBuilder: BatchAck.$_createMessage)
    ..aOM<TrackingConfig>(2, _omitFieldNames ? '' : 'config',
        subBuilder: TrackingConfig.$_createMessage)
    ..aOM<JobOffer>(3, _omitFieldNames ? '' : 'jobOffer',
        subBuilder: JobOffer.$_createMessage)
    ..aOM<JobCancelled>(4, _omitFieldNames ? '' : 'jobCancelled',
        subBuilder: JobCancelled.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ServerMessage clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ServerMessage copyWith(void Function(ServerMessage) updates) =>
      super.copyWith((message) => updates(message as ServerMessage))
          as ServerMessage;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ServerMessage() / ServerMessage.new instead')
  static ServerMessage create() => ServerMessage._();
  static $pb.GeneratedMessage $_createMessage() => ServerMessage._();
  @$core.override
  ServerMessage createEmptyInstance() => ServerMessage._();
  @$core.pragma('dart2js:noInline')
  static ServerMessage getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ServerMessage>(
          ServerMessage.$_createMessage);
  static ServerMessage? _defaultInstance;

  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  ServerMessage_Payload whichPayload() =>
      _ServerMessage_PayloadByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  void clearPayload() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  BatchAck get ack => $_getN(0);
  @$pb.TagNumber(1)
  set ack(BatchAck value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasAck() => $_has(0);
  @$pb.TagNumber(1)
  void clearAck() => $_clearField(1);
  @$pb.TagNumber(1)
  BatchAck ensureAck() => $_ensure(0);

  @$pb.TagNumber(2)
  TrackingConfig get config => $_getN(1);
  @$pb.TagNumber(2)
  set config(TrackingConfig value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasConfig() => $_has(1);
  @$pb.TagNumber(2)
  void clearConfig() => $_clearField(2);
  @$pb.TagNumber(2)
  TrackingConfig ensureConfig() => $_ensure(1);

  @$pb.TagNumber(3)
  JobOffer get jobOffer => $_getN(2);
  @$pb.TagNumber(3)
  set jobOffer(JobOffer value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasJobOffer() => $_has(2);
  @$pb.TagNumber(3)
  void clearJobOffer() => $_clearField(3);
  @$pb.TagNumber(3)
  JobOffer ensureJobOffer() => $_ensure(2);

  @$pb.TagNumber(4)
  JobCancelled get jobCancelled => $_getN(3);
  @$pb.TagNumber(4)
  set jobCancelled(JobCancelled value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasJobCancelled() => $_has(3);
  @$pb.TagNumber(4)
  void clearJobCancelled() => $_clearField(4);
  @$pb.TagNumber(4)
  JobCancelled ensureJobCancelled() => $_ensure(3);
}

class GeoPoint extends $pb.GeneratedMessage {
  factory GeoPoint({
    $core.double? latitude,
    $core.double? longitude,
  }) {
    final result = GeoPoint._();
    if (latitude != null) result.latitude = latitude;
    if (longitude != null) result.longitude = longitude;
    return result;
  }

  GeoPoint._();

  factory GeoPoint.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GeoPoint()..mergeFromBuffer(data, registry);
  factory GeoPoint.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GeoPoint()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GeoPoint',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'radian.telemetry.v1'),
      createEmptyInstance: GeoPoint.$_createMessage)
    ..aD(1, _omitFieldNames ? '' : 'latitude')
    ..aD(2, _omitFieldNames ? '' : 'longitude')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GeoPoint clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GeoPoint copyWith(void Function(GeoPoint) updates) =>
      super.copyWith((message) => updates(message as GeoPoint)) as GeoPoint;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use GeoPoint() / GeoPoint.new instead')
  static GeoPoint create() => GeoPoint._();
  static $pb.GeneratedMessage $_createMessage() => GeoPoint._();
  @$core.override
  GeoPoint createEmptyInstance() => GeoPoint._();
  @$core.pragma('dart2js:noInline')
  static GeoPoint getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GeoPoint>(GeoPoint.$_createMessage);
  static GeoPoint? _defaultInstance;

  @$pb.TagNumber(1)
  $core.double get latitude => $_getN(0);
  @$pb.TagNumber(1)
  set latitude($core.double value) => $_setDouble(0, value);
  @$pb.TagNumber(1)
  $core.bool hasLatitude() => $_has(0);
  @$pb.TagNumber(1)
  void clearLatitude() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.double get longitude => $_getN(1);
  @$pb.TagNumber(2)
  set longitude($core.double value) => $_setDouble(1, value);
  @$pb.TagNumber(2)
  $core.bool hasLongitude() => $_has(1);
  @$pb.TagNumber(2)
  void clearLongitude() => $_clearField(2);
}

class JobOffer extends $pb.GeneratedMessage {
  factory JobOffer({
    $core.String? jobId,
    GeoPoint? pickup,
    $core.String? pickupAddress,
    GeoPoint? dropoff,
    $core.String? dropoffAddress,
    $core.int? priority,
    $core.int? etaSeconds,
    $core.String? notes,
    $fixnum.Int64? expiresAtMs,
    $fixnum.Int64? number,
  }) {
    final result = JobOffer._();
    if (jobId != null) result.jobId = jobId;
    if (pickup != null) result.pickup = pickup;
    if (pickupAddress != null) result.pickupAddress = pickupAddress;
    if (dropoff != null) result.dropoff = dropoff;
    if (dropoffAddress != null) result.dropoffAddress = dropoffAddress;
    if (priority != null) result.priority = priority;
    if (etaSeconds != null) result.etaSeconds = etaSeconds;
    if (notes != null) result.notes = notes;
    if (expiresAtMs != null) result.expiresAtMs = expiresAtMs;
    if (number != null) result.number = number;
    return result;
  }

  JobOffer._();

  factory JobOffer.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      JobOffer()..mergeFromBuffer(data, registry);
  factory JobOffer.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      JobOffer()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'JobOffer',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'radian.telemetry.v1'),
      createEmptyInstance: JobOffer.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'jobId')
    ..aOM<GeoPoint>(2, _omitFieldNames ? '' : 'pickup',
        subBuilder: GeoPoint.$_createMessage)
    ..aOS(3, _omitFieldNames ? '' : 'pickupAddress')
    ..aOM<GeoPoint>(4, _omitFieldNames ? '' : 'dropoff',
        subBuilder: GeoPoint.$_createMessage)
    ..aOS(5, _omitFieldNames ? '' : 'dropoffAddress')
    ..aI(6, _omitFieldNames ? '' : 'priority')
    ..aI(7, _omitFieldNames ? '' : 'etaSeconds')
    ..aOS(8, _omitFieldNames ? '' : 'notes')
    ..aInt64(9, _omitFieldNames ? '' : 'expiresAtMs')
    ..aInt64(10, _omitFieldNames ? '' : 'number')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  JobOffer clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  JobOffer copyWith(void Function(JobOffer) updates) =>
      super.copyWith((message) => updates(message as JobOffer)) as JobOffer;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use JobOffer() / JobOffer.new instead')
  static JobOffer create() => JobOffer._();
  static $pb.GeneratedMessage $_createMessage() => JobOffer._();
  @$core.override
  JobOffer createEmptyInstance() => JobOffer._();
  @$core.pragma('dart2js:noInline')
  static JobOffer getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<JobOffer>(JobOffer.$_createMessage);
  static JobOffer? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get jobId => $_getSZ(0);
  @$pb.TagNumber(1)
  set jobId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasJobId() => $_has(0);
  @$pb.TagNumber(1)
  void clearJobId() => $_clearField(1);

  @$pb.TagNumber(2)
  GeoPoint get pickup => $_getN(1);
  @$pb.TagNumber(2)
  set pickup(GeoPoint value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasPickup() => $_has(1);
  @$pb.TagNumber(2)
  void clearPickup() => $_clearField(2);
  @$pb.TagNumber(2)
  GeoPoint ensurePickup() => $_ensure(1);

  @$pb.TagNumber(3)
  $core.String get pickupAddress => $_getSZ(2);
  @$pb.TagNumber(3)
  set pickupAddress($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasPickupAddress() => $_has(2);
  @$pb.TagNumber(3)
  void clearPickupAddress() => $_clearField(3);

  @$pb.TagNumber(4)
  GeoPoint get dropoff => $_getN(3);
  @$pb.TagNumber(4)
  set dropoff(GeoPoint value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasDropoff() => $_has(3);
  @$pb.TagNumber(4)
  void clearDropoff() => $_clearField(4);
  @$pb.TagNumber(4)
  GeoPoint ensureDropoff() => $_ensure(3);

  @$pb.TagNumber(5)
  $core.String get dropoffAddress => $_getSZ(4);
  @$pb.TagNumber(5)
  set dropoffAddress($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasDropoffAddress() => $_has(4);
  @$pb.TagNumber(5)
  void clearDropoffAddress() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get priority => $_getIZ(5);
  @$pb.TagNumber(6)
  set priority($core.int value) => $_setSignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasPriority() => $_has(5);
  @$pb.TagNumber(6)
  void clearPriority() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.int get etaSeconds => $_getIZ(6);
  @$pb.TagNumber(7)
  set etaSeconds($core.int value) => $_setSignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasEtaSeconds() => $_has(6);
  @$pb.TagNumber(7)
  void clearEtaSeconds() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get notes => $_getSZ(7);
  @$pb.TagNumber(8)
  set notes($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasNotes() => $_has(7);
  @$pb.TagNumber(8)
  void clearNotes() => $_clearField(8);

  /// The offer lapses (and goes to the next driver) at this time, Unix ms.
  @$pb.TagNumber(9)
  $fixnum.Int64 get expiresAtMs => $_getI64(8);
  @$pb.TagNumber(9)
  set expiresAtMs($fixnum.Int64 value) => $_setInt64(8, value);
  @$pb.TagNumber(9)
  $core.bool hasExpiresAtMs() => $_has(8);
  @$pb.TagNumber(9)
  void clearExpiresAtMs() => $_clearField(9);

  /// Human-friendly job number shown as "#1042".
  @$pb.TagNumber(10)
  $fixnum.Int64 get number => $_getI64(9);
  @$pb.TagNumber(10)
  set number($fixnum.Int64 value) => $_setInt64(9, value);
  @$pb.TagNumber(10)
  $core.bool hasNumber() => $_has(9);
  @$pb.TagNumber(10)
  void clearNumber() => $_clearField(10);
}

/// The dispatcher cancelled a job this vehicle was offered or working on.
class JobCancelled extends $pb.GeneratedMessage {
  factory JobCancelled({
    $core.String? jobId,
    $core.String? reason,
  }) {
    final result = JobCancelled._();
    if (jobId != null) result.jobId = jobId;
    if (reason != null) result.reason = reason;
    return result;
  }

  JobCancelled._();

  factory JobCancelled.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      JobCancelled()..mergeFromBuffer(data, registry);
  factory JobCancelled.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      JobCancelled()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'JobCancelled',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'radian.telemetry.v1'),
      createEmptyInstance: JobCancelled.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'jobId')
    ..aOS(2, _omitFieldNames ? '' : 'reason')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  JobCancelled clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  JobCancelled copyWith(void Function(JobCancelled) updates) =>
      super.copyWith((message) => updates(message as JobCancelled))
          as JobCancelled;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use JobCancelled() / JobCancelled.new instead')
  static JobCancelled create() => JobCancelled._();
  static $pb.GeneratedMessage $_createMessage() => JobCancelled._();
  @$core.override
  JobCancelled createEmptyInstance() => JobCancelled._();
  @$core.pragma('dart2js:noInline')
  static JobCancelled getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<JobCancelled>(
          JobCancelled.$_createMessage);
  static JobCancelled? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get jobId => $_getSZ(0);
  @$pb.TagNumber(1)
  set jobId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasJobId() => $_has(0);
  @$pb.TagNumber(1)
  void clearJobId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get reason => $_getSZ(1);
  @$pb.TagNumber(2)
  set reason($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasReason() => $_has(1);
  @$pb.TagNumber(2)
  void clearReason() => $_clearField(2);
}

class JobStatusUpdate extends $pb.GeneratedMessage {
  factory JobStatusUpdate({
    $core.String? jobId,
    JobStatus? status,
    $fixnum.Int64? occurredAtMs,
  }) {
    final result = JobStatusUpdate._();
    if (jobId != null) result.jobId = jobId;
    if (status != null) result.status = status;
    if (occurredAtMs != null) result.occurredAtMs = occurredAtMs;
    return result;
  }

  JobStatusUpdate._();

  factory JobStatusUpdate.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      JobStatusUpdate()..mergeFromBuffer(data, registry);
  factory JobStatusUpdate.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      JobStatusUpdate()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'JobStatusUpdate',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'radian.telemetry.v1'),
      createEmptyInstance: JobStatusUpdate.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'jobId')
    ..aE<JobStatus>(2, _omitFieldNames ? '' : 'status',
        enumValues: JobStatus.values)
    ..aInt64(3, _omitFieldNames ? '' : 'occurredAtMs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  JobStatusUpdate clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  JobStatusUpdate copyWith(void Function(JobStatusUpdate) updates) =>
      super.copyWith((message) => updates(message as JobStatusUpdate))
          as JobStatusUpdate;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use JobStatusUpdate() / JobStatusUpdate.new instead')
  static JobStatusUpdate create() => JobStatusUpdate._();
  static $pb.GeneratedMessage $_createMessage() => JobStatusUpdate._();
  @$core.override
  JobStatusUpdate createEmptyInstance() => JobStatusUpdate._();
  @$core.pragma('dart2js:noInline')
  static JobStatusUpdate getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<JobStatusUpdate>(
          JobStatusUpdate.$_createMessage);
  static JobStatusUpdate? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get jobId => $_getSZ(0);
  @$pb.TagNumber(1)
  set jobId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasJobId() => $_has(0);
  @$pb.TagNumber(1)
  void clearJobId() => $_clearField(1);

  @$pb.TagNumber(2)
  JobStatus get status => $_getN(1);
  @$pb.TagNumber(2)
  set status(JobStatus value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasStatus() => $_has(1);
  @$pb.TagNumber(2)
  void clearStatus() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get occurredAtMs => $_getI64(2);
  @$pb.TagNumber(3)
  set occurredAtMs($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasOccurredAtMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearOccurredAtMs() => $_clearField(3);
}

class BoundingBox extends $pb.GeneratedMessage {
  factory BoundingBox({
    $core.double? minLon,
    $core.double? minLat,
    $core.double? maxLon,
    $core.double? maxLat,
  }) {
    final result = BoundingBox._();
    if (minLon != null) result.minLon = minLon;
    if (minLat != null) result.minLat = minLat;
    if (maxLon != null) result.maxLon = maxLon;
    if (maxLat != null) result.maxLat = maxLat;
    return result;
  }

  BoundingBox._();

  factory BoundingBox.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      BoundingBox()..mergeFromBuffer(data, registry);
  factory BoundingBox.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      BoundingBox()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'BoundingBox',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'radian.telemetry.v1'),
      createEmptyInstance: BoundingBox.$_createMessage)
    ..aD(1, _omitFieldNames ? '' : 'minLon')
    ..aD(2, _omitFieldNames ? '' : 'minLat')
    ..aD(3, _omitFieldNames ? '' : 'maxLon')
    ..aD(4, _omitFieldNames ? '' : 'maxLat')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BoundingBox clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BoundingBox copyWith(void Function(BoundingBox) updates) =>
      super.copyWith((message) => updates(message as BoundingBox))
          as BoundingBox;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use BoundingBox() / BoundingBox.new instead')
  static BoundingBox create() => BoundingBox._();
  static $pb.GeneratedMessage $_createMessage() => BoundingBox._();
  @$core.override
  BoundingBox createEmptyInstance() => BoundingBox._();
  @$core.pragma('dart2js:noInline')
  static BoundingBox getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<BoundingBox>(
          BoundingBox.$_createMessage);
  static BoundingBox? _defaultInstance;

  @$pb.TagNumber(1)
  $core.double get minLon => $_getN(0);
  @$pb.TagNumber(1)
  set minLon($core.double value) => $_setDouble(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMinLon() => $_has(0);
  @$pb.TagNumber(1)
  void clearMinLon() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.double get minLat => $_getN(1);
  @$pb.TagNumber(2)
  set minLat($core.double value) => $_setDouble(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMinLat() => $_has(1);
  @$pb.TagNumber(2)
  void clearMinLat() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.double get maxLon => $_getN(2);
  @$pb.TagNumber(3)
  set maxLon($core.double value) => $_setDouble(2, value);
  @$pb.TagNumber(3)
  $core.bool hasMaxLon() => $_has(2);
  @$pb.TagNumber(3)
  void clearMaxLon() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.double get maxLat => $_getN(3);
  @$pb.TagNumber(4)
  set maxLat($core.double value) => $_setDouble(3, value);
  @$pb.TagNumber(4)
  $core.bool hasMaxLat() => $_has(3);
  @$pb.TagNumber(4)
  void clearMaxLat() => $_clearField(4);
}

/// Sent whenever the dashboard viewport changes; the server only streams
/// vehicles inside the box (plus a margin).
class DashboardSubscribe extends $pb.GeneratedMessage {
  factory DashboardSubscribe({
    BoundingBox? viewport,
  }) {
    final result = DashboardSubscribe._();
    if (viewport != null) result.viewport = viewport;
    return result;
  }

  DashboardSubscribe._();

  factory DashboardSubscribe.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DashboardSubscribe()..mergeFromBuffer(data, registry);
  factory DashboardSubscribe.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DashboardSubscribe()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DashboardSubscribe',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'radian.telemetry.v1'),
      createEmptyInstance: DashboardSubscribe.$_createMessage)
    ..aOM<BoundingBox>(1, _omitFieldNames ? '' : 'viewport',
        subBuilder: BoundingBox.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DashboardSubscribe clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DashboardSubscribe copyWith(void Function(DashboardSubscribe) updates) =>
      super.copyWith((message) => updates(message as DashboardSubscribe))
          as DashboardSubscribe;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use DashboardSubscribe() / DashboardSubscribe.new instead')
  static DashboardSubscribe create() => DashboardSubscribe._();
  static $pb.GeneratedMessage $_createMessage() => DashboardSubscribe._();
  @$core.override
  DashboardSubscribe createEmptyInstance() => DashboardSubscribe._();
  @$core.pragma('dart2js:noInline')
  static DashboardSubscribe getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DashboardSubscribe>(
          DashboardSubscribe.$_createMessage);
  static DashboardSubscribe? _defaultInstance;

  @$pb.TagNumber(1)
  BoundingBox get viewport => $_getN(0);
  @$pb.TagNumber(1)
  set viewport(BoundingBox value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasViewport() => $_has(0);
  @$pb.TagNumber(1)
  void clearViewport() => $_clearField(1);
  @$pb.TagNumber(1)
  BoundingBox ensureViewport() => $_ensure(0);
}

enum DashboardClientMessage_Payload { subscribe, notSet }

class DashboardClientMessage extends $pb.GeneratedMessage {
  factory DashboardClientMessage({
    DashboardSubscribe? subscribe,
  }) {
    final result = DashboardClientMessage._();
    if (subscribe != null) result.subscribe = subscribe;
    return result;
  }

  DashboardClientMessage._();

  factory DashboardClientMessage.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DashboardClientMessage()..mergeFromBuffer(data, registry);
  factory DashboardClientMessage.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DashboardClientMessage()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, DashboardClientMessage_Payload>
      _DashboardClientMessage_PayloadByTag = {
    1: DashboardClientMessage_Payload.subscribe,
    0: DashboardClientMessage_Payload.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DashboardClientMessage',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'radian.telemetry.v1'),
      createEmptyInstance: DashboardClientMessage.$_createMessage)
    ..oo(0, [1])
    ..aOM<DashboardSubscribe>(1, _omitFieldNames ? '' : 'subscribe',
        subBuilder: DashboardSubscribe.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DashboardClientMessage clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DashboardClientMessage copyWith(
          void Function(DashboardClientMessage) updates) =>
      super.copyWith((message) => updates(message as DashboardClientMessage))
          as DashboardClientMessage;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use DashboardClientMessage() / DashboardClientMessage.new instead')
  static DashboardClientMessage create() => DashboardClientMessage._();
  static $pb.GeneratedMessage $_createMessage() => DashboardClientMessage._();
  @$core.override
  DashboardClientMessage createEmptyInstance() => DashboardClientMessage._();
  @$core.pragma('dart2js:noInline')
  static DashboardClientMessage getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DashboardClientMessage>(
          DashboardClientMessage.$_createMessage);
  static DashboardClientMessage? _defaultInstance;

  @$pb.TagNumber(1)
  DashboardClientMessage_Payload whichPayload() =>
      _DashboardClientMessage_PayloadByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(1)
  void clearPayload() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  DashboardSubscribe get subscribe => $_getN(0);
  @$pb.TagNumber(1)
  set subscribe(DashboardSubscribe value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasSubscribe() => $_has(0);
  @$pb.TagNumber(1)
  void clearSubscribe() => $_clearField(1);
  @$pb.TagNumber(1)
  DashboardSubscribe ensureSubscribe() => $_ensure(0);
}

class VehicleDelta extends $pb.GeneratedMessage {
  factory VehicleDelta({
    $core.String? vehicleId,
    $core.double? latitude,
    $core.double? longitude,
    $core.double? headingDeg,
    $core.double? speedKmh,
    VehicleStatus? status,
    $fixnum.Int64? recordedAtMs,
  }) {
    final result = VehicleDelta._();
    if (vehicleId != null) result.vehicleId = vehicleId;
    if (latitude != null) result.latitude = latitude;
    if (longitude != null) result.longitude = longitude;
    if (headingDeg != null) result.headingDeg = headingDeg;
    if (speedKmh != null) result.speedKmh = speedKmh;
    if (status != null) result.status = status;
    if (recordedAtMs != null) result.recordedAtMs = recordedAtMs;
    return result;
  }

  VehicleDelta._();

  factory VehicleDelta.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      VehicleDelta()..mergeFromBuffer(data, registry);
  factory VehicleDelta.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      VehicleDelta()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'VehicleDelta',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'radian.telemetry.v1'),
      createEmptyInstance: VehicleDelta.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'vehicleId')
    ..aD(2, _omitFieldNames ? '' : 'latitude')
    ..aD(3, _omitFieldNames ? '' : 'longitude')
    ..aD(4, _omitFieldNames ? '' : 'headingDeg', fieldType: $pb.PbFieldType.OF)
    ..aD(5, _omitFieldNames ? '' : 'speedKmh', fieldType: $pb.PbFieldType.OF)
    ..aE<VehicleStatus>(6, _omitFieldNames ? '' : 'status',
        enumValues: VehicleStatus.values)
    ..aInt64(7, _omitFieldNames ? '' : 'recordedAtMs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VehicleDelta clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VehicleDelta copyWith(void Function(VehicleDelta) updates) =>
      super.copyWith((message) => updates(message as VehicleDelta))
          as VehicleDelta;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use VehicleDelta() / VehicleDelta.new instead')
  static VehicleDelta create() => VehicleDelta._();
  static $pb.GeneratedMessage $_createMessage() => VehicleDelta._();
  @$core.override
  VehicleDelta createEmptyInstance() => VehicleDelta._();
  @$core.pragma('dart2js:noInline')
  static VehicleDelta getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<VehicleDelta>(
          VehicleDelta.$_createMessage);
  static VehicleDelta? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get vehicleId => $_getSZ(0);
  @$pb.TagNumber(1)
  set vehicleId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasVehicleId() => $_has(0);
  @$pb.TagNumber(1)
  void clearVehicleId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.double get latitude => $_getN(1);
  @$pb.TagNumber(2)
  set latitude($core.double value) => $_setDouble(1, value);
  @$pb.TagNumber(2)
  $core.bool hasLatitude() => $_has(1);
  @$pb.TagNumber(2)
  void clearLatitude() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.double get longitude => $_getN(2);
  @$pb.TagNumber(3)
  set longitude($core.double value) => $_setDouble(2, value);
  @$pb.TagNumber(3)
  $core.bool hasLongitude() => $_has(2);
  @$pb.TagNumber(3)
  void clearLongitude() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.double get headingDeg => $_getN(3);
  @$pb.TagNumber(4)
  set headingDeg($core.double value) => $_setFloat(3, value);
  @$pb.TagNumber(4)
  $core.bool hasHeadingDeg() => $_has(3);
  @$pb.TagNumber(4)
  void clearHeadingDeg() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.double get speedKmh => $_getN(4);
  @$pb.TagNumber(5)
  set speedKmh($core.double value) => $_setFloat(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSpeedKmh() => $_has(4);
  @$pb.TagNumber(5)
  void clearSpeedKmh() => $_clearField(5);

  @$pb.TagNumber(6)
  VehicleStatus get status => $_getN(5);
  @$pb.TagNumber(6)
  set status(VehicleStatus value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasStatus() => $_has(5);
  @$pb.TagNumber(6)
  void clearStatus() => $_clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get recordedAtMs => $_getI64(6);
  @$pb.TagNumber(7)
  set recordedAtMs($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasRecordedAtMs() => $_has(6);
  @$pb.TagNumber(7)
  void clearRecordedAtMs() => $_clearField(7);
}

/// Coalesced per tick (~1s): at most one delta per vehicle.
class FleetUpdate extends $pb.GeneratedMessage {
  factory FleetUpdate({
    $core.Iterable<VehicleDelta>? deltas,
    $core.Iterable<$core.String>? removedVehicleIds,
    $fixnum.Int64? serverTimeMs,
    $core.bool? isSnapshot,
  }) {
    final result = FleetUpdate._();
    if (deltas != null) result.deltas.addAll(deltas);
    if (removedVehicleIds != null)
      result.removedVehicleIds.addAll(removedVehicleIds);
    if (serverTimeMs != null) result.serverTimeMs = serverTimeMs;
    if (isSnapshot != null) result.isSnapshot = isSnapshot;
    return result;
  }

  FleetUpdate._();

  factory FleetUpdate.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FleetUpdate()..mergeFromBuffer(data, registry);
  factory FleetUpdate.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FleetUpdate()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FleetUpdate',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'radian.telemetry.v1'),
      createEmptyInstance: FleetUpdate.$_createMessage)
    ..pPM<VehicleDelta>(1, _omitFieldNames ? '' : 'deltas',
        subBuilder: VehicleDelta.$_createMessage)
    ..pPS(2, _omitFieldNames ? '' : 'removedVehicleIds')
    ..aInt64(3, _omitFieldNames ? '' : 'serverTimeMs')
    ..aOB(4, _omitFieldNames ? '' : 'isSnapshot')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FleetUpdate clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FleetUpdate copyWith(void Function(FleetUpdate) updates) =>
      super.copyWith((message) => updates(message as FleetUpdate))
          as FleetUpdate;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use FleetUpdate() / FleetUpdate.new instead')
  static FleetUpdate create() => FleetUpdate._();
  static $pb.GeneratedMessage $_createMessage() => FleetUpdate._();
  @$core.override
  FleetUpdate createEmptyInstance() => FleetUpdate._();
  @$core.pragma('dart2js:noInline')
  static FleetUpdate getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<FleetUpdate>(
          FleetUpdate.$_createMessage);
  static FleetUpdate? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<VehicleDelta> get deltas => $_getList(0);

  /// Vehicles that left the viewport or went offline.
  @$pb.TagNumber(2)
  $pb.PbList<$core.String> get removedVehicleIds => $_getList(1);

  @$pb.TagNumber(3)
  $fixnum.Int64 get serverTimeMs => $_getI64(2);
  @$pb.TagNumber(3)
  set serverTimeMs($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasServerTimeMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearServerTimeMs() => $_clearField(3);

  /// True on the first message after a subscribe: deltas is the full snapshot.
  @$pb.TagNumber(4)
  $core.bool get isSnapshot => $_getBF(3);
  @$pb.TagNumber(4)
  set isSnapshot($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasIsSnapshot() => $_has(3);
  @$pb.TagNumber(4)
  void clearIsSnapshot() => $_clearField(4);
}

/// Something about a job changed; dashboards refetch the job list.
class JobsChanged extends $pb.GeneratedMessage {
  factory JobsChanged({
    $core.Iterable<$core.String>? jobIds,
  }) {
    final result = JobsChanged._();
    if (jobIds != null) result.jobIds.addAll(jobIds);
    return result;
  }

  JobsChanged._();

  factory JobsChanged.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      JobsChanged()..mergeFromBuffer(data, registry);
  factory JobsChanged.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      JobsChanged()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'JobsChanged',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'radian.telemetry.v1'),
      createEmptyInstance: JobsChanged.$_createMessage)
    ..pPS(1, _omitFieldNames ? '' : 'jobIds')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  JobsChanged clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  JobsChanged copyWith(void Function(JobsChanged) updates) =>
      super.copyWith((message) => updates(message as JobsChanged))
          as JobsChanged;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use JobsChanged() / JobsChanged.new instead')
  static JobsChanged create() => JobsChanged._();
  static $pb.GeneratedMessage $_createMessage() => JobsChanged._();
  @$core.override
  JobsChanged createEmptyInstance() => JobsChanged._();
  @$core.pragma('dart2js:noInline')
  static JobsChanged getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<JobsChanged>(
          JobsChanged.$_createMessage);
  static JobsChanged? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<$core.String> get jobIds => $_getList(0);
}

/// A vehicle crossed a zone boundary (confirmed by consecutive fixes).
class GeofenceEvent extends $pb.GeneratedMessage {
  factory GeofenceEvent({
    $fixnum.Int64? id,
    $core.String? geofenceId,
    $core.String? geofenceName,
    GeofenceKind? kind,
    $core.String? vehicleId,
    $core.String? licensePlate,
    $core.bool? entered,
    $fixnum.Int64? occurredAtMs,
    GeoPoint? position,
  }) {
    final result = GeofenceEvent._();
    if (id != null) result.id = id;
    if (geofenceId != null) result.geofenceId = geofenceId;
    if (geofenceName != null) result.geofenceName = geofenceName;
    if (kind != null) result.kind = kind;
    if (vehicleId != null) result.vehicleId = vehicleId;
    if (licensePlate != null) result.licensePlate = licensePlate;
    if (entered != null) result.entered = entered;
    if (occurredAtMs != null) result.occurredAtMs = occurredAtMs;
    if (position != null) result.position = position;
    return result;
  }

  GeofenceEvent._();

  factory GeofenceEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GeofenceEvent()..mergeFromBuffer(data, registry);
  factory GeofenceEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GeofenceEvent()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GeofenceEvent',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'radian.telemetry.v1'),
      createEmptyInstance: GeofenceEvent.$_createMessage)
    ..aInt64(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'geofenceId')
    ..aOS(3, _omitFieldNames ? '' : 'geofenceName')
    ..aE<GeofenceKind>(4, _omitFieldNames ? '' : 'kind',
        enumValues: GeofenceKind.values)
    ..aOS(5, _omitFieldNames ? '' : 'vehicleId')
    ..aOS(6, _omitFieldNames ? '' : 'licensePlate')
    ..aOB(7, _omitFieldNames ? '' : 'entered')
    ..aInt64(8, _omitFieldNames ? '' : 'occurredAtMs')
    ..aOM<GeoPoint>(9, _omitFieldNames ? '' : 'position',
        subBuilder: GeoPoint.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GeofenceEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GeofenceEvent copyWith(void Function(GeofenceEvent) updates) =>
      super.copyWith((message) => updates(message as GeofenceEvent))
          as GeofenceEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use GeofenceEvent() / GeofenceEvent.new instead')
  static GeofenceEvent create() => GeofenceEvent._();
  static $pb.GeneratedMessage $_createMessage() => GeofenceEvent._();
  @$core.override
  GeofenceEvent createEmptyInstance() => GeofenceEvent._();
  @$core.pragma('dart2js:noInline')
  static GeofenceEvent getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GeofenceEvent>(
          GeofenceEvent.$_createMessage);
  static GeofenceEvent? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get id => $_getI64(0);
  @$pb.TagNumber(1)
  set id($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get geofenceId => $_getSZ(1);
  @$pb.TagNumber(2)
  set geofenceId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasGeofenceId() => $_has(1);
  @$pb.TagNumber(2)
  void clearGeofenceId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get geofenceName => $_getSZ(2);
  @$pb.TagNumber(3)
  set geofenceName($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasGeofenceName() => $_has(2);
  @$pb.TagNumber(3)
  void clearGeofenceName() => $_clearField(3);

  @$pb.TagNumber(4)
  GeofenceKind get kind => $_getN(3);
  @$pb.TagNumber(4)
  set kind(GeofenceKind value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasKind() => $_has(3);
  @$pb.TagNumber(4)
  void clearKind() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get vehicleId => $_getSZ(4);
  @$pb.TagNumber(5)
  set vehicleId($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasVehicleId() => $_has(4);
  @$pb.TagNumber(5)
  void clearVehicleId() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get licensePlate => $_getSZ(5);
  @$pb.TagNumber(6)
  set licensePlate($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasLicensePlate() => $_has(5);
  @$pb.TagNumber(6)
  void clearLicensePlate() => $_clearField(6);

  /// True on entering the zone, false on leaving it.
  @$pb.TagNumber(7)
  $core.bool get entered => $_getBF(6);
  @$pb.TagNumber(7)
  set entered($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(7)
  $core.bool hasEntered() => $_has(6);
  @$pb.TagNumber(7)
  void clearEntered() => $_clearField(7);

  @$pb.TagNumber(8)
  $fixnum.Int64 get occurredAtMs => $_getI64(7);
  @$pb.TagNumber(8)
  set occurredAtMs($fixnum.Int64 value) => $_setInt64(7, value);
  @$pb.TagNumber(8)
  $core.bool hasOccurredAtMs() => $_has(7);
  @$pb.TagNumber(8)
  void clearOccurredAtMs() => $_clearField(8);

  @$pb.TagNumber(9)
  GeoPoint get position => $_getN(8);
  @$pb.TagNumber(9)
  set position(GeoPoint value) => $_setField(9, value);
  @$pb.TagNumber(9)
  $core.bool hasPosition() => $_has(8);
  @$pb.TagNumber(9)
  void clearPosition() => $_clearField(9);
  @$pb.TagNumber(9)
  GeoPoint ensurePosition() => $_ensure(8);
}

/// Zones were created or deleted; dashboards (and the geofencer) reload them.
class GeofencesChanged extends $pb.GeneratedMessage {
  factory GeofencesChanged() => GeofencesChanged._();

  GeofencesChanged._();

  factory GeofencesChanged.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GeofencesChanged()..mergeFromBuffer(data, registry);
  factory GeofencesChanged.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GeofencesChanged()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GeofencesChanged',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'radian.telemetry.v1'),
      createEmptyInstance: GeofencesChanged.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GeofencesChanged clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GeofencesChanged copyWith(void Function(GeofencesChanged) updates) =>
      super.copyWith((message) => updates(message as GeofencesChanged))
          as GeofencesChanged;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use GeofencesChanged() / GeofencesChanged.new instead')
  static GeofencesChanged create() => GeofencesChanged._();
  static $pb.GeneratedMessage $_createMessage() => GeofencesChanged._();
  @$core.override
  GeofencesChanged createEmptyInstance() => GeofencesChanged._();
  @$core.pragma('dart2js:noInline')
  static GeofencesChanged getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GeofencesChanged>(
          GeofencesChanged.$_createMessage);
  static GeofencesChanged? _defaultInstance;
}

enum DashboardServerMessage_Payload {
  fleetUpdate,
  jobsChanged,
  geofenceEvent,
  geofencesChanged,
  notSet
}

class DashboardServerMessage extends $pb.GeneratedMessage {
  factory DashboardServerMessage({
    FleetUpdate? fleetUpdate,
    JobsChanged? jobsChanged,
    GeofenceEvent? geofenceEvent,
    GeofencesChanged? geofencesChanged,
  }) {
    final result = DashboardServerMessage._();
    if (fleetUpdate != null) result.fleetUpdate = fleetUpdate;
    if (jobsChanged != null) result.jobsChanged = jobsChanged;
    if (geofenceEvent != null) result.geofenceEvent = geofenceEvent;
    if (geofencesChanged != null) result.geofencesChanged = geofencesChanged;
    return result;
  }

  DashboardServerMessage._();

  factory DashboardServerMessage.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DashboardServerMessage()..mergeFromBuffer(data, registry);
  factory DashboardServerMessage.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DashboardServerMessage()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, DashboardServerMessage_Payload>
      _DashboardServerMessage_PayloadByTag = {
    1: DashboardServerMessage_Payload.fleetUpdate,
    2: DashboardServerMessage_Payload.jobsChanged,
    3: DashboardServerMessage_Payload.geofenceEvent,
    4: DashboardServerMessage_Payload.geofencesChanged,
    0: DashboardServerMessage_Payload.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DashboardServerMessage',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'radian.telemetry.v1'),
      createEmptyInstance: DashboardServerMessage.$_createMessage)
    ..oo(0, [1, 2, 3, 4])
    ..aOM<FleetUpdate>(1, _omitFieldNames ? '' : 'fleetUpdate',
        subBuilder: FleetUpdate.$_createMessage)
    ..aOM<JobsChanged>(2, _omitFieldNames ? '' : 'jobsChanged',
        subBuilder: JobsChanged.$_createMessage)
    ..aOM<GeofenceEvent>(3, _omitFieldNames ? '' : 'geofenceEvent',
        subBuilder: GeofenceEvent.$_createMessage)
    ..aOM<GeofencesChanged>(4, _omitFieldNames ? '' : 'geofencesChanged',
        subBuilder: GeofencesChanged.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DashboardServerMessage clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DashboardServerMessage copyWith(
          void Function(DashboardServerMessage) updates) =>
      super.copyWith((message) => updates(message as DashboardServerMessage))
          as DashboardServerMessage;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use DashboardServerMessage() / DashboardServerMessage.new instead')
  static DashboardServerMessage create() => DashboardServerMessage._();
  static $pb.GeneratedMessage $_createMessage() => DashboardServerMessage._();
  @$core.override
  DashboardServerMessage createEmptyInstance() => DashboardServerMessage._();
  @$core.pragma('dart2js:noInline')
  static DashboardServerMessage getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DashboardServerMessage>(
          DashboardServerMessage.$_createMessage);
  static DashboardServerMessage? _defaultInstance;

  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  DashboardServerMessage_Payload whichPayload() =>
      _DashboardServerMessage_PayloadByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  void clearPayload() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  FleetUpdate get fleetUpdate => $_getN(0);
  @$pb.TagNumber(1)
  set fleetUpdate(FleetUpdate value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasFleetUpdate() => $_has(0);
  @$pb.TagNumber(1)
  void clearFleetUpdate() => $_clearField(1);
  @$pb.TagNumber(1)
  FleetUpdate ensureFleetUpdate() => $_ensure(0);

  @$pb.TagNumber(2)
  JobsChanged get jobsChanged => $_getN(1);
  @$pb.TagNumber(2)
  set jobsChanged(JobsChanged value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasJobsChanged() => $_has(1);
  @$pb.TagNumber(2)
  void clearJobsChanged() => $_clearField(2);
  @$pb.TagNumber(2)
  JobsChanged ensureJobsChanged() => $_ensure(1);

  @$pb.TagNumber(3)
  GeofenceEvent get geofenceEvent => $_getN(2);
  @$pb.TagNumber(3)
  set geofenceEvent(GeofenceEvent value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasGeofenceEvent() => $_has(2);
  @$pb.TagNumber(3)
  void clearGeofenceEvent() => $_clearField(3);
  @$pb.TagNumber(3)
  GeofenceEvent ensureGeofenceEvent() => $_ensure(2);

  @$pb.TagNumber(4)
  GeofencesChanged get geofencesChanged => $_getN(3);
  @$pb.TagNumber(4)
  set geofencesChanged(GeofencesChanged value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasGeofencesChanged() => $_has(3);
  @$pb.TagNumber(4)
  void clearGeofencesChanged() => $_clearField(4);
  @$pb.TagNumber(4)
  GeofencesChanged ensureGeofencesChanged() => $_ensure(3);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
