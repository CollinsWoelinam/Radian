import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../jobs/driver_job.dart';
import 'theme.dart';

/// A route line to draw: a road leg or a shift's trail.
class MapLine {
  const MapLine(this.points, this.color, {this.width = 6});
  final List<LatLon> points;
  final Color color;
  final double width;
}

const _accra = LatLng(5.6037, -0.1870);

/// OpenFreeMap vector tiles (no API key), the same styles as the dashboard.
String _style(Brightness b) =>
    b == Brightness.dark ? 'https://tiles.openfreemap.org/styles/dark' : 'https://tiles.openfreemap.org/styles/positron';

String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

LatLng _ll(LatLon p) => LatLng(p.lat, p.lon);

/// The driver's map: their position as the amber dot, plus any route lines
/// and stops. With [fit] the camera frames everything once; otherwise it
/// follows the driver.
class RadianMap extends StatefulWidget {
  const RadianMap({
    super.key,
    this.me,
    this.lines = const [],
    this.pickup,
    this.dropoff,
    this.fit = false,
    this.interactive = true,
    this.padding = EdgeInsets.zero,
  });

  final LatLon? me;
  final List<MapLine> lines;
  final LatLon? pickup;
  final LatLon? dropoff;
  final bool fit;
  final bool interactive;

  /// Space covered by overlays (sheets, cards) to keep framed content clear of.
  final EdgeInsets padding;

  @override
  State<RadianMap> createState() => _RadianMapState();
}

class _RadianMapState extends State<RadianMap> {
  MapLibreMapController? _map;
  bool _ready = false;
  bool _framed = false;
  bool _syncing = false;
  bool _again = false;

  @override
  void didUpdateWidget(covariant RadianMap old) {
    super.didUpdateWidget(old);
    _sync();
  }

  static Map<String, dynamic> _collection(List<Map<String, dynamic>> features) => {'type': 'FeatureCollection', 'features': features};

  static Map<String, dynamic> _point(LatLon p, Map<String, dynamic> props) => {
        'type': 'Feature',
        'properties': props,
        'geometry': {'type': 'Point', 'coordinates': [p.lon, p.lat]},
      };

  /// Our own sources and layers (not the plugin's annotation managers, whose
  /// setup throws if the map is torn down while its style loads).
  Future<void> _addLayers(MapLibreMapController map) async {
    final empty = _collection(const []);
    await map.addGeoJsonSource('r-lines', empty);
    await map.addGeoJsonSource('r-stops', empty);
    await map.addGeoJsonSource('r-me', empty);
    await map.addLineLayer('r-lines', 'r-lines-casing', const LineLayerProperties(lineColor: ['get', 'casing'], lineWidth: ['+', ['get', 'width'], 4], lineJoin: 'round', lineCap: 'round'));
    await map.addLineLayer('r-lines', 'r-lines', const LineLayerProperties(lineColor: ['get', 'color'], lineWidth: ['get', 'width'], lineJoin: 'round', lineCap: 'round'));
    await map.addCircleLayer('r-stops', 'r-stops', const CircleLayerProperties(circleRadius: ['get', 'radius'], circleColor: ['get', 'fill'], circleStrokeColor: ['get', 'stroke'], circleStrokeWidth: ['get', 'strokeWidth']));
    await map.addCircleLayer('r-me', 'r-me', const CircleLayerProperties(circleRadius: ['get', 'radius'], circleColor: ['get', 'fill'], circleOpacity: ['get', 'opacity'], circleStrokeColor: ['get', 'stroke'], circleStrokeWidth: ['get', 'strokeWidth']));
  }

  Future<void> _sync() async {
    final map = _map;
    if (map == null || !_ready || !mounted) return;
    if (_syncing) {
      _again = true; // coalesce updates that arrive mid-sync
      return;
    }
    _syncing = true;
    try {
      final dark = Theme.of(context).brightness == Brightness.dark;
      final ground = _hex(dark ? nightInk : Colors.white);
      await map.setGeoJsonSource('r-lines', _collection([
        for (final l in widget.lines.where((l) => l.points.length > 1))
          {
            'type': 'Feature',
            'properties': {'color': _hex(l.color), 'casing': ground, 'width': l.width},
            'geometry': {
              'type': 'LineString',
              'coordinates': [for (final p in l.points) [p.lon, p.lat]],
            },
          },
      ]));
      await map.setGeoJsonSource('r-stops', _collection([
        if (widget.pickup != null) _point(widget.pickup!, {'radius': 9, 'fill': _hex(liveGreen), 'stroke': ground, 'strokeWidth': 3}),
        if (widget.dropoff != null) _point(widget.dropoff!, {'radius': 8, 'fill': ground, 'stroke': _hex(dropoffPurple), 'strokeWidth': 4}),
      ]));
      final me = widget.me;
      await map.setGeoJsonSource('r-me', _collection([
        if (me != null) ...[
          _point(me, {'radius': 22, 'fill': _hex(liveAmber), 'opacity': 0.2, 'stroke': ground, 'strokeWidth': 0}),
          _point(me, {'radius': 8, 'fill': _hex(liveAmber), 'opacity': 1, 'stroke': ground, 'strokeWidth': 3}),
        ],
      ]));

      if (widget.fit) {
        if (!_framed) _framed = await _frame(map);
      } else if (me != null) {
        await map.animateCamera(_framed ? CameraUpdate.newLatLng(_ll(me)) : CameraUpdate.newLatLngZoom(_ll(me), 15));
        _framed = true;
      }
    } catch (_) {
      // The map can be torn down mid-update (screen change); nothing to do.
    } finally {
      _syncing = false;
      if (_again && mounted) {
        _again = false;
        _sync();
      }
    }
  }

  Future<bool> _frame(MapLibreMapController map) async {
    final pts = [
      for (final l in widget.lines) ...l.points,
      ?widget.me,
      ?widget.pickup,
      ?widget.dropoff,
    ];
    if (pts.isEmpty) return false;
    var minLat = pts.first.lat, maxLat = pts.first.lat, minLon = pts.first.lon, maxLon = pts.first.lon;
    for (final p in pts) {
      minLat = math.min(minLat, p.lat);
      maxLat = math.max(maxLat, p.lat);
      minLon = math.min(minLon, p.lon);
      maxLon = math.max(maxLon, p.lon);
    }
    // A single point (or a parked phone) gets a sensible zoom instead of the maximum.
    const pad = 0.004;
    final bounds = LatLngBounds(southwest: LatLng(minLat - pad, minLon - pad), northeast: LatLng(maxLat + pad, maxLon + pad));
    final p = widget.padding;
    await map.animateCamera(CameraUpdate.newLatLngBounds(bounds, left: p.left + 40, top: p.top + 40, right: p.right + 40, bottom: p.bottom + 40));
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return MapLibreMap(
      key: ValueKey(brightness), // the style is fixed at creation
      styleString: _style(brightness),
      initialCameraPosition: CameraPosition(target: widget.me != null ? _ll(widget.me!) : _accra, zoom: widget.me != null ? 15 : 11),
      onMapCreated: (c) => _map = c,
      onStyleLoadedCallback: () async {
        final map = _map;
        if (map == null) return;
        try {
          await _addLayers(map);
          _ready = true;
          _sync();
        } catch (_) {}
      },
      annotationOrder: const [],
      compassEnabled: false,
      rotateGesturesEnabled: false,
      tiltGesturesEnabled: false,
      scrollGesturesEnabled: widget.interactive,
      zoomGesturesEnabled: widget.interactive,
      doubleClickZoomEnabled: widget.interactive,
      attributionButtonPosition: AttributionButtonPosition.bottomLeft,
      attributionButtonMargins: math.Point(8, widget.padding.bottom + 8),
      logoEnabled: false,
    );
  }
}
