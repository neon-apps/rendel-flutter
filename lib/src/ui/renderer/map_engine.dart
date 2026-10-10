import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;

/// The map a `map` block draws on (`design/CATALOG-B5.md`): OpenFreeMap's
/// style over OpenStreetMap's data, hosted in the EU and asking for no key.
const String rendelMapStyle = 'https://tiles.openfreemap.org/styles/liberty';

/// Where a map looks: the point at its centre and how far in.
///
/// The zoom is MapLibre's, on which the whole world is 512 logical pixels
/// across at zoom 0 and twice as wide at each step. The SDK does its own Web
/// Mercator arithmetic on it, to fit the pins and to stand each pin's label
/// over its point, rather than asking the engine where a point is: that is
/// an asynchronous call per frame on a platform channel, and Android answers
/// it in device pixels where iOS answers in points. With rotation and tilt
/// off, the arithmetic is the engine's own projection.
@immutable
class RendelMapCamera {
  const RendelMapCamera({required this.lat, required this.lng, required this.zoom});

  final double lat;
  final double lng;
  final double zoom;

  /// The world's width at zoom 0, in logical pixels.
  static const double tile = 512;

  /// How far in a single pin, or pins on one spot, are shown: a street and
  /// its corners.
  static const double closest = 16;

  /// The camera that shows every one of [points] in a view of [size], none
  /// nearer its edge than [padding], as close in as that allows and never
  /// past [closest].
  static RendelMapCamera fit(
    List<({double lat, double lng})> points,
    Size size, {
    required EdgeInsets padding,
  }) {
    final xs = [for (final p in points) _x(p.lng)];
    final ys = [for (final p in points) _y(p.lat)];
    final left = xs.reduce(math.min), right = xs.reduce(math.max);
    final top = ys.reduce(math.min), bottom = ys.reduce(math.max);
    final room = Size(
      math.max(1, size.width - padding.horizontal),
      math.max(1, size.height - padding.vertical),
    );
    var zoom = closest;
    if (right > left) zoom = math.min(zoom, _log2(room.width / ((right - left) * tile)));
    if (bottom > top) zoom = math.min(zoom, _log2(room.height / ((bottom - top) * tile)));
    zoom = math.max(1, zoom);
    // The pins' middle sits in the middle of the padded room, so the view's
    // own centre moves by half of whatever one side's padding has over the
    // other's.
    final world = tile * math.pow(2, zoom);
    final x = (left + right) / 2 + (padding.right - padding.left) / 2 / world;
    final y = (top + bottom) / 2 + (padding.bottom - padding.top) / 2 / world;
    return RendelMapCamera(lat: _lat(y), lng: x * 360 - 180, zoom: zoom);
  }

  /// Where the point at [lat], [lng] falls in a view of [size] looking
  /// through this camera, in logical pixels from the view's top left.
  Offset project(double lat, double lng, Size size) {
    final world = tile * math.pow(2, zoom);
    return Offset(
      (_x(lng) - _x(this.lng)) * world + size.width / 2,
      (_y(lat) - _y(this.lat)) * world + size.height / 2,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RendelMapCamera && other.lat == lat && other.lng == lng && other.zoom == zoom;

  @override
  int get hashCode => Object.hash(lat, lng, zoom);

  @override
  String toString() => 'RendelMapCamera($lat, $lng, z$zoom)';
}

double _log2(double value) => math.log(value) / math.ln2;

/// A longitude across the world, 0 at the antimeridian's west edge to 1.
double _x(double lng) => (lng + 180) / 360;

/// A latitude down the world, 0 at the top to 1, in Web Mercator. Clamped to
/// the latitudes the projection draws at all.
double _y(double lat) {
  final phi = lat.clamp(-85.05112878, 85.05112878) * math.pi / 180;
  return (1 - math.log(math.tan(math.pi / 4 + phi / 2)) / math.pi) / 2;
}

double _lat(double y) => math.atan(_sinh(math.pi * (1 - 2 * y))) * 180 / math.pi;

double _sinh(double v) => (math.exp(v) - math.exp(-v)) / 2;

/// What draws the ground under a `map` block's pins.
///
/// MapLibre, through [RendelMapEngine.current]. A seam rather than a direct
/// call because the map is a platform view, which a widget test cannot run:
/// the tests put an engine of their own here and drive what the block does
/// around it, on the page and full screen.
abstract class RendelMapEngine {
  const RendelMapEngine();

  /// The engine every map block draws with.
  static RendelMapEngine current = const MapLibreEngine();

  /// The map, looking through [camera] when it is first drawn.
  ///
  /// [interactive] is whether it pans and zooms under a finger. [onMove]
  /// reports each camera the user moves it to, so the pins can follow.
  /// [onFailed] says the engine cannot draw here at all (no network for the
  /// style, a platform it does not run on), and the block shows its pins as
  /// a list instead.
  Widget build({
    required RendelMapCamera camera,
    required bool interactive,
    required ValueChanged<RendelMapCamera> onMove,
    required VoidCallback onFailed,
  });
}

/// MapLibre (`maplibre_gl`), on Android, iOS and the web.
class MapLibreEngine extends RendelMapEngine {
  const MapLibreEngine();

  /// How long the style has to load before the map counts as failed. The
  /// engine reports no error for a style it could not fetch; it simply never
  /// says the style loaded.
  static const Duration patience = Duration(seconds: 12);

  @override
  Widget build({
    required RendelMapCamera camera,
    required bool interactive,
    required ValueChanged<RendelMapCamera> onMove,
    required VoidCallback onFailed,
  }) =>
      _MapLibreView(camera: camera, interactive: interactive, onMove: onMove, onFailed: onFailed);
}

class _MapLibreView extends StatefulWidget {
  const _MapLibreView({
    required this.camera,
    required this.interactive,
    required this.onMove,
    required this.onFailed,
  });

  final RendelMapCamera camera;
  final bool interactive;
  final ValueChanged<RendelMapCamera> onMove;
  final VoidCallback onFailed;

  @override
  State<_MapLibreView> createState() => _MapLibreViewState();
}

class _MapLibreViewState extends State<_MapLibreView> {
  Timer? _waiting;

  /// MapLibre draws on Android, iOS and the web, and nowhere else: on a
  /// desktop build the block goes straight to its list.
  static bool get _runs =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    if (!_runs) {
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onFailed());
      return;
    }
    _waiting = Timer(MapLibreEngine.patience, widget.onFailed);
  }

  @override
  void dispose() {
    _waiting?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_runs) return const SizedBox.expand();
    final interactive = widget.interactive;
    return ml.MapLibreMap(
      styleString: rendelMapStyle,
      initialCameraPosition: ml.CameraPosition(
        target: ml.LatLng(widget.camera.lat, widget.camera.lng),
        zoom: widget.camera.zoom,
      ),
      onStyleLoadedCallback: () => _waiting?.cancel(),
      // North up and flat, always: the SDK's own projection of the pins
      // assumes both, and a map turned by accident is a map misread.
      rotateGesturesEnabled: false,
      tiltGesturesEnabled: false,
      compassEnabled: false,
      scrollGesturesEnabled: interactive,
      zoomGesturesEnabled: interactive,
      doubleClickZoomEnabled: interactive,
      // Nothing on it is dragged; this is the annotations' drag, not the map's.
      dragEnabled: false,
      trackCameraPosition: interactive,
      onCameraMove: interactive
          ? (position) => widget.onMove(RendelMapCamera(
                lat: position.target.latitude,
                lng: position.target.longitude,
                zoom: position.zoom,
              ))
          : null,
      // The block draws "© OpenStreetMap" itself, bottom right, where it is
      // always visible; the engine's own button, which lists the style's
      // sources in full, moves out of its way.
      attributionButtonPosition: ml.AttributionButtonPosition.bottomLeft,
      // Full screen the map takes every touch that lands on it at once, so
      // no gesture of Flutter's under it can claim a pan first. On the page
      // it takes none: the block lays a tap over it, and the page scrolls
      // through it.
      gestureRecognizers: interactive
          ? {Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new)}
          : null,
    );
  }
}
