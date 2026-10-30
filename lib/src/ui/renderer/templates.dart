part of 'blocks.dart';

// A kind of card drawn from the customer's own template
// (`packages/protocol/src/templates.ts`, read by `core/templates.dart`): the
// tree walked with the block's data.
//
// The pieces that act — an item that answers a tap or opens its detail, a
// button that carries an action — are the catalog's own (`_opens`,
// `_maybePressable`, `_actionButton`, `_tap`), so a templated card does
// exactly what the built-in one did; only where things sit and how they look
// is the template's. Returns null when the template draws nothing for this
// block, and the registry draws the built-in card instead.

/// [block] drawn from [template], or null when the template draws nothing for it.
Widget? buildTemplated(
  BuildContext context,
  WireBlock block,
  RendelDispatcher dispatch,
  RendelCardTemplate template,
) {
  final kind = block.type;
  if (kind == 'product_cards' || kind == 'item_list') {
    final layout = kind == 'product_cards' ? (template.layout ?? 'rail') : 'list';
    final items = <Widget>[];
    for (final item in _maps(block.props['items'])) {
      final drawn = _TemplateNode(node: template.node, data: item, dispatch: dispatch, inRow: false);
      if (!drawn.draws(item)) continue;
      final price = kind == 'item_list' ? (_str(_map(item['amount'])?['value']) ?? _str(item['trailing'])) : _str(item['price']);
      final label = _str(item['title']) ?? '';
      final open = _opens(context, item, price: price);
      items.add(open != null
          ? RendelPressable(semanticLabel: label, onTap: open, child: drawn)
          : _maybePressable(action: item['action'], dispatch: dispatch, semanticLabel: label, child: drawn));
    }
    if (items.isEmpty) return null;
    const gap = 10.0;
    switch (layout) {
      case 'rail':
        final width = template.itemWidth ?? 168;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: gap,
            children: [for (final item in items) SizedBox(width: width, child: item)],
          ),
        );
      case 'grid':
        return LayoutBuilder(builder: (context, constraints) {
          final width = constraints.maxWidth.isFinite ? (constraints.maxWidth - gap) / 2 : 168.0;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [for (final item in items) SizedBox(width: width, child: item)],
          );
        });
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: kind == 'item_list' ? 8 : gap,
          children: items,
        );
    }
  }
  final props = block.props;
  final drawn = _TemplateNode(node: template.node, data: props, dispatch: dispatch, inRow: false);
  return drawn.draws(props) ? drawn : null;
}

/// One node of a template, with the data it reads from.
class _TemplateNode extends StatelessWidget {
  const _TemplateNode({required this.node, required this.data, required this.dispatch, required this.inRow});

  final RendelTemplateNode node;
  final Object? data;
  final RendelDispatcher dispatch;

  /// Whether the node sits in a row, which decides how it takes room.
  final bool inRow;

  /// Whether this node draws anything for [value]: its condition holds, and
  /// a box or a list has at least one child that draws.
  bool draws(Object? value) => _draws(node, value);

  static bool _draws(RendelTemplateNode n, Object? data) {
    final when = n.when;
    if (when != null) {
      final value = rendelTemplateRead(data, when.bind);
      final equals = when.equals;
      final shown = equals != null ? rendelTemplatePresent(value) && '$value' == equals : rendelTemplatePresent(value);
      if (!shown) return false;
    }
    switch (n.type) {
      case 'box':
        return n.children.any((child) => _draws(child, data));
      case 'text':
        final value = n.bind != null ? rendelTemplateRead(data, n.bind!) : n.value;
        return value is num ? value.isFinite : (_str(value)?.isNotEmpty ?? false);
      case 'image':
        return _https(rendelTemplateRead(data, n.bind!)) != null;
      case 'stars':
        return _dbl(rendelTemplateRead(data, n.bind!)) != null;
      case 'button':
        return (_str(_map(rendelTemplateRead(data, n.bind!))?['label'])?.isNotEmpty ?? false);
      case 'each':
        final items = rendelTemplateRead(data, n.bind!);
        return items is List && items.take(n.max ?? 20).any((item) => _draws(n.child!, item));
      default:
        return true;
    }
  }

  static String? _https(Object? value) {
    final url = _str(value);
    if (url == null) return null;
    final uri = Uri.tryParse(url);
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty ? url : null;
  }

  /// A colour of the template: a hex, or one of the theme's roles. As words,
  /// the accent is its legible form, as everywhere else in the thread.
  static Color? _paint(RendelTheme theme, String? value, {bool words = false}) {
    if (value == null) return null;
    if (value.startsWith('#')) {
      final raw = value.substring(1);
      final full = raw.length == 3 ? raw.split('').map((c) => '$c$c').join() : raw;
      final parsed = int.tryParse('FF$full', radix: 16);
      return parsed == null ? null : Color(parsed);
    }
    final c = theme.colors;
    return switch (value) {
      'surface' => c.surface,
      'onSurface' => c.onSurface,
      'muted' => c.onSurfaceSoft,
      'accent' => words ? theme.accentText : c.accent,
      'onAccent' => c.onAccent,
      'raised' => c.surfaceRaised,
      'sunk' => c.surfaceSunk,
      'line' => c.lineStrong,
      _ => null,
    };
  }

  /// A child of a box or a list: in a row it takes the room it is given
  /// rather than asking for more than there is.
  Widget _child(RendelTemplateNode n, Object? value, {required bool row}) {
    final drawn = _TemplateNode(node: n, data: value, dispatch: dispatch, inRow: row);
    if (!row) return drawn;
    if (n.type == 'spacer' && n.size == null) return const Spacer();
    if (n.grow) return Expanded(child: drawn);
    if (n.type == 'spacer' || n.type == 'stars' || n.type == 'divider') return drawn;
    return Flexible(child: drawn);
  }

  @override
  Widget build(BuildContext context) {
    if (!draws(data)) return const SizedBox.shrink();
    final theme = RendelThemeScope.of(context);
    final n = node;
    switch (n.type) {
      case 'box': {
        final row = n.isRow;
        final children = [
          for (final child in n.children)
            if (_draws(child, data)) _child(child, data, row: row),
        ];
        final fill = _paint(theme, n.fill);
        final border = _paint(theme, n.border);
        final align = switch (n.align) {
          'center' => CrossAxisAlignment.center,
          'end' => CrossAxisAlignment.end,
          // A row's children cannot stretch to a height nothing gives them.
          'stretch' => row ? CrossAxisAlignment.start : CrossAxisAlignment.stretch,
          'start' => CrossAxisAlignment.start,
          // A column in a row is as wide as what it holds, as on the web; one
          // down the card takes its width.
          _ => row || inRow ? CrossAxisAlignment.start : CrossAxisAlignment.stretch,
        };
        final justify = switch (n.justify) {
          'center' => MainAxisAlignment.center,
          'end' => MainAxisAlignment.end,
          'between' => MainAxisAlignment.spaceBetween,
          _ => MainAxisAlignment.start,
        };
        final flex = Flex(
          direction: row ? Axis.horizontal : Axis.vertical,
          mainAxisSize: row && n.justify == 'between' ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: align,
          mainAxisAlignment: justify,
          spacing: n.gap ?? 0,
          children: children,
        );
        if (fill == null && border == null && n.padding == null && n.radius == null) return flex;
        return Container(
          padding: EdgeInsets.all(n.padding ?? 0),
          clipBehavior: n.radius != null ? Clip.antiAlias : Clip.none,
          decoration: BoxDecoration(
            color: fill,
            border: border == null ? null : Border.all(color: border),
            borderRadius: n.radius == null ? null : BorderRadius.circular(n.radius!),
          ),
          child: flex,
        );
      }
      case 'text': {
        final value = n.bind != null ? rendelTemplateRead(data, n.bind!) : n.value;
        final said = value is num
            ? rendelNumber(value, RendelStringsScope.of(context).numberLocale, digits: value == value.roundToDouble() ? 0 : 1)
            : _str(value)!;
        return Text(
          said,
          maxLines: n.maxLines,
          overflow: n.maxLines == null ? null : TextOverflow.ellipsis,
          textAlign: switch (n.textAlign) {
            'center' => TextAlign.center,
            'end' => TextAlign.end,
            _ => TextAlign.start,
          },
          style: theme.text.body.copyWith(
            fontSize: n.size,
            fontWeight: switch (n.weight) {
              'bold' => FontWeight.w700,
              'medium' => FontWeight.w500,
              'regular' => FontWeight.w400,
              _ => null,
            },
            color: _paint(theme, n.color, words: true),
          ),
        );
      }
      case 'image': {
        final url = _https(rendelTemplateRead(data, n.bind!))!;
        final alt = _str(rendelTemplateRead(data, 'title'));
        final fit = n.fit == 'contain' ? BoxFit.contain : BoxFit.cover;
        return LayoutBuilder(builder: (context, constraints) {
          final room = constraints.maxWidth.isFinite ? constraints.maxWidth : 120.0;
          final width = n.width ?? room;
          final height = n.height ?? width / (n.aspect ?? 1);
          return SizedBox(
            width: width,
            height: height,
            child: _Thumbnail(url: url, width: width, height: height, radius: n.radius ?? 0, alt: alt, fit: fit),
          );
        });
      }
      case 'stars': {
        final rating = _dbl(rendelTemplateRead(data, n.bind!))!.clamp(0.0, 5.0);
        final lit = rating.round();
        final color = _paint(theme, n.color, words: true) ?? theme.colors.onSurface;
        final strings = RendelStringsScope.of(context);
        return Semantics(
          label: strings.ratingStars.replaceAll('{n}', rendelNumber(rating, strings.numberLocale, digits: 1)),
          excludeSemantics: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 5; i++)
                Icon(Icons.star_rounded, size: n.size ?? 13, color: i < lit ? color : color.withValues(alpha: 0.25)),
            ],
          ),
        );
      }
      case 'button': {
        final button = _map(rendelTemplateRead(data, n.bind!))!;
        final label = _str(button['label'])!;
        final action = button['action'];
        final own = n.fill != null || n.color != null || n.radius != null || n.size != null || n.variant == 'outlined';
        // Without a look of its own it is the catalog's button, copy
        // feedback and all.
        if (!own) {
          return _actionButton(context, label: label, action: action, dispatch: dispatch, quiet: n.variant == 'quiet');
        }
        final onTap = _tap(dispatch, action);
        if (onTap == null) return const SizedBox.shrink();
        final outlined = n.variant == 'outlined';
        final quiet = n.variant == 'quiet';
        final fill = _paint(theme, n.fill) ?? (outlined ? null : quiet ? theme.colors.surfaceHigh : theme.colors.accent);
        final ink = _paint(theme, n.color, words: true) ?? (outlined || quiet ? theme.colors.onSurface : theme.colors.onAccent);
        return RendelPressable(
          semanticLabel: label,
          onTap: onTap,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: theme.space.xl, vertical: theme.space.md),
            decoration: BoxDecoration(
              color: fill,
              border: outlined ? Border.all(color: ink) : null,
              borderRadius: BorderRadius.circular(n.radius ?? theme.radius.control),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.text.labelStrong.copyWith(color: ink, fontSize: n.size),
            ),
          ),
        );
      }
      case 'divider': {
        final thickness = n.thickness ?? 1;
        final color = _paint(theme, n.color) ?? theme.colors.lineStrong;
        return inRow
            ? SizedBox(width: thickness, height: theme.type.body, child: ColoredBox(color: color))
            : SizedBox(height: thickness, width: double.infinity, child: ColoredBox(color: color));
      }
      case 'spacer': {
        final size = n.size ?? 0;
        return SizedBox(width: inRow ? size : 0, height: inRow ? 0 : size);
      }
      case 'each': {
        final items = (rendelTemplateRead(data, n.bind!) as List).take(n.max ?? 20).where((item) => _draws(n.child!, item));
        final row = n.isRow;
        if (row) {
          return Wrap(
            spacing: n.gap ?? 0,
            runSpacing: n.gap ?? 0,
            children: [for (final item in items) _TemplateNode(node: n.child!, data: item, dispatch: dispatch, inRow: true)],
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: n.gap ?? 0,
          children: [for (final item in items) _child(n.child!, item, row: false)],
        );
      }
    }
    return const SizedBox.shrink();
  }
}
