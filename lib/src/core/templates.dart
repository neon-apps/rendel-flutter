// Card templates as the device reads them: the console's `templates`
// (`packages/protocol/src/templates.ts`), re-checked rather than trusted.
//
// A template is a small tree of primitives — boxes, text, pictures, stars,
// buttons — each bound to a field of the block the model sent. The renderer
// (`ui/renderer/templates.dart`) walks it with the block's data. Every value
// here is a coercion with a bound, never a cast, like the rest of
// `remote_config.dart`: one value out of shape drops that kind's template
// whole, and the kind is drawn the built-in way, as a build that predates
// templates draws it.
//
// Whether a binding names a field the kind carries is the console's check;
// here a field that is not there simply draws nothing.

/// The kinds of card a template can draw, by catalog name.
const rendelTemplateKinds = ['product_cards', 'item_list', 'info_card', 'order_tracker'];

/// Colours a template can name instead of a hex: the theme's own roles.
const rendelTemplateRoles = ['surface', 'onSurface', 'muted', 'accent', 'onAccent', 'raised', 'sunk', 'line'];

const _maxNodes = 60;
const _maxDepth = 8;
final _hex = RegExp(r'^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$');
final _path = RegExp(r'^(\.|[a-z_]{1,32}(\.[a-z_]{1,32})?)$');

/// One kind of card's template.
class RendelCardTemplate {
  const RendelCardTemplate({required this.node, this.layout, this.itemWidth});

  final RendelTemplateNode node;

  /// `rail`, `grid` or `list`; `product_cards` only. Null is a rail.
  final String? layout;

  /// An item's width in a rail; `product_cards` only.
  final double? itemWidth;

  /// Every kind in [raw] this build can draw, each only when all of it is in shape.
  static Map<String, RendelCardTemplate> parseAll(Object? raw) {
    if (raw is! Map) return const {};
    final out = <String, RendelCardTemplate>{};
    for (final kind in rendelTemplateKinds) {
      final kept = tryParse(kind, raw[kind]);
      if (kept != null) out[kind] = kept;
    }
    return out;
  }

  static RendelCardTemplate? tryParse(String kind, Object? raw) {
    try {
      final o = _record(raw);
      _only(o, const ['node', 'layout', 'itemWidth']);
      final layout = _opt(o, 'layout', _oneOf(const ['rail', 'grid', 'list']));
      final itemWidth = _opt(o, 'itemWidth', _between(96, 360));
      if (kind != 'product_cards' && (layout != null || itemWidth != null)) throw const _Refused();
      return RendelCardTemplate(
        node: RendelTemplateNode._parse(o['node'], 1, _Count()),
        layout: layout,
        itemWidth: itemWidth,
      );
    } on _Refused {
      return null;
    }
  }
}

/// Draw a node only when [bind] has a value, or has exactly [equals].
class RendelTemplateWhen {
  const RendelTemplateWhen(this.bind, this.equals);
  final String bind;
  final String? equals;
}

/// One node of a template. Which fields mean anything depends on [type]:
/// `box`, `text`, `image`, `stars`, `button`, `divider`, `spacer`, `each`.
class RendelTemplateNode {
  const RendelTemplateNode._({
    required this.type,
    this.when,
    this.bind,
    this.value,
    this.direction,
    this.gap,
    this.padding,
    this.align,
    this.justify,
    this.fill,
    this.border,
    this.color,
    this.radius,
    this.grow = false,
    this.size,
    this.weight,
    this.maxLines,
    this.textAlign,
    this.aspect,
    this.width,
    this.height,
    this.fit,
    this.variant,
    this.thickness,
    this.max,
    this.children = const [],
    this.child,
  });

  final String type;
  final RendelTemplateWhen? when;

  /// A field of the data being drawn, or `.` for the element itself.
  final String? bind;

  /// A text's own words.
  final String? value;
  final String? direction;
  final double? gap;
  final double? padding;
  final String? align;
  final String? justify;
  final String? fill;
  final String? border;
  final String? color;
  final double? radius;
  final bool grow;
  final double? size;
  final String? weight;
  final int? maxLines;
  final String? textAlign;
  final double? aspect;
  final double? width;
  final double? height;
  final String? fit;
  final String? variant;
  final double? thickness;
  final int? max;
  final List<RendelTemplateNode> children;
  final RendelTemplateNode? child;

  bool get isRow => direction == 'row';

  static RendelTemplateNode _parse(Object? raw, int depth, _Count count) {
    if (depth > _maxDepth || ++count.n > _maxNodes) throw const _Refused();
    final o = _record(raw);
    final when = _opt(o, 'when', (v) {
      final w = _record(v);
      _only(w, const ['bind', 'equals']);
      return RendelTemplateWhen(
        _bind(w['bind']),
        _opt(w, 'equals', (e) => e is String && e.length <= 40 ? e : throw const _Refused()),
      );
    });
    switch (o['type']) {
      case 'box':
        _only(o, const ['type', 'when', 'direction', 'gap', 'padding', 'align', 'justify', 'fill', 'border', 'radius', 'grow', 'children']);
        final children = o['children'];
        if (children is! List || children.isEmpty || children.length > 12) throw const _Refused();
        return RendelTemplateNode._(
          type: 'box',
          when: when,
          direction: _opt(o, 'direction', _oneOf(const ['column', 'row'])),
          gap: _opt(o, 'gap', _between(0, 48)),
          padding: _opt(o, 'padding', _between(0, 48)),
          align: _opt(o, 'align', _oneOf(const ['start', 'center', 'end', 'stretch'])),
          justify: _opt(o, 'justify', _oneOf(const ['start', 'center', 'end', 'between'])),
          fill: _opt(o, 'fill', _colour),
          border: _opt(o, 'border', _colour),
          radius: _opt(o, 'radius', _between(0, 64)),
          grow: _opt(o, 'grow', _flag) ?? false,
          children: [for (final child in children) _parse(child, depth + 1, count)],
        );
      case 'text':
        _only(o, const ['type', 'when', 'bind', 'value', 'size', 'weight', 'color', 'maxLines', 'align']);
        final bind = _opt(o, 'bind', _bind);
        final value = _opt(o, 'value', (v) => v is String && v.isNotEmpty && v.length <= 60 ? v : throw const _Refused());
        if ((bind == null) == (value == null)) throw const _Refused();
        return RendelTemplateNode._(
          type: 'text',
          when: when,
          bind: bind,
          value: value,
          size: _opt(o, 'size', _between(8, 40)),
          weight: _opt(o, 'weight', _oneOf(const ['regular', 'medium', 'bold'])),
          color: _opt(o, 'color', _colour),
          maxLines: _opt(o, 'maxLines', _between(1, 6, whole: true))?.toInt(),
          textAlign: _opt(o, 'align', _oneOf(const ['start', 'center', 'end'])),
        );
      case 'image':
        _only(o, const ['type', 'when', 'bind', 'aspect', 'width', 'height', 'radius', 'fit']);
        return RendelTemplateNode._(
          type: 'image',
          when: when,
          bind: _bind(o['bind']),
          aspect: _opt(o, 'aspect', _between(0.25, 4)),
          width: _opt(o, 'width', _between(16, 400)),
          height: _opt(o, 'height', _between(16, 400)),
          radius: _opt(o, 'radius', _between(0, 64)),
          fit: _opt(o, 'fit', _oneOf(const ['cover', 'contain'])),
        );
      case 'stars':
        _only(o, const ['type', 'when', 'bind', 'size', 'color']);
        return RendelTemplateNode._(
          type: 'stars',
          when: when,
          bind: _bind(o['bind']),
          size: _opt(o, 'size', _between(8, 32)),
          color: _opt(o, 'color', _colour),
        );
      case 'button':
        _only(o, const ['type', 'when', 'bind', 'variant', 'fill', 'color', 'radius', 'size']);
        return RendelTemplateNode._(
          type: 'button',
          when: when,
          bind: _bind(o['bind']),
          variant: _opt(o, 'variant', _oneOf(const ['filled', 'outlined', 'quiet'])),
          fill: _opt(o, 'fill', _colour),
          color: _opt(o, 'color', _colour),
          radius: _opt(o, 'radius', _between(0, 999)),
          size: _opt(o, 'size', _between(9, 28)),
        );
      case 'divider':
        _only(o, const ['type', 'when', 'color', 'thickness']);
        return RendelTemplateNode._(
          type: 'divider',
          when: when,
          color: _opt(o, 'color', _colour),
          thickness: _opt(o, 'thickness', _between(0.5, 4)),
        );
      case 'spacer':
        _only(o, const ['type', 'when', 'size']);
        return RendelTemplateNode._(type: 'spacer', when: when, size: _opt(o, 'size', _between(0, 64)));
      case 'each':
        _only(o, const ['type', 'when', 'bind', 'direction', 'gap', 'max', 'child']);
        return RendelTemplateNode._(
          type: 'each',
          when: when,
          bind: _bind(o['bind']),
          direction: _opt(o, 'direction', _oneOf(const ['column', 'row'])),
          gap: _opt(o, 'gap', _between(0, 48)),
          max: _opt(o, 'max', _between(1, 20, whole: true))?.toInt(),
          child: _parse(o['child'], depth + 1, count),
        );
    }
    throw const _Refused();
  }
}

/// The templates the thread draws with: set when a published config is
/// applied (`Rendel._apply`), empty until then and for an app that publishes
/// none.
Map<String, RendelCardTemplate> rendelCardTemplates = const {};

/// Reads [path] out of [data]: `title`, `amount.value`, or `.` for [data] itself.
Object? rendelTemplateRead(Object? data, String path) {
  if (path == '.') return data;
  Object? value = data;
  for (final key in path.split('.')) {
    if (value is! Map) return null;
    value = value[key];
  }
  return value;
}

/// Whether [value] counts as there: not null, false, empty text or an empty list.
bool rendelTemplatePresent(Object? value) {
  if (value == null || value == false || value == '') return false;
  return value is! List || value.isNotEmpty;
}

// ————————————————————————— coercions —————————————————————————

class _Refused implements Exception {
  const _Refused();
}

class _Count {
  int n = 0;
}

Map _record(Object? value) => value is Map ? value : throw const _Refused();

void _only(Map o, List<String> keys) {
  for (final key in o.keys) {
    if (!keys.contains(key)) throw const _Refused();
  }
}

T? _opt<T>(Map o, String key, T Function(Object?) read) => o[key] == null ? null : read(o[key]);

double Function(Object?) _between(double min, double max, {bool whole = false}) => (v) {
      if (v is! num) throw const _Refused();
      final d = v.toDouble();
      if (d.isNaN || d < min || d > max || (whole && d != d.roundToDouble())) throw const _Refused();
      return d;
    };

String Function(Object?) _oneOf(List<String> values) =>
    (v) => v is String && values.contains(v) ? v : throw const _Refused();

String _colour(Object? v) =>
    v is String && (_hex.hasMatch(v) || rendelTemplateRoles.contains(v)) ? v : throw const _Refused();

String _bind(Object? v) => v is String && _path.hasMatch(v) ? v : throw const _Refused();

bool _flag(Object? v) => v is bool ? v : throw const _Refused();
