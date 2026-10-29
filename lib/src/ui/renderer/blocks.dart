import 'dart:async';
import 'dart:convert' show base64;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show Factory, defaultTargetPlatform, kIsWeb, listEquals;
import 'package:flutter/gestures.dart' show GestureRecognizer, OneSequenceGestureRecognizer, TapGestureRecognizer;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding, SchedulerPhase, Ticker;
import 'package:flutter/services.dart' show LogicalKeyboardKey, StandardMessageCodec;

import '../../engine/conversation_controller.dart'
    show RendelDetail, RendelSubmitOutcome;
import '../../protocol/protocol.dart';
import '../../core/numbers.dart';
import '../../core/strings.dart';
import '../../core/config.dart' show RendelAttachment, RendelAttachSource;
import '../../transport/api_client.dart' show RendelUploadFailure;
import '../theme.dart';
import 'map_engine.dart';
import 'registry.dart';

/// Built-in renderers for the RDUI/1 catalog.
///
/// The catalog is one system, not twenty-one widgets. Eight rules hold
/// everywhere below, and a renderer that breaks one is the renderer that will
/// read as

/// "the one added later":
///
///  1. **Type scale.** Nobody writes a font size. Every string takes a style
///     from `theme.text` — display, title, heading, prose, body, label,
///     caption, overline. One job each. A block's own name is `title`; the
///     one figure the block exists to report is `display`.

///  2. **Spacing scale.** Nobody writes a raw gap. Every gap is a step on
///     `theme.space` (2/4/8/12/16/24), and every plated block is inset by
///     `space.plate`.
///  3. **Motion scale.** Nobody writes a duration or a curve. Every animation
///     the SDK owns reads `theme.motion` and collapses under
///     `MediaQuery.disableAnimationsOf`. Three animations belong to Material
///     rather than to the SDK and are outside that guarantee: the `Switch`
///     thumb, the option sheet's slide-up, and the date and time pickers.
///  4. **Enclosure says whether the copilot is waiting on you.** A **field**
///     of sunk surface with no edge means here is what I found. An **edge**
///     means I am waiting on an answer, and only five blocks have one: `form`,
///     `datetime_slots`, `variant_picker`, `booking_card`, `confirm_card`. A
///     destructive card takes the edge to full ink. Four blocks carry no
///     enclosure at all, because their content already does: `text`,
///     `quick_replies`, `product_cards`, `media_gallery`.
///     A block settles into a field once it has been answered, and a skeleton
///     wears the enclosure its block will hydrate into. See [_enclosureFor].
///  5. **The accent is a promise: it means you can act.** Everything the
///     copilot merely tells you is drawn in ink, so a reader who scans a
///     thread for the accent finds exactly the decisions in it. A chart, a
///     progress bar, a tracker and a streaming caret are all readouts and all
///     carry none of it. At most one accent role per block; several spend
///     nothing. Accent as *text* is `theme.accentText`, the same hue at a
///     legible value.
///
///     The one exception is `status_banner`'s tone glyph, which uses
///     `accentText` for warning and error. A banner has no control in it, so
///     there is nothing for the mark to be confused with, and an urgent
///     notice that is not marked is worse than a rule with an exception in it.

///  6. **Numerals are tabular.** Any price, count, quantity, percentage or
///     timestamp uses a `*Tabular` style, so a figure that updates does not
///     shift the column it sits in.
///  7. **One tap surface.** Anything tappable is an [RendelPressable]: 44pt on
///     both axes, a button role carrying its own tap action and one complete
///     label, press physics, reduced-motion safe. Rows without an action are
///     not pressable and do not claim to be.
///  8. **No casts on props.** Props are whatever the server put on the wire.
///     Every read goes through [_str], [_maps], [_list] or [_dbl], so a block
///     that arrives with a number where a string belonged degrades instead of
///     taking the whole thread down with it.
///
/// Motion is block-atomic. A block draws its typed skeleton the moment the
/// server announces it and hydrates in one step; only `text` streams.

/// The comfortable floor for a finger. Apple and Google both land here.
const double _minTarget = 44;

// ————————————————————————— prop coercion —————————————————————————

/// Props arrive as untyped JSON. A renderer that reads them through `as String`
/// turns one wrong-typed field into a thrown build for the entire thread, so
/// nothing below casts.
String? _str(Object? value) {
  if (value == null) return null;
  if (value is String) return value;
  if (value is Map || value is List) return null;
  return '$value';
}

List<Object?> _list(Object? value) => value is List ? value : const [];

List<Map> _maps(Object? value) => _list(value).whereType<Map>().toList();

Map? _map(Object? value) => value is Map ? value : null;

double? _dbl(Object? value) {
  // Finite or nothing. `double.tryParse` happily returns NaN and Infinity, and
  // a single NaN in a series poisons every scale computed from it — the chart
  // does not draw wrong, it draws nothing.
  final parsed = switch (value) {
    num() => value.toDouble(),
    String() => double.tryParse(value),
    _ => null,
  };
  return (parsed != null && parsed.isFinite) ? parsed : null;
}

// ————————————————————————— text —————————————————————————

Widget buildFallback(BuildContext context, WireBlock block) {
  final theme = RendelThemeScope.of(context);
  return Text(
    block.fallbackText.isEmpty ? '…' : block.fallbackText,
    style: theme.text.prose.copyWith(color: theme.colors.onSurfaceSoft),
  );
}

/// One run of answer text in [style], its inline marks drawn ([_inline]),
/// with the streaming caret after it when more is coming. A widget with
/// state for its links' recognizers, which are its to dispose.
class _Prose extends StatefulWidget {
  const _Prose({
    required this.text,
    required this.style,
    required this.dispatch,
    this.align,
    this.caret = false,
  });

  final String text;
  final TextStyle style;
  final TextAlign? align;

  /// More of the words are coming: a caret after them says so, without a
  /// spinner claiming the whole message is unavailable.
  final bool caret;

  /// Opens a `[words](https://…)` link; one it cannot handle is its words.
  final RendelDispatcher dispatch;

  @override
  State<_Prose> createState() => _ProseState();
}

class _ProseState extends State<_Prose> {
  final _taps = <TapGestureRecognizer>[];

  void _forget() {
    for (final tap in _taps) {
      tap.dispose();
    }
    _taps.clear();
  }

  @override
  void dispose() {
    _forget();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    _forget();
    final inline = _inline(widget.text, base: widget.style, theme: theme, link: (open) {
      if (!widget.dispatch.canHandle(open)) return null;
      final tap = TapGestureRecognizer()..onTap = () => widget.dispatch.onAction(open);
      _taps.add(tap);
      return tap;
    });
    final spans = <InlineSpan>[
      if (inline.spans.isEmpty && !widget.caret) const TextSpan(text: '…') else ...inline.spans,
    ];
    // Ink. The accent is reserved for what the reader can act on, and a
    // cursor is the copilot talking.
    final caret = widget.caret ? _Caret(color: theme.colors.onSurface, height: theme.type.heading) : null;
    // Written at the page's pace while its block is arriving, as a stream or
    // whole (`_Flow`). A block seen before, and every block under reduced
    // motion, is simply there.
    final arriving = _Arriving.of(context);
    if ((arriving != null || widget.caret) && !MediaQuery.disableAnimationsOf(context)) {
      return _WordFlow(
        page: arriving?.page,
        notBefore: arriving?.at,
        spans: spans,
        style: widget.style,
        align: widget.align,
        caret: caret,
        marks: inline.marks,
        mark: theme.mark,
      );
    }
    final drawn = Text.rich(
      TextSpan(children: [...spans, if (caret != null) _caretSpan(caret)]),
      style: widget.style,
      textAlign: widget.align,
    );
    if (inline.marks.isEmpty) return drawn;
    return _Marks(ranges: inline.marks, color: theme.mark, child: drawn);
  }
}

/// [caret] after the words, in the line.
InlineSpan _caretSpan(Widget caret) => WidgetSpan(alignment: PlaceholderAlignment.middle, child: caret);

Widget buildTextBlock(BuildContext context, WireBlock block, RendelDispatcher dispatch) {
  final theme = RendelThemeScope.of(context);
  final page = RendelPage.maybeOf(context);
  final text = block.ready
      ? (_str(block.props['markdown']) ?? block.fallbackText)
      : block.streamingText;
  // The first paragraph of a page is the lede, set larger, and the rest a
  // step smaller than the prose style (`design/PAGES.md`). On a detail it is
  // the summary under the head, centred (`design/DETAIL.md`).
  final lede = page?.lede ?? false;
  final summary = lede && page!.detail;
  final style = summary
      ? theme.text.prose.copyWith(fontSize: 15.5, height: 1.45)
      : lede
          ? theme.text.prose.copyWith(
              fontSize: 21,
              fontWeight: FontWeight.w500,
              height: 1.32,
              letterSpacing: -0.015 * 21,
            )
          : theme.text.prose.copyWith(fontSize: 15, height: 1.5);
  final align = summary ? TextAlign.center : null;

  /* Only the first paragraph is the lede. An answer that ran on was drawn
     whole at 21pt, two paragraphs of headline (Grove report); what follows
     the first reads at the body size under it. */
  final split = lede && !summary ? text.indexOf(RegExp(r'\n\s*\n')) : -1;
  if (split > 0) {
    final rest = text.substring(split).trim();
    if (rest.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Prose(text: text.substring(0, split).trim(), style: style, dispatch: dispatch),
          SizedBox(height: theme.space.md),
          _Prose(
            text: rest,
            style: theme.text.prose.copyWith(fontSize: 15, height: 1.5),
            dispatch: dispatch,
            caret: !block.ready,
          ),
        ],
      );
    }
  }
  final paragraph = _Prose(text: text, style: style, align: align, dispatch: dispatch, caret: !block.ready);
  if (!summary) return paragraph;
  // At most 32 characters wide, and balanced, so two short lines come out
  // even rather than one long line over an orphan.
  return LayoutBuilder(
    builder: (context, box) {
      final scaler = MediaQuery.textScalerOf(context);
      final direction = Directionality.of(context);
      final ch = TextPainter(
        text: TextSpan(text: '0', style: style),
        textDirection: direction,
        textScaler: scaler,
      )..layout();
      final measure = math.min(box.maxWidth, ch.width * 32);
      ch.dispose();
      return Center(
        child: SizedBox(
          width: balancedWidth(
            _inline(text, base: style, theme: theme).plain,
            style,
            measure,
            scaler,
            direction,
          ),
          child: paragraph,
        ),
      );
    },
  );
}

/// The narrowest width that wraps [text] onto as few lines as [max] does, so
/// the lines come out even rather than one long line over an orphan.
double balancedWidth(
  String text,
  TextStyle style,
  double max,
  TextScaler scaler,
  TextDirection direction,
) {
  if (!max.isFinite) return max;
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: direction,
    textScaler: scaler,
    textAlign: TextAlign.center,
  )..layout(maxWidth: max);
  final lines = painter.computeLineMetrics().length;
  var narrow = 0.0;
  var wide = max;
  if (lines > 1) {
    for (var i = 0; i < 12; i++) {
      final middle = (narrow + wide) / 2;
      painter.layout(maxWidth: middle);
      if (painter.computeLineMetrics().length > lines) {
        narrow = middle;
      } else {
        wide = middle;
      }
    }
  }
  painter.dispose();
  return math.min(max, wide.ceilToDouble());
}

/// The inline marks an answer carries, as the web SDK and the console read
/// them (`markdown.ts`): `**bold**`, `*italic*`, `` `code` ``, `~~struck~~`,
/// `[words](https://…)`, and `==phrase==`, the phrase an answer marks.
/// Whitespace just inside a pair does not open or close one, so `a == b`
/// stays an equation and `5 * 3` a product, and a pair left unclosed stays
/// literal. The model is told to write none but the mark; what it wrote
/// anyway arrived as its asterisks (Özlem 2026-10-28, Cilt365).
final RegExp _inlinePattern = RegExp(
  r'\*\*(.+?)\*\*|\*(?!\s)(.+?)\*|`([^`]+)`|~~(.+?)~~|\[([^\]]+)\]\(([^)\s]+)\)|==(?=\S)(.+?)(?<=\S)==',
);

/// [_inline]'s reading of a text: flat spans, each in the style its marks
/// lay over the paragraph's, where the marked phrases fall, and the words
/// with every delimiter taken out.
class _Inline {
  final spans = <TextSpan>[];
  final marks = <TextRange>[];
  var _length = 0;

  String get plain => spans.map((span) => span.text).join();

  void _add(String text, TextStyle? style, GestureRecognizer? tap) {
    if (text.isEmpty) return;
    spans.add(TextSpan(text: text, style: style, recognizer: tap));
    _length += text.length;
  }
}

/// [text] with its inline marks read, for a paragraph set in [base]. A link
/// is live when [link] gives it a recognizer; otherwise, and when the
/// protocol does not read it (https alone), it is its words.
_Inline _inline(
  String text, {
  required TextStyle base,
  required RendelTheme theme,
  TapGestureRecognizer? Function(UIAction open)? link,
}) {
  final out = _Inline();
  void walk(String text, TextStyle? style, GestureRecognizer? tap) {
    TextStyle over(TextStyle more) => style?.merge(more) ?? more;
    var last = 0;
    for (final m in _inlinePattern.allMatches(text)) {
      out._add(text.substring(last, m.start), style, tap);
      last = m.end;
      if (m[1] != null) {
        walk(m[1]!, over(const TextStyle(fontWeight: FontWeight.w700)), tap);
      } else if (m[2] != null) {
        walk(m[2]!, over(const TextStyle(fontStyle: FontStyle.italic)), tap);
      } else if (m[3] != null) {
        out._add(
          m[3]!,
          over(TextStyle(
            fontFamily: 'monospace',
            fontFamilyFallback: const ['Menlo', 'Courier'],
            fontSize: (base.fontSize ?? 14) * 0.88,
          )),
          tap,
        );
      } else if (m[4] != null) {
        walk(m[4]!, over(const TextStyle(decoration: TextDecoration.lineThrough)), tap);
      } else if (m[5] != null) {
        final open = UIAction.tryParse({'kind': 'open_url', 'url': m[6]});
        final live = open == null ? null : link?.call(open);
        walk(
          m[5]!,
          live == null
              ? style
              : over(TextStyle(decoration: TextDecoration.underline, decorationColor: theme.colors.lineStrong)),
          live ?? tap,
        );
      } else {
        final start = out._length;
        walk(m[7]!, style, tap);
        out.marks.add(TextRange(start: start, end: out._length));
      }
    }
    out._add(text.substring(last), style, tap);
  }

  walk(text, null, null);
  return out;
}

/// Paints the mark behind each marked phrase of the paragraph below it: the
/// theme's mark role, a 6pt corner, 0.12em past each end, and a piece of its
/// own on every line the phrase wraps onto (box-decoration clone).
///
/// Painted from the laid-out paragraph rather than as a `TextSpan`
/// background, which has no corner and paints the line's full height, and
/// rather than as a `WidgetSpan`, which cannot wrap.
class _Marks extends SingleChildRenderObjectWidget {
  const _Marks({required this.ranges, required this.color, this.alphas, required super.child});

  final List<TextRange> ranges;
  final Color color;

  /// How far in each mark is, one per range, while its words are arriving
  /// (`_WordFlow`): a mark no fainter than the words it sits behind. Null
  /// once they are all in.
  final List<double>? alphas;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderMarks(ranges, color, alphas);

  @override
  void updateRenderObject(BuildContext context, _RenderMarks renderObject) {
    renderObject
      ..ranges = ranges
      ..color = color
      ..alphas = alphas;
  }
}

class _RenderMarks extends RenderProxyBox {
  _RenderMarks(this._ranges, this._color, this._alphas);

  List<TextRange> _ranges;
  set ranges(List<TextRange> value) {
    _ranges = value;
    markNeedsPaint();
  }

  List<double>? _alphas;
  set alphas(List<double>? value) {
    if (listEquals(value, _alphas)) return;
    _alphas = value;
    markNeedsPaint();
  }

  Color _color;
  set color(Color value) {
    if (value == _color) return;
    _color = value;
    markNeedsPaint();
  }

  RenderParagraph? get _paragraph {
    RenderObject? node = child;
    while (node != null && node is! RenderParagraph) {
      node = node is RenderObjectWithChildMixin ? node.child : null;
    }
    return node as RenderParagraph?;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final paragraph = _paragraph;
    if (paragraph != null && paragraph.hasSize) {
      final root = paragraph.text;
      final size = paragraph.textScaler.scale(
        (root is TextSpan ? root.style?.fontSize : null) ?? 14,
      );
      final reach = size * 0.12;
      final paint = Paint()..color = _color;
      final transform = paragraph.getTransformTo(this);
      for (var i = 0; i < _ranges.length; i++) {
        final range = _ranges[i];
        final alpha = _alphas == null || i >= _alphas!.length ? 1.0 : _alphas![i];
        if (alpha <= 0) continue;
        paint.color = _color.withValues(alpha: _color.a * alpha);
        final boxes = paragraph.getBoxesForSelection(
          TextSelection(baseOffset: range.start, extentOffset: range.end),
        );
        // One piece per line: a run split into several boxes on the same line
        // is joined, so it does not show seams.
        final lines = <Rect>[];
        for (final box in boxes) {
          final rect = box.toRect();
          final same = lines.indexWhere(
            (line) => (line.center.dy - rect.center.dy).abs() < rect.height / 2,
          );
          if (same == -1) {
            lines.add(rect);
          } else {
            lines[same] = lines[same].expandToInclude(rect);
          }
        }
        for (final line in lines) {
          final rect = MatrixUtils.transformRect(transform, line).shift(offset);
          context.canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTRB(rect.left - reach, rect.top, rect.right + reach, rect.bottom),
              const Radius.circular(6),
            ),
            paint,
          );
        }
      }
    }
    super.paint(context, offset);
  }
}

class _Caret extends StatefulWidget {
  const _Caret({required this.color, required this.height});
  final Color color;
  final double height;

  @override
  State<_Caret> createState() => _CaretState();
}

class _CaretState extends State<_Caret> with SingleTickerProviderStateMixin {
  // Created without touching the theme. Reading an inherited widget from a
  // `late final` initialiser is a trap in both directions: evaluated during
  // initState it asserts, and evaluated from dispose (which is what happens
  // when reduced motion makes build return before ever touching the field) it
  // looks up a deactivated ancestor. The duration arrives in
  // didChangeDependencies, which is the one callback where the lookup is both
  // legal and correct when the theme changes.
  late final AnimationController _blink = AnimationController(vsync: this);

  // The caret and the skeleton breath are the two most common motions on
  // screen, so they must not say the same thing: this one is faster and drops
  // further.
  late final Animation<double> _fade =
      Tween<double>(begin: 0.15, end: 0.99).animate(_blink);

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _blink.duration = RendelThemeScope.of(context).motion.caret;
    if (_started) return;
    _started = true;
    _blink.repeat(reverse: true);
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final caret = Container(
      width: 2,
      height: widget.height,
      margin: const EdgeInsetsDirectional.only(start: 3),

      color: widget.color,
    );
    // A blinking caret under reduced motion is exactly the flicker the setting
    // exists to remove; hold it solid instead of dropping the affordance.
    if (MediaQuery.disableAnimationsOf(context)) return caret;
    // Its own layer. An opacity that changes every frame marks needs-paint all
    // the way up to the nearest repaint boundary, and the nearest one here is
    // the whole block — so without this the entire streaming paragraph is
    // re-rasterised sixty times a second for the length of every answer.
    return RepaintBoundary(
      child: FadeTransition(opacity: _fade, child: caret),
    );
  }
}

// ————————————————————————— chips & cards —————————————————————————

/* Pills in a row, or cards at the foot of a page.

   A few words fit in a pill. A page ends here, with nothing below but the
   composer — so a whole question fits, and a row carrying one is a card
   rather than a pill. Which it is follows the block: the server sends a
   heading and icons for the way on. */
Widget buildQuickReplies(BuildContext context, WireBlock block, RendelDispatcher dispatch) {
  final theme = RendelThemeScope.of(context);
  final items = _maps(block.props['items']);
  if (items.isEmpty) return buildFallback(context, block);
  final title = _str(block.props['title']);
  final asCards = title != null || items.any((item) => _str(item['icon']) != null);

  if (!asCards) {
    return Wrap(
      spacing: theme.space.sm,
      runSpacing: theme.space.sm,
      children: [
        for (final item in items)
          RendelChip(
            label: _str(item['label']) ?? '',
            onTap: _tap(dispatch, item['action']),
          ),
      ],
    );
  }

  return _WayOn(
    title: title,
    inset: RendelPage.maybeOf(context)?.inset ?? 0,
    items: [
      for (final item in items)
        _WayOnCard(
          label: _str(item['label']) ?? '',
          icon: _str(item['icon']),
          onTap: _tap(dispatch, item['action']),
        ),
    ],
  );
}

/// The foot of an answer page (`design/PAGES.md`): a hairline the width of
/// the screen, the heading centred under it, then the questions as cards.
class _WayOn extends StatelessWidget {
  const _WayOn({required this.title, required this.inset, required this.items});

  final String? title;
  final double inset;
  final List<Widget> items;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Out through the page's padding to both edges.
        Positioned(
          left: -inset,
          right: -inset,
          top: 0,
          height: 1,
          child: ColoredBox(color: theme.hairline),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null) ...[
                Semantics(
                  header: true,
                  child: Text(
                    title!,
                    textAlign: TextAlign.center,
                    style: theme.text.title.copyWith(fontSize: 17, letterSpacing: -0.17),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                items[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// One whole question to go on with: the words, the item's mark on a round
/// of the mark role, and the arrow that says tapping it asks.
class _WayOnCard extends StatelessWidget {
  const _WayOnCard({required this.label, this.icon, this.onTap});

  final String label;

  /// One emoji, or a catalog icon name.
  final String? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final glyph = _iconFor(icon);
    final card = Container(
      constraints: const BoxConstraints(minHeight: 72),
      padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 14, 12),
      decoration: BoxDecoration(
        color: theme.colors.surfaceRaised,
        border: Border.all(color: theme.hairline),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: theme.colors.shadow.withValues(alpha: 0.45),
            offset: const Offset(0, 12),
            blurRadius: 26,
            spreadRadius: -20,
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.text.label.copyWith(fontSize: 14.5, height: 1.35),
            ),
          ),
          if (icon != null && icon!.isNotEmpty) ...[
            const SizedBox(width: 10),
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: theme.mark, shape: BoxShape.circle),
              child: glyph != null
                  ? Icon(glyph, size: 22, color: theme.colors.onSurface)
                  : Text(icon!, style: const TextStyle(fontSize: 22)),
            ),
          ],
          const SizedBox(width: 10),
          Icon(
            Icons.arrow_forward_rounded,
            size: 16,
            color: theme.colors.onSurfaceSoft,
          ),
        ],
      ),
    );
    if (onTap == null) {
      return Semantics(label: label, excludeSemantics: true, child: card);
    }
    return RendelPressable(semanticLabel: label, onTap: onTap, child: card);
  }
}

Widget buildInfoCard(BuildContext context, WireBlock block, RendelDispatcher dispatch) {
  final theme = RendelThemeScope.of(context);
  final cta = _map(block.props['cta']);
  // Up to three quiet buttons, and when there are any the CTA is not drawn:
  // a lit button over three quiet ones is two answers to one question.
  final actions = _maps(block.props['actions']).take(3).toList();
  final avatar = _str(block.props['avatar_url']);
  final picture = _str(block.props['image_url']);
  final file = _str(block.props['file_type']);
  // A person is their picture, round; a product its photograph, whole; a
  // document its type. Each takes the icon's place.
  final Widget? lead = avatar != null
      ? _Thumbnail(url: avatar, width: 44, height: 44, radius: 22)
      : picture != null
          ? _Thumbnail(
              url: picture,
              width: theme.size.cardRowImage,
              height: theme.size.cardRowImage,
              radius: theme.radius.sm,
              fit: BoxFit.contain,
            )
          : file != null && _fileTypes.contains(file)
              ? _FileBadge(type: file, size: 34)
              : null;
  return _Plate(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _IconLede(
          icon: _iconFor(_str(block.props['icon'])),
          lead: lead,
          title: _str(block.props['title']) ?? block.fallbackText,
          // The same line twice ("Red scooter · 7HG 21" as both, Grove
          // report P2-3) is drawn once.
          meta: _str(block.props['meta']) == _str(block.props['body'])
              ? null
              : _str(block.props['meta']),
          body: _str(block.props['body']),
        ),
        if (actions.isNotEmpty) ...[
          SizedBox(height: theme.space.lg),
          Row(
            children: [
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) SizedBox(width: theme.space.sm),
                Expanded(
                  child: _actionButton(
                    context,
                    label: _str(actions[i]['label']) ?? '',
                    action: actions[i]['action'],
                    dispatch: dispatch,
                    quiet: true,
                    expand: true,
                  ),
                ),
              ],
            ],
          ),
        ] else if (cta != null) ...[
          SizedBox(height: theme.space.lg),
          _actionButton(
            context,
            label: _str(cta['label']) ?? RendelStringsScope.of(context).open,
            action: cta['action'],
            dispatch: dispatch,
            part: 'button',
            expand: true,
          ),
        ],
      ],
    ),
  );
}

/// Icon, title, optional body. `info_card` and `status_banner` are the same
/// shape and used to solve it twice with three arbitrary differences in gap,
/// title weight and lead spacing; this is the one answer.
class _IconLede extends StatelessWidget {
  const _IconLede({
    required this.icon,
    required this.title,
    required this.body,
    this.iconColor,
    this.lead,
    this.meta,
  });

  final IconData? icon;
  final String title;
  final String? body;
  final Color? iconColor;

  /// Drawn in the icon's place: a person's picture, a document's type.
  final Widget? lead;

  /// One quiet line under the title: "PDF · 120 KB", "White Egea · 34 ABC 123".
  final String? meta;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // v6: the glyph sits on its tile.
        if (lead != null) ...[
          lead!,
          SizedBox(width: theme.space.md),
        ] else if (icon != null) ...[
          _GlyphTile(icon: icon!, color: iconColor),
          SizedBox(width: theme.space.md),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.part('title', theme.text.title)),
              if (meta != null && meta!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  meta!,
                  style: theme.text.caption.copyWith(fontSize: 13, color: theme.colors.onSurfaceSoft),
                ),
              ],

              if (body != null) ...[
                SizedBox(height: theme.space.xs),
                Text(body!, style: theme.part('body', theme.text.body)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

Widget buildItemList(BuildContext context, WireBlock block, RendelDispatcher dispatch) {
  final theme = RendelThemeScope.of(context);
  final items = _maps(block.props['items']);
  if (items.isEmpty) return _EmptyPlate(message: block.fallbackText);
  // Flat on a page, the rows line up with the text above them.
  final flat = RendelPage.maybeOf(context)?.flat ?? false;
  final inset = flat ? 0.0 : theme.space.plate;
  // One rank in the list gives every row the column, so the titles still
  // line up.
  final ranked = items.any((item) => _dbl(item['rank']) != null);

  /// What ends the row: an amount in place of `trailing`, signed by its tone.
  String? valueOf(Map item) {
    final amount = _map(item['amount']);
    return amount == null ? _str(item['trailing']) : _signed(amount);
  }

  Widget row(Map item) {
    final image = _str(item['image_url']);
    final file = _str(item['file_type']);
    final subtitle = _str(item['subtitle']);
    final date = _str(item['date_label']);
    final value = valueOf(item);
    final tone = _str(_map(item['amount'])?['tone']);
    final status = _map(item['status']);
    final statusLabel = _str(status?['label']);
    final rank = _dbl(item['rank'])?.round();
    final content = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: inset,
        vertical: theme.space.md,
      ),
      child: Row(
        children: [
          if (ranked) ...[
            SizedBox(
              width: 24,
              child: Text(
                rank == null ? '' : '$rank',
                style: theme.text.labelSoftTabular.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            SizedBox(width: theme.space.sm),
          ],
          // A document is its type, in the picture's place.
          if (file != null && _fileTypes.contains(file)) ...[
            _FileBadge(type: file, size: theme.size.rowThumb),
            SizedBox(width: theme.space.md),
          ] else if (image != null) ...[
            _Thumbnail(
              url: image,
              width: theme.size.rowThumb,
              height: theme.size.rowThumb,
            ),
            SizedBox(width: theme.space.md),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (date != null && date.isNotEmpty) ...[
                  Text(
                    date,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.text.captionTabular.copyWith(
                      fontSize: 12.5,
                      color: theme.colors.onSurfaceSoft,
                    ),
                  ),
                  SizedBox(height: theme.space.hair / 2),
                ],
                Text(
                  _str(item['title']) ?? '',
                  style: theme.part('title', theme.text.label),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null) ...[
                  SizedBox(height: theme.space.hair),
                  Text(
                    subtitle,
                    style: theme.part('subtitle', theme.text.caption),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (value != null || statusLabel != null) ...[
            SizedBox(width: theme.space.md),
            // Capped, not flexed. Unbounded it overflows the row on a 320pt
            // phone; given a flex share it takes half the row and wraps the
            // title for the sake of a price.
            _TrailingSlot(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (value != null)
                    Text(
                      value,
                      style: theme.part(
                        'trailing',
                        // A signed amount is the ink, a gain a step heavier;
                        // a neutral one, like any trailing value, the soft
                        // ink.
                        switch (tone) {
                          'positive' => theme.text.labelTabular.copyWith(fontWeight: FontWeight.w600),
                          'negative' => theme.text.labelTabular,
                          _ => theme.text.labelSoftTabular,
                        },
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (statusLabel != null) ...[
                    if (value != null) SizedBox(height: theme.space.xs),
                    _TonePill(label: statusLabel, tone: _str(status?['tone'])),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
    if (item['highlight'] != true) return content;
    // The user's own row in a ranking, on the mark at 40%. Out past the text
    // on a page, so the row's words still line up with the others'; inside
    // the plate's inset anywhere else.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: 0,
          bottom: 0,
          left: flat ? -theme.space.sm : theme.space.sm,
          right: flat ? -theme.space.sm : theme.space.sm,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.mark.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(theme.radius.card),
            ),
          ),
        ),
        content,
      ],
    );
  }

  Widget pressable(Map item) {
    final value = valueOf(item);
    final label = _joinParts([
      if (_dbl(item['rank']) case final rank?) '${rank.round()}',
      _str(item['title']),
      _str(item['date_label']),
      _str(item['subtitle']),
      value,
      _str(_map(item['status'])?['label']),
    ]);
    // On a page the item opens over it (`design/DETAIL.md`).
    final open = _opens(context, item, price: value);
    if (open != null) {
      return RendelPressable(semanticLabel: label, onTap: open, child: row(item));
    }
    return _maybePressable(
      action: item['action'],
      dispatch: dispatch,
      semanticLabel: label,
      child: row(item),
    );
  }

  return _Plate(
    padding: EdgeInsets.zero,
    child: _Fold(
      count: items.length,
      limit: 8,
      builder: (context, shown, more) {
        final children = <Widget>[];
        String? group;
        for (var i = 0; i < shown; i++) {
          // Consecutive rows of one group share a heading; the row under a
          // heading draws no line above it.
          final next = _str(items[i]['group']);
          final heads = next != null && next.isNotEmpty && next != group;
          group = next;
          if (heads) {
            children.add(
              Padding(
                padding: EdgeInsetsDirectional.fromSTEB(
                  inset,
                  i == 0 ? (flat ? 0 : theme.space.md) : theme.space.lg,
                  inset,
                  theme.space.xs,
                ),
                child: Semantics(header: true, child: RendelOverline(next)),
              ),
            );
          }
          children.add(_Divided(first: i == 0 || heads, child: pressable(items[i])));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...children,
            if (more != null)
              Padding(
                padding: EdgeInsetsDirectional.fromSTEB(
                  inset,
                  theme.space.sm,
                  inset,
                  flat ? 0 : theme.space.plate,
                ),
                child: more,
              ),
          ],
        );
      },
    ),
  );
}

/// An amount as its tone says it: a gain with its "+", a loss with a true
/// minus, a neutral one as written. The sign carries the meaning, so it is
/// never left to a colour.
String _signed(Map amount) {
  final value = (_str(amount['value']) ?? '').trim();
  switch (_str(amount['tone'])) {
    case 'positive':
      return value.startsWith('+') ? value : '+$value';
    case 'negative':
      if (value.startsWith('−')) return value;
      if (value.startsWith('-')) return '−${value.substring(1)}';
      return '−$value';
  }
  return value;
}

/// A long list shown to its first [limit] rows, the rest behind one quiet
/// "Show N more". The SDK's own behaviour rather than a prop: twenty rows
/// read as a list once eight of them have been read.
class _Fold extends StatefulWidget {
  const _Fold({required this.count, required this.limit, required this.builder});

  final int count;
  final int limit;

  /// Draws the first [shown] rows, with [more] under them while some are
  /// held back.
  final Widget Function(BuildContext context, int shown, Widget? more) builder;

  @override
  State<_Fold> createState() => _FoldState();
}

class _FoldState extends State<_Fold> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final shown = _open ? widget.count : math.min(widget.count, widget.limit);
    final held = widget.count - shown;
    return widget.builder(
      context,
      shown,
      held > 0
          ? RendelActionButton(
              label: RendelStringsScope.of(context).showMoreCount(held),
              onTap: () => setState(() => _open = true),
              quiet: true,
              expand: true,
            )
          : null,
    );
  }
}

/// A review score, as five stars and the number that made them.
///
/// Ink rather than the accent, which is the system's rule rather than a
/// preference: the accent is reserved for what the reader can act on, and a
/// rating is a readout. The order tracker marks its current step the same way.
///
/// The filled copy is clipped to the score rather than rounded to whole
/// stars. 4.7 is not 5 and not 4, and rounding it away is the one thing a
/// rating must not do.
class _Stars extends StatelessWidget {
  const _Stars({required this.rating, this.count});

  final double rating;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final clamped = rating.clamp(0.0, 5.0);
    // The stars and the words beside them are two parts of a product card.
    final style = theme.part('stars', theme.text.caption.copyWith(letterSpacing: 0.6, height: 1));
    final star = theme.parts['stars']?.color ?? theme.colors.onSurface;
    final strings = RendelStringsScope.of(context);
    final said = rendelNumber(clamped, strings.numberLocale, digits: 1);
    final reviews = count == null ? null : rendelNumber(count!, strings.numberLocale, digits: 0);
    final label = reviews == null
        ? strings.ratingStars.replaceAll('{n}', said)
        : strings.ratingFromOf(said, reviews);

    return Semantics(
      label: label,
      // A readout of fixed glyphs cannot wrap, so on a card a few points too
      // narrow for it ("★★★★ 3.9 (109)" on a 2-up row, Grove report P1-1) it
      // shrinks to fit instead of overflowing.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerStart,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              children: [
                Text(
                  '★★★★★',
                  style: style.copyWith(
                    color: star.withValues(alpha: 0.25),
                  ),
                ),
                ClipRect(
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    widthFactor: clamped / 5,
                    child: Text(
                      '★★★★★',
                      style: style.copyWith(color: star),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(width: theme.space.xs),
            Text(
              reviews == null ? said : '$said ($reviews)',
              style: theme.part('reviews', theme.text.caption),
            ),
          ],
        ),
      ),
    );
  }
}

Widget buildProductCards(BuildContext context, WireBlock block, RendelDispatcher dispatch) {
  final theme = RendelThemeScope.of(context);
  final items = _maps(block.props['items']);
  if (items.isEmpty) return buildFallback(context, block);

  final style = theme.style.product;
  // v6: the card is the plate's glass at a card's corner, with the plate's
  // hairline and a shorter shadow under the default build.
  final decoration = BoxDecoration(
    color: theme.glass,
    border: _cardEdge(theme, Border.all(color: theme.hairline)),
    borderRadius: BorderRadius.circular(theme.cardRadius),
    boxShadow: _cardShadow(theme, theme.cardShadow),
  );

  // The words on a card, the same three ways round. A row ends its line with
  // the price instead, and sets its lines a step closer.
  List<Widget> details(Map item, {required double gap, bool price = true}) {
    final badge = _str(item['badge']);
    final subtitle = _str(item['subtitle']);
    final amount = price ? _str(item['price']) : null;
    final rating = _dbl(item['rating']);
    final ratingCount = _dbl(item['rating_count'])?.round();
    final chips = _productChips(item);
    return [
      // The badge is the only accent this block spends. Painted in the
      // legible form of the accent, because it is text.
      if (badge != null && badge.isNotEmpty) ...[
        RendelOverline(badge, color: theme.accentText, part: 'badge'),
        SizedBox(height: gap),
      ],
      Text(
        _str(item['title']) ?? '',
        // Three lines: a brand-first name ("INNER GOODNESS Regular Soy Milk
        // 1L") lost the product itself at two (Grove report).
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: theme.part('title', theme.text.label),
      ),
      if (subtitle != null) ...[
        SizedBox(height: theme.space.hair),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.part('subtitle', theme.text.caption),
        ),
      ],
      if (chips.isNotEmpty) ...[
        SizedBox(height: gap + theme.space.hair),
        _FactChips(chips),
      ],
      if (rating != null) ...[
        SizedBox(height: gap),
        _Stars(rating: rating, count: ratingCount),
      ],
      if (amount != null) ...[
        SizedBox(height: gap),
        Text(amount, style: theme.part('price', theme.text.labelSoftTabular)),
      ],
    ];
  }

  Widget card(Map item) => switch (style) {
        RendelProductStyle.tile => Container(
            width: theme.size.cardWidth,
            padding: EdgeInsets.all(theme.space.plate),
            decoration: decoration,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Thumbnail(
                  url: _str(item['image_url']),
                  width: theme.size.cardImageWidth,
                  height: theme.size.cardImageHeight,
                  fit: BoxFit.contain,
                ),
                SizedBox(height: theme.space.sm),
                ...details(item, gap: theme.space.xs),
              ],
            ),
          ),
        RendelProductStyle.row => Container(
            width: double.infinity,
            padding: EdgeInsets.all(theme.space.md),
            decoration: decoration,
            child: Row(
              children: [
                _Thumbnail(
                  url: _str(item['image_url']),
                  width: theme.size.cardRowImage,
                  height: theme.size.cardRowImage,
                  radius: theme.radius.sm,
                  fit: BoxFit.contain,
                ),
                SizedBox(width: theme.space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: details(item, gap: theme.space.hair, price: false),
                  ),
                ),
                if (_str(item['price']) case final price?) ...[
                  SizedBox(width: theme.space.md),
                  _TrailingSlot(
                    child: Text(
                      price,
                      style: theme.part('price', theme.text.labelSoftTabular),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
        // The photograph runs to the card's edge, so the card clips it and
        // only its top corners are rounded.
        RendelProductStyle.photo => Container(
            width: double.infinity,
            clipBehavior: Clip.antiAlias,
            decoration: decoration,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Thumbnail(
                  url: _str(item['image_url']),
                  height: theme.size.cardPhotoHeight,
                  radius: 0,
                ),
                Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(
                    theme.space.md + theme.space.hair,
                    theme.space.md,
                    theme.space.md + theme.space.hair,
                    theme.space.md + theme.space.hair,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: details(item, gap: theme.space.xs),
                  ),
                ),
              ],
            ),
          ),
      };

  Widget wrapped(Map item) {
    // The pressable excludes its subtree, so a field left out of this join
    // exists nowhere for a screen reader. `subtitle` is the colour or the
    // variant — the thing that tells two otherwise identical cards apart.
    final label = _joinParts([
      _str(item['title']),
      _str(item['subtitle']),
      ..._productChips(item),
      _str(item['badge']),
      // The pressable excludes its subtree, so the stars' own Semantics
      // node is invisible to a screen reader once the card is tappable.
      if (_dbl(item['rating']) case final score?)
        RendelStringsScope.of(context)
            .ratingStars
            .replaceAll('{n}', rendelNumber(score, RendelStringsScope.of(context).numberLocale, digits: 1)),
      _str(item['price']),
    ]);
    // On a page the card opens over it (`design/DETAIL.md`).
    final open = _opens(context, item, price: _str(item['price']));
    if (open != null) {
      return RendelPressable(semanticLabel: label, onTap: open, child: card(item));
    }
    return _maybePressable(
      action: item['action'],
      dispatch: dispatch,
      semanticLabel: label,
      child: card(item),
    );
  }

  // A list rather than a rail: each card takes the width of the thread.
  if (style != RendelProductStyle.tile) {
    return Column(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) SizedBox(height: theme.space.sm),
          wrapped(items[i]),
        ],
      ],
    );
  }

  if (items.length == 1) {
    // The multi-card rail mirrors; a single card used to stay put.
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: wrapped(items.first),
    );

  }
  return _Rail(
    itemWidth: theme.size.cardWidth,
    children: [for (final item in items) wrapped(item)],
  );
}

// ————————————————————————— confirmation —————————————————————————

Widget buildConfirmCard(BuildContext context, WireBlock block, RendelDispatcher dispatch) {
  // The card carries its own deadline, so it has to watch it. The controller
  // already refuses an expired invocation, so without this the user presses a
  // full-ink accent button and nothing whatsoever happens.
  return _ExpiryWatch(
    at: DateTime.tryParse(_str(block.props['expires_at']) ?? ''),
    builder: (context, expired) {
      final open = !expired && _str(block.props[RendelLocalKeys.resolved]) == null;
      // A value typed back and a long text read whole (P0.2): held by
      // `_ConfirmExtras` while the card waits.
      final asks = _typedValueOf(block) != null || _fullTextOf(block) != null;
      Widget card(_CardEditsState? edits) => asks
          ? _ConfirmExtras(
              block: block,
              dispatch: dispatch,
              open: open,
              builder: (context, extras) => _confirmCard(context, block, dispatch, expired, edits, extras),
            )
          : _confirmCard(context, block, dispatch, expired, edits, null);
      // Values the user may change here, while the card waits for an answer
      // and something can send the change (`_CardEdits`).
      if (!open || dispatch.onEditCard == null || _maps(block.props['editable']).isEmpty) {
        return card(null);
      }
      return _CardEdits(
        block: block,
        dispatch: dispatch,
        builder: (context, edits) => card(edits),
      );
    },
  );
}

// ——— typed confirmation and full text (rendel-in-console P0.2) ———

/// How much of a long text a card shows before "Read all".
const int fullTextPreview = 400;

/// The "Suggested after reading …" line on a card drawn after reading what
/// a customer or a third party wrote.
const bool showSuggestedAfter = true;

String? _typedValueOf(WireBlock block) {
  final ask = block.props['type_to_confirm'];
  final value = ask is Map ? ask['value'] : null;
  return value is String && value.trim().isNotEmpty ? value : null;
}

String? _fullTextOf(WireBlock block) {
  final full = block.props['full_text'];
  final value = full is Map ? full['value'] : null;
  return value is String ? value : null;
}

/// A value the card asks the user to type back, and a long text it carries
/// whole, with what changes. The button arms on an exact match (spaces
/// trimmed) and once all of the text was opened. Kept in the block's props,
/// so a redraw keeps what was typed and read.
class _ConfirmExtras extends StatefulWidget {
  const _ConfirmExtras({required this.block, required this.dispatch, required this.open, required this.builder});

  final WireBlock block;
  final RendelDispatcher dispatch;
  final bool open;
  final Widget Function(BuildContext context, _ConfirmExtrasState extras) builder;

  @override
  State<_ConfirmExtras> createState() => _ConfirmExtrasState();
}

class _ConfirmExtrasState extends State<_ConfirmExtras> {
  Map<String, dynamic> get _props => widget.block.props;
  late final TextEditingController _typed = TextEditingController(text: _props[RendelLocalKeys.typed] as String? ?? '');

  String? get _expected => _typedValueOf(widget.block);
  String? get _full => _fullTextOf(widget.block);
  bool get read => _full == null || _full!.length <= fullTextPreview || _props[RendelLocalKeys.read] == true;
  bool get matches => _expected == null || _typed.text.trim() == _expected!.trim();
  bool get armed => matches && read;

  /// What goes with the confirm when the card asks for a typed value.
  String? get typedValue => _expected == null ? null : _typed.text.trim();

  @override
  void initState() {
    super.initState();
    final full = _full;
    final source = widget.dispatch.cardSource;
    if (full != null && widget.open && source != null && !_props.containsKey(RendelLocalKeys.current)) {
      final params = _props['params'] is Map ? Map<String, dynamic>.from(_props['params'] as Map) : <String, dynamic>{};
      final pending = source(_str(_props['action_name']) ?? '', params);
      if (pending != null) {
        unawaited(pending.then((text) {
          if (!mounted) return;
          setState(() => _props[RendelLocalKeys.current] = text);
        }));
      }
    }
  }

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  List<Widget> parts(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final strings = RendelStringsScope.of(context);
    final full = _full;
    final expected = _expected;
    return [
      if (full != null) ...[
        SizedBox(height: theme.space.md),
        Container(
          width: double.infinity,
          constraints: BoxConstraints(maxHeight: read ? 360 : double.infinity),
          padding: EdgeInsets.symmetric(horizontal: theme.space.md, vertical: theme.space.sm),
          decoration: BoxDecoration(color: theme.colors.surfaceHigh, borderRadius: BorderRadius.circular(14)),
          child: read
              ? SingleChildScrollView(child: Text(full, style: theme.text.body))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${full.substring(0, fullTextPreview).trimRight()}…', style: theme.text.body),
                    SizedBox(height: theme.space.xs),
                    RendelActionButton(
                      label: strings.readAllOf('${full.length}'),
                      quiet: true,
                      onTap: () => setState(() => _props[RendelLocalKeys.read] = true),
                    ),
                  ],
                ),
        ),
        if (_props.containsKey(RendelLocalKeys.current)) ...[
          SizedBox(height: theme.space.sm),
          if (_props[RendelLocalKeys.current] is String)
            _Diff(before: _props[RendelLocalKeys.current] as String, after: full, title: strings.changes)
          else
            Text(strings.currentUnavailable, style: theme.text.caption),
        ],
      ],
      if (expected != null && widget.open) ...[
        SizedBox(height: theme.space.md),
        Text(strings.typeToConfirmFor(expected), style: theme.text.caption),
        SizedBox(height: theme.space.xs),
        TextField(
          controller: _typed,
          autocorrect: false,
          enableSuggestions: false,
          style: theme.text.body.copyWith(fontFamily: 'monospace', color: theme.colors.onSurface),
          onChanged: (text) => setState(() {
            _props[RendelLocalKeys.typed] = text;
            _props.remove(RendelLocalKeys.mismatch);
          }),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: theme.space.sm, vertical: theme.space.xs + 2),
            filled: true,
            fillColor: theme.colors.surfaceHigh,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: theme.hairline)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: theme.hairline)),
          ),
        ),
        if (_props[RendelLocalKeys.mismatch] == true) ...[
          SizedBox(height: theme.space.xs),
          Semantics(
            liveRegion: true,
            child: Text(strings.typedMismatch, style: theme.text.caption.copyWith(color: theme.danger)),
          ),
        ],
      ],
      if (!read && widget.open) ...[
        SizedBox(height: theme.space.sm),
        Text(strings.readToConfirm, style: theme.text.caption.copyWith(color: theme.colors.onSurfaceFaint)),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, this);
}

/// The lines that change from [before] to [after], under [title].
class _Diff extends StatelessWidget {
  const _Diff({required this.before, required this.after, required this.title});

  final String before;
  final String after;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final mono = theme.text.caption.copyWith(fontFamily: 'monospace', height: 1.45);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.text.labelStrong),
        SizedBox(height: theme.space.xs),
        for (final (kind, line) in lineDiff(before, after))
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: switch (kind) {
                'add' => theme.colors.accent.withValues(alpha: 0.14),
                'del' => theme.danger.withValues(alpha: 0.12),
                _ => null,
              },
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${switch (kind) { 'add' => '+', 'del' => '−', _ => ' ' }} $line',
              style: kind == 'del' ? mono.copyWith(decoration: TextDecoration.lineThrough) : mono,
            ),
          ),
      ],
    );
  }
}

/// The lines that change from [before] to [after] (`add`, `del`, `same`),
/// unchanged lines far from a change folded away, as the web SDK does.
List<(String, String)> lineDiff(String before, String after) {
  final a = before.split('\n');
  final b = after.split('\n');
  if (a.length * b.length > 400000) {
    final kept = a.toSet();
    final now = b.toSet();
    return [for (final l in a) if (!now.contains(l)) ('del', l), for (final l in b) if (!kept.contains(l)) ('add', l)];
  }
  final lcs = List.generate(a.length + 1, (_) => List.filled(b.length + 1, 0));
  for (var i = a.length - 1; i >= 0; i--) {
    for (var j = b.length - 1; j >= 0; j--) {
      lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1 : (lcs[i + 1][j] >= lcs[i][j + 1] ? lcs[i + 1][j] : lcs[i][j + 1]);
    }
  }
  final out = <(String, String)>[];
  var i = 0;
  var j = 0;
  while (i < a.length && j < b.length) {
    if (a[i] == b[j]) {
      out.add(('same', a[i]));
      i++;
      j++;
    } else if (lcs[i + 1][j] >= lcs[i][j + 1]) {
      out.add(('del', a[i++]));
    } else {
      out.add(('add', b[j++]));
    }
  }
  while (i < a.length) {
    out.add(('del', a[i++]));
  }
  while (j < b.length) {
    out.add(('add', b[j++]));
  }
  bool near(int k) {
    for (var x = k - 2; x <= k + 2; x++) {
      if (x >= 0 && x < out.length && out[x].$1 != 'same') return true;
    }
    return false;
  }

  return [for (var k = 0; k < out.length; k++) if (out[k].$1 != 'same' || near(k)) out[k]];
}

/// What the user changed on a confirmation card, not yet redrawn by the
/// server: held here, sent after a short pause (`RendelDispatcher.onEditCard`),
/// and dropped once the server has redrawn the card with it. While a change
/// is waiting, on its way or refused, the card cannot be confirmed: the card
/// confirmed is always the one the server drew last.
class _CardEdits extends StatefulWidget {
  const _CardEdits({required this.block, required this.dispatch, required this.builder});

  final WireBlock block;
  final RendelDispatcher dispatch;
  final Widget Function(BuildContext context, _CardEditsState edits) builder;

  @override
  State<_CardEdits> createState() => _CardEditsState();
}

class _CardEditsState extends State<_CardEdits> {
  final Map<String, dynamic> _pending = {};
  Map<String, String> errors = const {};
  bool _sending = false;
  Timer? _timer;

  /// The value shown for [param]: the user's while it is waiting, the
  /// card's otherwise.
  dynamic valueOf(String param) => _pending.containsKey(param)
      ? _pending[param]
      : (widget.block.props['params'] is Map ? (widget.block.props['params'] as Map)[param] : null);

  bool get blocked => _sending || _pending.isNotEmpty || errors.isNotEmpty;

  void change(String param, dynamic value, {Duration wait = const Duration(milliseconds: 450)}) {
    setState(() {
      _pending[param] = value;
      errors = {...errors}..remove(param)..remove('');
    });
    _timer?.cancel();
    _timer = Timer(wait, _send);
  }

  Future<void> _send() async {
    if (_pending.isEmpty || _sending) return;
    final edits = Map<String, dynamic>.of(_pending);
    setState(() => _sending = true);
    final problems = await widget.dispatch.onEditCard!(widget.block, edits);
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (problems == null) {
        _pending.removeWhere((k, v) => edits.containsKey(k) && edits[k] == v);
      } else {
        errors = problems;
      }
    });
    if (problems == null && _pending.isNotEmpty) unawaited(_send());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, this);
}

/// One value the user may change on a card, with the control its kind
/// takes: a stepper, a number or text field, the options, a switch.
class _EditRow extends StatefulWidget {
  const _EditRow({required this.control, required this.edits});

  final Map control;
  final _CardEditsState edits;

  @override
  State<_EditRow> createState() => _EditRowState();
}

class _EditRowState extends State<_EditRow> {
  TextEditingController? _text;

  String get _param => _str(widget.control['param']) ?? '';
  String get _kind => _str(widget.control['kind']) ?? 'text';

  @override
  void initState() {
    super.initState();
    if (_kind == 'text' || _kind == 'number') {
      final value = widget.edits.valueOf(_param);
      _text = TextEditingController(text: value == null ? '' : '$value');
    }
  }

  @override
  void dispose() {
    _text?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final strings = RendelStringsScope.of(context);
    final label = _str(widget.control['label']) ?? _param;
    final value = widget.edits.valueOf(_param);
    final labelStyle = _asPart(theme, 'details', theme.text.caption);
    final valueStyle = _asPart(theme, 'details', theme.text.captionSoftTabular);
    final error = widget.edits.errors[_param];

    Widget control;
    switch (_kind) {
      case 'stepper':
        final n = value is num ? value.toInt() : int.tryParse('$value') ?? 0;
        final min = _dbl(widget.control['min']);
        final max = _dbl(widget.control['max']);
        Widget step(IconData icon, String name, int to, bool allowed) => RendelPressable(
              semanticLabel: name,
              onTap: allowed ? () => widget.edits.change(_param, to) : null,
              child: Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: _white(theme, 999),
                child: Icon(icon, size: 16, color: allowed ? theme.colors.onSurface : theme.colors.onSurfaceFaint),
              ),
            );
        control = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            step(Icons.remove_rounded, strings.cardLess, n - 1, min == null || n - 1 >= min),
            SizedBox(
              width: 36,
              child: Text('$n', textAlign: TextAlign.center, style: valueStyle.copyWith(color: theme.colors.onSurface)),
            ),
            step(Icons.add_rounded, strings.cardMore, n + 1, max == null || n + 1 <= max),
          ],
        );
      case 'toggle':
        final on = value == true;
        control = Semantics(
          toggled: on,
          label: label,
          onTap: () => widget.edits.change(_param, !on, wait: Duration.zero),
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.edits.change(_param, !on, wait: Duration.zero),
            child: _SwitchMark(on: on, enabled: true),
          ),
        );
      case 'choice':
        control = Wrap(
          spacing: theme.space.xs,
          runSpacing: theme.space.xs,
          children: [
            for (final option in _maps(widget.control['options']))
              RendelChip(
                label: _str(option['label']) ?? '',
                selected: option['value'] == value,
                onTap: () => widget.edits.change(_param, option['value'], wait: Duration.zero),
              ),
          ],
        );
      default:
        control = TextField(
          controller: _text,
          keyboardType: _kind == 'number' ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
          maxLength: _dbl(widget.control['max_length'])?.toInt(),
          minLines: 1,
          maxLines: _kind == 'number' ? 1 : 4,
          style: valueStyle.copyWith(color: theme.colors.onSurface),
          onChanged: (text) => widget.edits.change(
            _param,
            _kind == 'number' ? (num.tryParse(text) ?? text) : text,
            wait: const Duration(milliseconds: 700),
          ),
          decoration: InputDecoration(
            isDense: true,
            counterText: '',
            contentPadding: EdgeInsets.symmetric(horizontal: theme.space.sm, vertical: theme.space.xs + 2),
            filled: true,
            fillColor: theme.colors.surfaceHigh,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: theme.hairline)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: theme.hairline)),
          ),
        );
    }

    final stacked = _kind == 'text' || _kind == 'choice';
    return MergeSemantics(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: theme.space.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (stacked) ...[
              Text(label, style: labelStyle),
              SizedBox(height: theme.space.xs),
              control,
            ] else
              Row(
                children: [
                  Expanded(child: Text(label, style: labelStyle)),
                  control,
                ],
              ),
            if (error != null) ...[
              SizedBox(height: theme.space.hair * 2),
              Text(strings.cardEditInvalid, style: theme.text.caption.copyWith(color: theme.danger)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Rebuilds once, when [at] passes.
///
/// A card that expires while the user is looking at it has to stop looking
/// confirmable then, not whenever some unrelated event next redraws the thread.
class _ExpiryWatch extends StatefulWidget {
  const _ExpiryWatch({required this.at, required this.builder});

  final DateTime? at;
  final Widget Function(BuildContext context, bool expired) builder;

  @override
  State<_ExpiryWatch> createState() => _ExpiryWatchState();
}

class _ExpiryWatchState extends State<_ExpiryWatch> {
  Timer? _timer;
  bool _expired = false;

  @override
  void initState() {
    super.initState();
    _arm();
  }

  @override
  void didUpdateWidget(_ExpiryWatch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.at != widget.at) _arm();
  }

  void _arm() {
    _timer?.cancel();
    _timer = null;
    final at = widget.at;
    if (at == null) {
      _expired = false;
      return;
    }
    final remaining = at.difference(DateTime.now());
    _expired = remaining.isNegative;
    if (!_expired) {
      _timer = Timer(remaining, () {
        if (mounted) setState(() => _expired = true);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _expired);
}

Widget _confirmCard(
  BuildContext context,
  WireBlock block,
  RendelDispatcher dispatch,
  bool expired,
  _CardEditsState? edits,
  _ConfirmExtrasState? extras,
) {
  final theme = RendelThemeScope.of(context);
  final resolved = _str(block.props[RendelLocalKeys.resolved]);
  // A destructive action the app says can be taken back (an order that can
  // still be cancelled) is asked like any other: danger means "cannot be
  // taken back" (`design/SYSTEM.md` §6a), and saying so of it was untrue.
  final destructive = (_str(block.props['risk']) ?? 'write') == 'destructive' &&
      block.props['irreversible'] != false;
  final display = _maps(block.props['params_display']);
  // The parameters the user may change here, by name, when they can.
  final controls = {
    if (edits != null)
      for (final control in _maps(block.props['editable']))
        if (_str(control['param']) != null) _str(control['param'])!: control,
  };
  final rowParams = {for (final row in display) _str(row['param'])};
  // A value the person fills in here (`card_fill`): until a redraw carries
  // it, the card cannot be confirmed.
  final params = block.props['params'];
  final unfilled = _maps(block.props['editable']).any((control) {
    if (control['required'] != true) return false;
    final value = params is Map ? params[_str(control['param'])] : null;
    return value == null || value is String && value.trim().isEmpty;
  });
  // The server's verb for the button, with the amount when it charges one
  // ("Place order · A$8.41"); the build's own word otherwise.
  final confirmLabel = _str(block.props['confirm_label']) ?? RendelStringsScope.of(context).confirm;

  return _Plate(
    // A destructive card raises its own edge to full ink. The accent stays on
    // the confirm button, which is the one thing to act on: weight carries the
    // warning so the host never has to own a red it did not choose.
    // An expired card has nothing left to decide, so it releases the raised
    // warning edge the same way a resolved one does.
    // Live while it is waiting, recorded once it is answered: a settled card
    // is a record of what happened, and the thread should stop asking.
    enclosure: resolved != null || expired
        ? _Enclosure.recorded
        : destructive
            ? _Enclosure.destructive
            : _Enclosure.live,

    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // No eyebrow on an ordinary confirmation: the summary asks a question
        // and two buttons answer it, so a label reading CONFIRM above a button
        // reading Confirm is decoration. The destructive card gets the one
        // thing the buttons cannot say.
        if (showSuggestedAfter ? _str(block.props['suggested_after']) : null case final source?) ...[
          Text(
            RendelStringsScope.of(context).suggestedAfterFrom(source),
            style: theme.text.caption.copyWith(color: theme.colors.onSurfaceFaint),
          ),
          SizedBox(height: theme.space.xs),
        ],
        if (destructive) ...[
          // In the one colour that means "this cannot be taken back". It was
          // full ink, which is the same weight the card's title carries, so
          // the warning read as a label rather than as a warning.
          RendelOverline(RendelStringsScope.of(context).irreversible,
              color: theme.danger, part: 'warning'),
          SizedBox(height: theme.space.sm),
        ],
        // The product it acts on, beside the question, when a result gave its
        // picture: a person adding a whey to the cart should see which one.
        if (_str(block.props['image_url']) case final picture?)
          Row(
            children: [
              _Thumbnail(
                url: picture,
                width: theme.size.cardRowImage,
                height: theme.size.cardRowImage,
                radius: theme.radius.sm,
                fit: BoxFit.contain,
              ),
              SizedBox(width: theme.space.md),
              Expanded(
                child: Text(
                  _str(block.props['summary']) ?? block.fallbackText,
                  style: theme.part('summary', theme.text.prose),
                ),
              ),
            ],
          )
        else
          Text(
            _str(block.props['summary']) ?? block.fallbackText,
            style: theme.part('summary', theme.text.prose),
          ),
        if (display.isNotEmpty || controls.isNotEmpty) ...[
          SizedBox(height: theme.space.md),
          _KvPanel(children: [
            for (final row in display) ...[
              if (controls[_str(row['param'])] case final control?)
                _EditRow(control: control, edits: edits!)
              // A support message or an address is read whole, from the left,
              // not squeezed into the value column.
              else if ((_str(row['value']) ?? '').length > 40)
                _StackedRow(
                  label: _str(row['label']) ?? '',
                  value: _str(row['value']) ?? '',
                  part: 'details',
                )
              else
                _KeyValueRow(
                  label: _str(row['label']) ?? '',
                  value: _str(row['value']) ?? '',
                  part: 'details',
                ),
              if (row['remembered'] == true) _Remembered(dispatch: dispatch),
            ],
            // An editable value the call left empty (an optional note) still
            // has its control.
            for (final entry in controls.entries)
              if (!rowParams.contains(entry.key)) _EditRow(control: entry.value, edits: edits!),
          ]),
          if (edits != null && edits.errors.containsKey('')) ...[
            SizedBox(height: theme.space.xs),
            Text(RendelStringsScope.of(context).cardEditFailed,
                style: theme.text.caption.copyWith(color: theme.danger)),
          ],
        ],
        if (extras != null) ...extras.parts(context),
        SizedBox(height: theme.space.lg),
        // Resolving a confirm card is the highest-stakes state change in the
        // catalog and it used to happen in one frame, collapsing the card by
        // ~24pt and yanking the thread with it.
        RendelSwap(
          stateKey: resolved ?? (expired ? 'expired' : 'open'),
          child: expired && resolved == null
              ? Semantics(
                  liveRegion: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Resolution(
                        icon: Icons.schedule_rounded,
                        label: RendelStringsScope.of(context).expired,
                      ),
                      SizedBox(height: theme.space.xs),
                      Text(
                        RendelStringsScope.of(context).expiredBody,
                        style: theme.text.body,
                      ),
                    ],
                  ),
                )
              : resolved != null
              ? Semantics(
                  liveRegion: true,
                  child: _Resolution(
                    icon: switch (resolved) {
                      'confirmed' => Icons.check_rounded,
                      // Nobody said no; the question was left behind.
                      'abandoned' => Icons.subdirectory_arrow_right_rounded,
                      _ => Icons.close_rounded,
                    },
                    label: switch (resolved) {
                      'confirmed' => RendelStringsScope.of(context).confirmed,
                      'abandoned' => RendelStringsScope.of(context).notAnswered,
                      _ => RendelStringsScope.of(context).notConfirmed,
                    },
                  ),
                )

              : _confirmButtons(
                  context,
                  confirm: RendelActionButton(
                    label: confirmLabel,
                    expand: true,
                    danger: destructive,
                    // Not while a change is waiting for the server (the card
                    // confirmed is the one it drew last), nor before the
                    // value is typed back and the text read, nor while a
                    // value it asks for is missing.
                    onTap: edits?.blocked == true || extras?.armed == false || unfilled
                        ? null
                        : extras?.typedValue != null
                            ? () => dispatch.onAction(ConfirmAction(
                                  _str(block.props['invocation_id']) ?? '',
                                  typed: extras!.typedValue,
                                ))
                            : _tap(dispatch, block.props['confirm']),
                    part: 'confirm',
                  ),
                  cancel: RendelActionButton(
                    // Never "Cancel": on a card asking whether to cancel an
                    // order, the decline button and the action being
                    // confirmed would be the same word.
                    label: RendelStringsScope.of(context).goBack,
                    quiet: true,
                    expand: true,
                    onTap: _tap(dispatch, block.props['cancel']),
                    part: 'cancel',
                  ),
                  // "Place order · A$8.41" does not fit half a card on a phone.
                  stacked: confirmLabel.length > 14,
                ),
        ),
      ],
    ),
  );
}

/// The two answers side by side, or one above the other when the confirm
/// button names its action at length.
Widget _confirmButtons(
  BuildContext context, {
  required Widget confirm,
  required Widget cancel,
  required bool stacked,
}) {
  final theme = RendelThemeScope.of(context);
  if (stacked) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [confirm, SizedBox(height: theme.space.sm), cancel],
    );
  }
  return Row(
    children: [
      Expanded(child: confirm),
      SizedBox(width: theme.space.sm),
      Expanded(child: cancel),
    ],
  );
}

/// A detail too long for the value column: its label, then the value at the
/// panel's full width, from the left.
class _StackedRow extends StatelessWidget {
  const _StackedRow({required this.label, required this.value, this.part});

  final String label;
  final String value;
  final String? part;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    return MergeSemantics(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: theme.space.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: _asPart(theme, part, theme.text.caption)),
            SizedBox(height: theme.space.hair * 2),
            Text(value, style: _asPart(theme, part, theme.text.captionSoftTabular)),
          ],
        ),
      ),
    );
  }
}

/// "From your preferences", with a bookmark, under a value the server filled
/// from what the person asked Rendel to remember (preference memory §3.4).
/// A tap opens "What I remember for you", where the build can open it.
class _Remembered extends StatelessWidget {
  const _Remembered({required this.dispatch});

  final RendelDispatcher dispatch;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final words = RendelStringsScope.of(context).memoryFromPreference;
    final faint = theme.colors.onSurfaceFaint;
    final mark = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.bookmark_border_rounded, size: theme.type.caption, color: faint),
        SizedBox(width: theme.space.xs),
        Flexible(child: Text(words, style: theme.text.caption.copyWith(color: faint))),
      ],
    );
    final open = dispatch.onOpenMemory;
    if (open == null) return mark;
    return RendelPressable(
      semanticLabel: words,
      onTap: open,
      pressedScale: 0.98,
      child: Align(alignment: AlignmentDirectional.centerStart, widthFactor: 1, child: mark),
    );
  }
}

/// The settled state of something the user answered: a confirm card they
/// resolved, a form they sent. One mark, one word, in the quiet ink.
class _Resolution extends StatelessWidget {
  const _Resolution({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    return Row(
      children: [
        Icon(icon, size: theme.type.label, color: theme.colors.onSurfaceFaint),
        SizedBox(width: theme.space.sm),
        // Wrapped, not ellipsised: "Not confirmed" losing its first word to an
        // ellipsis would state the opposite of what happened.
        Flexible(
          child: Text(
            label,
            style: theme.text.labelSoft,
            maxLines: 2,
            // An end ellipsis never eats the first word, which is the thing
            // the note above is protecting. Without it the default is `clip`,
            // and a clipped glyph looks like a rendering fault.
            overflow: TextOverflow.ellipsis,
          ),
        ),

      ],
    );
  }
}

/// One thing replacing another in place, sized and faded through as one
/// gesture.
///
/// The outgoing child is fully gone before the incoming one appears: a plain
/// crossfade leaves both at half opacity and the block visibly washes out. The
/// stack is top-left aligned so a taller replacement does not centre itself
/// against what it replaced and jitter, and the size eases so a collapse does
/// not yank the thread.
///
/// Used for every replacement in the SDK — a skeleton hydrating, a confirm
/// card resolving, a form locking — so all three read as the same gesture.
class RendelSwap extends StatelessWidget {
  const RendelSwap({
    super.key,
    required this.stateKey,
    required this.child,
    this.alignment = Alignment.topCenter,
  });

  /// Which edge stays put as the box resizes.
  final Alignment alignment;

  /// Changes when the child is a different thing rather than the same thing
  /// rebuilt.
  final String stateKey;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final still = MediaQuery.disableAnimationsOf(context);
    // No animation widgets at all, rather than zero-duration ones.
    //
    // `AnimatedSize` with `Duration.zero` drives its controller to completion
    // synchronously from inside `performLayout`, and the listener then calls
    // `markNeedsLayout` on the object still being laid out: "a RenderObject
    // must not re-dirty itself while still being laid out." Every confirm-card
    // resolution and every skeleton hydration threw it, twice — once for the
    // card's own swap and once for the thread's per-block one — for any host
    // developer running in debug with Reduce Motion on.
    if (still) return KeyedSubtree(key: ValueKey(stateKey), child: child);
    return AnimatedSize(
      duration: still ? Duration.zero : theme.motion.settle,

      curve: theme.motion.curve,
      alignment: alignment,
      child: AnimatedSwitcher(
        duration: still ? Duration.zero : theme.motion.swap,
        switchOutCurve: theme.motion.swapOut,
        switchInCurve: theme.motion.swapIn,
        layoutBuilder: (current, previous) => Stack(
          alignment: AlignmentDirectional.topStart,

          children: [
            // The outgoing child is on its way out and must not still take
            // taps: a confirm card's buttons stayed hit-testable underneath
            // their own replacement for the length of the crossfade.
            for (final gone in previous) IgnorePointer(child: gone),
            if (current != null) current,
          ],
        ),
        child: KeyedSubtree(key: ValueKey(stateKey), child: child),
      ),
    );
  }
}

// ————————————————————————— notices & readouts —————————————————————————

/// The assistant will not answer for now, on purpose: the person's usage
/// limit, or the app's budget or credit paused (`notices`). It is the answer,
/// not a failure, so it never takes an error's colour or icon: a quiet plate,
/// a clock, the sentence, and the app's own way on when it set one.
Widget buildNotice(BuildContext context, WireBlock block, RendelDispatcher dispatch) {
  final theme = RendelThemeScope.of(context);
  final message = _str(block.props['message']) ?? block.fallbackText;
  final action = block.props['action'];
  final label = action is Map ? _str(action['label']) : null;
  final url = action is Map ? _str(action['url']) : null;
  // The app's own page (its plans), in the system browser: it needs nothing from the host.
  final open = label != null && url != null ? OpenUrlAction(url, external: true) : null;
  return Semantics(
    liveRegion: true,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.fromSTEB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: theme.colors.surfaceSunk,
        borderRadius: BorderRadius.circular(theme.plateRadius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: theme.colors.surfaceRaised,
              shape: BoxShape.circle,
              border: Border.all(color: theme.colors.line),
            ),
            child: Icon(Icons.schedule_rounded, size: 18, color: theme.colors.onSurfaceSoft),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message,
                    style: theme.text.prose.copyWith(fontSize: 15, height: 1.5, color: theme.colors.onSurface),
                  ),
                  if (open != null && dispatch.canHandle(open)) ...[
                    const SizedBox(height: 12),
                    RendelActionButton(label: label!, quiet: true, onTap: () => dispatch.onAction(open)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

Widget buildStatusBanner(BuildContext context, WireBlock block, RendelDispatcher dispatch) {
  final theme = RendelThemeScope.of(context);
  final tone = _str(block.props['tone']) ?? 'info';
  const iconFor = {
    'success': Icons.check_circle_outlined,
    'warning': Icons.error_outlined,
    'error': Icons.cancel_outlined,
    'info': Icons.info_outlined,
  };
  // Tone is carried by icon and by emphasis, not by inventing a green and a
  // red the host never mapped. The accent goes to the two tones that ask for
  // attention; success reads at full ink; info stays quiet.
  final iconColor = switch (tone) {
    'warning' || 'error' => theme.accentText,
    'success' => theme.colors.onSurface,
    _ => theme.colors.onSurfaceSoft,
  };

  return _Plate(

    child: _IconLede(
      icon: iconFor[tone] ?? iconFor['info'],
      iconColor: iconColor,
      title: _str(block.props['title']) ?? block.fallbackText,
      body: _str(block.props['body']),
    ),
  );
}

Widget buildStatGroup(BuildContext context, WireBlock block, RendelDispatcher dispatch) {
  final theme = RendelThemeScope.of(context);
  final items = _maps(block.props['items']);
  if (items.isEmpty) return _EmptyPlate(message: block.fallbackText);

  Widget stat(Map item) {
    final delta = _str(item['delta']);
    // Merged for the same reason `_KeyValueRow` is: read as three separate
    // nodes, a stat group becomes a row of labels followed by a row of bare
    // numbers, and "92" on its own is not a fact.
    return MergeSemantics(
        child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        RendelOverline(_str(item['label']) ?? ''),
        SizedBox(height: theme.space.xs),
        // Label, value and delta stack. Set beside the value, the delta
        // competes with it for a third of the plate and the number is the one
        // that loses: "$1,284" ellipsised to "$1,…" is a KPI that no longer
        // says anything.
        Text(
          _str(item['value']) ?? '',
          style: theme.text.displayTabular,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (delta != null) ...[
          SizedBox(height: theme.space.hair),
          // Direction is a glyph, not a colour: a red-green delta is
          // unreadable to a third of colour-blind users and would spend an
          // accent this block does not have.
          _TrendMark(trend: _str(item['trend']), delta: delta),
        ],
      ],
    ));
  }

  // Up to three KPIs share the plate as an even band, which is what makes a
  // readout look measured rather than left over. Beyond three they wrap,
  // because four even columns on a phone is four truncated numbers.
  final band = items.length <= 3
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) SizedBox(width: theme.space.lg),
                Expanded(child: stat(items[i])),
              ],
            ],
          )
        // Beyond three, an even two-column grid rather than a Wrap whose
        // children size to their own text: four KPIs of unequal width
        // otherwise stack into one ragged column.
        : LayoutBuilder(
            builder: (context, constraints) {
              final column = (constraints.maxWidth - theme.space.xl) / 2;
              return Wrap(
                spacing: theme.space.xl,
                runSpacing: theme.space.lg,
                children: [
                  for (final item in items)
                    SizedBox(width: column, child: stat(item)),
                ],
              );
            },
          );
  // When the figures were true, so a snapshot opened later says so.
  final asOf = _instant(block.props['as_of']);
  return _Plate(
    child: asOf == null
        ? band
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              band,
              SizedBox(height: theme.space.md),
              Text(
                RendelStringsScope.of(context).asOfTime(_clock(context, asOf)),
                style: theme.text.captionTabular.copyWith(
                  fontSize: 12.5,
                  color: theme.colors.onSurfaceSoft,
                ),
              ),
            ],
          ),
  );
}

class _TrendMark extends StatelessWidget {
  const _TrendMark({required this.trend, required this.delta});
  final String? trend;
  final String delta;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final icon = switch (trend) {
      'up' => Icons.arrow_upward_rounded,
      'down' => Icons.arrow_downward_rounded,
      _ => null,
    };
    final direction = switch (trend) {
      'up' => 'up',
      'down' => 'down',
      _ => null,
    };
    return Semantics(
      label: direction == null ? delta : '$delta, $direction',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            Icon(icon, size: theme.type.caption, color: theme.colors.onSurfaceSoft),
          Flexible(
            child: Text(
              delta,
              style: theme.text.captionSoftTabular,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

Widget buildProgress(BuildContext context, WireBlock block, RendelDispatcher dispatch) {
  final theme = RendelThemeScope.of(context);
  final items = _maps(block.props['items']);
  if (items.isEmpty) return _EmptyPlate(message: block.fallbackText);
  // Rings for one to three goals; more than three side by side would be too
  // small to read, so they fall back to bars (`design/CATALOG-B6.md`).
  final rings = block.props['style'] == 'ring' && items.length <= 3;

  return _Plate(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _BlockTitle(block.props['title']),
        if (rings)
          _ProgressRings(items: items)
        else
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) SizedBox(height: theme.space.lg),
            _ProgressRow(item: items[i]),
          ],
      ],
    ),
  );
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({required this.item});
  final Map item;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final value = _dbl(item['value']) ?? 0;
    final max = _dbl(item['max']) ?? 0;
    final fraction = max > 0 ? (value / max).clamp(0.0, 1.0) : 0.0;
    final numbers = RendelStringsScope.of(context).numberLocale;
    final valueLabel = _str(item['value_label']) ?? '${_num(value, numbers)} / ${_num(max, numbers)}';
    final caption = _str(item['caption']);

    return Semantics(
      label: [
        _str(item['label']) ?? '',
        valueLabel,
        // Inside the excluded subtree below, so it has to be named here or no
        // screen reader ever reaches it.
        if (caption != null) caption,
      ].where((part) => part.isNotEmpty).join(', '),
      value: '${(fraction * 100).round()}%',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _str(item['label']) ?? '',
                  style: theme.text.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(width: theme.space.sm),
              _TrailingSlot(
                child: Text(
                  valueLabel,
                  style: theme.text.captionTabular,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          SizedBox(height: theme.space.sm),
          // v6: no border. The track is the ink's 7% tint and the value the
          // soft readout fill, both rounded; the value label above carries
          // the number for anyone who cannot judge a length.
          //
          // `width: double.infinity` is load-bearing. A plate's Column passes
          // loose cross-axis constraints, so without it this Container sized
          // to its child — and its child is the fraction. The bordered box
          // WAS the fill: a 1% bar drew a 2.8pt rounded rectangle and a 99%
          // bar drew a 281pt one, with no reference length anywhere on screen
          // to read either against.
          Container(
            width: double.infinity,
            height: theme.size.trackHeight,
            decoration: BoxDecoration(
              color: theme.tint,
              borderRadius: BorderRadius.circular(theme.radius.control),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(theme.radius.control),
              child: FractionallySizedBox(
                alignment: AlignmentDirectional.centerStart,
                widthFactor: fraction,
                // Ink, not the accent: a bar is a readout, not a control.
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.readoutFill,
                    borderRadius: BorderRadius.circular(theme.radius.control),
                  ),
                ),
              ),
            ),
          ),
          if (caption != null) ...[
            SizedBox(height: theme.space.xs),
            Text(caption, style: theme.text.caption),
          ],
        ],
      ),
    );
  }
}

Widget buildOrderTracker(BuildContext context, WireBlock block, RendelDispatcher dispatch) {
  final steps = _maps(block.props['steps']);
  if (steps.isEmpty) return _EmptyPlate(message: block.fallbackText);
  final theme = RendelThemeScope.of(context);
  final title = _str(block.props['title']);
  // The current step, said once in the head (blocks v6, "Line"). Every style
  // keeps it; a parcel with nothing under way has no pill.
  final current = steps.indexWhere((step) => _str(step['status']) == 'current');
  final pill = current < 0 ? null : _str(steps[current]['label']);
  final hasTitle = title != null && title.isNotEmpty;
  final hasPill = pill != null && pill.isNotEmpty;
  final arrives = _arrival(context, block.props);
  final reference = _map(block.props['reference']);
  // What the order holds, as a row of photographs between its head and its steps.
  final pictures = [
    for (final url in (block.props['images'] is List ? block.props['images'] as List : const []).take(4))
      if (_str(url) case final picture?) picture,
  ];

  return _Plate(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasTitle || hasPill) ...[
          Row(
            children: [
              Expanded(
                child: hasTitle
                    ? Text(title, style: theme.part('title', theme.text.title))
                    : const SizedBox.shrink(),
              ),
              if (hasPill) ...[
                SizedBox(width: theme.space.sm),
                Flexible(child: _StatusPill(label: pill)),
              ],
            ],
          ),
          SizedBox(height: arrives == null ? theme.space.md : theme.space.xs),
        ],
        if (arrives != null) ...[
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: arrives.$1),
                if (arrives.$2 != null)
                  TextSpan(
                    text: ' · ${arrives.$2}',
                    style: TextStyle(color: theme.colors.onSurfaceSoft, fontWeight: FontWeight.w400),
                  ),
              ],
            ),
            style: theme.text.labelTabular.copyWith(fontWeight: FontWeight.w500),
          ),
          SizedBox(height: theme.space.md),
        ],
        if (pictures.isNotEmpty) ...[
          Row(
            children: [
              for (var i = 0; i < pictures.length; i++) ...[
                if (i > 0) SizedBox(width: theme.space.sm),
                _Thumbnail(
                  url: pictures[i],
                  width: theme.size.cardRowImage,
                  height: theme.size.cardRowImage,
                  radius: theme.radius.sm,
                  fit: BoxFit.contain,
                ),
              ],
            ],
          ),
          SizedBox(height: theme.space.md),
        ],
        // Across holds the eight steps the tracker was drawn for; past that a
        // phone has no room for a mark each, and the steps go down instead.
        ...switch (steps.length > 8 && theme.style.tracker == RendelTrackerStyle.horizontal
            ? RendelTrackerStyle.vertical
            : theme.style.tracker) {
          RendelTrackerStyle.vertical => [
              for (var i = 0; i < steps.length; i++) ...[
                if (i > 0) SizedBox(height: theme.space.hair),
                _TrackerStep(
                  label: _str(steps[i]['label']) ?? '',
                  timestamp: _str(steps[i]['timestamp']),
                  note: _str(steps[i]['note']),
                  status: _str(steps[i]['status']) ?? 'pending',
                  isLast: i == steps.length - 1,
                ),
              ],
            ],
          RendelTrackerStyle.horizontal => [_TrackerAcross(steps: steps)],
          RendelTrackerStyle.bar => [_TrackerBar(steps: steps)],
        },
        if (reference != null) ...[
          SizedBox(height: theme.space.md),
          _reference(context, reference, dispatch),
        ],
      ],
    ),
  );
}

/// When the order arrives, as "Arrives …" and, where it is not fresh, when
/// that was known: `eta_label` or the clock time, and "as of" the time it
/// was true. A relative phrase ("in about 25 min") only for an ETA still
/// ahead that was known under half an hour ago, so a stored answer opened
/// days later claims no freshness it does not have. Null when there is no
/// ETA to say.
(String, String?)? _arrival(BuildContext context, Map<String, dynamic> props) {
  final strings = RendelStringsScope.of(context);
  final eta = _instant(props['eta']);
  final label = _str(props['eta_label']);
  final asOf = _instant(props['as_of']);
  if (eta == null && (label == null || label.isEmpty)) return null;
  final now = DateTime.now();
  final fresh = eta != null &&
      eta.isAfter(now) &&
      asOf != null &&
      now.difference(asOf) < const Duration(minutes: 30);
  if (fresh) {
    final soon = _soon(context, eta);
    if (soon != null) return (strings.arrivesAt(soon), null);
  }
  return (
    strings.arrivesAt(label != null && label.isNotEmpty ? label : _clock(context, eta!)),
    asOf == null ? null : strings.asOfTime(_clock(context, asOf)),
  );
}

/// The tracker's head pill: the current step on the highlight, behind a small
/// faint dot. Drawn, not read: the step rows below already say it.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    return ExcludeSemantics(
      child: Container(
        padding: EdgeInsetsDirectional.fromSTEB(
          theme.space.sm,
          theme.space.xs,
          theme.space.sm + theme.space.hair,
          theme.space.xs,
        ),
        decoration: BoxDecoration(
          color: theme.highlight,
          borderRadius: BorderRadius.circular(theme.radius.control),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colors.onSurfaceFaint,
              ),
            ),
            SizedBox(width: theme.space.xs + theme.space.hair),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.text.captionSoft
                    .copyWith(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _stepLabel(String label, String? timestamp, String status) =>
    _joinParts([
      label,
      timestamp,
      switch (status) {
        'done' => 'done',
        'current' => 'in progress',
        _ => 'pending',
      },
    ]);

/// Whether a step has been reached: done, or under way.
bool _reached(Map step) =>
    const {'done', 'current'}.contains(_str(step['status']));

/// The mark on a tracker step, wherever the step is drawn.
///
/// No solid ink anywhere (blocks v6): done is an outlined circle with a small
/// tick, the current step a soft ring and dot with a halo of the tint, and a
/// pending one a dashed circle of the rail.
class _StepMark extends StatelessWidget {
  const _StepMark({required this.status});

  final String status;

  static const double size = 22;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    return switch (status) {
      'done' => Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.colors.surfaceRaised,
            border: Border.all(
              color: theme.colors.onSurface.withValues(alpha: 0.22),
              width: 1.5,
            ),
          ),
          child: Icon(
            Icons.check_rounded,
            size: theme.type.caption,
            color: theme.colors.onSurfaceSoft,
          ),
        ),
      'current' => Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.colors.surfaceRaised,
            border: Border.all(color: theme.readoutFill, width: 1.5),
            boxShadow: [BoxShadow(color: theme.tint, spreadRadius: 3)],
          ),
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.readoutFill,
            ),
          ),
        ),
      _ => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.colors.surfaceRaised,
          ),
          child: CustomPaint(painter: _Dashed.circle(theme.rail)),
        ),
    };
  }
}

/// A 1.5pt dashed stroke: round a circle, or along a box's long axis.
class _Dashed extends CustomPainter {
  _Dashed.circle(this.color) : circle = true;
  _Dashed.line(this.color) : circle = false;

  final Color color;
  final bool circle;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    if (circle) {
      final radius = size.shortestSide / 2 - 0.75;
      final rect =
          Rect.fromCircle(center: size.center(Offset.zero), radius: radius);
      // Twelve dashes, each half its arc.
      const dashes = 12;
      const sweep = math.pi * 2 / dashes;
      for (var i = 0; i < dashes; i++) {
        canvas.drawArc(rect, i * sweep, sweep / 2, false, paint);
      }
      return;
    }
    // 3 on, 4 off, along whichever axis is longer.
    final vertical = size.height >= size.width;
    final length = vertical ? size.height : size.width;
    final across = (vertical ? size.width : size.height) / 2;
    paint.strokeCap = StrokeCap.butt;
    for (var at = 0.0; at < length; at += 7) {
      final end = math.min(at + 3, length);
      canvas.drawLine(
        vertical ? Offset(across, at) : Offset(at, across),
        vertical ? Offset(across, end) : Offset(end, across),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_Dashed old) => old.color != color || old.circle != circle;
}

/// `order_tracker` with its steps across: one row of equal steps, a mark
/// each, joined by the rail at the marks' middle, and the name under it. No
/// times; the vertical tracker is the one with room for them.
class _TrackerAcross extends StatelessWidget {
  const _TrackerAcross({required this.steps});

  final List<Map> steps;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    // The rail, darkened a little where the road has been walked.
    Widget join(Map into) => Container(
          height: 1.5,
          color: _reached(into)
              ? theme.colors.onSurface.withValues(alpha: 0.26)
              : theme.rail,
        );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < steps.length; i++)
          Expanded(
            child: Semantics(
              label: _stepLabel(
                _str(steps[i]['label']) ?? '',
                _str(steps[i]['timestamp']),
                _str(steps[i]['status']) ?? 'pending',
              ),
              excludeSemantics: true,
              child: Column(
                children: [
                  // Each step draws half of the line on either side of its
                  // mark, so two neighbours meet at their shared edge. The half
                  // leading in takes this step's colour, the half leading out
                  // the next one's, which makes each whole segment the colour
                  // of the step it leads into. A Row, so RTL mirrors it.
                  Row(
                    children: [
                      Expanded(
                          child: i > 0 ? join(steps[i]) : const SizedBox()),
                      _StepMark(status: _str(steps[i]['status']) ?? 'pending'),
                      Expanded(
                        child: i < steps.length - 1
                            ? join(steps[i + 1])
                            : const SizedBox(),
                      ),
                    ],
                  ),
                  SizedBox(height: theme.space.sm + theme.space.hair),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: theme.space.hair),
                    child: Text(
                      _str(steps[i]['label']) ?? '',
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.part(
                        'step',
                        switch (_str(steps[i]['status'])) {
                          'current' => theme.text.caption.copyWith(
                              color: theme.colors.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          'done' => theme.text.captionSoft,
                          _ => theme.text.caption,
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// `order_tracker` as one bar: filled as far as the steps that are done or
/// under way, and under it the step it is on, "Step k of N", and when.
class _TrackerBar extends StatelessWidget {
  const _TrackerBar({required this.steps});

  final List<Map> steps;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final strings = RendelStringsScope.of(context);
    final reached = steps.where(_reached).length;
    // The step under way; failing that the last one finished; failing that
    // the first.
    var now = steps.indexWhere((step) => _str(step['status']) == 'current');
    if (now < 0) {
      now = steps.lastIndexWhere((step) => _str(step['status']) == 'done');
    }
    if (now < 0) now = 0;
    final label = _str(steps[now]['label']) ?? '';
    final timestamp = _str(steps[now]['timestamp']);
    final height = theme.size.stepBar;
    final position = strings.stepOfCount(now + 1, steps.length);

    return Semantics(
      label: _joinParts([
        _stepLabel(label, timestamp, _str(steps[now]['status']) ?? ''),
        _str(steps[now]['note']),
      ]),
      value: position,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // `width: double.infinity` for the reason `_ProgressRow` gives: a
          // plate's Column passes loose constraints, and without it the track
          // would be as wide as its own fill.
          Container(
            width: double.infinity,
            height: height,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: theme.tint,
              borderRadius: BorderRadius.circular(height / 2),
            ),
            child: FractionallySizedBox(
              alignment: AlignmentDirectional.centerStart,
              widthFactor: reached / steps.length,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.readoutFill,
                  borderRadius: BorderRadius.circular(height / 2),
                ),
              ),
            ),
          ),
          SizedBox(height: theme.space.sm + theme.space.hair),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(label, style: theme.part('step', theme.text.label))),
              SizedBox(width: theme.space.md),
              // Flexible: "Step 2 of 2" is words now, not "2/2", and at the
              // largest text size it wraps rather than pushing off the plate.
              Flexible(
                child: Text(
                  position,
                  textAlign: TextAlign.end,
                  style: theme.part('time', theme.text.captionTabular),
                ),
              ),
            ],
          ),
          if (timestamp != null) ...[
            SizedBox(height: theme.space.hair),
            Text(timestamp, style: theme.part('time', theme.text.captionTabular)),
          ],
          if (_str(steps[now]['note']) case final note? when note.isNotEmpty) ...[
            SizedBox(height: theme.space.hair),
            Text(
              note,
              style: theme.text.caption.copyWith(fontSize: 13.5, color: theme.colors.onSurfaceSoft),
            ),
          ],
        ],
      ),
    );
  }
}

/// One step of the vertical tracker ("Line"): a 22pt mark, the label, the
/// time at the far edge, and the road down to the next mark — solid behind,
/// dashed out of the current step. The current row sits on the highlight.
class _TrackerStep extends StatelessWidget {
  const _TrackerStep({
    required this.label,
    required this.timestamp,
    required this.status,
    required this.isLast,
    this.note,
  });

  final String label;
  final String? timestamp;
  final String status;
  final bool isLast;

  /// A line under the step: "Left the Rotterdam depot", "Signed by M. Doğan".
  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final current = status == 'current';
    final inset = theme.space.sm + theme.space.hair;
    const mark = _StepMark.size;

    final note = this.note;
    return Semantics(
      label: _joinParts([_stepLabel(label, timestamp, status), note]),
      excludeSemantics: true,
      // A Stack sized by the row, with the road stretched behind it. The
      // obvious IntrinsicHeight costs a speculative layout pass per step, and
      // a tracker at the schema's eight-step cap pays it eight times every
      // time its constraints change.
      child: Stack(
        // The road runs on past this row's foot to the next mark.
        clipBehavior: Clip.none,
        children: [
          if (current)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.highlight,
                  borderRadius: BorderRadius.circular(theme.radius.card),
                ),
              ),
            ),
          if (!isLast)
            PositionedDirectional(
              // Centred under the mark. Directional, or the Row mirrors and
              // the road does not.
              start: inset + mark / 2 - 0.75,
              top: inset + mark,
              // Down through the gap and the next row's inset, to its mark.
              bottom: -(inset + theme.space.hair),
              width: 1.5,
              child: current
                  ? CustomPaint(painter: _Dashed.line(theme.rail))
                  : ColoredBox(color: theme.rail),
            ),
          Padding(
            padding: EdgeInsets.all(inset),
            child: Row(
              // A step with a note keeps its mark at the top, where the road
              // under it starts.
              crossAxisAlignment: note != null && note.isNotEmpty
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
              children: [
                _StepMark(status: status),
                SizedBox(width: inset),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: theme.part(
                          'step',
                          switch (status) {
                            'current' => theme.text.labelEmphasis,
                            'done' => theme.text.labelSoft,
                            _ => theme.text.label
                                .copyWith(color: theme.colors.onSurfaceFaint),
                          },
                        ),
                      ),
                      if (note != null && note.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          note,
                          style: theme.text.caption.copyWith(
                            fontSize: 13.5,
                            color: theme.colors.onSurfaceSoft,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (timestamp != null) ...[
                  SizedBox(width: theme.space.sm),
                  // Capped like every trailing value, so a long time cannot
                  // push the step's own name off the plate.
                  _TrailingSlot(
                    child: Text(
                      timestamp!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.part('time', theme.text.captionTabular),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Widget buildReceipt(BuildContext context, WireBlock block, RendelDispatcher dispatch) {
  final theme = RendelThemeScope.of(context);
  final lines = _maps(block.props['lines']);
  final currency = _str(block.props['currency']);
  final title = _str(block.props['title']);
  final subtotal = _str(block.props['subtotal']);
  final tax = _str(block.props['tax']);
  final total = _str(block.props['total']);
  if (lines.isEmpty && total == null) {
    return _EmptyPlate(message: block.fallbackText);
  }

  return _Plate(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The currency codes the whole receipt, so it sits with the title
        // rather than inside the total's label, where "Total (USD)" competed
        // with the amount it was labelling.
        if ((title != null && title.isNotEmpty) || currency != null) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null && title.isNotEmpty)
                Expanded(child: Text(title, style: theme.text.title))

              else
                const Spacer(),
              if (currency != null) ...[
                SizedBox(width: theme.space.sm),
                Padding(
                  padding: EdgeInsets.only(top: theme.space.hair),
                  child: RendelOverline(currency),
                ),
              ],
            ],
          ),
          SizedBox(height: theme.space.md),
        ],
        for (final line in lines)
          _withPicture(
            context,
            _str(line['image_url']),
            _str(line['note']) != null || _str(line['delta']) != null
                ? _ReceiptLine(
                    label: _str(line['label']) ?? '',
                    amount: _str(line['amount']) ?? '',
                    note: _str(line['note']),
                    delta: _str(line['delta']),
                  )
                : _KeyValueRow(
                    label: _str(line['label']) ?? '',
                    value: _str(line['amount']) ?? '',
                  ),
          ),
        if (subtotal != null || tax != null) ...[
          const _Rule(strong: false),
          if (subtotal != null)
            _KeyValueRow(label: RendelStringsScope.of(context).subtotal, value: subtotal),
          if (tax != null) _KeyValueRow(label: RendelStringsScope.of(context).tax, value: tax),
        ],
        if (total != null) ...[
          const _Rule(strong: true),
          _KeyValueRow(label: RendelStringsScope.of(context).total, value: total, strong: true),
        ],
      ],
    ),
  );
}

/// [line] with the product's photograph before it, when it has one.
Widget _withPicture(BuildContext context, String? picture, Widget line) {
  if (picture == null) return line;
  final theme = RendelThemeScope.of(context);
  return Row(
    children: [
      _Thumbnail(url: picture, width: 40, height: 40, radius: theme.radius.sm, fit: BoxFit.contain),
      SizedBox(width: theme.space.sm),
      Expanded(child: line),
    ],
  );
}

// ————————————————————————— booking —————————————————————————

Widget buildDatetimeSlots(
  BuildContext context,
  WireBlock block,
  RendelDispatcher dispatch,
) {
  final theme = RendelThemeScope.of(context);
  final slots = _maps(block.props['slots']);
  if (slots.isEmpty) return _EmptyPlate(message: block.fallbackText);
  final chosen = _str(block.props[RendelLocalKeys.chosen]);

  // Grouped by calendar day when the model supplied timestamps, because a flat
  // run of "09:00 09:30 10:00" across three dates is a booking mistake waiting
  // to happen. Without timestamps the labels are all the user has, so the list
  // stays flat rather than inventing a grouping.
  final groups = <String, List<Map>>{};
  for (final slot in slots) {
    groups.putIfAbsent(_dayKey(RendelStringsScope.of(context), slot['starts_at']), () => []).add(slot);
  }

  final select = dispatch.onSelect;
  Widget chipFor(Map slot) {
    final id = _str(slot['id']);
    final label = _str(slot['label']) ?? '';
    // A "10:00" alone does not say which 10:00 was asked for, so the question
    // carries the day it sits under.
    final day = _dayKey(RendelStringsScope.of(context), slot['starts_at']);
    // A booked-out window, shown so the reader sees it rather than reads
    // about it, and not pickable (Grove report).
    final open = slot['available'] != false;
    return RendelChip(
      label: label,
      unavailable: !open,
      // Slot labels are clock times, so proportional digits would make every
      // chip a different width and re-flow the Wrap between renders.
      tabular: true,
      selected: id != null && id == chosen,
      // The pick goes up as a `selection`, and whoever sends it marks the
      // slot chosen, only if it does send: a slot marked after a tap the open
      // turn dropped is a booking the user believes they made.
      onTap: open && id != null && select != null
          ? () => select(block, id, day.isEmpty ? label : '$day, $label')
          : null,
    );
  }

  final ordered = groups.entries.toList();
  // One day that the title already names ("Tomorrow morning – Sun 11 Oct")
  // is not said again over its slots.
  final title = _str(block.props['title']) ?? '';
  final saidInTitle = ordered.length == 1 && ordered.first.key.isNotEmpty && title.contains(ordered.first.key);

  return _Plate(
    enclosure: _Enclosure.live,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _BlockTitle(block.props['title']),
        for (var i = 0; i < ordered.length; i++) ...[
          if (i > 0) SizedBox(height: theme.space.lg),
          if (ordered[i].key.isNotEmpty && !saidInTitle) ...[
            RendelOverline(ordered[i].key),
            SizedBox(height: theme.space.sm),
          ],
          Wrap(
            spacing: theme.space.sm,
            runSpacing: theme.space.sm,
            children: [for (final slot in ordered[i].value) chipFor(slot)],
          ),
        ],
      ],
    ),
  );
}

Widget buildBookingCard(BuildContext context, WireBlock block, RendelDispatcher dispatch) {
  final theme = RendelThemeScope.of(context);
  final cta = _map(block.props['cta']);
  final lines = _maps(block.props['lines']);
  final image = _str(block.props['image_url']);
  final subtitle = _str(block.props['subtitle']);
  final when = _str(block.props['when']);
  final where = _str(block.props['where']);
  final title = _str(block.props['title']) ?? block.fallbackText;
  final reference = _map(block.props['reference']);
  final status = _map(block.props['status']);
  final statusLabel = _str(status?['label']);
  // "In 2 hours", "tomorrow 10:00", while it is still ahead.
  final startsAt = _instant(block.props['starts_at']);
  final soon = startsAt == null ? null : _soon(context, startsAt);

  Widget detail(IconData icon, String value, {String? under}) => Padding(
        padding: EdgeInsets.only(top: theme.space.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(top: theme.space.hair),
              child: Icon(icon, size: theme.type.body, color: theme.colors.onSurfaceFaint),
            ),
            SizedBox(width: theme.space.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, style: theme.text.body),
                  if (under != null)
                    Text(
                      under,
                      style: theme.text.captionTabular.copyWith(color: theme.colors.onSurfaceSoft),
                    ),
                ],
              ),
            ),
          ],
        ),
      );

  return _Plate(
    enclosure: _Enclosure.live,
    padding: EdgeInsets.zero,
    // The image runs to the plate's own edge, so the plate has to clip it or
    // the photograph's square corners paint over the enclosure's rounded ones.
    clip: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (image != null)
          // Decorative: the title is the very next thing in the tree, and an
          // alt that repeats it makes a reader hear it twice.
          _Thumbnail(url: image, height: theme.size.heroHeight, radius: 0),
        Padding(
          padding: EdgeInsets.all(theme.space.plate),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Text(title, style: theme.text.title)),
                  if (statusLabel != null) ...[
                    SizedBox(width: theme.space.sm),
                    // Capped like a trailing value, so the title keeps the
                    // row.
                    _TrailingSlot(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: _TonePill(label: statusLabel, tone: _str(status?['tone'])),
                      ),
                    ),
                  ],
                ],
              ),

              if (subtitle != null) ...[
                SizedBox(height: theme.space.hair),
                Text(subtitle, style: theme.text.body),
              ],
              if (when != null) detail(Icons.schedule_outlined, when, under: soon),
              if (where != null) detail(Icons.place_outlined, where),
              if (lines.isNotEmpty || reference != null) ...[
                SizedBox(height: theme.space.md),
                _KvPanel(children: [
                  for (final line in lines)
                    _KeyValueRow(
                      label: _str(line['label']) ?? '',
                      value: _str(line['value']) ?? '',
                    ),
                  if (reference != null) _reference(context, reference, dispatch),
                ]),
              ],
              if (cta != null) ...[
                SizedBox(height: theme.space.lg),
                _actionButton(
                  context,
                  label: _str(cta['label']) ?? 'Confirm',
                  action: cta['action'],
                  dispatch: dispatch,
                  expand: true,
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

// ————————————————————————— data —————————————————————————

typedef _Series = ({String? name, List<double> data});

Widget buildChart(BuildContext context, WireBlock block, RendelDispatcher dispatch) {
  final theme = RendelThemeScope.of(context);
  final kind = _str(block.props['kind']) ?? 'line';
  final labels = [for (final l in _list(block.props['labels'])) _str(l) ?? ''];
  final series = <_Series>[
    for (final s in _maps(block.props['series']))
      (
        name: _str(s['name']),
        // Parsed once per value, not twice: this runs on every rebuild, and
        // a rebuild happens on every streamed token.
        data: [
          for (final v in _list(s['data']))
            if (_dbl(v) case final parsed?) parsed,
        ],
      ),
  ].where((s) => s.data.isNotEmpty).toList();

  if (series.isEmpty) return _EmptyPlate(message: block.fallbackText);

  final unit = _str(block.props['unit']);
  // The painting carries no readable text, so a chart whose fallback_text is
  // missing would be an unnamed region. Describing it from its own data beats
  // announcing nothing.
  final description = block.fallbackText.isEmpty
      ? _describeChart(kind, labels, series, unit, RendelStringsScope.of(context).numberLocale)
      : block.fallbackText;

  // A legend exists to attach names to swatches. With no names there is
  // nothing to attach, and "Series 1 / Series 2" is a placeholder pretending
  // to be data.
  final named = series.length > 1 &&
      series.every((s) => s.name != null && s.name!.isNotEmpty);

  return _Plate(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _BlockTitle(block.props['title']),
        if (kind == 'donut')
          _Donut(
              labels: labels, data: series.first.data, description: description)
        else if (kind == 'hbar')
          _HBars(labels: labels, series: series, unit: unit, description: description)
        // One series stacked on nothing is a bar chart, and reads as one.
        else if ((kind == 'bar' || kind == 'stacked_bar') && series.length == 1)
          _Bars(
            labels: labels,
            data: series.first.data,
            unit: unit,
            description: description,
          )
        else
          _Plot(
            kind: kind,
            labels: labels,
            series: series,
            unit: unit,
            description: description,
          ),
        if (kind != 'donut' && named) ...[
          SizedBox(height: theme.space.md),
          Wrap(
            spacing: theme.space.lg,
            runSpacing: theme.space.sm,
            children: [
              for (var i = 0; i < series.length; i++)
                _LegendMark(color: _seriesColor(theme, i), label: series[i].name!),
            ],
          ),
        ],
      ],
    ),
  );
}

String _describeChart(
  String kind,
  List<String> labels,
  List<_Series> series,
  String? unit,
  String locale,
) {
  var high = series.first.data.first;
  var low = series.first.data.first;
  for (final s in series) {
    for (final v in s.data) {
      high = math.max(high, v);
      low = math.min(low, v);
    }
  }
  String said(double v) => _withUnit(_num(v, locale), unit);
  final points = series.first.data.length;
  if (kind == 'donut') {
    final total = series.first.data.fold<double>(0, (sum, v) => sum + math.max(0, v));
    final share = total > 0 ? (math.max(0.0, series.first.data.first) / total * 100).round() : 0;
    final first = labels.isNotEmpty ? labels.first : 'the largest slice';
    return 'donut chart, $points slices, $first $share%';
  }
  final name = switch (kind) {
    'hbar' => 'horizontal bar',
    'stacked_bar' => 'stacked bar',
    _ => kind,
  };
  return '$name chart, $points points, '
      'high ${said(high)}, low ${said(low)}';
}

/// Series are told apart by weight of ink, not by hue. A chart is a readout,
/// and the accent is reserved for what the reader can act on.
Color _seriesColor(RendelTheme theme, int index) => switch (index) {
      0 => theme.colors.onSurface,
      1 => theme.colors.onSurfaceSoft,
      _ => theme.colors.onSurfaceFaint,
    };


class _Plot extends StatelessWidget {
  const _Plot({
    required this.kind,
    required this.labels,
    required this.series,
    required this.unit,
    required this.description,
  });

  final String kind;
  final List<String> labels;
  final List<_Series> series;
  final String? unit;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final stacked = kind == 'stacked_bar';
    var maxValue = 0.0;
    var minValue = 0.0;
    if (stacked) {
      // A stacked column reaches the sum of its parts, so the scale is the
      // tallest sum, not the largest part: positives stack up from the axis
      // and negatives down from it.
      final columns = series.map((s) => s.data.length).reduce(math.max);
      for (var i = 0; i < columns; i++) {
        var up = 0.0, down = 0.0;
        for (final s in series) {
          if (i >= s.data.length) continue;
          if (s.data[i] >= 0) {
            up += s.data[i];
          } else {
            down += s.data[i];
          }
        }
        maxValue = math.max(maxValue, up);
        minValue = math.min(minValue, down);
      }
    } else {
      for (final s in series) {
        for (final v in s.data) {
          maxValue = math.max(maxValue, v);
          minValue = math.min(minValue, v);
        }
      }
    }
    if (maxValue == minValue) maxValue = minValue + 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _withUnit(_num(maxValue, RendelStringsScope.of(context).numberLocale), unit),
          style: theme.text.captionTabular,
          // The two axis labels below this are capped; this was the only
          // caption in the catalog that could wrap to three lines and push
          // the plot down the plate.
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),

        SizedBox(height: theme.space.xs),
        // Only the painting is replaced by the description; the axis labels
        // and the legend beside it are real text and stay readable.
        Semantics(
          label: description,
          excludeSemantics: true,
          // A chart is the one block that repaints for reasons other than its
          // own data, so it gets its own layer.
          child: RepaintBoundary(
            // A CustomPaint canvas is never mirrored: `_PlotPainter` always
            // draws data[0] at x=0. The label row below it is directional, so
            // in RTL the first label sat over the last data point and the
            // chart stated the wrong endpoints. Flipping the canvas — rather
            // than pinning the labels to LTR — keeps the data reading
            // start-to-end in both directions and leaves a label written in
            // Arabic to lay itself out in Arabic.
            child: Transform(
              alignment: Alignment.center,
              transform: Directionality.of(context) == TextDirection.rtl
                  ? (Matrix4.identity()..scaleByDouble(-1.0, 1.0, 1.0, 1.0))
                  : Matrix4.identity(),
              child: CustomPaint(
                size: Size(double.infinity, theme.size.plotHeight),
                painter: _PlotPainter(
                  bar: kind == 'bar' || stacked,
                  stacked: stacked,
                  area: kind == 'area',
                  series: [for (final s in series) s.data],
                  minValue: math.min(0, minValue),
                  maxValue: maxValue,
                  // The v6 hairline. A single series of bars is drawn by
                  // `_Bars`; what reaches here is a line, an area, or grouped
                  // or stacked bars, which keep their structure and only
                  // soften their lines.
                  grid: theme.hairline,
                  colors: [
                    for (var i = 0; i < series.length; i++)
                      _seriesColor(theme, i)
                  ],
                ),
              ),
            ),
          ),
        ),
        if (labels.isNotEmpty) ...[
          SizedBox(height: theme.space.sm),
          // Flexible, not a Spacer between two unbounded Texts: the schema
          // allows 40 characters per label, and two of them overflow the plate
          // on a 320pt phone at the default font scale.
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  labels.first,
                  style: theme.text.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (labels.length > 1) ...[
                SizedBox(width: theme.space.sm),
                Flexible(
                  child: Text(
                    labels.last,
                    style: theme.text.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

/// One series of bars (blocks v6): the latest value read out first, large,
/// with a line saying where it is and whether it is the highest; then one
/// rounded bar per label with the label under it. No grid and no axis
/// maximum — the readout and the bars' own heights carry the scale.
///
/// The latest bar is lit like the primary action and its label set in full
/// ink; every other bar is a 10% tint of the ink, and a month with nothing in
/// it is a small dot rather than a sliver of bar.
///
/// A tap on a bar reads that one out instead, and lights it; a second tap
/// goes back to the latest. The bars carried no values at all, so a month
/// other than the last could only be guessed from its height (Grove report).
class _Bars extends StatefulWidget {
  const _Bars({
    required this.labels,
    required this.data,
    required this.unit,
    required this.description,
  });

  final List<String> labels;
  final List<double> data;
  final String? unit;
  final String description;

  @override
  State<_Bars> createState() => _BarsState();
}

class _BarsState extends State<_Bars> {
  /// The bar read out; null is the latest.
  int? _shown;

  @override
  Widget build(BuildContext context) {
    final labels = widget.labels;
    final data = widget.data;
    final unit = widget.unit;
    final description = widget.description;
    final theme = RendelThemeScope.of(context);
    final last = (_shown != null && _shown! < data.length) ? _shown! : data.length - 1;
    final peak = data.reduce(math.max);
    final top = peak > 0 ? peak : 1.0;
    final latest = data[last];
    final latestLabel = last < labels.length ? labels[last] : '';
    final height = theme.size.plotHeight;
    final said = _chartFormat(data, unit, RendelStringsScope.of(context).numberLocale);

    Widget bar(int i) {
      final value = data[i];
      if (value <= 0) {
        return Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.colors.onSurface.withValues(alpha: 0.18),
          ),
        );
      }
      final radius = BorderRadius.circular(10);
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 34),
        child: Container(
          height: math.max(6.0, value / top * height),
          decoration: i == last
              ? _lit(theme, radius, shadow: const [
                  BoxShadow(
                    color: Color(0x66000000),
                    offset: Offset(0, 10),
                    blurRadius: 20,
                    spreadRadius: -12,
                  ),
                ])
              : BoxDecoration(
                  color: theme.colors.onSurface.withValues(alpha: 0.10),
                  borderRadius: radius,
                ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                _withUnit(said(latest), unit),
                style: theme.text.displayTabular,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (latestLabel.isNotEmpty) ...[
              SizedBox(width: theme.space.sm),
              Flexible(
                child: Text(
                  RendelStringsScope.of(context)
                      .readoutAt(latestLabel,
                          peak: latest >= peak, now: _isWhen(latestLabel)),
                  style: theme.text.body,
                ),
              ),
            ],
          ],
        ),
        SizedBox(height: theme.space.md + theme.space.hair),
        Semantics(
          label: description,
          excludeSemantics: true,
          child: RepaintBoundary(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // 8 apart, closing up when there are so many bars that the
                // gaps would take the plate.
                final gap = math.min(
                  theme.space.sm,
                  constraints.maxWidth / data.length * 0.25,
                );
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < data.length; i++) ...[
                      if (i > 0) SizedBox(width: gap),
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => setState(
                            () => _shown = _shown == i || i == data.length - 1 && _shown == null ? null : i,
                          ),
                          child: Column(
                          children: [
                            SizedBox(
                              height: height,
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: bar(i),
                              ),
                            ),
                            SizedBox(height: theme.space.sm),
                            Text(
                              i < labels.length ? labels[i] : '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: i == last
                                  ? theme.text.caption.copyWith(
                                      color: theme.colors.onSurface,
                                      fontWeight: FontWeight.w600,
                                    )
                                  : theme.text.caption,
                            ),
                          ],
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _PlotPainter extends CustomPainter {
  _PlotPainter({
    required this.bar,
    this.stacked = false,
    this.area = false,
    required this.series,
    required this.minValue,
    required this.maxValue,
    required this.grid,
    required this.colors,
  });

  final bool bar;

  /// With [bar]: one column per label, the series on top of each other.
  final bool stacked;

  /// Without [bar]: each line filled down to the axis at 12% of its ink.
  final bool area;
  final List<List<double>> series;
  final double minValue;
  final double maxValue;
  final Color grid;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i <= 2; i++) {
      final y = size.height * i / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    double yFor(double value) =>
        size.height - ((value - minValue) / (maxValue - minValue)) * size.height;

    if (bar && stacked) {
      final columns = series.map((s) => s.length).reduce(math.max);
      final columnWidth = size.width / columns;
      final gap = math.min(4.0, columnWidth * 0.2);
      final paint = Paint();
      for (var i = 0; i < columns; i++) {
        final left = i * columnWidth + gap / 2;
        final right = left + columnWidth - gap;
        var up = 0.0, down = 0.0;
        for (var s = 0; s < series.length; s++) {
          if (i >= series[s].length || series[s][i] == 0) continue;
          final value = series[s][i];
          final from = value > 0 ? up : down;
          final to = from + value;
          // A point of plate between one part and the next, as the donut
          // keeps between slices: the series' inks sit close together, and
          // the gap is what says where one part ends.
          final near = from == 0 ? 0.0 : 1.0;
          final top = yFor(math.max(from, to));
          final bottom = yFor(math.min(from, to));
          canvas.drawRect(
            Rect.fromLTRB(
              left,
              top + (value < 0 ? near : 0),
              right,
              bottom - (value > 0 ? near : 0),
            ),
            paint..color = colors[math.min(s, colors.length - 1)],
          );
          if (value > 0) {
            up = to;
          } else {
            down = to;
          }
        }
      }
      return;
    }

    if (bar) {
      final columns = series.first.length;
      if (columns == 0) return;
      final groupWidth = size.width / columns;
      final gap = math.min(4.0, groupWidth * 0.2);
      final barWidth = math.max(1.5, (groupWidth - gap) / series.length);
      final baseline = yFor(0);
      final bar = Paint();
      for (var s = 0; s < series.length; s++) {
        final seriesColor = colors[math.min(s, colors.length - 1)];
        for (var i = 0; i < series[s].length && i < columns; i++) {
          final left = i * groupWidth + gap / 2 + s * barWidth;
          final top = yFor(series[s][i]);
          canvas.drawRect(
            Rect.fromLTRB(
              left,
              math.min(top, baseline),
              left + barWidth - 0.5,
              math.max(top, baseline),
            ),
            bar..color = seriesColor,
          );
        }
      }
      return;
    }

    for (var s = 0; s < series.length; s++) {
      final data = series[s];
      final color = colors[math.min(s, colors.length - 1)];
      final path = Path();
      final step = data.length == 1 ? 0.0 : size.width / (data.length - 1);
      for (var i = 0; i < data.length; i++) {
        final point = Offset(data.length == 1 ? size.width / 2 : i * step, yFor(data[i]));
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      if (area && data.length > 1) {
        // Under the line, down to the axis: the line's own ink at 12%, so
        // three series overlapping still read as three lines.
        final base = yFor(0);
        canvas.drawPath(
          Path.from(path)
            ..lineTo(size.width, base)
            ..lineTo(0, base)
            ..close(),
          Paint()..color = color.withValues(alpha: color.a * 0.12),
        );
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      if (data.length == 1) {
        canvas.drawCircle(
          Offset(size.width / 2, yFor(data.first)),
          3,
          Paint()..color = color,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_PlotPainter old) =>
      old.bar != bar ||
      old.stacked != stacked ||
      old.area != area ||
      old.minValue != minValue ||
      old.maxValue != maxValue ||
      old.grid != grid ||
      !_sameColors(old.colors, colors) ||
      !_sameSeries(old.series, series);
}

bool _sameColors(List<Color> a, List<Color> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _sameValues(List<double> a, List<double> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _sameSeries(List<List<double>> a, List<List<double>> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].length != b[i].length) return false;
    for (var j = 0; j < a[i].length; j++) {
      if (a[i][j] != b[i][j]) return false;
    }
  }
  return true;
}

class _Donut extends StatelessWidget {
  const _Donut({
    required this.labels,
    required this.data,
    required this.description,
  });

  final List<String> labels;
  final List<double> data;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final positive = [for (final v in data) math.max(0.0, v)];
    final total = positive.fold<double>(0, (sum, v) => sum + v);
    final percents = _percentages(positive, total);
    final colors = [
      for (var i = 0; i < positive.length; i++) _sliceColor(theme, i, positive.length),
    ];
    final named = positive.asMap().keys.every(
          (i) => i < labels.length && labels[i].isNotEmpty,
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        // The ring was a fixed 104pt beside an Expanded legend. On a 320pt
        // phone a plate is 232pt wide, so ring plus gap took 52% of it and
        // never gave any back: "Groceries" was cut at the second text-size
        // step, and both names at the fourth. A chart the reader cannot name
        // is a picture.
        final ring = constraints.maxWidth.isFinite
            ? math.min(theme.size.donut, constraints.maxWidth * 0.36)
            : theme.size.donut;
        return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label: description,
          excludeSemantics: true,
          child: RepaintBoundary(
            child: CustomPaint(
              size: Size(ring, ring),

              painter: _DonutPainter(
                values: positive,
                colors: colors,
                // `lineControl`, not `surfaceSunk`: an all-zero donut is a
                // ring and nothing else, and sunk against the plate measures
                // 1.10:1 — a 104pt blank where a chart should be.
                empty: theme.lineControl,

                stroke: theme.size.donutStroke * (ring / theme.size.donut),

              ),
            ),
          ),
        ),
        SizedBox(width: theme.space.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < positive.length && i < 6; i++)
                Padding(
                  padding: EdgeInsets.only(bottom: theme.space.xs),
                  child: MergeSemantics(
                    child: Row(
                    children: [
                      // A swatch with no name attaches a colour to nothing, so
                      // an unlabelled donut reads as a plain column of
                      // percentages — the same rule the plot's legend follows.
                      Expanded(
                        child: named
                            ? _LegendMark(color: colors[i], label: labels[i])
                            : const SizedBox.shrink(),
                      ),
                      SizedBox(width: theme.space.sm),
                      // Capped, not flexible. Two flex-1 children split the
                      // legend evenly, so a percentage that never exceeds
                      // "100%" reserved half of it and the slice name — which
                      // the schema allows to be 40 characters — was left 63pt
                      // and ellipsised. Same cap the rest of the catalog uses
                      // for a trailing value.
                      _TrailingSlot(
                        child: Text(
                          total > 0 ? '${percents[i]}%' : _num(positive[i], RendelStringsScope.of(context).numberLocale),
                          style: theme.text.captionTabular,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),

                    ],
                  ),
                  ),
                ),
              if (positive.length > 6)
                Text('+${positive.length - 6} more', style: theme.text.caption),
            ],
          ),
        ),
      ],
        );
      },
    );
  }
}


/// Whole percentages that add up to 100.
///
/// Rounding each slice on its own is how a four-slice donut ends up reading
/// 46 + 30 + 12 + 13, and a legend whose column does not total 100 reads as a
/// bug in the host's own numbers. Largest remainder hands the leftover points
/// to the slices that lost the most to rounding.
List<int> _percentages(List<double> values, double total) {
  if (total <= 0) return [for (final _ in values) 0];
  final exact = [for (final v in values) v / total * 100];
  final floors = [for (final e in exact) e.floor()];
  var remaining = 100 - floors.fold<int>(0, (sum, f) => sum + f);
  final order = [for (var i = 0; i < values.length; i++) i]
    ..sort((a, b) => (exact[b] - floors[b]).compareTo(exact[a] - floors[a]));
  for (var i = 0; i < order.length && remaining > 0; i++, remaining--) {
    floors[order[i]] += 1;
  }
  return floors;
}

/// One ramp from full ink down through it, so a twenty-slice donut never needs
/// twenty invented colours.
///
/// The largest slice used to take the accent. It does not any more: a donut is
/// something the copilot is telling you, and the accent is reserved for what
/// you can act on. Full ink already marks the largest slice, and the hairline
/// gaps between arcs are what separate neighbours.
Color _sliceColor(RendelTheme theme, int index, int count) {
  final t = count <= 1 ? 0.0 : index / math.max(1, count - 1);

  // Capped at 0.55, not 0.8: past that the ramp drops under 3:1 against the
  // plate, and an 8pt swatch is the only thing attaching a name to a slice.
  return Color.lerp(theme.colors.onSurface, theme.colors.surfaceSunk, t * 0.55)!;
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.values,
    required this.colors,
    required this.empty,
    required this.stroke,
  });

  final List<double> values;
  final List<Color> colors;
  final Color empty;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (sum, v) => sum + v);
    final rect = Rect.fromLTWH(0, 0, size.width, size.height).deflate(stroke / 2);
    if (total <= 0) {
      canvas.drawArc(
        rect,
        0,
        math.pi * 2,
        false,
        Paint()
          // The ring is the only thing on screen when every value is zero, and
          // `surfaceSunk` against the plate measures 1.10:1 — a 104pt blank.
          ..color = empty

          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke,
      );
      return;
    }
    final slice = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    // Consecutive steps on the ramp sit about 1.64:1 apart, so two neighbours
    // read as one slice — and a monochrome ramp cannot answer that with more
    // colour without inventing a palette the host never chose. The boundary is
    // structural instead: a hairline of plate between every pair, which is
    // also what 1.4.11 asks for between adjacent non-text areas.
    final gap = values.length > 1
        ? math.min(0.05, math.pi * 2 / values.length / 6)
        : 0.0;
    var start = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = values[i] / total * math.pi * 2;
      // A slice keeps its full sweep until it is at least three times the
      // gap: losing a sliver entirely is worse than losing its separation.

      final inset = sweep > gap * 3 ? gap : 0.0;
      canvas.drawArc(
        rect,
        start + inset / 2,
        sweep - inset,
        false,
        slice..color = colors[i],
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.empty != empty ||
      old.stroke != stroke ||
      !_sameColors(old.colors, colors) ||
      !_sameValues(old.values, values);
}

class _LegendMark extends StatelessWidget {
  const _LegendMark({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // `radius.xs` is the step that exists for the smallest marks in the
        // catalog. A hard square here was the one corner in the product that
        // did not belong to the radius scale.
        Container(
          width: theme.size.swatch,
          height: theme.size.swatch,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(theme.radius.xs / 2),
          ),
        ),
        if (label.isNotEmpty) ...[
          SizedBox(width: theme.space.sm),
          Flexible(
            child: Text(
              label,
              style: theme.text.caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }
}

Widget buildTable(BuildContext context, WireBlock block, RendelDispatcher dispatch) {
  final theme = RendelThemeScope.of(context);
  final columns = [for (final c in _list(block.props['columns'])) _str(c) ?? ''];
  final rows = [
    for (final row in _list(block.props['rows']))
      [for (final cell in _list(row)) _str(cell) ?? ''],
  ];
  if (columns.isEmpty || rows.isEmpty) {
    return _EmptyPlate(message: block.fallbackText);
  }

  // Row heights are uniform by construction — that is what lets the sticky
  // column stay in step with the scrolling half — but uniform is not the same
  // as fixed: at the largest OS font scale a two-line cell needs more than
  // 48pt and would otherwise clip.
  final scaler = MediaQuery.textScalerOf(context);
  final headerHeight =
      math.max(38.0, scaler.scale(theme.type.overline) * 1.2 + theme.space.md);
  final rowHeight = math.max(
      _minTarget, scaler.scale(theme.type.caption) * 1.35 * 2 + theme.space.md);

  String cellAt(int row, int column) =>
      column < rows[row].length ? rows[row][column] : '';

  // A column of figures lines up on the right, in tabular digits (v6). The
  // first column names the row, so it is never one.
  final numeric = [
    for (var c = 0; c < columns.length; c++)
      c > 0 &&
          rows.every((row) {
            final value = c < row.length ? row[c].trim() : '';
            return value.isEmpty || _figure.hasMatch(value);
          }),
  ];

  final headStyle = theme.text.overline.copyWith(fontWeight: FontWeight.w500);
  final firstStyle =
      theme.text.labelTabular.copyWith(fontWeight: FontWeight.w600);

  Widget cell(
    String value, {
    required bool header,
    required bool sticky,
    required bool figure,
  }) =>
      Container(
        height: header ? headerHeight : rowHeight,
        alignment: figure
            ? AlignmentDirectional.centerEnd
            : AlignmentDirectional.centerStart,
        padding: EdgeInsets.symmetric(horizontal: theme.space.md),
        child: Text(
          value,
          // Two lines then an ellipsis: a cell that grows to six lines
          // destroys the table it belongs to.
          maxLines: header ? 1 : 2,
          overflow: TextOverflow.ellipsis,
          textAlign: figure ? TextAlign.end : TextAlign.start,
          style: header
              ? headStyle
              : sticky
                  ? firstStyle
                  : theme.text.labelSoftTabular,
        ),
      );

  final columnScale =
      math.max(1.0, scaler.scale(theme.type.caption) / theme.type.caption);
  // One hairline under the head, lighter ones between the rows.
  final between = theme.colors.onSurface.withValues(alpha: 0.06);

  Widget column(int index, {required bool sticky, required double width}) =>
      SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            cell(columns[index],
                header: true, sticky: sticky, figure: numeric[index]),
            for (var r = 0; r < rows.length; r++)
              _Divided(
                first: false,
                color: r == 0 ? theme.hairline : between,
                child: Semantics(
                  // Traversal is column-major, so every value has to name the
                  // column it belongs to or it is read as a bare number.
                  label: '${columns[index]}, ${cellAt(r, index)}',
                  excludeSemantics: true,
                  child: cell(
                    cellAt(r, index),
                    header: false,
                    sticky: sticky,
                    figure: numeric[index],
                  ),
                ),
              ),
          ],
        ),
      );

  return _Plate(
    padding: EdgeInsets.symmetric(
      horizontal: theme.space.xs + theme.space.hair,
      vertical: theme.space.xs,
    ),
    // The cells scale with the reader's text size, so the columns do too — but
    // the screen does not. Unclamped, a sticky column at the largest OS font
    // scale took most of the plate and left the other columns a slit to
    // scroll through. Nothing overflowed, because clipping is what a
    // horizontal scroll view is for, which is why this needs measuring rather
    // than an overflow test.
    child: LayoutBuilder(
      builder: (context, constraints) {
        final rest = columns.length - 1;
        if (rest == 0) {
          return column(0, sticky: true, width: constraints.maxWidth);
        }
        final stickyWidth = math.min(
          theme.size.stickyColumn * columnScale,
          constraints.maxWidth * 0.45,
        );
        // The columns share the plate's width rather than leaving half of it
        // empty, and scroll only when they cannot fit at their least.
        final room = constraints.maxWidth - stickyWidth;
        final least = theme.size.column * columnScale;
        final fits = rest * least <= room;
        final others = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var c = 1; c < columns.length; c++)
              column(c, sticky: false, width: fits ? room / rest : least),
          ],
        );
        // No divider after the pinned column: the first column's weight
        // already says where the names end.
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            column(0, sticky: true, width: stickyWidth),
            Expanded(
              child: fits
                  ? others
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: others,
                    ),
            ),
          ],
        );
      },
    ),
  );
}

/// A cell that is a figure: a number with at most a short prefix or suffix —
/// `$1,284`, `25.0 cm`, `+18%`, `−3`.
final RegExp _figure =
    RegExp(r'^[^\d\s]{0,3}\s?[-+−]?\d[\d.,\s]*\s?[^\d\s]{0,4}$');

Widget buildMediaGallery(
  BuildContext context,
  WireBlock block,
  RendelDispatcher dispatch,
) {
  final theme = RendelThemeScope.of(context);
  final images = _maps(block.props['images']);
  final carousel = block.props['layout'] == 'carousel';
  if (images.isEmpty) return buildFallback(context, block);

  String altFor(int i) =>
      _str(images[i]['alt']) ?? 'Image ${i + 1} of ${images.length}';

  // A picture, as a video's poster when it is one, with its caption under it
  // (`design/CATALOG-B6.md`).
  Widget tile(int i, {required double width, required double height}) => _GalleryTile(
        url: _str(images[i]['url']),
        alt: altFor(i),
        caption: _str(images[i]['caption']),
        video: _str(images[i]['video_url']),
        width: width,
        height: height,
        dispatch: dispatch,
      );

  if (carousel) {
    // A caption makes the tiles as tall as their words, which the rail then
    // measures; without one they are all one height by construction.
    final captioned = images.any((image) => _str(image['caption'])?.isNotEmpty ?? false);
    return _Rail(
      height: captioned ? null : theme.size.tileHeight,
      itemWidth: theme.size.tileWidth,
      children: [
        for (var i = 0; i < images.length; i++)
          tile(i, width: theme.size.tileWidth, height: theme.size.tileHeight),
      ],
    );
  }

  final columns = images.length <= 2 ? images.length : 3;
  return LayoutBuilder(
    builder: (context, constraints) {
      final gap = theme.space.sm;
      final side = (constraints.maxWidth - gap * (columns - 1)) / columns;
      // A trailing row of one tile in a three-wide grid leaves a hole where a
      // picture should be. The last row keeps the row height and shares the
      // full width instead, so the gallery reads as one composed block.
      final remainder = images.length % columns;
      final lastRowStart = remainder == 0 ? images.length : images.length - remainder;
      final lastSide = remainder == 0
          ? side
          : (constraints.maxWidth - gap * (remainder - 1)) / remainder;

      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (var i = 0; i < images.length; i++)
            tile(i, width: i < lastRowStart ? side : lastSide, height: side),
        ],
      );
    },
  );
}

// ————————————————————————— form —————————————————————————

Widget buildForm(BuildContext context, WireBlock block, RendelDispatcher dispatch) {
  return _FormBlock(block: block, dispatch: dispatch);
}

class _FormBlock extends StatefulWidget {
  const _FormBlock({required this.block, required this.dispatch});

  final WireBlock block;
  final RendelDispatcher dispatch;

  @override
  State<_FormBlock> createState() => _FormBlockState();
}

class _FormBlockState extends State<_FormBlock> {
  /// Working values live on the block, not in this State: a form that is
  /// scrolled out of the thread and back is the same form, with the same half
  /// of it filled in. Reading them through the current widget rather than
  /// caching them means a swapped block never leaves the fields stale.
  Map<String, dynamic> get _values => _valuesIn(widget.block);

  static Map<String, dynamic> _valuesIn(WireBlock block) {
    final existing = block.props[RendelLocalKeys.values];
    if (existing is Map<String, dynamic>) return existing;
    final fresh =
        existing is Map ? existing.cast<String, dynamic>() : <String, dynamic>{};
    block.props[RendelLocalKeys.values] = fresh;
    return fresh;
  }

  /// An upload field's files, on the block for the same reason as the values,
  /// and read by block rather than through the widget: an upload outlives the
  /// State that started it when the form is scrolled away mid-flight.
  static List<_FormFile> _filesIn(WireBlock block, String name) {
    var all = block.props[RendelLocalKeys.files];
    if (all is! Map) block.props[RendelLocalKeys.files] = all = <String, List<_FormFile>>{};
    final existing = all[name];
    if (existing is List<_FormFile>) return existing;
    final fresh = <_FormFile>[if (existing is List) ...existing.whereType<_FormFile>()];
    all[name] = fresh;
    return fresh;
  }

  List<_FormFile> _filesOf(String name) => _filesIn(widget.block, name);

  /// The ids an upload field submits: its files that have landed, in the
  /// order they were picked. A field with no files of its own here — one the
  /// copilot prefilled with ids — keeps what its value says.
  List<String> _uploadIds(String name) {
    final all = widget.block.props[RendelLocalKeys.files];
    if (all is! Map || all[name] == null) {
      return _list(_values[name]).whereType<String>().toList();
    }
    return [for (final file in _filesOf(name)) if (file.id != null) file.id!];
  }

  /// The fields the user changed themselves, on the block for the same reason
  /// as the values: the controller reads it when the copilot redraws this
  /// form, and when it tells the server which answers are the user's.
  Set<String> get _edited {
    final existing = widget.block.props[RendelLocalKeys.edited];
    if (existing is Set<String>) return existing;
    final fresh = <String>{
      if (existing is Iterable) ...existing.whereType<String>(),
    };
    widget.block.props[RendelLocalKeys.edited] = fresh;
    return fresh;
  }

  final Map<String, String> _errors = {};
  final Map<String, TextEditingController> _controllers = {};

  /// One per field typed into, so the block can say which field has the
  /// keyboard, and the form that replaces it can hand it back.
  final Map<String, FocusNode> _focus = {};
  bool _sending = false;
  String? _formError;

  /// Only fields the wire actually named. A field with no `name` has nowhere
  /// to put its value, so it is not drawn rather than drawn and then crashing
  /// on the first keystroke.
  List<Map> get _fields => [
        for (final field in _maps(widget.block.props['fields']))
          if (_str(field['name']) != null) field,
      ];

  bool get _submitted => widget.block.props[RendelLocalKeys.submitted] == true;

  @override
  void initState() {
    super.initState();
    for (final field in _fields) {
      final name = _str(field['name'])!;
      // Prefill, but never over the top of something the user already typed:
      // a form scrolled out of the thread and back keeps its own answers.
      for (final seed in formFieldSeeds(field).entries) {
        _values.putIfAbsent(seed.key, () => seed.value);
      }
      if (_typed(field)) {
        _controllers[name] =
            TextEditingController(text: _values[name]?.toString() ?? '');
        final node = FocusNode()..addListener(() => _noteFocus(name));
        _focus[name] = node;
      }
    }

    // This form replaced one whose field had the keyboard. Asked for once,
    // after the first frame, when the field exists to take it.
    // Looked up before it is removed: a block with no props at all carries a
    // read-only map, and removing even an absent key from one throws.
    final refocus = widget.block.props[RendelLocalKeys.refocus];
    final node = refocus is String ? _focus[refocus] : null;
    if (node != null) {
      widget.block.props.remove(RendelLocalKeys.refocus);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) node.requestFocus();
      });
    }
  }

  void _noteFocus(String name) {
    final props = widget.block.props;
    if (_focus[name]?.hasFocus ?? false) {
      props[RendelLocalKeys.focused] = name;
    } else if (props[RendelLocalKeys.focused] == name) {
      props.remove(RendelLocalKeys.focused);
    }
  }

  @override
  void didUpdateWidget(_FormBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.block, widget.block)) return;
    for (final entry in _controllers.entries) {
      final text = _values[entry.key]?.toString() ?? '';
      if (entry.value.text != text) entry.value.text = text;
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final node in _focus.values) {
      node.dispose();
    }
    super.dispose();
  }

  String _labelOf(Map field) => _str(field['label']) ?? _str(field['name']) ?? '';

  bool _isBlank(Object? value) =>
      value == null || (value is String && value.trim().isEmpty);

  /// Every write from a control lands here, so the one `mounted` check after
  /// an awaited picker or sheet lives in one place instead of four.
  void _set(String name, Object? value) => _write(name, {name: value});

  /// [entries] under the keys [field] is sent with: its name, or a date
  /// range's two days.
  void _write(String field, Map<String, Object?> entries) {
    if (!mounted) return;
    _values.addAll(entries);
    // Only this path marks a field: every control reports here on a user's
    // change and never on a programmatic one, so a value the copilot put in
    // stays the copilot's to change.
    _edited.addAll(entries.keys);
    setState(() {
      _errors.remove(field);
      _formError = null;
    });
  }

  /// Where an upload field may pick from: the camera and the library for a
  /// photo, the file picker for a document. A host's own picker is offered as
  /// the one source and stands in for all three, so it opens for any field.
  List<RendelAttachSource> _sourcesFor(String? accept) {
    final offered = widget.dispatch.fileSources;
    final fit = switch (accept) {
      'image' => offered.where((source) => source != RendelAttachSource.files),
      'document' => offered.where((source) => source == RendelAttachSource.files),
      _ => offered,
    }.toList();
    return fit.isEmpty ? offered : fit;
  }

  /// Picks a file for [field] and starts its upload at once, so the wait is
  /// spent while the rest of the form is filled in, as the composer does it.
  Future<void> _attach(Map field) async {
    final pick = widget.dispatch.onPickFile;
    final upload = widget.dispatch.onUpload;
    if (pick == null || upload == null) return;
    final name = _str(field['name'])!;
    final strings = RendelStringsScope.of(context);
    final theme = RendelThemeScope.of(context);

    final sources = _sourcesFor(_str(field['accept']));
    final RendelAttachSource? source;
    if (sources.length == 1) {
      source = sources.single;
    } else {
      final picked = await _pickOption(
        context,
        theme,
        [
          for (final source in sources)
            {
              'label': switch (source) {
                RendelAttachSource.photos => strings.photos,
                RendelAttachSource.camera => strings.camera,
                RendelAttachSource.files => strings.files,
              },
              'value': source.name,
            },
        ],
        title: _labelOf(field),
      );
      source = RendelAttachSource.values.where((s) => s.name == picked).firstOrNull;
    }
    if (source == null || !mounted) return;

    final RendelAttachment? picked;
    try {
      picked = await pick(source);
    } catch (_) {
      // A picker that threw is the host's to log; the field says it once, so
      // the add tile has not silently stopped working.
      if (mounted) setState(() => _errors[name] = strings.attachFailed);
      return;
    }
    if (picked == null || !mounted) return;

    final block = widget.block;
    final file = _FormFile(picked);
    _filesIn(block, name).add(file);
    _set(name, _uploadIds(name));
    file.done = upload(picked).then<void>(
      (id) => file.id = id,
      onError: (Object error) {
        // The server's own sentence when it gave one: "that file is over
        // 20 MB" is something the user can act on.
        file.error = (error is RendelUploadFailure ? error.message : null) ??
            strings.attachFailed;
      },
    ).whenComplete(() => _landed(block, name, file));
  }

  /// An upload finished, for better or worse. Written to [block] whether or
  /// not this State is still the one drawing it.
  void _landed(WireBlock block, String name, _FormFile file) {
    final files = _filesIn(block, name);
    if (file.error != null) files.remove(file);
    _valuesIn(block)[name] = [for (final f in files) if (f.id != null) f.id!];
    if (!mounted || !identical(block, widget.block)) return;
    setState(() {
      if (file.error != null) _errors[name] = file.error!;
    });
  }

  /// Takes a file off [name]. One still uploading is let go: when it lands
  /// it is no longer among the field's files, so its id is never sent.
  void _detach(String name, _FormFile file) {
    _filesOf(name).remove(file);
    _set(name, _uploadIds(name));
  }

  /// Whatever [field] holds for a date range: its two days, either missing.
  List<String?> _rangeOf(Map field) => [
        for (final key in formFieldKeys(field)) _str(_values[key]),
      ];

  Future<void> _submit() async {
    // Files go up as soon as they are picked, and an id that does not exist
    // yet is a file the server never sees, so Send waits for the last of
    // them, showing that it is sending, rather than refusing the press.
    final uploading = [
      for (final field in _fields)
        if (field['kind'] == 'upload')
          for (final file in _filesOf(_str(field['name'])!))
            if (file.id == null && file.error == null) file,
    ];
    if (uploading.isNotEmpty) {
      setState(() {
        _sending = true;
        _formError = null;
      });
      await Future.wait([for (final file in uploading) file.done]);
      if (!mounted) return;
      // A file that failed on the way is said under its field. Sending the
      // form without it would be sending something the user did not mean.
      if (uploading.any((file) => file.error != null)) {
        setState(() => _sending = false);
        return;
      }
    }

    final strings = RendelStringsScope.of(context);
    final errors = <String, String>{};
    final payload = <String, Object>{};

    for (final field in _fields) {
      final name = _str(field['name'])!;
      final kind = _str(field['kind']) ?? 'text';
      final required = field['required'] == true;
      final raw = _values[name];

      if (kind == 'number' && field['stepper'] == true) {
        // A stepper always shows a number, so it always sends the one shown.
        payload[name] = _stepperValue(field, raw);
        continue;
      }

      if (kind == 'number') {
        final text = raw?.toString().trim() ?? '';
        if (text.isEmpty) {
          if (required) errors[name] = strings.fieldRequired;
          continue;
        }
        final parsed = num.tryParse(text);
        if (parsed == null) {
          errors[name] = strings.fieldNumber;
          continue;
        }
        final min = _dbl(field['min']);
        final max = _dbl(field['max']);
        if (min != null && parsed < min) {
          errors[name] = strings.fieldAtLeastOf(_numText(min));
          continue;
        }
        if (max != null && parsed > max) {
          errors[name] = strings.fieldAtMostOf(_numText(max));
          continue;
        }
        payload[name] = parsed;
        continue;
      }

      if (kind == 'multi_select' || kind == 'upload') {
        final chosen = kind == 'upload'
            ? _uploadIds(name)
            : _list(raw).whereType<String>().toList();
        if (chosen.isEmpty) {
          if (required) errors[name] = strings.fieldRequired;
          continue;
        }
        payload[name] = chosen;
        continue;
      }

      if (kind == 'date_range') {
        // Two keys or none: half a range is not a range the server can use.
        final keys = formFieldKeys(field);
        final range = _rangeOf(field);
        if (range.contains(null)) {
          if (required) errors[name] = strings.fieldRequired;
          continue;
        }
        // The pickers hold to the bounds; a prefill need not, and neither
        // need an end the model put before its start.
        final wrong = _dayOutOfBounds(strings, field, range[0]!) ??
            _dayOutOfBounds(strings, field, range[1]!) ??
            (range[1]!.compareTo(range[0]!) < 0
                ? strings.fieldOnOrAfterOf(range[0]!)
                : null);
        if (wrong != null) {
          errors[name] = wrong;
          continue;
        }
        payload[keys[0]] = range[0]!;
        payload[keys[1]] = range[1]!;
        continue;
      }

      if (kind == 'date' && !_isBlank(raw)) {
        final wrong = _dayOutOfBounds(strings, field, raw.toString());
        if (wrong != null) {
          errors[name] = wrong;
          continue;
        }
      }

      if (kind == 'toggle') {
        // A toggle always has a value, so "required" cannot mean "not empty";
        // it means the user has to say yes — and saying so as
        // "<label> is required" produces a sentence nobody can act on.
        final on = raw == true;
        if (required && !on) {
          errors[name] = strings.fieldSwitchRequired;
          continue;
        }
        payload[name] = on;
        continue;
      }

      if (_isBlank(raw)) {
        if (required) errors[name] = strings.fieldRequired;
        continue;
      }
      payload[name] = raw.toString();
    }

    if (errors.isNotEmpty) {
      setState(() {
        // Set only while it waited on an upload; the form is open again.
        _sending = false;
        _errors
          ..clear()
          ..addAll(errors);
        // The per-field messages are correct, but in a six-field form they sit
        // above the fold the Send button is in, so pressing Send appeared to
        // do nothing at all. This slot is directly above the button.
        _formError = errors.length == 1
            ? '1 field above needs fixing.'
            : '${errors.length} fields above need fixing.';
      });
      return;
    }

    setState(() {
      _errors.clear();
      _formError = null;
      _sending = true;
    });

    final formId = _str(widget.block.props['form_id']) ?? widget.block.id;
    final outcome = await widget.dispatch.onSubmitForm(formId, payload);

    if (outcome != RendelSubmitOutcome.sent) {
      // Two different failures that used to share one sentence. "Still
      // working" over an error bar reading "the connection dropped" is a
      // contradiction, and it points away from the retry that would help.
      if (!mounted) return;
      setState(() {
        _sending = false;
        final strings = RendelStringsScope.of(context);
        _formError = outcome == RendelSubmitOutcome.busy
            ? strings.formBusy
            : strings.formFailedWith(
                _str(widget.block.props['submit_label']) ?? strings.send,
              );
      });
      return;
    }

    // The block's props are the durable record, so the submitted flag is
    // written before the mounted check: a form scrolled out of the list while
    // the request was in flight must not come back live and re-submittable.
    widget.block.props[RendelLocalKeys.submitted] = true;
    if (!mounted) return;
    setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final fields = _fields;
    if (fields.isEmpty) return _EmptyPlate(message: widget.block.fallbackText);

    // Locking a form replaces the tallest block in the catalog with a short
    // receipt; doing that in one frame is the biggest unannounced jump the
    // thread can make.
    return RendelSwap(
      stateKey: _submitted ? 'sent' : 'open',
      child: _submitted ? _sentView(theme, fields) : _formView(theme, fields),
    );
  }

  // A sent form is a record of what was sent. It stops asking, so it loses its
  // edge and settles into a field, the same move a resolved confirm card makes.
  Widget _sentView(RendelTheme theme, List<Map> fields) => _Plate(

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _BlockTitle(widget.block.props['title']),
            for (final field in fields)
              if (_sentValue(field) case final shown?)
                _KeyValueRow(label: _labelOf(field), value: shown),
            SizedBox(height: theme.space.md),
            Semantics(
              liveRegion: true,
              child: _Resolution(icon: Icons.check_rounded, label: RendelStringsScope.of(context).sent),
            ),
          ],
        ),
      );

  /// What the receipt of a sent form says for [field], or nothing when it
  /// was left empty.
  String? _sentValue(Map field) {
    final name = _str(field['name'])!;
    final raw = _values[name];
    switch (_str(field['kind'])) {
      case 'date_range':
        final range = _rangeOf(field);
        return range.contains(null) ? null : '${range[0]} – ${range[1]}';
      case 'upload':
        // The files by name: the ids are the server's, not the user's.
        final landed = [
          for (final file in _filesOf(name))
            if (file.id != null) file.name,
        ];
        return landed.isEmpty ? null : landed.join(', ');
      case 'number' when field['stepper'] == true:
        return _numText(_stepperValue(field, raw));
    }
    if (raw is List && raw.isEmpty) return null;
    return raw == null ? null : _displayValue(field, raw);
  }

  Widget _fieldOf(Map field) {
    final name = _str(field['name'])!;
    final kind = _str(field['kind']);
    final canAttach =
        widget.dispatch.onPickFile != null && widget.dispatch.onUpload != null;
    final control = _Field(
      field: field,
      controller: _controllers[name],
      focusNode: _focus[name],
      value: switch (kind) {
        'date_range' => _rangeOf(field),
        _ => _values[name],
      },
      error: _errors[name],
      enabled: !_sending,
      onChanged: kind == 'date_range'
          ? (range) => _write(name, {
                for (final (i, key) in formFieldKeys(field).indexed)
                  key: (range as List)[i],
              })
          : (value) => _set(name, value),
      files: kind == 'upload' ? _filesOf(name) : null,
      onAttach: kind == 'upload' && canAttach ? () => _attach(field) : null,
      onDetach: (file) => _detach(name, file),
    );
    // Filled from the person's notes, until they change it themselves.
    if (field['remembered'] != true || formFieldKeys(field).any(_edited.contains)) return control;
    final theme = RendelThemeScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        control,
        Padding(
          padding: EdgeInsets.fromLTRB(theme.space.md, 0, theme.space.md, theme.space.xs),
          child: _Remembered(dispatch: widget.dispatch),
        ),
      ],
    );
  }

  Widget _formView(RendelTheme theme, List<Map> fields) => _Plate(
        enclosure: _Enclosure.live,
        child: Column(

          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _BlockTitle(widget.block.props['title']),
            // v6 "F3": the fields are the rows of one white panel, divided
            // by the hairline, each led by the glyph of its kind.
            Container(
              width: double.infinity,
              clipBehavior: Clip.antiAlias,
              decoration: _white(theme, theme.radius.card + theme.space.hair),
              // One group, so the device fills a name, an email and an
              // address together rather than one field at a time.
              child: AutofillGroup(
                child: Column(
                  children: [
                    for (var i = 0; i < fields.length; i++)
                      _Divided(
                        first: i == 0,
                        child: _fieldOf(fields[i]),
                      ),
                  ],
                ),
              ),
            ),
            // Its own slot rather than a conditional insert: appearing at
            // full height in one frame shoved the Send button out from under
            // the finger that had just pressed it, and the enclosing swap then
            // clipped the button while the box caught up.
            RendelSwap(
              stateKey: _formError ?? 'none',
              child: _formError == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: EdgeInsets.only(top: theme.space.md),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          _formError!,
                          style: theme.text.caption
                              .copyWith(color: theme.colors.onSurface),
                        ),
                      ),
                    ),
            ),
            SizedBox(height: theme.space.md),
            RendelActionButton(
              // Send / Sending… / Sent: one verb through the whole flow.
              label: _sending
                  ? RendelStringsScope.of(context).sending
                  : (_str(widget.block.props['submit_label']) ??
                      RendelStringsScope.of(context).send),
              onTap: _sending ? null : _submit,
              expand: true,
            ),
          ],
        ),
      );
}

String _displayValue(Map field, Object? value) {
  if (value is bool) return value ? 'Yes' : 'No';
  if (value is List) {
    final labels = {
      for (final option in _maps(field['options']))
        option['value']: _str(option['label']) ?? '',
    };
    return [for (final picked in value) labels[picked] ?? _str(picked) ?? ''].join(', ');
  }
  if (field['kind'] == 'select') {
    for (final option in _maps(field['options'])) {
      if (option['value'] == value) return _str(option['label']) ?? '';
    }
  }
  return _str(value) ?? '';
}

/// One field of a form, as a row of the form's panel (blocks v6, "F3"): the
/// glyph of its kind on a tile, the label over the value, and a caret where
/// there is a choice to open. A field that may stay empty says "Optional" at
/// the far edge of its label; the required ones are not marked, which is the
/// rarer word to read on a form that is mostly required.
class _Field extends StatelessWidget {
  const _Field({
    required this.field,
    required this.controller,
    this.focusNode,
    required this.value,
    required this.error,
    required this.enabled,
    required this.onChanged,
    this.files,
    this.onAttach,
    this.onDetach,
  });

  final Map field;
  final TextEditingController? controller;
  final FocusNode? focusNode;

  /// The field's value; for a `date_range`, its start and end as a list of
  /// two, either of them null, and [onChanged] is handed the same shape.
  final Object? value;
  final String? error;
  final bool enabled;
  final ValueChanged<Object?> onChanged;

  /// An `upload` field's files, the control that adds one (null where the
  /// build cannot pick or upload), and the one that takes one away.
  final List<_FormFile>? files;
  final VoidCallback? onAttach;
  final ValueChanged<_FormFile>? onDetach;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final strings = RendelStringsScope.of(context);
    final kind = _str(field['kind']) ?? 'text';
    // Falls back to the field's name, as the form's own `_labelOf` does. The
    // schema requires a label, but rule 8 is degrade rather than break, and an
    // empty one left the control with no accessible name at all and its error
    // announced with a leading comma.
    final label = _str(field['label']) ?? _str(field['name']) ?? '';
    final required = field['required'] == true;
    final placeholder = _str(field['placeholder']);
    final inset = theme.space.sm + theme.space.hair;

    final valueStyle = theme.text.label.copyWith(fontSize: theme.type.body);
    final hintStyle = valueStyle.copyWith(
      color: theme.colors.onSurfaceFaint,
      fontWeight: FontWeight.w400,
    );

    // The label stays above the value. A placeholder that doubles as the
    // label disappears exactly when the user needs it most. "Optional" is
    // pushed to the opposite edge, because set next to the label it simply
    // reads as the last word of it.
    final header = Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            label,
            style: theme.text.overline.copyWith(
              color: theme.colors.onSurfaceSoft,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        if (!required) ...[
          SizedBox(width: theme.space.sm),
          // Flexible: laid out first at unbounded width, a flag grew to 202pt
          // at the largest font scale and left the label 76pt to wrap in.
          // Drawn, not read: the control's own `isRequired` flag tells a
          // screen reader which fields must be filled.
          Flexible(
            child: ExcludeSemantics(
              child: Text(
                strings.optional,
                style:
                    theme.text.overline.copyWith(fontWeight: FontWeight.w400),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),

        ],
      ],
    );

    Widget labelled(Widget shown) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [header, SizedBox(height: theme.space.hair), shown],
        );

    // [top] for the rows that grow — chips, a long note, thumbnails — whose
    // glyph stays level with the label instead of drifting to the middle.
    Widget row(IconData glyph, Widget body, {Widget? end, bool top = false}) => Padding(
          padding:
              EdgeInsets.symmetric(horizontal: theme.space.md, vertical: inset),
          child: Row(
            crossAxisAlignment:
                top ? CrossAxisAlignment.start : CrossAxisAlignment.center,
            children: [
              ExcludeSemantics(child: _GlyphTile(icon: glyph)),
              SizedBox(width: theme.space.md),
              Expanded(child: body),
              if (end != null) ...[SizedBox(width: theme.space.sm), end],
            ],
          ),
        );

    final caret = Icon(
      Icons.expand_more_rounded,
      size: theme.type.body,
      color: theme.colors.onSurfaceFaint,
    );
    final still = MediaQuery.disableAnimationsOf(context);
    final motion = still ? Duration.zero : theme.motion.settle;
    // Turned over while what it opens is open, as on the web.
    Widget caretOf(bool open) => AnimatedRotation(
          turns: open ? 0.5 : 0,
          duration: motion,
          curve: theme.motion.curve,
          child: caret,
        );

    // What a select, a day or a time opens: a sheet in the field's own row,
    // under the label and the value and the row's width, not a dialog or a
    // route over the app (no picker of the platform's is drawn anywhere in a
    // form). Nothing open is a zero-height slot, so the row grows and
    // shrinks in place.
    Widget sheetSlot(Widget? sheet) => AnimatedSize(
          duration: motion,
          curve: theme.motion.curve,
          alignment: Alignment.topCenter,
          child: sheet == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: EdgeInsets.fromLTRB(theme.space.md, 0, theme.space.md, inset),
                  child: Container(
                    width: double.infinity,
                    clipBehavior: Clip.antiAlias,
                    decoration: _white(theme, theme.radius.card * 0.8),
                    child: sheet,
                  ),
                ),
        );

    final name = _str(field['name']) ?? label;

    final Widget content;
    switch (kind) {
      case 'toggle':
        final on = value == true;
        content = Semantics(
          isRequired: required ? true : null,
          child: Semantics(
            toggled: on,
            enabled: enabled,
            label: label,
            // The tap action has to sit on this node: excludeSemantics drops
            // the gesture detector's own, and a switch a reader cannot flip
            // is not a switch.
            onTap: enabled ? () => onChanged(!on) : null,
            excludeSemantics: true,
            child: _Keyed(
              onTap: enabled ? () => onChanged(!on) : null,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: enabled ? () => onChanged(!on) : null,
                // The whole row is the switch's target, so it is never under
                // 44pt however small the track is drawn.
                child: row(
                  Icons.toggle_on_outlined,
                  labelled(Text(on ? 'Yes' : 'No', style: valueStyle)),
                  end: _SwitchMark(on: on, enabled: enabled),
                ),
              ),
            ),
          ),
        );
      case 'select':
        final options = _maps(field['options']);
        final selected = options.where((o) => o['value'] == value).firstOrNull;
        final shown = selected != null
            ? (_str(selected['label']) ?? '')
            : (placeholder ?? 'Choose an option');
        content = _Unfolding(
          key: ValueKey('select:$name'),
          enabled: enabled,
          builder: (context, open, show, node) {
            // `options` is optional in the schema, so a select can legally
            // arrive with none. Opening onto nothing is worse than not
            // opening: everywhere else here an unusable control is inert.
            final flip = enabled && options.isNotEmpty
                ? () => show(open == null ? 'list' : null)
                : null;
            return Column(
              children: [
                Semantics(
                  isRequired: required ? true : null,
                  child: _Keyed(
                    focusNode: node('list'),
                    onTap: flip,
                    child: RendelPressable(
                      semanticLabel: '$label, ${selected != null ? shown : 'not chosen'}',
                      expanded: options.isEmpty ? null : open != null,
                      onTap: flip,
                      child: row(
                        Icons.format_list_bulleted_rounded,
                        labelled(Text(
                          shown,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: selected != null ? valueStyle : hintStyle,
                        )),
                        end: caretOf(open != null),
                      ),
                    ),
                  ),
                ),
                sheetSlot(open == null
                    ? null
                    : _OptionList(
                        choices: [
                          for (final o in options)
                            if (_str(o['value']) case final v?)
                              (value: v, label: _str(o['label']) ?? v),
                        ],
                        chosen: selected != null ? _str(selected['value']) : null,
                        // Past a dozen, a list is scrolled through rather
                        // than read, so it gets a search field whether or not
                        // the model asked for one.
                        searchable: field['searchable'] == true || options.length > 12,
                        onPick: (picked) {
                          onChanged(picked);
                          show(null);
                        },
                      )),
              ],
            );
          },
        );
      case 'date':
        final chosen = _str(value);
        final day = _dayOf(chosen);
        final shown = day != null
            ? _dayWords(context, day)
            : chosen ?? placeholder ?? strings.chooseDate;
        content = _Unfolding(
          key: ValueKey('date:$name'),
          enabled: enabled,
          builder: (context, open, show, node) {
            final flip = enabled ? () => show(open == null ? 'day' : null) : null;
            return Column(
              children: [
                Semantics(
                  isRequired: required ? true : null,
                  child: _Keyed(
                    focusNode: node('day'),
                    onTap: flip,
                    child: RendelPressable(
                      semanticLabel:
                          '$label, ${day != null ? _spokenDay(context, day) : chosen ?? strings.notChosen}',
                      expanded: open != null,
                      onTap: flip,
                      child: row(
                        Icons.calendar_today_outlined,
                        labelled(Text(
                          shown,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: chosen != null ? valueStyle.tabular : hintStyle,
                        )),
                        end: caretOf(open != null),
                      ),
                    ),
                  ),
                ),
                sheetSlot(open == null
                    ? null
                    : _MonthSheet(
                        value: chosen,
                        first: _str(field['min_date']),
                        last: _str(field['max_date']),
                        onPick: (picked) {
                          onChanged(picked);
                          show(null);
                        },
                      )),
              ],
            );
          },
        );
      case 'time':
        final chosen = _str(value);
        final held = chosen != null && _hourMinute.hasMatch(chosen) ? chosen : null;
        final shown = held != null
            ? _clockWords(context, held)
            : chosen ?? placeholder ?? strings.chooseTime;
        content = _Unfolding(
          key: ValueKey('time:$name'),
          enabled: enabled,
          builder: (context, open, show, node) {
            final flip = enabled ? () => show(open == null ? 'time' : null) : null;
            return Column(
              children: [
                Semantics(
                  isRequired: required ? true : null,
                  child: _Keyed(
                    focusNode: node('time'),
                    onTap: flip,
                    child: RendelPressable(
                      semanticLabel: '$label, ${held != null ? shown : chosen ?? strings.notChosen}',
                      expanded: open != null,
                      onTap: flip,
                      child: row(
                        Icons.schedule_outlined,
                        labelled(Text(
                          shown,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: chosen != null ? valueStyle.tabular : hintStyle,
                        )),
                        end: caretOf(open != null),
                      ),
                    ),
                  ),
                ),
                sheetSlot(open == null
                    ? null
                    : _OptionList(
                        choices: _quarterHours(context, held),
                        chosen: held,
                        start: _nextQuarter(DateTime.now()),
                        onPick: (picked) {
                          onChanged(picked);
                          show(null);
                        },
                      )),
              ],
            );
          },
        );
      case 'date_range':
        final range = _list(value);
        final start = range.isNotEmpty ? _str(range[0]) : null;
        final end = range.length > 1 ? _str(range[1]) : null;
        final first = _str(field['min_date']);
        final last = _str(field['max_date']);
        content = _Unfolding(
          key: ValueKey('range:$name'),
          enabled: enabled,
          builder: (context, open, show, node) {
            // From and To, each its own button opening a month under the
            // two, as on the web.
            Widget half(String key, String caption, String? held) {
              final day = _dayOf(held);
              final isOpen = open == key;
              final flip = enabled ? () => show(isOpen ? null : key) : null;
              return _Keyed(
                focusNode: node(key),
                onTap: flip,
                radius: 10,
                child: RendelPressable(
                  semanticLabel:
                      '$label, $caption, ${day != null ? _spokenDay(context, day) : held ?? strings.notChosen}',
                  expanded: isOpen,
                  onTap: flip,
                  child: AnimatedContainer(
                    duration: motion,
                    curve: theme.motion.curve,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: theme.tint,
                      borderRadius: BorderRadius.circular(10),
                      // The open half is ringed, so it is plain which day
                      // the month under them picks.
                      border: Border.all(
                        color: isOpen ? theme.colors.onSurface : theme.colors.onSurface.withValues(alpha: 0),
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(caption, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.text.caption),
                        Text(
                          day != null ? _shortDayWords(context, day) : held ?? strings.choose,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: held != null ? valueStyle.tabular : hintStyle,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            return Column(
              children: [
                Semantics(
                  container: true,
                  isRequired: required ? true : null,
                  child: row(
                    Icons.date_range_outlined,
                    labelled(Padding(
                      padding: EdgeInsets.only(top: theme.space.xs),
                      child: Row(
                        children: [
                          Expanded(child: half('start', strings.dateRangeStart, start)),
                          SizedBox(width: theme.space.sm),
                          Expanded(child: half('end', strings.dateRangeEnd, end)),
                        ],
                      ),
                    )),
                    top: true,
                  ),
                ),
                sheetSlot(switch (open) {
                  'start' => _MonthSheet(
                      key: const ValueKey('start'),
                      value: start,
                      first: first,
                      last: last,
                      onPick: (picked) {
                        // To is kept while it is still on or after From;
                        // otherwise it is cleared, and its month opens next.
                        final keep = end != null && end.compareTo(picked) >= 0;
                        onChanged([picked, keep ? end : null]);
                        show(keep ? null : 'end');
                      },
                    ),
                  'end' => _MonthSheet(
                      key: const ValueKey('end'),
                      value: end,
                      // To starts no earlier than From, where From is set.
                      first: start ?? first,
                      last: last,
                      onPick: (picked) {
                        onChanged([start, picked]);
                        show(null);
                      },
                    ),
                  _ => null,
                }),
              ],
            );
          },
        );
      case 'multi_select':
        final options = _maps(field['options']);
        final picked = _list(value).whereType<String>().toSet();
        // The value is kept in the options' own order, whatever order they
        // were tapped in, so the same picks always read the same.
        void toggle(String option) {
          final next = {...picked};
          if (!next.remove(option)) next.add(option);
          onChanged([
            for (final o in options)
              if (next.contains(_str(o['value']))) _str(o['value'])!,
          ]);
        }

        content = Semantics(
          container: true,
          isRequired: required ? true : null,
          child: row(
            Icons.checklist_rounded,
            labelled(Padding(
              padding: EdgeInsets.only(top: theme.space.xs),
              child: Wrap(
                spacing: theme.space.sm,
                runSpacing: theme.space.sm,
                children: [
                  // Each its own node: a lone chip would otherwise merge
                  // with the field's label into one checkbox named by both.
                  for (final option in options)
                    if (_str(option['value']) case final id?)
                      Semantics(
                        container: true,
                        child: _ChoiceChip(
                          label: _str(option['label']) ?? id,
                          on: picked.contains(id),
                          multi: true,
                          onTap: enabled ? () => toggle(id) : null,
                        ),
                      ),
                ],
              ),
            )),
            top: true,
          ),
        );
      case 'upload':
        final photo = field['accept'] == 'image';
        final most = field['max_files'] is int ? field['max_files'] as int : 1;
        final attached = files ?? const <_FormFile>[];
        content = Semantics(
          container: true,
          isRequired: required ? true : null,
          child: row(
            photo ? Icons.photo_camera_outlined : Icons.attach_file_rounded,
            labelled(Padding(
              padding: EdgeInsets.only(top: theme.space.xs),
              child: Wrap(
                spacing: theme.space.sm,
                runSpacing: theme.space.sm,
                children: [
                  for (final file in attached)
                    _UploadThumb(
                      file: file,
                      onRemove: enabled && onDetach != null
                          ? () => onDetach!(file)
                          : null,
                    ),
                  if (attached.length < most)
                    _UploadAdd(
                      label: photo ? strings.uploadAddPhoto : strings.uploadAdd,
                      onTap: enabled ? onAttach : null,
                    ),
                ],
              ),
            )),
            top: true,
          ),
        );
      case 'number' when field['stepper'] == true:
        final min = _dbl(field['min']);
        final max = _dbl(field['max']);
        final step = _dbl(field['step']) ?? 1;
        final shown = _stepperValue(field, value);
        final down = min == null || shown > min
            ? _clampNum(_stepBy(shown, -step), min, max)
            : null;
        final up = max == null || shown < max
            ? _clampNum(_stepBy(shown, step), min, max)
            : null;
        Widget press(IconData icon, num? to) => RendelPressable(
              semanticLabel: '',
              onTap: enabled && to != null ? () => onChanged(to) : null,
              child: SizedBox(
                width: _minTarget,
                height: _minTarget,
                child: Icon(
                  icon,
                  size: theme.type.heading,
                  color: enabled && to != null
                      ? theme.colors.onSurface
                      : theme.colors.onSurfaceFaint,
                ),
              ),
            );
        // One adjustable node, as a platform stepper is: a screen reader
        // hears the label and the number, and swipes it up and down.
        content = Semantics(
          isRequired: required ? true : null,
          child: Semantics(
            label: label,
            value: _numText(shown),
            increasedValue: up == null ? null : _numText(up),
            decreasedValue: down == null ? null : _numText(down),
            onIncrease: enabled && up != null ? () => onChanged(up) : null,
            onDecrease: enabled && down != null ? () => onChanged(down) : null,
            excludeSemantics: true,
            child: row(
              Icons.tag_rounded,
              labelled(Align(
                alignment: AlignmentDirectional.centerStart,
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.colors.surfaceHigh,
                    border: Border.all(color: theme.hairline),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      press(Icons.remove_rounded, down),
                      Flexible(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minWidth: 28),
                          child: Text(
                            _numText(shown),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: valueStyle.tabular,
                          ),
                        ),
                      ),
                      press(Icons.add_rounded, up),
                    ],
                  ),
                ),
              )),
            ),
          ),
        );
      default:
        final numeric = kind == 'number';
        final multiline = kind == 'multiline';
        // A text field has no name of its own, so the visible label above it
        // merges into its node. The row around it hands a tap anywhere on it
        // to the field.
        content = GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: enabled ? () => focusNode?.requestFocus() : null,
          child: row(
            switch (kind) {
              'number' => Icons.tag_rounded,
              'multiline' => Icons.notes_rounded,
              'email' => Icons.alternate_email_rounded,
              'tel' => Icons.call_outlined,
              'url' => Icons.link_rounded,
              _ => Icons.short_text_rounded,
            },
            MergeSemantics(
              child: labelled(
                Semantics(
                  isRequired: required ? true : null,
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    enabled: enabled,
                    // The platform's own keyboard for the kind: the @ on the
                    // first screen, the dial pad, the .com key.
                    keyboardType: switch (kind) {
                      'number' =>
                        const TextInputType.numberWithOptions(decimal: true),
                      'multiline' => TextInputType.multiline,
                      'email' => TextInputType.emailAddress,
                      'tel' => TextInputType.phone,
                      'url' => TextInputType.url,
                      _ => TextInputType.text,
                    },
                    // A description grows with what is typed, from three
                    // lines to eight, and scrolls after that.
                    minLines: multiline ? 3 : 1,
                    maxLines: multiline ? 8 : 1,
                    autofillHints: switch (_autofillHints[_str(field['autofill'])]) {
                      final hint? => [hint],
                      null => null,
                    },
                    style: numeric ? valueStyle.tabular : valueStyle,
                    onChanged: onChanged,
                    decoration: InputDecoration(
                      filled: false,
                      isDense: true,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      hintText: placeholder,
                      hintStyle: hintStyle,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        content,
        if (error != null)
          // The message sits under the field it is about, aligned with its
          // label, not in a summary at the top of a form the user has already
          // scrolled past — and outside the merge, or the whole field
          // re-announces on every keystroke. It names its own field: two
          // empty required fields produced two identical "Fill this in to
          // continue." stops with nothing saying which was which.
          Padding(
            padding: EdgeInsetsDirectional.only(
              start: theme.space.md * 2 + 34,
              end: theme.space.md,
              bottom: inset,
            ),
            child: Semantics(
              container: true,
              liveRegion: true,
              label: '$label, ${error!}',
              excludeSemantics: true,
              child: Text(
                error!,
                style:
                    theme.text.caption.copyWith(color: theme.colors.onSurface),
              ),
            ),
          ),
      ],
    );
  }
}

/// A form control's enclosure, for a host drawing a control of its own beside
/// the catalog's: white with the hairline at the card's corner (blocks v6),
/// the ring a step heavier when the field is wrong. The catalog's own form
/// draws its fields as the rows of one panel instead.
class RendelControlShell extends StatelessWidget {
  const RendelControlShell({super.key, required this.child, this.invalid = false});

  final Widget child;
  final bool invalid;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: _minTarget),
      decoration: BoxDecoration(
        color: theme.colors.surfaceHigh,
        border: Border.all(
          color: invalid ? theme.lineControl : theme.hairline,
          width: invalid ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(theme.radius.card),
      ),
      padding: EdgeInsets.symmetric(horizontal: theme.space.md),
      alignment: AlignmentDirectional.centerStart,

      child: child,
    );
  }
}

/// Where an upload field's file comes from, when the build offers more than
/// one place (the camera, the library, the files): a sheet of the SDK's own
/// rows. A form's select, day and time open in the field's row instead.
Future<String?> _pickOption(
  BuildContext context,
  RendelTheme theme,
  List<Map> options, {
  required String title,
}) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: theme.colors.surface,
    useSafeArea: true,
    builder: (sheetContext) => RendelThemeScope(
      theme: theme,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                theme.space.plate,
                theme.space.lg,
                theme.space.plate,
                theme.space.sm,
              ),
              child: RendelOverline(title),
            ),
            for (final option in options)
              RendelPressable(
                semanticLabel: _str(option['label']) ?? '',
                onTap: () => Navigator.of(sheetContext).pop(_str(option['value']) ?? ''),
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(
                    horizontal: theme.space.plate,
                    vertical: theme.space.md,
                  ),
                  child: Text(_str(option['label']) ?? '', style: theme.text.label),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// Keyboard focus and Enter/Space for a control the SDK draws itself: a
/// field that opens a sheet, an option, a day. Touch and a screen reader go
/// through the [RendelPressable] inside it; this adds what a hardware
/// keyboard needs, and a ring in the accent's edge while the keyboard is on
/// it. It adds no semantics node of its own.
class _Keyed extends StatefulWidget {
  const _Keyed({
    required this.onTap,
    required this.child,
    this.focusNode,
    this.autofocus = false,
    this.radius = 12,
  });

  final VoidCallback? onTap;
  final Widget child;
  final FocusNode? focusNode;
  final bool autofocus;
  final double radius;

  @override
  State<_Keyed> createState() => _KeyedState();
}

class _KeyedState extends State<_Keyed> {
  bool _ring = false;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    void activate() => widget.onTap?.call();
    return FocusableActionDetector(
      enabled: widget.onTap != null,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      includeFocusSemantics: false,
      onShowFocusHighlight: (on) {
        if (mounted && on != _ring) setState(() => _ring = on);
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          activate();
          return null;
        }),
        ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(onInvoke: (_) {
          activate();
          return null;
        }),
      },
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: _ring
            ? BoxDecoration(
                border: Border.all(color: theme.accentEdge, width: 2),
                borderRadius: BorderRadius.circular(widget.radius),
              )
            : const BoxDecoration(),
        child: widget.child,
      ),
    );
  }
}

/// Which sheet a field has open in its row, if any: a select's options, a
/// month, a time's quarter hours, or one of a range's two months. Escape
/// closes it, and closing it hands the keyboard back to the button that
/// opened it, as the web SDK does. A form that is sending closes it.
class _Unfolding extends StatefulWidget {
  const _Unfolding({super.key, required this.enabled, required this.builder});

  final bool enabled;
  final Widget Function(
    BuildContext context,
    String? open,
    ValueChanged<String?> show,
    FocusNode Function(String key) node,
  ) builder;

  @override
  State<_Unfolding> createState() => _UnfoldingState();
}

class _UnfoldingState extends State<_Unfolding> {
  String? _open;
  final Map<String, FocusNode> _nodes = {};

  FocusNode _node(String key) => _nodes.putIfAbsent(key, () => FocusNode(debugLabel: key));

  void _show(String? which) {
    if (!mounted || which == _open) return;
    final was = _open;
    setState(() => _open = which);
    if (which == null && was != null) _nodes[was]?.requestFocus();
  }

  @override
  void didUpdateWidget(_Unfolding old) {
    super.didUpdateWidget(old);
    if (!widget.enabled) _open = null;
  }

  @override
  void dispose() {
    for (final node in _nodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
        bindings: {
          if (_open != null) const SingleActivator(LogicalKeyboardKey.escape): () => _show(null),
        },
        child: widget.builder(context, _open, _show, _node),
      );
}

/// A toggle's switch, drawn by the SDK rather than the platform: a 44 by 26
/// track and a white knob that slides across it, the accent's fill when on
/// and the strong line when off, as the web SDK draws its own. Only a mark:
/// the row it sits in is the target and carries the `toggled` semantics.
class _SwitchMark extends StatelessWidget {
  const _SwitchMark({required this.on, required this.enabled});

  final bool on;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: AnimatedContainer(
        duration: duration,
        curve: theme.motion.curve,
        width: 44,
        height: 26,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: on ? theme.colors.accent : theme.colors.lineStrong,
          borderRadius: BorderRadius.circular(999),
        ),
        child: AnimatedAlign(
          duration: duration,
          curve: theme.motion.curve,
          alignment: on ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
          child: Container(
            width: 20,
            height: 20,
            decoration: const BoxDecoration(
              color: Color(0xFFFFFFFF),
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Color(0x40000000), offset: Offset(0, 1), blurRadius: 3)],
            ),
          ),
        ),
      ),
    );
  }
}

/// An option a field's list offers: what it sends, and what it says.
typedef _Option = ({String value, String label});

/// A list of [choices] in a field's row: a select's options, or a time's
/// quarter hours. The one [chosen] is tinted and ticked; opened, the list is
/// scrolled to it, or to [start] with nothing chosen, and the keyboard lands
/// there. A [searchable] list has a search field over the options; Enter in
/// it picks the first one it leaves. At most 264 tall, then it scrolls.
class _OptionList extends StatefulWidget {
  const _OptionList({
    required this.choices,
    required this.chosen,
    required this.onPick,
    this.searchable = false,
    this.start,
  });

  final List<_Option> choices;
  final String? chosen;
  final ValueChanged<String> onPick;
  final bool searchable;
  final String? start;

  @override
  State<_OptionList> createState() => _OptionListState();
}

class _OptionListState extends State<_OptionList> {
  static const double _row = 44;
  static const double _most = 264;
  static const double _pad = 4;

  var _query = '';
  late final ScrollController _scroll;

  String? get _at => widget.chosen ?? widget.start;

  @override
  void initState() {
    super.initState();
    // Every row is one line at 44, so where the one to show sits is known
    // before anything is laid out: in the middle of the list's window.
    final count = widget.choices.length;
    final index = math.max(0, widget.choices.indexWhere((c) => c.value == _at));
    final whole = count * _row + _pad * 2;
    final window = math.min(_most, whole);
    final offset = (index * _row - (window - _row) / 2).clamp(0.0, math.max(0.0, whole - window));
    _scroll = ScrollController(initialScrollOffset: offset.toDouble());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final strings = RendelStringsScope.of(context);
    final needle = _query.trim().toLowerCase();
    final shown = needle.isEmpty
        ? widget.choices
        : [
            for (final c in widget.choices)
              if (c.label.toLowerCase().contains(needle)) c,
          ];
    final textStyle = theme.text.label.copyWith(fontSize: theme.type.body);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.searchable)
          DecoratedBox(
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: theme.hairline))),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: TextField(
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: (text) {
                  setState(() => _query = text);
                  if (_scroll.hasClients) _scroll.jumpTo(0);
                },
                // Enter in a form's field would otherwise send nothing at all.
                onSubmitted: (_) {
                  if (shown.isNotEmpty) widget.onPick(shown.first.value);
                },
                style: textStyle,
                decoration: InputDecoration(
                  filled: false,
                  isDense: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  hintText: strings.searchOptions,
                  hintStyle: textStyle.copyWith(
                    color: theme.colors.onSurfaceFaint,
                    fontWeight: FontWeight.w400,
                  ),
                  icon: Icon(
                    Icons.search_rounded,
                    size: theme.type.heading,
                    color: theme.colors.onSurfaceSoft,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(strings.nothingToShow, style: theme.text.labelSoft),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: _most),
            child: ListView.builder(
              controller: _scroll,
              shrinkWrap: true,
              padding: const EdgeInsets.all(_pad),
              itemCount: shown.length,
              itemBuilder: (context, i) {
                final choice = shown[i];
                final on = choice.value == widget.chosen;
                void pick() => widget.onPick(choice.value);
                return _Keyed(
                  // The keyboard lands on the one chosen, or else the first.
                  autofocus: !widget.searchable && choice.value == (_at ?? shown.first.value),
                  onTap: pick,
                  radius: 10,
                  child: RendelPressable(
                    semanticLabel: choice.label,
                    selected: on,
                    onTap: pick,
                    pressedScale: 0.98,
                    child: Container(
                      constraints: const BoxConstraints(minHeight: _row),
                      alignment: AlignmentDirectional.centerStart,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: on
                          ? BoxDecoration(color: theme.tint, borderRadius: BorderRadius.circular(10))
                          : null,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              choice.label,
                              // `labelStrong` is onAccent ink, legible on an
                              // accent fill and nowhere else; the list is a
                              // plain surface.
                              style: on ? theme.text.labelEmphasis : theme.text.label,
                            ),
                          ),
                          if (on) ...[
                            SizedBox(width: theme.space.sm),
                            Icon(Icons.check_rounded, size: theme.type.body, color: theme.colors.onSurface),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

/// A month of days to pick one from, drawn by the SDK in a date field's row
/// (the web SDK's calendar): the month and year between the two buttons that
/// turn it, the week starting on the day the host's locale starts it
/// (Monday where nothing says), today ringed, the day picked lit like the
/// primary, and the days before [first] or after [last] there but not to be
/// picked. The buttons stop at the bounds. Opened, it shows the month of
/// the day it holds, or of today held to the bounds, and the keyboard lands
/// on that day; the arrows move between days.
class _MonthSheet extends StatefulWidget {
  const _MonthSheet({
    super.key,
    required this.value,
    required this.first,
    required this.last,
    required this.onPick,
  });

  /// The day held, as YYYY-MM-DD, or null.
  final String? value;

  /// The bounds, as YYYY-MM-DD: `min_date` and `max_date`.
  final String? first;
  final String? last;
  final ValueChanged<String> onPick;

  @override
  State<_MonthSheet> createState() => _MonthSheetState();
}

class _MonthSheetState extends State<_MonthSheet> {
  late DateTime _month;
  late DateTime _landing;

  DateTime? get _lo => _dayOf(widget.first);
  DateTime? get _hi => _dayOf(widget.last);

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    var at = _dayOf(widget.value) ?? DateTime(now.year, now.month, now.day);
    final lo = _lo;
    final hi = _hi;
    if (lo != null && at.isBefore(lo)) at = lo;
    if (hi != null && at.isAfter(hi)) at = hi;
    _landing = at;
    _month = DateTime(at.year, at.month);
  }

  bool _outside(DateTime day) {
    final lo = _lo;
    final hi = _hi;
    return (lo != null && day.isBefore(lo)) || (hi != null && day.isAfter(hi));
  }

  void _turn(int by) => setState(() => _month = DateTime(_month.year, _month.month + by));

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final strings = RendelStringsScope.of(context);
    final material = _material(context);
    // 0 is Sunday, as MaterialLocalizations counts.
    final weekStart = material?.firstDayOfWeekIndex ?? 1;
    final year = _month.year;
    final month = _month.month;
    final days = DateTime(year, month + 1, 0).day;
    final lead = (DateTime(year, month).weekday % 7 - weekStart + 7) % 7;
    final lo = _lo;
    final hi = _hi;
    final canBack = lo == null || !DateTime(year, month, 0).isBefore(lo);
    final canOn = hi == null || !DateTime(year, month + 1).isAfter(hi);
    final now = DateTime.now();
    final chosen = _dayOf(widget.value);

    Widget turn(IconData icon, String name, VoidCallback? onTap) => _Keyed(
          onTap: onTap,
          radius: 999,
          child: RendelPressable(
            semanticLabel: name,
            onTap: onTap,
            pressedScale: 0.92,
            child: Center(
              child: Opacity(
                opacity: onTap == null ? 0.35 : 1,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: theme.tint, shape: BoxShape.circle),
                  child: Icon(icon, size: 18, color: theme.colors.onSurface),
                ),
              ),
            ),
          ),
        );

    final dayStyle = theme.text.label.copyWith(fontSize: 14, fontWeight: FontWeight.w500).tabular;

    Widget cell(DateTime day, double side) {
      final off = _outside(day);
      final on = chosen != null && DateUtils.isSameDay(day, chosen);
      final today = DateUtils.isSameDay(day, now);
      final pick = off ? null : () => widget.onPick(_isoDay(day));
      return _Keyed(
        autofocus: DateUtils.isSameDay(day, _landing),
        onTap: pick,
        radius: 999,
        child: RendelPressable(
          semanticLabel: _spokenDay(context, day),
          selected: on,
          onTap: pick,
          pressedScale: 0.92,
          child: Center(
            child: Container(
              width: side,
              height: side,
              alignment: Alignment.center,
              decoration: on
                  ? _lit(theme, BorderRadius.circular(999), shadow: const [])
                  : today
                      ? BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: theme.rail, width: 1.5),
                        )
                      : null,
              child: Text(
                '${day.day}',
                style: on
                    ? dayStyle.copyWith(color: theme.colors.onAccent, fontWeight: FontWeight.w600)
                    : off
                        ? dayStyle.copyWith(color: theme.colors.onSurfaceFaint.withValues(alpha: 0.5))
                        : today
                            ? dayStyle.copyWith(fontWeight: FontWeight.w600)
                            : dayStyle,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              turn(Icons.chevron_left_rounded, strings.previousMonth, canBack ? () => _turn(-1) : null),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    material?.formatMonthYear(_month) ?? '${strings.shortMonths[month - 1]} $year',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.text.label.copyWith(fontSize: 14.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              turn(Icons.chevron_right_rounded, strings.nextMonth, canOn ? () => _turn(1) : null),
            ],
          ),
          SizedBox(height: theme.space.xs),
          // Each day's button says its whole date, so the letters over the
          // columns are drawn, not read.
          ExcludeSemantics(
            child: Row(
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        material?.narrowWeekdays[(weekStart + i) % 7] ??
                            strings.shortDays[((weekStart + i) % 7 + 6) % 7],
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: theme.text.caption.copyWith(fontSize: 11.5, color: theme.colors.onSurfaceFaint),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          LayoutBuilder(
            builder: (context, box) {
              final side = math.min(40.0, box.maxWidth / 7 - 2);
              final cells = <Widget?>[
                for (var i = 0; i < lead; i++) null,
                for (var d = 1; d <= days; d++) cell(DateTime(year, month, d), side),
              ];
              while (cells.length % 7 != 0) {
                cells.add(null);
              }
              return Column(
                children: [
                  for (var w = 0; w < cells.length; w += 7)
                    Row(
                      children: [
                        for (final c in cells.sublist(w, w + 7))
                          Expanded(child: c ?? const SizedBox(height: _minTarget)),
                      ],
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// The host's Material words, when it has any: the SDK carries no date
/// library, so a month's name and a day said in full come from them.
MaterialLocalizations? _material(BuildContext context) =>
    Localizations.of<MaterialLocalizations>(context, MaterialLocalizations);

/// A day as a date field shows it, in the host's language: "Nov 14, 2026".
String _dayWords(BuildContext context, DateTime day) =>
    _material(context)?.formatShortDate(day) ??
    '${day.day} ${RendelStringsScope.of(context).shortMonths[day.month - 1]} ${day.year}';

/// A day short enough for half a row: without its year in this one.
String _shortDayWords(BuildContext context, DateTime day) {
  if (day.year != DateTime.now().year) return _dayWords(context, day);
  return _material(context)?.formatShortMonthDay(day) ??
      '${day.day} ${RendelStringsScope.of(context).shortMonths[day.month - 1]}';
}

/// A day as a screen reader says it: "Saturday, November 14, 2026".
String _spokenDay(BuildContext context, DateTime day) =>
    _material(context)?.formatFullDate(day) ??
    '${RendelStringsScope.of(context).dayHeadingFor(day)} ${day.year}';

/// A time on the wire: HH:MM, 00:00 to 23:59.
final RegExp _hourMinute = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');

/// HH:MM on the device's clock: "14:30", or "2:30 PM" where the locale
/// keeps a 12-hour one.
String _clockWords(BuildContext context, String hm) {
  final at = TimeOfDay(hour: int.parse(hm.substring(0, 2)), minute: int.parse(hm.substring(3)));
  return _material(context)?.formatTimeOfDay(
        at,
        alwaysUse24HourFormat: MediaQuery.maybeAlwaysUse24HourFormatOf(context) ?? false,
      ) ??
      hm;
}

/// The day's quarter hours, sent as HH:MM and shown on the device's clock;
/// a [held] time off the quarter is listed in its place.
List<_Option> _quarterHours(BuildContext context, String? held) {
  final slots = [
    for (var i = 0; i < 96; i++) '${_two(i ~/ 4)}:${_two(i % 4 * 15)}',
  ];
  if (held != null && !slots.contains(held)) {
    slots
      ..add(held)
      ..sort();
  }
  return [for (final hm in slots) (value: hm, label: _clockWords(context, hm))];
}

/// The quarter hour at or after [now], where a time list with nothing
/// chosen opens.
String _nextQuarter(DateTime now) {
  final quarter = ((now.hour * 60 + now.minute) / 15).ceil() % 96;
  return '${_two(quarter ~/ 4)}:${_two(quarter % 4 * 15)}';
}

String _two(int value) => value.toString().padLeft(2, '0');

/// The kinds a form draws as a field to type into. Anything it does not know
/// is typed into too, as a `text` field, which degrades rather than breaks.
bool _typed(Map field) => switch (_str(field['kind'])) {
      'toggle' || 'select' || 'date' || 'time' => false,
      'multi_select' || 'date_range' || 'upload' => false,
      'number' => field['stepper'] != true,
      _ => true,
    };

/// `autofill` as the platform's hints, so the keyboard offers the user's own
/// name, address and number over the field (WCAG 1.3.5).
const Map<String, String> _autofillHints = {
  'name': AutofillHints.name,
  'email': AutofillHints.email,
  'tel': AutofillHints.telephoneNumber,
  'street_address': AutofillHints.fullStreetAddress,
  'postal_code': AutofillHints.postalCode,
  'city': AutofillHints.addressCity,
  'country': AutofillHints.countryName,
};

/// What a form says under [day] when it falls outside [field]'s `min_date`
/// or `max_date`, or nothing. Compared as YYYY-MM-DD text, which sorts as
/// the days do.
String? _dayOutOfBounds(RendelStrings strings, Map field, String day) {
  final first = _str(field['min_date']);
  final last = _str(field['max_date']);
  if (first != null && day.compareTo(first) < 0) return strings.fieldOnOrAfterOf(first);
  if (last != null && day.compareTo(last) > 0) return strings.fieldOnOrBeforeOf(last);
  return null;
}

/// A YYYY-MM-DD as a local day, or nothing for anything else.
DateTime? _dayOf(Object? value) {
  if (value is! String) return null;
  final parsed = DateTime.tryParse(value);
  return parsed == null ? null : DateTime(parsed.year, parsed.month, parsed.day);
}

String _isoDay(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-${_two(day.month)}-${_two(day.day)}';

/// The number a stepper shows: its value, or else its lowest, or else 0,
/// held to its bounds.
num _stepperValue(Map field, Object? value) {
  final min = _dbl(field['min']);
  final max = _dbl(field['max']);
  final given = value is num ? value : num.tryParse('${value ?? ''}');
  return _clampNum(given ?? min ?? 0, min, max);
}

num _clampNum(num value, double? min, double? max) {
  var held = value;
  if (min != null && held < min) held = min;
  if (max != null && held > max) held = max;
  return _tidy(held);
}

/// [value] moved by [step], rounded to the step's own decimals: 0.1 three
/// times is 0.3 here, not 0.30000000000000004.
num _stepBy(num value, num step) {
  final text = step.toString();
  final dot = text.indexOf('.');
  final decimals = text.contains('e') ? 10 : (dot == -1 ? 0 : text.length - dot - 1);
  return _tidy(double.parse((value + step).toStringAsFixed(decimals)));
}

/// A whole number as an int, so a count of 2 is sent and shown as 2, not 2.0.
num _tidy(num value) =>
    value is double && value == value.roundToDouble() && value.abs() < 1e15
        ? value.toInt()
        : value;

String _numText(num value) => _tidy(value).toString();

/// A file an upload field holds: picked, then uploading, then landed with
/// its id or failed with the sentence why.
class _FormFile {
  _FormFile(RendelAttachment file)
      : name = file.name,
        bytes = file.bytes,
        isImage = file.mediaType.startsWith('image/');

  final String name;

  /// Kept for the thumbnail. A picture the user chose is the only honest
  /// thumbnail of itself, and it came in memory anyway.
  final Uint8List bytes;
  final bool isImage;

  /// Null until the upload lands.
  String? id;

  /// Set when the upload failed: the server's sentence, or the SDK's.
  String? error;

  /// The upload, finishing either way; it never throws.
  late Future<void> done;
}

/// One file of an upload field: the picture itself or a document's face, a
/// ring over it while it uploads, and the button that takes it off. A button
/// and never a swipe, which nobody finds on a thumbnail.
class _UploadThumb extends StatelessWidget {
  const _UploadThumb({required this.file, required this.onRemove});

  final _FormFile file;
  final VoidCallback? onRemove;

  static const double side = 72;
  static const double _dot = 22;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final strings = RendelStringsScope.of(context);
    final radius = BorderRadius.circular(theme.radius.card * 0.8);
    final uploading = file.id == null;

    Widget face() => Container(
          padding: EdgeInsets.all(theme.space.xs + theme.space.hair),
          color: theme.colors.surfaceRaised,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.insert_drive_file_outlined,
                size: theme.type.heading,
                color: theme.colors.onSurfaceSoft,
              ),
              // The name takes what height is left, and at a large font
              // scale shows what fits of it rather than pushing the tile open.
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.bottomStart,
                  child: Text(
                    file.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.text.caption.copyWith(fontSize: 10, height: 1.2),
                  ),
                ),
              ),
            ],
          ),
        );

    return Semantics(
      container: true,
      label: uploading ? '${file.name}, ${strings.loading}' : file.name,
      child: SizedBox(
        width: side,
        height: side,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: ExcludeSemantics(
                child: ClipRRect(
                  borderRadius: radius,
                  child: file.isImage
                      ? Image.memory(
                          file.bytes,
                          fit: BoxFit.cover,
                          // A picture that cannot be decoded is still the file
                          // that was picked, so it falls back to the document
                          // face rather than a broken-image glyph.
                          errorBuilder: (context, _, __) => face(),
                        )
                      : face(),
                ),
              ),
            ),
            // The ring while the bytes go up: the file is visibly there and
            // visibly not ready, which is the difference between a slow
            // upload and a picker that did nothing.
            if (uploading)
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: radius,
                  child: ColoredBox(
                    color: theme.colors.surface.withValues(alpha: 0.62),
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colors.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            // Over the corner, with the 44pt target centred on the dot, so
            // the target reaches past the thumbnail into the gap beside it.
            Positioned(
              top: 4 - (_minTarget - _dot) / 2,
              right: 4 - (_minTarget - _dot) / 2,
              // Its own node, or it merges into the thumbnail's.
              child: Semantics(
                container: true,
                child: RendelPressable(
                  semanticLabel: '${strings.uploadRemove}, ${file.name}',
                  onTap: onRemove,
                  child: SizedBox(
                    width: _minTarget,
                    height: _minTarget,
                    child: Center(
                      child: Container(
                        width: _dot,
                        height: _dot,
                        decoration: BoxDecoration(
                          color: theme.colors.onSurface,
                          shape: BoxShape.circle,
                          border: Border.all(color: theme.colors.surfaceHigh, width: 2),
                        ),
                        child: Icon(
                          Icons.close_rounded,
                          size: 12,
                          color: theme.colors.surfaceHigh,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The dashed tile that adds a file or a photo, as tall as a thumbnail and
/// as wide as its words need.
class _UploadAdd extends StatelessWidget {
  const _UploadAdd({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final radius = theme.radius.card * 0.8;
    final ink = onTap == null ? theme.colors.onSurfaceFaint : theme.colors.onSurface;
    // Its own node, or it merges with the field's label into one button.
    return Semantics(
      container: true,
      child: RendelPressable(
        semanticLabel: label,
        onTap: onTap,
        child: CustomPaint(
          painter: _DashedFrame(theme.rail, radius),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: _UploadThumb.side,
              minHeight: _UploadThumb.side,
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: theme.space.md,
                vertical: theme.space.sm,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_rounded, size: theme.type.heading, color: ink),
                  SizedBox(height: theme.space.hair),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: theme.text.caption.copyWith(color: ink),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A rounded frame drawn in dashes, 4 on and 3 off.
class _DashedFrame extends CustomPainter {
  _DashedFrame(this.color, this.radius);

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final frame = Path()
      ..addRRect(RRect.fromRectAndRadius(
        (Offset.zero & size).deflate(0.75),
        Radius.circular(radius),
      ));
    for (final metric in frame.computeMetrics()) {
      for (var at = 0.0; at < metric.length; at += 7) {
        canvas.drawPath(metric.extractPath(at, math.min(at + 4, metric.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedFrame old) => old.color != color || old.radius != radius;
}

// ————————————————————————— skeletons —————————————————————————

/// The typed placeholder a block shows between `block.start` and
/// `block.ready`. It is the shape of the answer, drawn before the answer
/// arrives, which is why every type gets its own rather than sharing one grey
/// rectangle: the thread should not re-flow when the real widget lands.
/// Which blocks are asking the reader something.
///
/// The one list, so a skeleton and its block cannot disagree and a new block
/// type has to answer the question rather than inherit an answer.
_Enclosure _enclosureFor(String type) => switch (type) {
      'form' ||
      'datetime_slots' ||
      'variant_picker' ||
      'booking_card' ||
      'confirm_card' =>
        _Enclosure.live,
      _ => _Enclosure.recorded,
    };

Widget buildSkeleton(BuildContext context, String type) {

  final theme = RendelThemeScope.of(context);
  final space = theme.space;

  // The same enclosure the block will hydrate into, or the swap changes the
  // block's material under the reader: a form skeleton drawn as a field and
  // then rebuilt with an edge is a flash, not a hydration.
  Widget plated(List<Widget> children) => _Plate(
        enclosure: _enclosureFor(type),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );


  final body = switch (type) {
    'quick_replies' => Wrap(
        spacing: space.sm,
        runSpacing: space.sm,
        children: const [
          _SkBox(width: 96, height: _minTarget, rounded: true),
          _SkBox(width: 124, height: _minTarget, rounded: true),
          _SkBox(width: 80, height: _minTarget, rounded: true),
        ],
      ),
    // The hydrated block is a scrolling rail, so its placeholder is one too:
    // two cards side by side are wider than any phone, and a bare Row would
    // paint overflow stripes for the whole loading window.
    'product_cards' => _SkRail(
        height: 232,
        children: [
          _SkBox(width: theme.size.cardWidth, height: 232),
          _SkBox(width: theme.size.cardWidth, height: 232),
        ],
      ),
    'media_gallery' => Wrap(
        spacing: space.sm,
        runSpacing: space.sm,
        children: const [
          _SkBox(width: 104, height: 104),
          _SkBox(width: 104, height: 104),
          _SkBox(width: 104, height: 104),
        ],
      ),
    'item_list' => plated([
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) SizedBox(height: space.md),
          Row(
            children: [
              _SkBox(width: theme.size.rowThumb, height: theme.size.rowThumb),
              SizedBox(width: space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SkLine(widthFactor: 0.62),
                    SizedBox(height: space.xs),
                    const _SkLine(widthFactor: 0.38, height: 8),
                  ],
                ),
              ),
            ],
          ),
        ],
      ]),
    'info_card' || 'status_banner' => plated([
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SkBox(width: theme.type.heading, height: theme.type.heading),
            SizedBox(width: space.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SkLine(widthFactor: 0.56),
                  SizedBox(height: space.sm),
                  const _SkLine(widthFactor: 0.92, height: 8),
                  SizedBox(height: space.xs),
                  const _SkLine(widthFactor: 0.7, height: 8),
                ],
              ),
            ),
          ],
        ),
      ]),
    // The confirm card hydrates into a plate carrying two 44pt buttons, so a
    // generic three-line placeholder would double in height mid-crossfade —
    // exactly the reflow the block-atomic rule exists to prevent.
    'confirm_card' => plated([
        const _SkLine(widthFactor: 0.34, height: 8),
        SizedBox(height: space.md),
        const _SkLine(widthFactor: 0.9, height: 8),
        SizedBox(height: space.xs),
        const _SkLine(widthFactor: 0.7, height: 8),
        SizedBox(height: space.lg),
        Row(
          children: [
            const Expanded(
              child: _SkBox(width: double.infinity, height: _minTarget, rounded: true),
            ),
            SizedBox(width: space.sm),
            const Expanded(
              child: _SkBox(width: double.infinity, height: _minTarget, rounded: true),
            ),
          ],
        ),
      ]),
    'stat_group' => plated([
        Row(
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) SizedBox(width: space.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SkLine(widthFactor: 0.7, height: 8),
                    SizedBox(height: space.xs),
                    _SkLine(widthFactor: 0.9, height: theme.type.display),
                  ],
                ),
              ),
            ],
          ],
        ),
      ]),
    'order_tracker' => plated([
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) SizedBox(height: space.lg),
          Row(
            children: [
              _SkBox(
                width: theme.size.stepDot,
                height: theme.size.stepDot,
                rounded: true,
              ),
              SizedBox(width: space.md),
              // Expanded, because a FractionallySizedBox handed unbounded
              // width throws rather than degrading.
              const Expanded(child: _SkLine(widthFactor: 0.5)),
            ],
          ),
        ],
      ]),
    // Same shape hydrated: a stack of label/value rows.
    'receipt' || 'table' || 'key_value' => plated([
        for (var i = 0; i < 4; i++) ...[
          if (i > 0) SizedBox(height: space.md),
          Row(
            children: [
              const Expanded(child: _SkLine(widthFactor: 0.55)),
              SizedBox(width: space.md),
              const _SkBox(width: 52, height: 10),
            ],
          ),
        ],
      ]),
    'chart' => plated([
        _SkBox(width: double.infinity, height: theme.size.plotHeight),
      ]),
    'form' => plated([
        const _SkLine(widthFactor: 0.4),
        SizedBox(height: space.lg),
        const _SkBox(width: double.infinity, height: _minTarget),
        SizedBox(height: space.lg),
        const _SkBox(width: double.infinity, height: _minTarget),
        SizedBox(height: space.lg),
        const _SkBox(width: 132, height: _minTarget, rounded: true),
      ]),
    // Same shape hydrated: a title over a wrap of 44pt pills.
    'datetime_slots' || 'variant_picker' => plated([
        const _SkLine(widthFactor: 0.32),
        SizedBox(height: space.md),
        Wrap(
          spacing: space.sm,
          runSpacing: space.sm,
          children: const [
            _SkBox(width: 84, height: _minTarget, rounded: true),
            _SkBox(width: 84, height: _minTarget, rounded: true),
            _SkBox(width: 84, height: _minTarget, rounded: true),
            _SkBox(width: 84, height: _minTarget, rounded: true),
          ],
        ),
      ]),
    'booking_card' => plated([
        _SkBox(width: double.infinity, height: theme.size.heroHeight),
        SizedBox(height: space.md),
        const _SkLine(widthFactor: 0.58),
        SizedBox(height: space.sm),
        const _SkLine(widthFactor: 0.36, height: 8),
      ]),
    'article_card' => plated([
        const _SkLine(widthFactor: 0.62),
        SizedBox(height: space.sm),
        const _SkLine(widthFactor: 0.9, height: 8),
        SizedBox(height: space.xs),
        const _SkLine(widthFactor: 0.74, height: 8),
        SizedBox(height: space.lg),
        const _SkBox(width: 132, height: _minTarget, rounded: true),
      ]),
    'progress' => plated([
        const _SkLine(widthFactor: 0.44),
        SizedBox(height: space.sm),
        const _SkBox(width: double.infinity, height: 8, rounded: true),
      ]),
    // A heading has no enclosure in either place it is drawn.
    'section' => const _SkLine(widthFactor: 0.46),
    'tags' => const Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          _SkBox(width: 64, height: 26, rounded: true),
          _SkBox(width: 92, height: 26, rounded: true),
          _SkBox(width: 72, height: 26, rounded: true),
        ],
      ),
    'actions' => const _SkBox(width: double.infinity, height: 48, rounded: true),
    // Same shape hydrated: two things across the top, then rows of a label
    // over a value each.
    'comparison' => plated([
        Row(
          children: [
            for (var i = 0; i < 2; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              const Expanded(child: _SkLine(widthFactor: 0.7, height: 14)),
            ],
          ],
        ),
        for (var i = 0; i < 3; i++) ...[
          SizedBox(height: space.lg),
          const _SkLine(widthFactor: 0.3, height: 8),
          SizedBox(height: space.sm),
          Row(
            children: [
              for (var j = 0; j < 2; j++) ...[
                if (j > 0) const SizedBox(width: 12),
                const Expanded(child: _SkLine(widthFactor: 0.5)),
              ],
            ],
          ),
        ],
      ]),
    'screens' => const _SkBox(width: double.infinity, height: 68),
    // No plate either way: the question over a few pills.
    'choice' => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SkLine(widthFactor: 0.6, height: 14),
          SizedBox(height: space.md),
          const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SkBox(width: 96, height: 46, rounded: true),
              _SkBox(width: 84, height: 46, rounded: true),
              _SkBox(width: 112, height: 46, rounded: true),
            ],
          ),
        ],
      ),
    // Catalog wave 4, each the shape it hydrates into: contact on its own
    // raised plate, the other four flat on the page.
    'contact' => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          border: Border.all(color: theme.hairline),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SkLine(widthFactor: 0.6, height: 14),
            SizedBox(height: space.sm),
            const _SkLine(widthFactor: 0.9, height: 8),
            const SizedBox(height: 14),
            const _SkBox(width: double.infinity, height: 48, rounded: true),
          ],
        ),
      ),
    'rating' => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SkLine(widthFactor: 0.6, height: 14),
          SizedBox(height: space.md),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 5; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                const _SkBox(width: 36, height: 36, rounded: true),
              ],
            ],
          ),
        ],
      ),
    'disclosure' || 'checklist' => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < 3; i++)
            _Divided(
              first: i == 0,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 17),
                child: Row(
                  children: [
                    if (type == 'checklist') ...[
                      const _SkBox(width: 22, height: 22, rounded: true),
                      const SizedBox(width: 12),
                    ],
                    const Expanded(child: _SkLine(widthFactor: 0.7)),
                  ],
                ),
              ),
            ),
        ],
      ),
    'timeline' => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SkLine(widthFactor: 0.24, height: 8),
          SizedBox(height: space.sm),
          for (var i = 0; i < 3; i++)
            Container(
              padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 0, 12),
              decoration: BoxDecoration(
                border: BorderDirectional(start: BorderSide(color: theme.rail, width: 2)),
              ),
              child: const Row(
                children: [
                  SizedBox(width: 56, child: _SkLine(widthFactor: 0.7)),
                  SizedBox(width: 12),
                  Expanded(child: _SkLine(widthFactor: 0.6)),
                ],
              ),
            ),
        ],
      ),
    // Catalog wave 5: a place and a pass on their own plates, as they
    // hydrate; a map as its 200 pt ground.
    'place_card' || 'pass' => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          border: Border.all(color: theme.hairline),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (type == 'pass') ...[
              const _SkLine(widthFactor: 0.3, height: 8),
              SizedBox(height: space.sm),
            ],
            const _SkLine(widthFactor: 0.6, height: 14),
            SizedBox(height: space.sm),
            const _SkLine(widthFactor: 0.8, height: 8),
            const SizedBox(height: 14),
            if (type == 'pass')
              const Center(child: _SkBox(width: 160, height: 160))
            else
              const _SkBox(width: double.infinity, height: 48, rounded: true),
          ],
        ),
      ),
    'map' => const _SkBox(width: double.infinity, height: 200),
    // Catalog wave 6: code as its plate, a head and a few lines tall.
    'code' => const _SkBox(width: double.infinity, height: 112),
    'key_points' => plated([
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SkBox(width: 20, height: 20, rounded: true),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SkLine(widthFactor: 0.4),
                    SizedBox(height: space.xs),
                    const _SkLine(widthFactor: 0.8, height: 8),
                  ],
                ),
              ),
            ],
          ),
        ],
      ]),
    // Everything registered has its own arm above, so this is only ever the
    // unknown or host-registered type — the forward-compatibility path, where
    // `ready` hands over to `buildFallback`'s bare Text. Plating it here drew
    // an enclosure that then vanished and re-flowed the thread by 24pt.
    _ => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SkLine(widthFactor: 0.86),
          SizedBox(height: space.xs),
          const _SkLine(widthFactor: 0.52, height: 8),
        ],
      ),
  };

  return Semantics(
    label: RendelStringsScope.of(context).loading,
    excludeSemantics: true,
    child: RendelPulse(child: body),
  );
}

/// A skeleton for a block that hydrates into a rail. Unbounded width, so a
/// placeholder wider than the screen clips at the viewport exactly where the
/// real rail will, instead of overflowing its parent.
class _SkRail extends StatelessWidget {
  const _SkRail({required this.height, required this.children});

  final double height;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    return SizedBox(
      height: height,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        child: Row(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) SizedBox(width: theme.space.sm),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

class _SkBox extends StatelessWidget {
  const _SkBox({required this.width, required this.height, this.rounded = false});

  final double width;
  final double height;
  final bool rounded;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: theme.colors.surfaceSunk,
        borderRadius: BorderRadius.circular(
          rounded ? theme.radius.control : theme.radius.card,
        ),
      ),
    );
  }
}

class _SkLine extends StatelessWidget {
  const _SkLine({required this.widthFactor, this.height = 10});

  final double widthFactor;
  final double height;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      // Inert under the loose constraints of a plated arm, and not inert
      // inside an Expanded — which is where the tracker, item_list, info_card
      // and status_banner skeletons put it. In RTL a bar opened a 132pt hole
      // between a dot and its own line.
      alignment: AlignmentDirectional.centerStart,
      widthFactor: widthFactor,

      child: _SkBox(width: double.infinity, height: height),
    );
  }
}

/// The one breath in the SDK: skeletons, loading images, and the thread's
/// working dot all share it, so "not content yet" is one gesture rather than
/// three near-misses.
///
/// One controller for a whole skeleton, not one per bar. Reduced motion holds
/// it still rather than flickering the thing the setting exists to remove.
class RendelPulse extends StatefulWidget {
  const RendelPulse({super.key, required this.child});
  final Widget child;

  @override
  State<RendelPulse> createState() => _RendelPulseState();
}

class _RendelPulseState extends State<RendelPulse> with SingleTickerProviderStateMixin {
  // No theme lookup in the initialisers — see the note on _CaretState.
  late final AnimationController _controller = AnimationController(vsync: this);

  // Built once as a field, not per build. A CurvedAnimation adds a status
  // listener to its parent in its constructor, so building one inside build()
  // grew the controller's listener list by one on every rebuild — and a
  // skeleton rebuilds on every streamed token.
  late final CurvedAnimation _curve =
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut);

  late final Animation<double> _fade =
      Tween<double>(begin: 0.55, end: 0.99).animate(_curve);

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final motion = RendelThemeScope.of(context).motion;
    _controller.duration = motion.breath;
    _curve.curve = motion.breathCurve;
    if (_started) return;
    _started = true;
    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    return FadeTransition(opacity: _fade, child: widget.child);
  }
}

// ————————————————————————— shared primitives —————————————————————————

VoidCallback? _tap(RendelDispatcher dispatch, Object? raw) {
  final action = UIAction.tryParse(raw);
  // Parsing is not the same as being able to act: an `open_url` with no host
  // handler, or an `app_action` the server never stamped, is a tap that would
  // do nothing. Those are drawn as content rather than as a live control.
  if (action == null || !dispatch.canHandle(action)) return null;
  return () => dispatch.onAction(action);
}

Widget _maybePressable({
  required Object? action,
  required RendelDispatcher dispatch,
  required String semanticLabel,
  required Widget child,
}) {
  final onTap = _tap(dispatch, action);
  // A row that does nothing does not announce itself as a button and does not
  // scale under the finger. Half the catalog used to lie about this.
  //
  // It is still one thing to read, though: without the merge the row broke
  // into a title, a subtitle and a bare "£18.00" standing on its own. No
  // button role, one node.
  if (onTap == null) return MergeSemantics(child: child);
  return RendelPressable(semanticLabel: semanticLabel, onTap: onTap, child: child);
}

/// A value that ends a row: an amount, a count, a percentage, a date.
///
/// The cap has to be relative to the row, not absolute. A bare
/// `ConstrainedBox(maxWidth: theme.size.trailing)` is a NON-FLEX child, so
/// `RenderFlex` measures it first at unbounded width and it takes the whole
/// 120pt before the `Expanded` beside it is measured at all. On a 320pt phone
/// an `item_list` row is 232pt wide, so the title was left 46pt — three
/// characters of a field the schema allows 120 — at the DEFAULT text size, and
/// the donut legend's slice name was left 24pt at twice it. Neither depended
/// on the text scale, which is the tell: the loser is decided by the winner's
/// constant.
///
/// Forty percent, so the leading content always keeps the majority of its own
/// row. `theme.size.trailing` stays the ceiling for a roomy row.
class _TrailingSlot extends StatelessWidget {
  const _TrailingSlot({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: constraints.maxWidth.isFinite
              ? math.min(theme.size.trailing, constraints.maxWidth * 0.4)
              : theme.size.trailing,
        ),
        child: child,
      ),
    );
  }
}

String _joinParts(List<String?> parts) =>

    parts.whereType<String>().where((p) => p.isNotEmpty).join(', ');

/// The quiet label a block opens with.
///
/// It used to uppercase its text. It no longer does: the web surfaces set
/// this step at 75% width instead of letterspaced caps, on the principle that
/// a label should be a different voice rather than the same voice shouting,
/// and a catalog that shouted while the site whispered would not read as one
/// product. Flutter has no width axis to reach for without shipping a font,
/// so the step takes the same job with weight and quiet ink.
///
/// One implementation, so the treatment can never be applied at eight call
/// sites and forgotten at the ninth.
class RendelOverline extends StatelessWidget {
  const RendelOverline(this.text, {super.key, this.color, this.maxLines, this.part});

  final String text;
  final Color? color;
  final int? maxLines;

  /// The card part this overline is, if it is one; see [RendelTheme.part].
  final String? part;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    // Nothing is transformed any more, so the semantics wrapper that existed
    // to hand VoiceOver the original casing is gone with it: "US MEN" and
    // "WED 2 SEP" now reach the reader exactly as the server sent them.
    return Text(
          text,
          maxLines: maxLines,
          overflow: maxLines == null ? null : TextOverflow.ellipsis,
          style: _asPart(
            theme,
            part,
            color == null ? theme.text.overline : theme.text.overline.copyWith(color: color),
          ),
    );
  }
}

/// The optional heading a data block opens with, plus the gap after it. Kept
/// in one place so `chart`, `progress`, `datetime_slots` and `form` never
/// drift apart. (`receipt` composes its own title row because the currency
/// code has to share the line, and `order_tracker` because its status pill
/// does.)
class _BlockTitle extends StatelessWidget {
  const _BlockTitle(this.title);
  final Object? title;

  @override
  Widget build(BuildContext context) {
    final text = _str(title);
    if (text == null || text.isEmpty) return const SizedBox.shrink();
    final theme = RendelThemeScope.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: theme.space.md),
      child: Text(text, style: theme.text.title),
    );
  }
}

/// [base] as the card part [name], or as it is when it is no part.
TextStyle _asPart(RendelTheme theme, String? name, TextStyle base) =>
    name == null ? base : theme.part(name, base);

class _KeyValueRow extends StatelessWidget {

  const _KeyValueRow({
    required this.label,
    required this.value,
    this.strong = false,
    this.part,
    this.tone,
    this.range,
    this.masked = false,
    this.copy = false,
    this.dispatch,
  });

  /// The card part these rows are, if they are one; see [RendelTheme.part].
  final String? part;

  final String label;
  final String value;
  final bool strong;

  /// A `key_value` row's own (`design/CATALOG-B2.md`): the value's status
  /// tone, its reference range under it, shown as its last four until
  /// tapped, and a copy button at the row's end, which needs [dispatch].
  final String? tone;
  final String? range;
  final bool masked;
  final bool copy;
  final RendelDispatcher? dispatch;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final style = _asPart(
      theme,
      part,
      strong ? theme.text.displayTabular : theme.text.captionSoftTabular,
    );
    final row = MergeSemantics(
        child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        // The free space goes between them, not after them. Two loose
        // Flexibles in a start-aligned Row both hug their text and the slack
        // falls at the trailing edge, so the value sat packed against the
        // label and `textAlign: end` was a no-op on a box never wider than its
        // own string — measured, a 32.5pt spread across three amounts that are
        // meant to read as one column. Making the label `Expanded` does not
        // fix it either: both children default to flex 1 and simply split the
        // row in half.
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              style: _asPart(theme, part, strong ? theme.text.heading : theme.text.caption),

            ),
          ),
          SizedBox(width: theme.space.md),
          Flexible(
            // A receipt's total, a key_value's headline row: the one figure
            // the reader opened the block for. It was the same size as
            // "Subtotal".
            child: _FactValue(
              value: value,
              style: tone == null ? style : style.copyWith(color: _toneInk(theme, tone)),
              masked: masked,
              range: range,
            ),
          ),
        ],
        ),
      );
    return Padding(
      padding: EdgeInsets.symmetric(vertical: theme.space.hair),
      // "Subtotal" and "£118.00" are one fact. Read as two nodes, a receipt
      // becomes a column of labels followed by a column of bare numbers. The
      // copy button stays a node of its own, so the fact is not read as a
      // button.
      child: copy && dispatch != null
          ? Row(
              children: [
                Expanded(child: row),
                _CopyButton(text: value, name: label, dispatch: dispatch!),
              ],
            )
          : row,
    );
  }
}

/// The value side of a fact: in [style], shown as its last four behind dots
/// until tapped when [masked], with its reference [range] under it.
class _FactValue extends StatefulWidget {
  const _FactValue({
    required this.value,
    required this.style,
    this.masked = false,
    this.range,
  });

  final String value;
  final TextStyle style;
  final bool masked;
  final String? range;

  @override
  State<_FactValue> createState() => _FactValueState();
}

class _FactValueState extends State<_FactValue> {
  bool _shown = false;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final value = widget.value;
    final hidden = widget.masked && !_shown;
    final text = hidden
        ? '•••• ${value.length > 4 ? value.substring(value.length - 4) : value}'
        : value;
    final range = widget.range;
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text, style: widget.style, textAlign: TextAlign.end),
        if (range != null && range.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            range,
            textAlign: TextAlign.end,
            style: theme.text.caption.copyWith(fontSize: 13, color: theme.colors.onSurfaceSoft),
          ),
        ],
      ],
    );
    if (!hidden) return column;
    // Revealed for good once tapped: a number that hides itself again while
    // it is being typed into a bank form is a number typed wrong.
    return RendelPressable(
      semanticLabel: '$text, ${RendelStringsScope.of(context).reveal}',
      onTap: () => setState(() => _shown = true),
      child: Align(
        alignment: AlignmentDirectional.centerEnd,
        widthFactor: 1,
        child: column,
      ),
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule({required this.strong});
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: theme.space.sm),
      child: Container(
        height: 1,
        color: strong ? theme.rail : theme.hairline,
      ),
    );
  }
}

class _Divided extends StatelessWidget {
  const _Divided({required this.first, required this.child, this.color});
  final bool first;
  final Widget child;

  /// The line above; the hairline unless the caller wants a lighter one.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    return DecoratedBox(
      decoration: first
          ? const BoxDecoration()
          : BoxDecoration(
              border: Border(top: BorderSide(color: color ?? theme.hairline)),
            ),
      child: child,
    );
  }
}

/// What a plated block draws when its payload is empty. It says what the block
/// was for rather than presenting a 2pt bordered sliver that reads as a bug.
class _EmptyPlate extends StatelessWidget {
  const _EmptyPlate({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    return _Plate(
      child: Text(
        message.isEmpty ? RendelStringsScope.of(context).nothingToShow : message,
        style: theme.text.body,
      ),
    );
  }
}

/// A horizontal rail of cards, all the height of the tallest one.
///
/// [IntrinsicHeight] rather than a computed height: a rail height derived from
/// font metrics and item counts is a number that goes wrong the first time a
/// host changes the type scale or the reader raises the OS font size, and it
/// renders an empty band when it does. At most twelve cards ever sit in a
/// rail, so the extra layout pass is cheap.
class _Rail extends StatelessWidget {
  const _Rail({required this.children, required this.itemWidth, this.height});

  final List<Widget> children;

  /// How wide each card is, which is where a rail on a page snaps to.
  final double itemWidth;

  /// Set only when the content is uniform by construction, where a fixed
  /// height is the truth rather than a guess.
  final double? height;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final inset = RendelPage.maybeOf(context)?.inset ?? 0;
    final row = Row(
      crossAxisAlignment:
          height == null ? CrossAxisAlignment.stretch : CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(width: theme.space.sm),
          // Its own layer per card: a non-lazy horizontal viewport repaints on
          // every scroll offset, so without this a fling re-rasterises every
          // card in the rail on every frame.
          RepaintBoundary(child: children[i]),
        ],
        // Room for the last card to clear the fade below.
        SizedBox(width: theme.space.xl),
      ],
    );
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final rail = SizedBox(
      height: height,
      // A rail that scrolls says so: its trailing 28pt fades out, so the last
      // card visibly runs on past the edge.
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) => LinearGradient(
          begin: rtl ? Alignment.centerRight : Alignment.centerLeft,
          end: rtl ? Alignment.centerLeft : Alignment.centerRight,
          colors: const [
            Color(0xFF000000),
            Color(0xFF000000),
            Color(0x00000000)
          ],
          stops: [0, bounds.width <= 28 ? 0 : 1 - 28 / bounds.width, 1],
        ).createShader(bounds),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          // The rail runs out to the screen's edges, with the page's padding
          // as its own, and settles on a card's leading edge: the first card
          // lines up with the text, and so does any card it stops on
          // (`design/PAGES.md`).
          padding: EdgeInsets.symmetric(horizontal: inset),
          physics: _SnapPhysics(extent: itemWidth + theme.space.sm),
          child: height == null ? IntrinsicHeight(child: row) : row,
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) => OverflowBox(
        fit: OverflowBoxFit.deferToChild,
        minWidth: constraints.maxWidth + inset * 2,
        maxWidth: constraints.maxWidth + inset * 2,
        child: rail,
      ),
    );
  }
}

/// Settles a scroll on the nearest multiple of [extent]: a rail's card edge.
class _SnapPhysics extends ScrollPhysics {
  const _SnapPhysics({required this.extent, super.parent});

  final double extent;

  @override
  _SnapPhysics applyTo(ScrollPhysics? ancestor) =>
      _SnapPhysics(extent: extent, parent: buildParent(ancestor));

  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) {
    if ((velocity <= 0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    final tolerance = toleranceFor(position);
    var card = position.pixels / extent;
    if (velocity < -tolerance.velocity) {
      card -= 0.5;
    } else if (velocity > tolerance.velocity) {
      card += 0.5;
    }
    final target = (card.roundToDouble() * extent)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((target - position.pixels).abs() < tolerance.distance) return null;
    return ScrollSpringSimulation(
      spring,
      position.pixels,
      target,
      velocity,
      tolerance: tolerance,
    );
  }
}

/// Remote image with the states a network fetch actually has. A silent grey
/// rectangle that never resolves is indistinguishable from a bug, so both the
/// missing-url and the failed-fetch paths say so.
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({
    required this.url,
    this.width = double.infinity,
    required this.height,
    this.radius,
    this.alt,
    this.fit = BoxFit.cover,
  });

  final String? url;
  final double width;
  final double height;
  final double? radius;
  final String? alt;

  /// How the picture meets its box.
  ///
  /// `cover` is right for a photograph of a place, which is a scene with no
  /// edges that matter. It is wrong for a catalogue shot, which is one object
  /// photographed whole: covering a 4:3 box with a tall bottle cuts the cap
  /// off the top and the label off the bottom, and every product on the shelf
  /// arrives trimmed. Product cards pass `contain` and get a tinted tray
  /// around the object instead.
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final corner = radius ?? theme.radius.card;
    final still = MediaQuery.disableAnimationsOf(context);

    Widget placeholder({bool broken = true}) => Container(
          // The plate keeps a handle whether or not it draws the torn icon:
          // it is the only thing on screen when an image is absent.
          key: ValueKey(broken ? 'image:broken' : 'image:none'),
          width: width,
          height: height,
          // Never an empty grey box: a pale wash from the accent's own hue.
          decoration: BoxDecoration(
            gradient: theme.wash,
            borderRadius: BorderRadius.circular(corner),
          ),
          alignment: Alignment.center,
          child: broken
              ? Icon(
                  Icons.image_not_supported_outlined,
                  size: theme.type.heading,
                  color: theme.colors.onSurfaceSoft,
                )
              : null,
        );

    // No picture to draw is not a broken picture. Both used to render the
    // same torn-image icon, so a card whose image the server took off (an
    // untrusted host: `url-guard.ts`) looked exactly like one whose photo
    // failed to load, and neither the customer nor we could tell which from
    // the screen. An absent image is the plate alone from here.
    if (url == null) return placeholder(broken: false);

    // Decode at the size actually drawn, on whichever axis `cover` will be
    // driven by. A 2000px product shot decoded for a 40pt row is most of a
    // frame budget and all of a memory spike; passing both axes would let
    // ResizeImage distort the aspect ratio instead.
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final targetWidth = width.isFinite ? width : height;
    final decodeOnWidth = targetWidth >= height;
    final cacheWidth = decodeOnWidth ? (targetWidth * ratio).round() : null;
    final cacheHeight = decodeOnWidth ? null : (height * ratio).round();

    return Semantics(
      label: alt,
      image: alt != null,
      excludeSemantics: alt != null,
      // Its own layer: the loading pulse and the decode fade both change
      // opacity every frame, and without a boundary here a single image still
      // in flight re-rasterises the whole gallery block around it.
      child: RepaintBoundary(
        child: ClipRRect(
        borderRadius: BorderRadius.circular(corner),
        child: Image.network(
          url!,
          width: width,
          height: height,
          fit: fit,
          cacheWidth: (cacheWidth ?? 0) > 0 ? cacheWidth : null,
          cacheHeight: (cacheHeight ?? 0) > 0 ? cacheHeight : null,
          filterQuality: FilterQuality.medium,
          // Flutter composes these as loadingBuilder(frameBuilder(...)), so
          // returning the pulse *instead of* `child` tore the frameBuilder
          // subtree down for the whole fetch. It then remounted at opacity 1
          // in the same frame the photo arrived, and an implicit animation
          // does not animate on its first build: the fade below was dead on
          // every image that reports chunk events, which is every network
          // image. Keeping the child mounted underneath is what makes it run.
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return SizedBox(
              width: width,
              height: height,
              child: Stack(
                fit: StackFit.expand,
                children: [RendelPulse(child: placeholder(broken: false)), child],
              ),
            );
          },
          // The decoded frame fades in rather than hard-cutting from a
          // breathing plate to a photograph, which is the one loading-to-loaded
          // handoff in the SDK that used to snap.
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded || still) return child;
            return AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: theme.motion.swap,
              curve: theme.motion.swapIn,
              child: child,
            );
          },
          errorBuilder: (context, _, __) => placeholder(),
          ),
        ),
      ),
    );
  }
}

/// What a plate is for, which is the only thing that decides how it is drawn.
///
/// Fifteen blocks used to share one enclosure: a transparent rectangle inside
/// a 10% hairline. At thread length that is a stack of faint boxes with no
/// block prioritised over any other, and the reader has to read all of them to
/// find the one that wants something.
///
/// So the enclosure says what the block is:
///
///  * a **field** means here is what I found;
///  * an **edge** means I am waiting on you;
///  * and the accent, used nowhere else, means this is the thing to touch.
enum _Enclosure {
  /// A readout. A field of sunk surface and no edge at all, so ten of these in
  /// a row group by material instead of stacking ten hairlines.
  recorded,

  /// The copilot is waiting on an answer: a form, a slot, a variant, a
  /// booking, a confirmation. Surface inside a real boundary.
  live,

  /// Waiting on an answer that cannot be taken back. The boundary goes to
  /// full ink and carries its own weight.
  destructive,
}

class _Plate extends StatelessWidget {
  const _Plate({
    required this.child,
    this.padding,
    this.enclosure = _Enclosure.recorded,
    this.clip = false,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final _Enclosure enclosure;


  /// Clips the child to the plate's corners. Only for plates whose content
  /// runs to their own edge; a clip layer on every plate is a cost none of
  /// the others need to pay.
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final still = MediaQuery.disableAnimationsOf(context);
    // On an answer page a readout lies on the page itself: no glass, no
    // hairline, no shadow and no inset (`design/PAGES.md`).
    if (RendelPage.maybeOf(context)?.flat ?? false) {
      return SizedBox(width: double.infinity, child: child);
    }
    // Animated, because a confirm card releasing its emphasis is part of the
    // same gesture as its buttons being replaced.
    return AnimatedContainer(
      duration: still ? Duration.zero : theme.motion.settle,
      curve: theme.motion.curve,
      width: double.infinity,
      padding: padding ?? EdgeInsets.all(theme.space.plate),
      clipBehavior: clip ? Clip.antiAlias : Clip.none,
      decoration: BoxDecoration(
        // v6: every plate is the same glass — the raised surface at 82%, so
        // the thread's light comes through it — whatever it is for. The
        // enclosure no longer changes the material: a readout and a question
        // are told apart by what is on them (the lit primary, the chips), and
        // a destructive one says so in words, in `danger`, on its overline.
        color: theme.glass,
        // Raised (the default on the wire) is the full plate: a hairline
        // drawn inside it and the long soft shadow. Outlined keeps its
        // stronger line and drops the shadow; flat is the glass alone. All
        // three now read as one look (`design/BLOCKS-v6.md`, rule 5).
        border: _cardEdge(theme, Border.all(color: theme.hairline)),
        // Uniform, and 8 rounder than the theme's card corner, so a row or a
        // panel inside the plate at the card corner is concentric with it.
        borderRadius: BorderRadiusDirectional.all(
          Radius.circular(theme.plateRadius),
        ),
        boxShadow: _cardShadow(theme, theme.plateShadow),
      ),

      child: child,
    );
  }
}

/// The edge a plate or a card takes under `theme.style.card`, given the one it
/// draws when raised.
BoxBorder? _cardEdge(RendelTheme theme, BoxBorder? raised) =>
    switch (theme.style.card) {
      RendelCardStyle.raised => raised,
      RendelCardStyle.outlined => Border.all(color: theme.colors.lineStrong),
      RendelCardStyle.flat => null,
    };

/// Only a raised plate or card casts a shadow.
List<BoxShadow> _cardShadow(RendelTheme theme, List<BoxShadow> raised) =>
    theme.style.card == RendelCardStyle.raised ? raised : const <BoxShadow>[];

/// The decoration of something white sitting on a plate: a chip, a glyph tile,
/// a quiet button, a field, a panel of grouped rows. White with a hairline,
/// never a grey fill (`design/BLOCKS-v6.md`, rule 2).
BoxDecoration _white(RendelTheme theme, double radius) => BoxDecoration(
      color: theme.colors.surfaceHigh,
      border: Border.all(color: theme.hairline),
      borderRadius: BorderRadius.circular(radius),
    );

/// The primary action's look, shared by the button, a chosen chip and the
/// chart's latest bar: the accent lit from above, a highlight along its top
/// and a soft shadow, with no edge.
BoxDecoration _lit(RendelTheme theme, BorderRadiusGeometry radius,
        {List<BoxShadow> shadow = RendelTheme.litShadow}) =>
    BoxDecoration(
      gradient: theme.litFill,
      // Only the top is drawn; the other three sides keep their point of
      // inset unpainted, so a lit control is exactly the size of a quiet one.
      border: const Border(
        top: BorderSide(color: RendelTheme.litEdge),
        left: _unpainted,
        right: _unpainted,
        bottom: _unpainted,
      ),
      borderRadius: radius,
      boxShadow: shadow,
    );

const BorderSide _unpainted = BorderSide(width: 1, style: BorderStyle.none);

/// A glyph on its tile: 34 square, white with a hairline, the glyph in the
/// soft ink unless a tone asks for another.
class _GlyphTile extends StatelessWidget {
  const _GlyphTile({required this.icon, this.color});

  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: _white(theme, theme.radius.card * 0.8),
      child: Icon(
        icon,
        size: theme.type.heading,
        color: color ?? theme.colors.onSurfaceSoft,
      ),
    );
  }
}

/// Rows that belong together on one white panel: a confirmation's or a
/// booking's key/value rows. (A `key_value` block and a receipt keep open
/// rows, because their rows are the block.)
class _KvPanel extends StatelessWidget {
  const _KvPanel({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: theme.space.md,
        vertical: theme.space.sm - theme.space.hair,
      ),
      decoration: _white(theme, theme.radius.card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

/// A suggestion or a choice, sized to its label.
class RendelChip extends StatelessWidget {
  const RendelChip({
    super.key,
    required this.label,
    required this.onTap,
    this.selected,
    this.tabular = false,
    this.unavailable = false,
  });

  final String label;
  final VoidCallback? onTap;

  /// Whether this is the chosen one of a set, or null when the chip is not
  /// part of one.
  ///
  /// Null rather than false, because `Semantics(selected: false)` still sets
  /// the has-selected-state flag: every quick reply announced "not selected",
  /// which is a fact about a set the user is not in.
  final bool? selected;

  /// Set when the label is a number or a clock time, so a row of chips does
  /// not re-flow as the digits change.
  final bool tabular;

  /// Offered but not selectable — a sold-out size, a booked slot.
  ///
  /// It stays visible on purpose: a gap the reader can see beats a list that
  /// quietly omits their size. Drawn faint against a hairline border rather
  /// than the control boundary, because it is no longer a control, and
  /// announced as unavailable before its label.
  final bool unavailable;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final still = MediaQuery.disableAnimationsOf(context);
    // v6: ink words on a white chip with a hairline, which is what makes a
    // row of them read as something to press without a heavy outline.
    final base = tabular ? theme.text.labelTabular : theme.text.label;
    // Faint ink on a transparent chip, because an inert chip is no longer a
    // control. The treatment follows inertness; `unavailable` adds the
    // strike-through, so a sold-out size is told apart by more than colour.
    final inert = onTap == null;
    final ink = inert || unavailable
        ? base.copyWith(
            color: theme.colors.onSurfaceFaint,
            decoration: unavailable ? TextDecoration.lineThrough : null,
            decorationThickness: 1.5,
            decorationColor: theme.colors.onSurface.withValues(alpha: 0.45),
          )
        : base;
    final isSelected = selected ?? false;
    final radius = BorderRadius.circular(theme.radius.control);
    // No `alignment` on the Container: a Container with an alignment expands
    // to fill bounded constraints, which turned a row of chips into a stack of
    // full-width bars. The Row hugs the label; the 44pt floor comes from the
    // vertical padding plus RendelPressable's minimum.
    final chip = AnimatedContainer(
      duration: still ? Duration.zero : theme.motion.swap,
      curve: theme.motion.curve,
      padding: EdgeInsets.symmetric(
          horizontal: theme.space.lg, vertical: theme.space.md),
      // Chosen, it takes the lit accent the primary action wears.
      decoration: isSelected
          ? _lit(theme, radius, shadow: const [
              BoxShadow(
                color: Color(0x73000000),
                offset: Offset(0, 8),
                blurRadius: 18,
                spreadRadius: -12,
              ),
            ])
          : inert || unavailable
              ? BoxDecoration(
                  border: Border.all(color: theme.hairline),
                  borderRadius: radius,
                )
              : _white(theme, theme.radius.control),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: AnimatedDefaultTextStyle(
              duration: still ? Duration.zero : theme.motion.swap,
              curve: theme.motion.curve,
              style: isSelected ? base.copyWith(color: theme.colors.onAccent) : ink,
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) {
      // Still announced. A sold-out size a screen reader hears as a bare
      // number is worse than one it never hears at all.
      return Semantics(
        label: unavailable ? 'Unavailable, $label' : label,

        enabled: false,
        selected: selected,
        // Unconditionally: with this keyed off `unavailable`, a chip that was
        // inert for any other reason left its own Text in the tree and merged
        // it under this label, so it announced "Track order, Track order".
        excludeSemantics: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: _minTarget),
          child: chip,
        ),
      );
    }
    return RendelPressable(
      // The flag, not a suffix on the label: the platform has its own word
      // for this and its own place in the utterance to put it.
      semanticLabel: label,
      selected: selected,
      onTap: onTap,
      child: chip,
    );
  }
}

/// The lit accent by default, a white tile with a hairline when [quiet].
///
/// Sized to its label unless [expand]. Inside the catalog every block's
/// primary action is full width (blocks v6); a host placing one elsewhere
/// chooses.
class RendelActionButton extends StatelessWidget {
  const RendelActionButton({
    super.key,
    required this.label,
    required this.onTap,
    this.quiet = false,
    this.expand = false,
    this.part,
    this.detail,
    this.icon,
    this.danger = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool quiet;
  final bool expand;

  /// The `danger` control (`design/SYSTEM.md` §6a): filled in danger with
  /// white words, for the confirmation of something that cannot be taken
  /// back. A card part's own fill still wins.
  final bool danger;

  /// A smaller line under [label]: what the action itself names, such as the
  /// number a call dials or the start of an event added to the calendar.
  final String? detail;

  /// A glyph before [label], such as the check a copy button shows once it
  /// has copied.
  final IconData? icon;

  /// The card part this button is, if it is one: its fill and corner come
  /// from that part and its words from `<part>_text`. See [RendelTheme.part].
  final String? part;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final still = MediaQuery.disableAnimationsOf(context);
    final disabled = onTap == null;
    // The filled button's look is the customer's to choose; a quiet one keeps
    // its own under either.
    final outlined = !quiet && theme.style.button == RendelButtonStyle.outlined;
    // The outlined rim is half a point heavier than the filled one, taken
    // back out of the padding so both are the same size.
    final own = part == null ? null : theme.parts[part];
    final fill = disabled ? null : own?.fill;
    final rim = outlined && !disabled && fill == null ? 0.5 : 0.0;
    final radius = BorderRadius.circular(own?.radius ?? theme.radius.control);
    // v6 (`design/BLOCKS-v6.md`):
    //  * filled is the accent lit from above, a highlight along its top and a
    //    soft shadow, and no edge — never faded, which would read as disabled;
    //  * outlined (the legacy style) is white with a soft ring of the accent
    //    and a small lift, never a heavy dark ring;
    //  * quiet is white with the hairline and ink words;
    //  * a card part's own fill is drawn flat, as the customer chose it.
    final BoxDecoration decoration;
    final dangerous = danger && !quiet && !disabled && fill == null;
    if (fill != null) {
      decoration = BoxDecoration(
        color: fill,
        border: Border.all(color: fill),
        borderRadius: radius,
      );
    } else if (dangerous) {
      decoration = BoxDecoration(color: theme.danger, borderRadius: radius);
    } else if (quiet) {
      decoration = disabled
          ? BoxDecoration(
              border: Border.all(color: theme.hairline),
              borderRadius: radius,
            )
          : _white(theme, own?.radius ?? theme.radius.control);
    } else if (disabled) {
      // A tint, not a grey slab, and no lift: a disabled control that casts
      // a shadow is claiming to be pressable.
      decoration = BoxDecoration(
        color: theme.tint,
        border: Border.all(color: theme.hairline),
        borderRadius: radius,
      );
    } else if (outlined) {
      decoration = BoxDecoration(
        color: theme.colors.surfaceHigh,
        border: Border.all(
          color: theme.colors.accent.withValues(alpha: 0.45),
          width: 1.5,
        ),
        borderRadius: radius,
        boxShadow: const [
          BoxShadow(
            color: Color(0x59000000),
            offset: Offset(0, 8),
            blurRadius: 18,
            spreadRadius: -12,
          ),
        ],
      );
    } else {
      decoration = _lit(theme, radius);
    }
    final words = _asPart(
      theme,
      part == null ? null : '${part}_text',
      // A quiet action's words are the ink: the white tile, not
      // a faint label, is what makes it secondary.
      quiet
          ? (disabled
              ? theme.text.label
                  .copyWith(color: theme.colors.onSurfaceFaint)
              : theme.text.label)
          : disabled
              ? theme.text.labelStrong
                  .copyWith(color: theme.colors.onSurfaceFaint)
              : dangerous
                  ? theme.text.labelStrong.copyWith(color: const Color(0xFFFFFFFF))
                  : outlined
                      ? theme.text.labelStrong
                          .copyWith(color: theme.accentText)
                      : theme.text.labelStrong,
    );
    return RendelPressable(
      semanticLabel: detail == null ? label : '$label, $detail',
      onTap: onTap,
      // Submitting a form flips this button to disabled and its label to
      // "Sending…" in the same frame the press is still easing back over, so
      // a hard cut here put two clocks on one gesture — on the most
      // consequential tap in the catalog. `RendelChip` already animates its own
      // selection; this is the same 180ms.
      child: AnimatedContainer(
        duration: still ? Duration.zero : theme.motion.swap,
        curve: theme.motion.curve,
        padding: EdgeInsets.symmetric(
          // A button that fills its box does not need padding to look sized,
          // and 48pt of it took 39% of each half of a confirm card on a 320pt
          // phone — enough that "Confirm" itself broke across two lines at
          // large text, on the highest-stakes control in the catalog.
          horizontal: (expand ? theme.space.md : theme.space.xl) - rim,
          vertical: theme.space.md - rim,
        ),
        decoration: decoration,
        child: Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: theme.type.body, color: words.color),
              SizedBox(width: theme.space.xs + theme.space.hair),
            ],
            Flexible(
              child: AnimatedDefaultTextStyle(
                duration: still ? Duration.zero : theme.motion.swap,
                curve: theme.motion.curve,
                // Two lines. The schema lets a CTA label run to 60 characters
                // and a plan card was 208pt wide, so one line ellipsised
                // "Choose Standard" down to "Choose Stand…" at the default
                // font scale — on the one string on the card the user is
                // meant to act on. A button that grows a line is ordinary;
                // a button that cannot be read is not.
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: words,
                child: detail == null
                    ? Text(label)
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(label, textAlign: TextAlign.center),
                          Text(
                            detail!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            // The words' own ink, a step down, so it reads
                            // as the same button on the lit fill and on a
                            // quiet one.
                            style: theme.text.captionTabular.copyWith(
                              color: words.color?.withValues(alpha: 0.72),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The one tap surface in the SDK — catalog and thread shell alike.
///
/// A bare [GestureDetector] gave no press feedback, no screen-reader role and
/// no minimum size, so half the catalog shipped 34pt targets that announced
/// themselves as plain text. This gives every tappable the same guarantees:
/// 44pt on both axes, a button role carrying its own tap action, one complete
/// label, and a physical response that collapses under reduced motion.
class RendelPressable extends StatefulWidget {
  const RendelPressable({
    super.key,
    required this.onTap,
    required this.child,
    required this.semanticLabel,
    this.selected,
    this.checked,
    this.exclusive = false,
    this.expanded,
    this.tapHint,
    this.pressedScale = 0.97,
  });

  final VoidCallback? onTap;
  final Widget child;
  final String semanticLabel;

  /// Whether this is ticked, when it is one of a group of radios or
  /// checkboxes (a `choice`). Null for anything else. Set, it is announced as
  /// the radio or checkbox it is rather than as a button.
  final bool? checked;

  /// With [checked]: one of a group of which only one can be ticked, a radio.
  final bool exclusive;

  /// Whether what this opens is open, when it opens something in place (a
  /// `disclosure` row). Null for anything else. Set, it is announced as
  /// expanded or collapsed, which a chevron alone does not say.
  final bool? expanded;

  /// What a tap does, said in place of the platform's own "activate": "Show"
  /// or "Hide" for a `disclosure` row. Null for the platform's word.
  final String? tapHint;

  /// How far it gives under the finger. A card a whole row wide gives less,
  /// or its edges travel further than a chip's do.
  final double pressedScale;

  /// Whether this is the chosen one of a set. Null for a button that is not
  /// part of a choice, which is most of them.
  final bool? selected;

  @override
  State<RendelPressable> createState() => _RendelPressableState();
}

class _RendelPressableState extends State<RendelPressable> {
  bool _down = false;

  void _set(bool down) {
    if (_down == down) return;
    setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final enabled = widget.onTap != null;
    return Semantics(
      button: widget.checked == null,
      checked: widget.checked,
      inMutuallyExclusiveGroup: widget.checked != null && widget.exclusive,
      expanded: widget.expanded,
      onTapHint: widget.tapHint,
      enabled: enabled,
      selected: widget.selected,
      label: widget.semanticLabel,
      // The tap action has to live on this node. `excludeSemantics` stops the
      // reader repeating every string inside the button after its label, but
      // it also drops the gesture detector's own action, and a button a
      // screen reader cannot activate is a label with a shape.
      onTap: widget.onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _set(true) : null,
        onTapCancel: enabled ? () => _set(false) : null,
        onTapUp: enabled ? (_) => _set(false) : null,
        onTap: widget.onTap,
        // Asymmetric on purpose: a real tap is 50-80ms between down and up,
        // so a symmetric 120ms reverses before the scale ever lands and the
        // press is invisible on exactly the quick taps a chip row invites.
        child: AnimatedScale(
          scale: _down && !reduceMotion ? widget.pressedScale : 1,
          duration: _down ? theme.motion.press : theme.motion.settle,
          curve: theme.motion.pressCurve,
          child: AnimatedOpacity(
            opacity: _down ? 0.82 : 1,
            duration: reduceMotion
                ? Duration.zero
                : (_down ? theme.motion.press : theme.motion.settle),
            curve: theme.motion.pressCurve,
            child: ConstrainedBox(
              // Both axes: a one-glyph chip label ("9", "£5") clears 44
              // vertically and lands near 39 horizontally without this.
              constraints: const BoxConstraints(
                minHeight: _minTarget,
                minWidth: _minTarget,
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// One-shot entrance for a block.
///
/// Motion here carries meaning: it marks the arrival of a new piece of the
/// answer, and it is the only entrance in the catalog. A block plays it once
/// in the life of a conversation — [seen] is the set of ids that have already
/// arrived, so scrolling back through a long thread re-reads it rather than
/// re-animating it, which is the accidental scroll-reveal this design rejects.
class BlockEnter extends StatefulWidget {
  const BlockEnter({
    super.key,
    required this.id,
    required this.seen,
    this.page,
    required this.child,
  });

  final String id;
  final Set<String> seen;

  /// The page this block is on, by identity: its words are written at one
  /// pace with the page's other blocks, and it enters once the words above
  /// it are in (`_Flow`). Null for a block on no page, which keeps its own.
  final Object? page;

  final Widget child;

  @override
  State<BlockEnter> createState() => _BlockEnterState();
}

class _BlockEnterState extends State<BlockEnter> with SingleTickerProviderStateMixin {
  // No theme lookup in the initialisers — see the note on _CaretState. This
  // one mattered most: initState touches the controller immediately, so the
  // lookup ran before initState completed and every block in the thread
  // rendered as an error widget in debug.
  late final AnimationController _controller = AnimationController(vsync: this);

  late final CurvedAnimation _curve =
      CurvedAnimation(parent: _controller, curve: rendelEase);

  bool _fresh = false;
  bool _started = false;

  /// How long this block waits for its turn (`_Flow.enter`), held at the
  /// start of its own animation rather than on a timer.
  var _waitMs = 0;

  /// When its entrance begins, on the frame clock, for the words inside it
  /// to wait for.
  double? _enterAt;

  /// The block below keeps its state when the blur above it is dropped as it
  /// lands: without this it was built afresh, and its words began again.
  final _keep = GlobalKey();

  @override
  void initState() {
    super.initState();
    // `add` returns false when the id was already there, which is exactly the
    // "this block has arrived before" test. Done here rather than in
    // didChangeDependencies, which can run more than once.
    _fresh = widget.seen.add(widget.id);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started && _fresh) {
      // Its turn: after the block before it, and after the words above it
      // are written (`_Flow`).
      final at = _Flow.enter(widget.page);
      _enterAt = at;
      _waitMs = (at - _frameNow()).round();
    }
    // A section arriving on a page rises out of a blur (`design/PAGES.md`),
    // after the block before it has begun to.
    const enterMs = 520;
    final curve = RendelThemeScope.of(context).motion.curve;
    _controller.duration = Duration(milliseconds: enterMs + _waitMs);
    _curve.curve = _waitMs == 0 ? curve : Interval(_waitMs / (enterMs + _waitMs), 1, curve: curve);
    if (_started) return;
    _started = true;
    if (_fresh) {
      _controller.forward();
    } else {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = KeyedSubtree(
      key: _keep,
      child: _Arriving(fresh: _fresh, page: widget.page, at: _enterAt, child: widget.child),
    );
    if (MediaQuery.disableAnimationsOf(context)) return child;
    const travel = 14.0;
    return FadeTransition(
      opacity: _curve,
      // There for a screen reader while it fades in, waiting its turn included.
      alwaysIncludeSemantics: true,
      // Translated by a fixed distance rather than a fraction of the block's
      // own height, so the arrival reads the same whether the block is one
      // line of prose or a rail of product cards.
      child: AnimatedBuilder(
        animation: _curve,
        builder: (context, child) {
          final moved = Transform.translate(
            offset: Offset(0, travel * (1 - _curve.value)),
            child: child,
          );
          if (_curve.value >= 1) return moved;
          // 6px of CSS blur, clearing as it lands.
          final blur = 3 * (1 - _curve.value);
          return ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            child: moved,
          );
        },
        child: child,
      ),
    );
  }
}

/// Whether the block below is arriving now, for the first time: a text block
/// then has its words come in at the page's pace ([_WordFlow]).
class _Arriving extends InheritedWidget {
  const _Arriving({required this.fresh, required this.page, required this.at, required super.child});

  final bool fresh;

  /// The page the block is on (`BlockEnter.page`).
  final Object? page;

  /// When the block's entrance begins, on the frame clock; null while that
  /// is not yet known.
  final double? at;

  /// The block arriving now around [context], or null for one seen before.
  static _Arriving? of(BuildContext context) {
    final arriving = context.dependOnInheritedWidgetOfExactType<_Arriving>();
    return arriving != null && arriving.fresh ? arriving : null;
  }

  @override
  bool updateShouldNotify(_Arriving oldWidget) =>
      oldWidget.fresh != fresh || oldWidget.page != page || oldWidget.at != at;
}

/// Now, on the frame clock: the clock tickers run on, so a wait booked
/// here and the animation that plays it agree — in the app and under a
/// test's clock alike, which a wall clock would not. Between frames, the
/// last frame's time.
double _frameNow() {
  final binding = SchedulerBinding.instance;
  if (binding.schedulerPhase != SchedulerPhase.idle) {
    _lastFrame = binding.currentFrameTimeStamp.inMilliseconds.toDouble();
  }
  return _lastFrame;
}

double _lastFrame = 0;

/// The writer. One pace for the whole page, so its paragraphs come in one
/// after another and its cards land once the words above them are written,
/// rather than each block in its own burst (Özlem 2026-10-28: ours came
/// "tak tak tak", a paragraph at a time, where Monogram's flows). A text
/// books its characters here as it arrives; a block enters once the one
/// before it has begun to and the words above it are due.
class _Flow {
  /// Characters a second: Monogram's pace, read off a recording (~110).
  static const charsPerSecond = 110.0;

  /// The most one arrival may take. A long text is written faster, not later.
  static const longestMs = 4000.0;

  /// One word's fade, from nothing to its ink.
  static const fadeMs = 180.0;

  /// Blocks that arrive in one burst enter at least this far apart, in step
  /// rather than all at once (Tuna 2026-10-23: smooth, as Monogram's).
  static const enterGapMs = 150.0;

  /// The page being written, by identity; when its last booked character
  /// is due; and when its next block may enter. All on the frame clock. A
  /// new page starts a new writer: the one before it was dissolved, words
  /// still owed and all.
  static Object _page = _none;
  static double _end = 0;
  static double _nextEnter = 0;
  static const _none = Object();

  static void _turnTo(Object? page, double now) {
    final key = page ?? _none;
    if (identical(key, _page)) return;
    _page = key;
    _end = now;
    _nextEnter = now;
  }

  /// When a block of [page] may enter, and books it: after the block
  /// before it, and after the words above it are written, so a page is
  /// written top to bottom at one pace rather than its cards landing while
  /// its first paragraph is still coming.
  static double enter(Object? page) {
    final now = _frameNow();
    _turnTo(page, now);
    final at = math.max(now, math.max(_nextEnter, _end));
    _nextEnter = at + enterGapMs;
    return at;
  }

  /// Books [chars] more characters of [page], from [notBefore] at the
  /// earliest: when the first is due, and how many milliseconds each takes.
  static ({double at, double perChar}) book(Object? page, int chars, {double? notBefore}) {
    final now = _frameNow();
    _turnTo(page, now);
    var at = math.max(_end, now);
    if (notBefore != null) at = math.max(at, notBefore);
    final perChar = math.min(1000 / charsPerSecond, longestMs / math.max(chars, 1));
    _end = at + chars * perChar;
    return (at: at, perChar: perChar);
  }
}

/// A paragraph written at the page's pace (`_Flow`): its words fade in one
/// after another, each as its first character comes due, with more booked
/// as a stream brings more. Opacity alone — the words are all laid out from
/// the start, so nothing reflows and a screen reader has them whole — and
/// the caret, when there is one, once the words so far are all in.
class _WordFlow extends StatefulWidget {
  const _WordFlow({
    required this.page,
    required this.notBefore,
    required this.spans,
    required this.style,
    required this.align,
    required this.caret,
    required this.marks,
    required this.mark,
  });

  /// The page the words are on (`BlockEnter.page`), and when its block
  /// begins entering (frame clock), which the first word waits for.
  final Object? page;
  final double? notBefore;

  /// Flat text spans, as `_inline` makes them: each in its own style over
  /// the paragraph's, a link's with its recognizer.
  final List<InlineSpan> spans;
  final TextStyle style;
  final TextAlign? align;

  /// The streaming caret, while more is coming.
  final Widget? caret;

  /// The `==marked==` phrases, drawn behind their words as they come in.
  final List<TextRange> marks;
  final Color mark;

  @override
  State<_WordFlow> createState() => _WordFlowState();
}

class _WordFlowState extends State<_WordFlow> with SingleTickerProviderStateMixin {
  static final _pieces = RegExp(r'\s+|\S+');

  late final Ticker _ticker = createTicker(_tick);

  /// The frame clock as this paragraph last saw it: at each tick while it
  /// has words still coming in, and when more are booked.
  double _now = 0;
  double _origin = 0;

  /// The text booked so far, and when each run of it is due: from
  /// character [from] up to [to], the first at [at] on the clock and each
  /// after it [perChar] later.
  String _booked = '';
  final _runs = <({int from, int to, double at, double perChar})>[];

  @override
  void initState() {
    super.initState();
    _plan();
  }

  @override
  void didUpdateWidget(_WordFlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    _plan();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _tick(Duration elapsed) {
    setState(() => _now = _origin + elapsed.inMilliseconds);
    if (_now >= _done + _Flow.fadeMs) _ticker.stop();
  }

  /// When the last booked character is due.
  double get _done {
    if (_runs.isEmpty) return 0;
    final last = _runs.last;
    return last.at + (last.to - last.from) * last.perChar;
  }

  /// When the character at [offset] is due.
  double _due(int offset) {
    for (final run in _runs) {
      if (offset < run.to) return run.at + (offset - run.from) * run.perChar;
    }
    return _done;
  }

  /// How far in the word at [offset] is: nothing before it is due, its ink
  /// a fade later.
  double _alpha(int offset) => ((_now - _due(offset)) / _Flow.fadeMs).clamp(0.0, 1.0);

  String get _plain => [for (final span in widget.spans) if (span is TextSpan) span.text ?? ''].join();

  /// Books what the text adds to what was booked. Text that changed under
  /// its booking — a stream's words tidied as they settled — is rebooked
  /// from where it changed, never from the start.
  void _plan() {
    final text = _plain;
    var same = 0;
    while (same < text.length && same < _booked.length && text.codeUnitAt(same) == _booked.codeUnitAt(same)) {
      same++;
    }
    if (same < _booked.length) {
      _runs.removeWhere((run) => run.from >= same);
      if (_runs.isNotEmpty && _runs.last.to > same) {
        final last = _runs.removeLast();
        _runs.add((from: last.from, to: same, at: last.at, perChar: last.perChar));
      }
    }
    _booked = text;
    if (text.length == same) return;
    final booking = _Flow.book(widget.page, text.length - same, notBefore: widget.notBefore);
    _runs.add((from: same, to: text.length, at: math.max(booking.at, _done), perChar: booking.perChar));
    _now = _frameNow();
    if (_ticker.isActive) return;
    _origin = _now;
    _ticker.start();
  }

  @override
  Widget build(BuildContext context) {
    final ink = widget.style.color ?? DefaultTextStyle.of(context).style.color ?? const Color(0xFF000000);
    var offset = 0;
    final children = <InlineSpan>[];
    for (final span in widget.spans) {
      if (span is! TextSpan) {
        children.add(span);
        continue;
      }
      final pieces = <InlineSpan>[];
      for (final match in _pieces.allMatches(span.text ?? '')) {
        final piece = match.group(0)!;
        if (piece.trim().isEmpty) {
          pieces.add(TextSpan(text: piece, recognizer: span.recognizer));
        } else {
          final color = span.style?.color ?? ink;
          pieces.add(TextSpan(
            text: piece,
            recognizer: span.recognizer,
            style: TextStyle(color: color.withValues(alpha: color.a * _alpha(offset))),
          ));
        }
        offset += piece.length;
      }
      children.add(TextSpan(style: span.style, children: pieces));
    }
    // The caret once the words so far are all in: the writer has caught up
    // with the stream and waits, as the reader does, for more.
    final caret = widget.caret;
    if (caret != null && (_runs.isEmpty || _now >= _done + _Flow.fadeMs)) children.add(_caretSpan(caret));
    final drawn = Text.rich(TextSpan(children: children), style: widget.style, textAlign: widget.align);
    if (widget.marks.isEmpty) return drawn;
    return _Marks(
      ranges: widget.marks,
      color: widget.mark,
      alphas: [for (final range in widget.marks) _alpha(range.start)],
      child: drawn,
    );
  }
}

// ————————————————————————— comparison —————————————————————————

/// Two to four things on the same rows, read side by side
/// (`design/CATALOG-B2.md`, the prototype's variant A): the things across the
/// top, then each row's label on a line of its own over one value per
/// column, so a value has a whole column even with four on a phone and
/// nothing scrolls sideways. Once the things have scrolled under the bar,
/// their titles stay pinned there while the rows go by.
Widget buildComparison(BuildContext context, WireBlock block, RendelDispatcher dispatch) {
  final items = _maps(block.props['items']).take(4).toList();
  final rows = _maps(block.props['rows']);
  if (items.length < 2 || rows.isEmpty) return buildFallback(context, block);
  return _Plate(
    child: _Comparison(
      title: block.props['title'],
      items: items,
      rows: rows,
      summary: _str(block.props['summary']),
      dispatch: dispatch,
    ),
  );
}

class _Comparison extends StatefulWidget {
  const _Comparison({
    required this.title,
    required this.items,
    required this.rows,
    required this.summary,
    required this.dispatch,
  });

  final Object? title;
  final List<Map> items;
  final List<Map> rows;
  final String? summary;
  final RendelDispatcher dispatch;

  @override
  State<_Comparison> createState() => _ComparisonState();
}

class _ComparisonState extends State<_Comparison> {
  static const double _pinHeight = 38;

  final _head = GlobalKey();
  ScrollPosition? _position;

  /// Where the pinned titles sit inside the block, and whether they show.
  /// The place is kept while they fade out.
  final _pin = ValueNotifier<(double, bool)>((0, false));
  bool _placing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (position == _position) return;
    _position?.removeListener(_schedule);
    _position = position?..addListener(_schedule);
    _schedule();
  }

  @override
  void dispose() {
    _position?.removeListener(_schedule);
    _pin.dispose();
    super.dispose();
  }

  /// Measured after the frame, not in the scroll callback: a list places its
  /// children during layout, so in the callback every box is still where the
  /// last frame put it.
  void _schedule() {
    if (_placing) return;
    _placing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _placing = false;
      _place();
    });
  }

  void _place() {
    if (!mounted) return;
    final viewport = Scrollable.maybeOf(context)?.context.findRenderObject();
    final own = context.findRenderObject();
    final head = _head.currentContext?.findRenderObject();
    if (viewport is! RenderBox || own is! RenderBox || head is! RenderBox) return;
    if (!own.attached || !head.attached) return;
    final bar = RendelPage.maybeOf(context)?.bar ?? 0;
    final top = own.localToGlobal(Offset.zero, ancestor: viewport).dy;
    final headFoot = head.localToGlobal(Offset(0, head.size.height), ancestor: viewport).dy;
    // From the moment the things are under the bar until the block's own
    // foot comes up to meet it: pinned inside the block, as CSS `sticky` is.
    final at = (bar - top).clamp(0.0, math.max(0.0, own.size.height - _pinHeight)).toDouble();
    final on = headFoot < bar && bar - top < own.size.height - _pinHeight;
    _pin.value = (on ? at : _pin.value.$1, on);
  }

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final strings = RendelStringsScope.of(context);
    final page = RendelPage.maybeOf(context);
    final still = MediaQuery.disableAnimationsOf(context);
    final items = widget.items;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    const gap = 12.0;

    String titleOf(Map item) => _str(item['title']) ?? '';

    Widget columns(List<Widget> cells, {CrossAxisAlignment align = CrossAxisAlignment.start}) => Row(
          crossAxisAlignment: align,
          children: [
            for (var i = 0; i < cells.length; i++) ...[
              if (i > 0) const SizedBox(width: gap),
              Expanded(child: cells[i]),
            ],
          ],
        );

    Widget head(Map item) {
      final image = _str(item['image_url']);
      final badge = _str(item['badge']);
      final price = _str(item['price']);
      final cell = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (image != null) ...[
            LayoutBuilder(
              builder: (context, constraints) => _Thumbnail(
                url: image,
                width: constraints.maxWidth,
                height: constraints.maxWidth * 3 / 4,
                radius: 14,
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (badge != null && badge.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colors.onSurface,
                borderRadius: BorderRadius.circular(theme.radius.control),
              ),
              child: Text(
                badge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.text.caption.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: theme.colors.surfaceRaised,
                ),
              ),
            ),
            const SizedBox(height: 4),
          ],
          Text(
            titleOf(item),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.text.label.copyWith(fontSize: 15, fontWeight: FontWeight.w600, height: 1.2),
          ),
          if (price != null) ...[
            const SizedBox(height: 4),
            Text(
              price,
              style: theme.text.labelSoftTabular.copyWith(fontSize: 13.5),
            ),
          ],
        ],
      );
      final label = _joinParts([titleOf(item), _str(item['subtitle']), badge, price]);
      // A reply asks about the thing; on an answer page the thing opens
      // over the page, as a product card does (`design/DETAIL.md`).
      final onTap = _opens(context, item, price: price) ?? _tap(widget.dispatch, item['action']);
      if (onTap == null) {
        return Semantics(label: label, excludeSemantics: true, child: cell);
      }
      return RendelPressable(semanticLabel: label, onTap: onTap, pressedScale: 0.98, child: cell);
    }

    Widget value(Map row, int index) {
      final values = _list(row['values']);
      final text = index < values.length ? _str(values[index]) ?? '' : '';
      final best = _dbl(row['best_index'])?.round() == index;
      final check = _str(row['kind']) == 'check';
      final said = check ? (text == 'yes' ? strings.yes : strings.no) : text;
      final Widget drawn;
      if (check) {
        final yes = text == 'yes';
        // Yes is the ink, as done is everywhere; no is a faint dash, not a
        // cross: the thing simply does not have it.
        drawn = Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: yes ? BoxDecoration(color: theme.colors.onSurface, shape: BoxShape.circle) : null,
          child: Icon(
            yes ? Icons.check_rounded : Icons.remove_rounded,
            size: 15,
            color: yes ? theme.colors.surfaceRaised : theme.colors.onSurfaceFaint,
          ),
        );
      } else {
        final words = Text(
          text,
          style: theme.text.labelTabular.copyWith(
            fontSize: 15,
            height: 1.3,
            fontWeight: best ? FontWeight.w600 : FontWeight.w500,
          ),
        );
        // The best value in a row carries the page's one mark, drawn back by
        // its own padding so its words still start on the column's line.
        drawn = best
            ? Transform.translate(
                offset: Offset(rtl ? 6 : -6, 0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: theme.mark,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: words,
                ),
              )
            : words;
      }
      // Every cell names its row and its thing, so a value is never read as
      // a bare "248 g"; the best one says so, since the mark is only drawn.
      return Semantics(
        label: '${_str(row['label']) ?? ''}, ${titleOf(items[index])}: $said'
            '${best ? ', ${strings.best}' : ''}',
        excludeSemantics: true,
        child: Align(alignment: AlignmentDirectional.centerStart, child: drawn),
      );
    }

    final line = BorderSide(color: theme.hairline);
    final table = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BlockTitle(widget.title),
        Container(
          key: _head,
          padding: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(border: Border(bottom: line)),
          child: columns([for (final item in items) head(item)]),
        ),
        for (final row in widget.rows)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(border: Border(bottom: line)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ExcludeSemantics(
                  child: Text(
                    _str(row['label']) ?? '',
                    style: theme.text.caption.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: theme.colors.onSurfaceSoft,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                columns(
                  [for (var i = 0; i < items.length; i++) value(row, i)],
                  align: CrossAxisAlignment.center,
                ),
              ],
            ),
          ),
        if (widget.rows.any((row) => row['best_index'] != null))
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              strings.comparisonBest,
              style: theme.text.caption.copyWith(color: theme.colors.onSurfaceSoft),
            ),
          ),
        if (widget.summary != null && widget.summary!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(
              widget.summary!,
              style: theme.text.body.copyWith(
                fontSize: 14,
                height: 1.45,
                color: theme.colors.onSurfaceSoft,
              ),
            ),
          ),
      ],
    );

    // Out through the page's padding on a page, as the bar above it is.
    final flat = page?.flat ?? false;
    final reach = flat ? page!.inset : 0.0;
    // Opaque, on the ground it lies on, and up under the bar too (QA
    // 2026-10-24): frosted, the rows read through it, and the page's fade
    // under the bar let a row's label show between the bar and the titles.
    final under = page?.bar ?? 0.0;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        table,
        ValueListenableBuilder<(double, bool)>(
          valueListenable: _pin,
          builder: (context, pin, _) => Positioned(
            top: pin.$1 - under,
            left: -reach,
            right: -reach,
            height: _pinHeight + under,
            // Drawn, not read: the cells already name their things.
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: AnimatedOpacity(
                  key: const ValueKey('rendel-comparison-pin'),
                  opacity: pin.$2 ? 1 : 0,
                  duration: still ? Duration.zero : const Duration(milliseconds: 220),
                  curve: theme.motion.curve,
                  child: Container(
                    padding: EdgeInsets.fromLTRB(reach, under, reach, 0),
                    decoration: BoxDecoration(
                      color: flat ? theme.colors.surface : theme.colors.surfaceRaised,
                      border: Border(bottom: line),
                    ),
                    child: columns(
                      [
                        for (final item in items)
                          Text(
                            titleOf(item),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.text.label.copyWith(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                      align: CrossAxisAlignment.center,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ————————————————————————— records —————————————————————————
//
// What catalog wave 2 adds to the blocks that hold the user's own records
// (`design/CATALOG-B2.md`): buttons that act on the device, status in a tone,
// a document's type, and times that say when they were true.

/// A control that carries out its action, and says so when that was a copy:
/// for 1.5 s it reads [RendelStrings.copied] with a check, in a live region,
/// so a screen reader hears it as well as the eye sees it.
///
/// Whether it copied is the dispatcher's answer, not the tap: a clipboard
/// that refused the value says nothing.
class _Acting extends StatefulWidget {
  const _Acting({required this.action, required this.dispatch, required this.builder});

  /// The action as it came on the wire.
  final Object? action;
  final RendelDispatcher dispatch;

  /// Draws the control with its tap, null when this build cannot act, and
  /// whether it has just copied.
  final Widget Function(BuildContext context, VoidCallback? onTap, bool copied) builder;

  @override
  State<_Acting> createState() => _ActingState();
}

class _ActingState extends State<_Acting> {
  Timer? _settle;
  bool _copied = false;

  @override
  void dispose() {
    _settle?.cancel();
    super.dispose();
  }

  Future<void> _act(UIAction action) async {
    final done = await widget.dispatch.onAction(action);
    if (!done || action is! CopyAction || !mounted) return;
    _settle?.cancel();
    setState(() => _copied = true);
    _settle = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final action = UIAction.tryParse(widget.action);
    final live = action != null && widget.dispatch.canHandle(action);
    return Semantics(
      liveRegion: action is CopyAction,
      child: widget.builder(context, live ? () => _act(action) : null, _copied),
    );
  }
}

/// A block's button for [action]: [label] on it, and under it what the
/// action itself names — the number a call dials, or the label it gives in
/// its place, and the start of an event added to the calendar — so the user
/// reads what a tap will do before making it.
Widget _actionButton(
  BuildContext context, {
  required String label,
  required Object? action,
  required RendelDispatcher dispatch,
  bool quiet = false,
  bool expand = false,
  String? part,
}) {
  final detail = switch (UIAction.tryParse(action)) {
    CallAction(label: final name, :final phone) => name ?? phone,
    AddToCalendarAction(:final startsAt) => _when(context, startsAt),
    _ => null,
  };
  return _Acting(
    action: action,
    dispatch: dispatch,
    builder: (context, onTap, copied) => RendelActionButton(
      label: copied ? RendelStringsScope.of(context).copied : label,
      detail: detail == label ? null : detail,
      icon: copied ? Icons.check_rounded : null,
      onTap: onTap,
      quiet: quiet,
      expand: expand,
      part: part,
    ),
  );
}

/// A copy button at the end of a row: the copy glyph on a 44pt target, the
/// check for a moment once it has copied. [name] is what it copies, for a
/// screen reader.
class _CopyButton extends StatelessWidget {
  const _CopyButton({required this.text, required this.name, required this.dispatch});

  final String text;
  final String name;
  final RendelDispatcher dispatch;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final strings = RendelStringsScope.of(context);
    return _Acting(
      action: {'kind': 'copy', 'text': text},
      dispatch: dispatch,
      builder: (context, onTap, copied) => RendelPressable(
        semanticLabel: copied ? strings.copied : '${strings.copy}, $name',
        onTap: onTap,
        child: SizedBox(
          width: _minTarget,
          height: _minTarget,
          child: Icon(
            copied ? Icons.check_rounded : Icons.content_copy_rounded,
            size: 16,
            color: copied ? theme.colors.onSurface : theme.colors.onSurfaceSoft,
          ),
        ),
      ),
    );
  }
}

/// The ink a status `tone` reads in.
///
/// There is no status palette (`design/SYSTEM.md` §6a), so the tones take
/// the roles the system already has: success the ink, as done and yes are
/// drawn everywhere; warning the accent's legible form, as a status banner's
/// glyph is; error `danger`; neutral, or none, the soft ink.
Color _toneInk(RendelTheme theme, String? tone) => switch (tone) {
      'success' => theme.colors.onSurface,
      'warning' => theme.accentText,
      'error' => theme.danger,
      _ => theme.colors.onSurfaceSoft,
    };

/// A record's status (`{label, tone}`): its label on the highlight, behind a
/// dot in the tone's ink. The words say it; the dot only helps.
class _TonePill extends StatelessWidget {
  const _TonePill({required this.label, this.tone});

  final String label;
  final String? tone;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(7, 2, 8, 2),
      decoration: BoxDecoration(
        color: theme.highlight,
        border: Border.all(color: theme.hairline),
        borderRadius: BorderRadius.circular(theme.radius.control),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tone == null || tone == 'neutral'
                  ? theme.colors.onSurfaceFaint
                  : _toneInk(theme, tone),
            ),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.text.captionSoft.copyWith(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

/// A document's type, drawn where its picture or glyph would be: PDF, CSV,
/// IMG or DOC on a white tile with the hairline.
class _FileBadge extends StatelessWidget {
  const _FileBadge({required this.type, required this.size});

  final String type;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: _white(theme, theme.radius.card * 0.8),
      child: Text(
        switch (type) {
          'image' => 'IMG',
          _ => type.toUpperCase(),
        },
        maxLines: 1,
        style: theme.text.caption.copyWith(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: theme.colors.onSurfaceSoft,
        ),
      ),
    );
  }
}

/// The file types a record may name.
const Set<String> _fileTypes = {'pdf', 'csv', 'image', 'doc'};

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// [at]'s clock time as the reader's device says it, from the host's
/// Material localizations when there are any.
String _time(BuildContext context, DateTime at) {
  final local = at.toLocal();
  final material = Localizations.of<MaterialLocalizations>(context, MaterialLocalizations);
  if (material == null) return '${_two(local.hour)}:${_two(local.minute)}';
  return material.formatTimeOfDay(
    TimeOfDay.fromDateTime(local),
    alwaysUse24HourFormat: MediaQuery.maybeAlwaysUse24HourFormatOf(context) ?? false,
  );
}

/// [at] as a clock: the time alone today, the day before it on any other, so
/// a stored answer opened days later does not pass yesterday off as today.
String _clock(BuildContext context, DateTime at) {
  final local = at.toLocal();
  final time = _time(context, local);
  if (_sameDay(local, DateTime.now())) return time;
  return '${RendelStringsScope.of(context).dayHeadingFor(local)} $time';
}

/// [at] with its date, always: the start a calendar button adds.
String _when(BuildContext context, DateTime at) {
  final local = at.toLocal();
  final material = Localizations.of<MaterialLocalizations>(context, MaterialLocalizations);
  final day = material?.formatMediumDate(local) ??
      RendelStringsScope.of(context).dayHeadingFor(local);
  return '$day, ${_time(context, local)}';
}

/// How soon [at] is while it is still ahead: within the hour and a half in
/// minutes ("in about 25 min"), later today in hours, tomorrow at its time.
/// Null once it has passed, and for anything further off, where the date
/// already says it.
String? _soon(BuildContext context, DateTime at) {
  final strings = RendelStringsScope.of(context);
  final local = at.toLocal();
  final now = DateTime.now();
  final ahead = local.difference(now);
  if (ahead.isNegative) return null;
  final minutes = ahead.inMinutes;
  if (minutes < 90) {
    // "About", so to the nearest five once it is more than a few minutes.
    final about = minutes < 10 ? math.max(1, minutes) : (minutes / 5).round() * 5;
    return strings.inMinutesCount(about);
  }
  if (_sameDay(local, now)) return strings.inHoursCount((minutes / 60).round());
  if (_sameDay(local, DateTime(now.year, now.month, now.day + 1))) {
    return strings.tomorrowAtTime(_time(context, local));
  }
  return null;
}

/// An instant on the wire, or null.
DateTime? _instant(Object? value) {
  final text = _str(value);
  return text == null ? null : DateTime.tryParse(text);
}

/// A `{label, value}` reference — a tracking number, a booking's code — as
/// a row with a copy button, flat on a page and on a plate anywhere else.
Widget _reference(BuildContext context, Map reference, RendelDispatcher dispatch) {
  final label = _str(reference['label']) ?? '';
  final value = _str(reference['value']) ?? '';
  return RendelPage.maybeOf(context)?.flat ?? false
      ? _Fact(label: label, value: value, copy: true, dispatch: dispatch)
      : _KeyValueRow(label: label, value: value, copy: true, dispatch: dispatch);
}

// ————————————————————————— small helpers —————————————————————————

/// The icons `info_card` may name. A closed set, because an open one means the
/// model guesses a name and the card silently loses its glyph.
const Map<String, IconData> _icons = {
  'info': Icons.info_outlined,
  'check': Icons.check_circle_outlined,
  'warning': Icons.error_outlined,
  'error': Icons.cancel_outlined,
  'order': Icons.receipt_long_outlined,
  'package': Icons.inventory_2_outlined,
  'truck': Icons.local_shipping_outlined,
  'calendar': Icons.calendar_today_outlined,
  'clock': Icons.schedule_outlined,
  'card': Icons.credit_card_outlined,
  'wallet': Icons.account_balance_wallet_outlined,
  'tag': Icons.sell_outlined,
  'gift': Icons.card_giftcard_outlined,
  'star': Icons.star_outlined,
  'heart': Icons.favorite_outlined,
  'user': Icons.person_outlined,
  'settings': Icons.tune_outlined,
  'search': Icons.search_outlined,
  'location': Icons.place_outlined,
  'phone': Icons.call_outlined,
  'mail': Icons.mail_outlined,
  'lock': Icons.lock_outlined,
  'refresh': Icons.refresh_outlined,
  'download': Icons.download_outlined,
  'link': Icons.link_outlined,
  'bag': Icons.shopping_bag_outlined,
  'ticket': Icons.confirmation_number_outlined,
  'chart': Icons.insights_outlined,
  'document': Icons.description_outlined,
  'person': Icons.person_outline_rounded,
  'map_pin': Icons.location_on_outlined,
  'search_off': Icons.search_off_outlined,
};

/// Every icon name `info_card` accepts. Exported so the docs and the
/// model-facing catalog description cannot drift from the map.
List<String> get infoCardIconNames => _icons.keys.toList();

IconData? _iconFor(String? name) => name == null ? null : _icons[name.toLowerCase()];

/// Whole numbers stay whole. A "12.0 orders" axis label is a rounding artefact
/// wearing a decimal point.
String _num(double value, String locale) {
  if (value == value.roundToDouble() && value.abs() < 1e9) {
    return rendelNumber(value.toInt(), locale, digits: 0);
  }
  return rendelNumber(value, locale, digits: 1);
}

/// A currency as a chart's unit: a sign like € or ₺, one with letters like
/// A$ or US$, or a code like EUR.
final RegExp _currencyUnit = RegExp(r'^([A-Z]{0,3}\p{Sc}|[A-Z]{3})$', unicode: true);

/// A sign written before the amount wherever it is used: $, £, ¥, ₹, ₩, and
/// the dollars that carry letters (A$, US$, HK$). Not €, ₺ or kr, which most
/// of their own languages write after it.
final RegExp _currencySign = RegExp(r'^[A-Z]{0,3}[$£¥₹₩]$', unicode: true);

/// [said] with its unit: a sign before it ("A$119.04", as the prose writes
/// it, Grove report P2-6), anything else after it ("12 kg", "40 EUR").
String _withUnit(String said, String? unit) {
  if (unit == null) return said;
  final trimmed = unit.trim();
  return _currencySign.hasMatch(trimmed) ? '$trimmed$said' : '$said $unit';
}

/// How a chart writes its values, as the web SDK does: all with as many
/// decimals as the most precise of them has, at most two, so 53.4 beside
/// 48.25 reads 53.40; and money with cents anywhere always with two.
String Function(double) _chartFormat(List<double> values, String? unit, String locale) {
  int own(double v) {
    if (v == v.roundToDouble()) return 0;
    final text = v.toString();
    final dot = text.indexOf('.');
    return text.contains('e') || dot == -1 ? 2 : text.length - dot - 1;
  }

  final fractional = values.any((v) => v != v.roundToDouble());
  final money = unit != null && _currencyUnit.hasMatch(unit.trim());
  final places = money && fractional ? 2 : math.min(2, values.map(own).fold(0, math.max));
  return (value) => rendelNumber(value, locale, digits: places);
}

/// Whether a chart's [label] is itself a when ("Today", "This week",
/// "Bugün") that "in" reads wrong before. The SDK carries no date library,
/// so the words are the six languages' own, by hand.
bool _isWhen(String label) => _whenWords.hasMatch(label.trim().toLowerCase());

final RegExp _whenWords = RegExp(
  r'^(today|tonight|yesterday|tomorrow|now|this |last |next |past '
  r'|bugün|dün|yarın|şimdi|bu |geçen |gelecek '
  r'|heute|gestern|morgen|jetzt|diese|dieser|dieses|letzte|nächste'
  r'|aujourd|hier|demain|maintenant|ce |cet |cette '
  r'|hoy|ayer|mañana|ahora|este |esta '
  r'|اليوم|أمس|غدا|غدًا|الآن|هذا|هذه)',
  unicode: true,
);

/// The day heading for a slot, or an empty string when the model sent no
/// timestamp and there is nothing true to say.
String _dayKey(RendelStrings strings, Object? startsAt) {
  final text = _str(startsAt);
  if (text == null) return '';
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return '';
  return strings.dayHeadingFor(parsed.toLocal());
}

// ————————————————————————— key_value —————————————————————————

/// Label-and-value rows: what a thing IS. `table` is for several things that
/// share columns; this is the detail sheet for one of them.
Widget buildKeyValue(BuildContext context, WireBlock block, RendelDispatcher dispatch) {
  final theme = RendelThemeScope.of(context);
  final rows = _maps(block.props['rows']);
  if (rows.isEmpty) return _EmptyPlate(message: block.fallbackText);
  final cta = _map(block.props['cta']);
  // The one product the rows describe: its photograph, whole, beside the title.
  final picture = _str(block.props['image_url']);
  final title = _str(block.props['title']);

  return _Plate(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (picture != null)
          Padding(
            padding: EdgeInsets.only(bottom: theme.space.md),
            child: Row(
              children: [
                _Thumbnail(
                  url: picture,
                  width: theme.size.cardRowImage,
                  height: theme.size.cardRowImage,
                  radius: theme.radius.sm,
                  fit: BoxFit.contain,
                ),
                if (title != null && title.isNotEmpty) ...[
                  SizedBox(width: theme.space.md),
                  Expanded(child: Text(title, style: theme.text.title)),
                ],
              ],
            ),
          )
        else
          _BlockTitle(title),
        for (final row in rows)
          // On a page, rows across hairlines (`design/DETAIL.md`).
          if (RendelPage.maybeOf(context)?.flat ?? false)
            _Fact(
              label: _str(row['label']) ?? '',
              value: _str(row['value']) ?? '',
              strong: row['emphasis'] == true,
              tone: _str(row['tone']),
              range: _str(row['range_label']),
              masked: row['masked'] == true,
              copy: row['copy'] == true,
              dispatch: dispatch,
            )
          else
            _KeyValueRow(
              label: _str(row['label']) ?? '',
              value: _str(row['value']) ?? '',
              // The emphasised row is the one the user asked about; it reads
              // at label weight while the rest stay caption, so the sheet has
              // an answer rather than twelve equal facts.
              strong: row['emphasis'] == true,
              tone: _str(row['tone']),
              range: _str(row['range_label']),
              masked: row['masked'] == true,
              copy: row['copy'] == true,
              dispatch: dispatch,
            ),
        if (cta != null) ...[
          SizedBox(height: theme.space.lg),
          _actionButton(
            context,
            label: _str(cta['label']) ?? RendelStringsScope.of(context).open,
            action: cta['action'],
            dispatch: dispatch,
            expand: true,
          ),
        ],
      ],
    ),
  );
}

// ————————————————————————— variant_picker —————————————————————————

/// One choice out of a set that differs by a single attribute: size, colour,
/// capacity. Sold-out options stay on screen and unselectable, because a gap
/// the reader can see beats a list that quietly omits their size.
Widget buildVariantPicker(BuildContext context, WireBlock block, RendelDispatcher dispatch) {
  final theme = RendelThemeScope.of(context);
  final options = _maps(block.props['options']);
  if (options.isEmpty) return _EmptyPlate(message: block.fallbackText);
  // The user's tap wins over the drawing it was made on, as a slot's does. A
  // redrawn picker keeps it only when the model names no selection of its
  // own: one that does has already heard the tap, which went up as a
  // selection.
  final selectedId =
      _str(block.props[RendelLocalKeys.chosen]) ?? _str(block.props['selected_id']);
  final label = _str(block.props['label']);
  final style = _str(block.props['style']);
  final soldOut = [
    for (final option in options)
      if (option['available'] == false) _str(option['label']) ?? '',
  ].where((name) => name.isNotEmpty).toList();

  return _Plate(
    enclosure: _Enclosure.live,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _BlockTitle(block.props['title']),
        if (label != null && label.isNotEmpty) ...[
          // The same role and gap `datetime_slots` uses to name a Wrap of
          // chips, rather than a third label treatment.
          RendelOverline(label),
          SizedBox(height: theme.space.sm),
        ],
        Wrap(
          spacing: theme.space.sm,
          runSpacing: theme.space.sm,
          children: [
            for (final option in options)
              Builder(
                builder: (context) {
                  final id = _str(option['id']);
                  final name = _str(option['label']) ?? '';
                  final available = option['available'] != false;
                  final select = dispatch.onSelect;
                  // Sent as a `selection` and marked chosen by the sender, as
                  // a slot is. The question names what was being chosen,
                  // because "43" alone could be a size or a quantity.
                  final onTap = available && id != null && select != null
                      ? () => select(
                            block,
                            id,
                            label != null && label.isNotEmpty ? '$label: $name' : name,
                          )
                      : null;
                  // A swatch or a thumbnail when the style asks for one and
                  // the option has it; a chip otherwise.
                  final swatch = style == 'swatches' ? _hexColor(option['swatch_hex']) : null;
                  final picture = style == 'images' ? _str(option['image_url']) : null;
                  if (swatch != null || picture != null) {
                    return _VariantTile(
                      label: name,
                      swatch: swatch,
                      image: picture,
                      selected: id != null && id == selectedId,
                      unavailable: !available,
                      onTap: onTap,
                    );
                  }
                  return RendelChip(
                    label: name,
                    tabular: true,
                    selected: id != null && id == selectedId,
                    // A null handler is how every control in this SDK spells
                    // disabled: it dims and stops responding to a press.
                    unavailable: !available,
                    onTap: onTap,
                  );
                },
              ),
          ],
        ),
        // Named as well as struck through: a fainter chip alone is colour
        // alone. Its own words for a screen reader are on each chip already.
        if (soldOut.isNotEmpty) ...[
          SizedBox(height: theme.space.md),
          ExcludeSemantics(
            child: Text(
              RendelStringsScope.of(context).soldOutNamed(soldOut),
              style: theme.text.body,
            ),
          ),
        ],
      ],
    ),
  );
}

// ————————————————————————— choice —————————————————————————

/// A question answered by tapping (`design/CHOICE.md`): one pick from a few
/// chips, or one or several from a list whose rows can carry a picture, with
/// a row to write an answer of one's own in and a way to answer with none.
///
/// No plate around it: the page asks the question, so it is set as the page's
/// own heading, and only a list is a plate, because its rows are parts of one
/// question rather than cards. Once answered it folds into the answer, for
/// good, and is drawn folded wherever it is seen again.
Widget buildChoice(BuildContext context, WireBlock block, RendelDispatcher dispatch) {
  final question = _str(block.props['question']);
  final options = [
    for (final option in _maps(block.props['options']))
      if (_str(option['id']) != null && _str(option['label']) != null) option,
  ];
  if (question == null || options.isEmpty) return buildFallback(context, block);
  return _Choice(block: block, question: question, options: options, dispatch: dispatch);
}

class _Choice extends StatefulWidget {
  const _Choice({
    required this.block,
    required this.question,
    required this.options,
    required this.dispatch,
  });

  final WireBlock block;
  final String question;
  final List<Map> options;
  final RendelDispatcher dispatch;

  @override
  State<_Choice> createState() => _ChoiceState();
}

class _ChoiceState extends State<_Choice> {
  /// The `other` row has been opened into its field. Only for as long as the
  /// block is on screen: what was written is not an answer until it is sent.
  bool _writing = false;
  final _written = TextEditingController();

  @override
  void initState() {
    super.initState();
    // The Send beside the field lights the moment there is something to send.
    _written.addListener(_rebuild);
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    _written.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _props => widget.block.props;
  bool get _multi => _props['mode'] == 'multi';

  /// The ids lit so far. In the block's props rather than in this state, as a
  /// form's values are, so several picks survive the page being left and
  /// come back to.
  List<String> get _picked => [
        for (final id in _list(_props[RendelLocalKeys.chosen]))
          if (id is String) id,
      ];

  String _labelOf(String id) =>
      _str(widget.options.firstWhere((o) => o['id'] == id, orElse: () => const {})['label']) ??
      id;

  void _tap(String id) {
    final choose = widget.dispatch.onChoose;
    if (choose == null) return;
    if (!_multi) {
      // A single pick is the answer. The sender lights it, then sends it once
      // it has been seen to land; under reduced motion there is nothing to
      // watch, so it goes at once.
      final still = MediaQuery.disableAnimationsOf(context);
      unawaited(choose(
        widget.block,
        [id],
        _labelOf(id),
        lit: still ? Duration.zero : const Duration(milliseconds: 260),
      ));
      return;
    }
    final picked = _picked;
    if (!picked.remove(id)) {
      // Past the most it takes, a row does not tick: the server would refuse
      // the answer, and a tick taken back later is worse than none.
      if (picked.length >= choiceBounds(_props).$2) return;
      picked.add(id);
    }
    setState(() => _props[RendelLocalKeys.chosen] = picked);
  }

  void _submit() {
    final picked = _picked;
    unawaited(widget.dispatch.onChoose
        ?.call(widget.block, picked, picked.map(_labelOf).join(', ')));
  }

  void _sendWritten() {
    final text = _written.text.trim();
    if (text.isEmpty) return;
    unawaited(widget.dispatch.onChoose?.call(widget.block, const [], text, otherText: text));
  }

  void _skip(String label) {
    unawaited(widget.dispatch.onChoose?.call(widget.block, const [], label));
  }

  @override
  Widget build(BuildContext context) {
    final answered = _map(_props[RendelLocalKeys.answered]);
    return RendelSwap(
      stateKey: answered == null ? 'open' : 'answered',
      alignment: Alignment.topLeft,
      child: answered == null
          ? _open(context)
          : _ChoiceAnswered(question: widget.question, answer: _str(answered['shown']) ?? ''),
    );
  }

  Widget _open(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final strings = RendelStringsScope.of(context);
    final hint = _str(_props['hint']);
    final other = _map(_props['other']);
    final skip = _str(_map(_props['skip'])?['label']);
    final live = widget.dispatch.onChoose != null;
    final picked = _picked;
    final multi = _multi;
    // Chips only for a few short words: a subtitle or a picture needs a row.
    final chips = switch (_str(_props['style'])) {
      'chips' => true,
      'list' => false,
      _ => !multi &&
          widget.options.every((o) => _str(o['subtitle']) == null && _str(o['image_url']) == null),
    };
    final (min, _) = choiceBounds(_props);

    Widget optionFor(Map option) {
      final id = _str(option['id'])!;
      final on = picked.contains(id);
      final tap = live ? () => _tap(id) : null;
      final label = _str(option['label'])!;
      return chips
          ? _ChoiceChip(label: label, icon: _str(option['icon']), on: on, multi: multi, onTap: tap)
          : _ChoiceRow(
              label: label,
              subtitle: _str(option['subtitle']),
              image: _str(option['image_url']),
              icon: _str(option['icon']),
              on: on,
              multi: multi,
              onTap: tap,
            );
    }

    final otherLabel = _str(other?['label']);
    final writeOwn = otherLabel == null
        ? null
        : _writing
            ? _ChoiceWrite(
                controller: _written,
                label: otherLabel,
                placeholder: _str(other?['placeholder']),
                send: strings.choiceSend,
                onSend: _written.text.trim().isEmpty ? null : _sendWritten,
              )
            : chips
                ? _ChoiceChip(
                    label: '$otherLabel…',
                    glyph: Icons.edit_outlined,
                    on: false,
                    multi: false,
                    onTap: live ? () => setState(() => _writing = true) : null,
                  )
                : _ChoiceRow(
                    label: '$otherLabel…',
                    glyph: Icons.edit_outlined,
                    quiet: true,
                    on: false,
                    multi: false,
                    onTap: live ? () => setState(() => _writing = true) : null,
                  );

    final Widget options;
    if (chips) {
      options = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in widget.options) optionFor(option),
              if (writeOwn is _ChoiceChip) writeOwn,
            ],
          ),
          // Open, the field is a row of its own under the chips.
          if (writeOwn is _ChoiceWrite) ...[const SizedBox(height: 8), _ChoicePlate(rows: [writeOwn])],
        ],
      );
    } else {
      options = _ChoicePlate(rows: [
        for (final option in widget.options) optionFor(option),
        if (writeOwn != null) writeOwn,
      ]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            widget.question,
            style: theme.text.title.copyWith(fontSize: 17, letterSpacing: -0.17),
          ),
        ),
        if (hint != null) ...[
          const SizedBox(height: 3),
          Text(hint, style: theme.text.body.copyWith(height: 1.4)),
        ],
        SizedBox(height: hint == null ? 12 : 14),
        // A radio group, or a group of checkboxes, named by the question; a
        // group of several says how many are ticked as that changes.
        Semantics(
          container: true,
          explicitChildNodes: true,
          label: widget.question,
          value: multi ? strings.choiceCountOf(picked.length, widget.options.length) : null,
          liveRegion: multi,
          child: options,
        ),
        if (multi) ...[
          const SizedBox(height: 12),
          _ChoiceButton(
            label: [
              _str(_props['submit_label']) ?? strings.choiceSubmit,
              if (picked.isNotEmpty) '${picked.length}',
            ].join(' · '),
            height: 50,
            expand: true,
            onTap: live && picked.length >= min ? _submit : null,
          ),
        ],
        if (skip != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: _ChoiceSkip(label: skip, onTap: live ? () => _skip(skip) : null),
          ),
        ],
      ],
    );
  }
}

/// The glyph a `choice` option names: an info_card icon name, or else the
/// emoji it is. [own] is one the SDK draws itself, the `other` row's pencil.
Widget? _choiceGlyph(String? icon, {IconData? own, required double size, required Color color}) {
  final known = own ?? _iconFor(icon);
  if (known != null) return Icon(known, size: size, color: color);
  if (icon == null) return null;
  return Text(icon, style: TextStyle(fontSize: size, height: 1));
}

/// A chip of a `choice`: the raised ground, the hairline and a soft shadow,
/// and the primary action's lit fill once picked.
class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    required this.label,
    this.icon,
    this.glyph,
    required this.on,
    required this.multi,
    this.onTap,
  });

  final String label;
  final String? icon;

  /// A glyph of the SDK's own, in place of [icon].
  final IconData? glyph;
  final bool on;
  final bool multi;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final still = MediaQuery.disableAnimationsOf(context);
    final radius = BorderRadius.circular(999);
    final ink = on ? theme.colors.onAccent : theme.colors.onSurface;
    final glyph = _choiceGlyph(icon, own: this.glyph, size: 17, color: ink);
    final chip = AnimatedContainer(
      duration: still ? Duration.zero : theme.motion.swap,
      curve: theme.motion.curve,
      // No `alignment`: in a Wrap that would stretch the chip to the row's
      // width. The Row is held to 46 by the minimum and centres its words.
      constraints: const BoxConstraints(minHeight: 46),
      padding: EdgeInsetsDirectional.fromSTEB(glyph == null ? 18 : 14, 0, 18, 0),
      decoration: on
          ? _lit(theme, radius)
          : BoxDecoration(
              color: theme.colors.surfaceRaised,
              border: Border.all(color: theme.hairline),
              borderRadius: radius,
              boxShadow: _choiceShadow(theme),
            ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (glyph != null) ...[ExcludeSemantics(child: glyph), const SizedBox(width: 8)],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.text.label.copyWith(fontSize: 15, color: ink),
            ),
          ),
        ],
      ),
    );
    return _ChoicePress(label: label, on: on, multi: multi, onTap: onTap, child: chip);
  }
}

/// A row of a `choice` list: a picture or a glyph on its tile, the label over
/// its subtitle, and a radio or a checkbox. Picked, it takes the mark's
/// yellow over the raised ground.
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.label,
    this.subtitle,
    this.image,
    this.icon,
    this.glyph,
    this.quiet = false,
    required this.on,
    required this.multi,
    this.onTap,
  });

  final String label;
  final String? subtitle;
  final String? image;
  final String? icon;

  /// A glyph of the SDK's own, in place of [icon].
  final IconData? glyph;

  /// The `other` row: soft ink, and no tick, since it is not itself a pick.
  final bool quiet;
  final bool on;
  final bool multi;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final still = MediaQuery.disableAnimationsOf(context);
    final ink = theme.colors.onSurface;
    final glyph = _choiceGlyph(icon, own: this.glyph, size: 20, color: ink);
    final Widget? leading = image != null
        ? _Thumbnail(url: image, width: 48, height: 48, radius: 12)
        : glyph == null
            ? null
            : Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: theme.tint, borderRadius: BorderRadius.circular(12)),
                child: glyph,
              );
    final ground = theme.colors.surfaceRaised;
    final row = AnimatedContainer(
      duration: still ? Duration.zero : theme.motion.swap,
      curve: theme.motion.curve,
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 16, 10),
      decoration: BoxDecoration(
        color: on ? Color.lerp(ground, theme.mark, 0.55) : ground.withValues(alpha: 0),
      ),
      child: Row(
        children: [
          if (leading != null) ...[ExcludeSemantics(child: leading), const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: theme.text.label.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: quiet ? theme.colors.onSurfaceSoft : ink,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: theme.text.body.copyWith(fontSize: 13, height: 1.35),
                  ),
                ],
              ],
            ),
          ),
          if (!quiet) ...[const SizedBox(width: 12), _ChoiceTick(on: on, multi: multi)],
        ],
      ),
    );
    final said = subtitle == null ? label : '$label, $subtitle';
    // The `other` row opens a field; it is a button, not one of the picks.
    if (quiet) {
      return RendelPressable(semanticLabel: said, onTap: onTap, pressedScale: 0.98, child: row);
    }
    return _ChoicePress(label: said, on: on, multi: multi, onTap: onTap, pressedScale: 0.98, child: row);
  }
}

/// A radio (one pick) or a rounded checkbox (several), 22 across.
class _ChoiceTick extends StatelessWidget {
  const _ChoiceTick({required this.on, required this.multi});

  final bool on;
  final bool multi;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final still = MediaQuery.disableAnimationsOf(context);
    final ink = theme.colors.onSurface;
    return AnimatedContainer(
      duration: still ? Duration.zero : theme.motion.swap,
      curve: theme.motion.curve,
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: multi && on ? ink : ink.withValues(alpha: 0),
        borderRadius: BorderRadius.circular(multi ? 7 : 11),
        // A picked radio is a thick ring of ink round a hole; a picked box is
        // filled, so it has no ring at all.
        border: multi && on ? null : Border.all(color: on ? ink : theme.rail, width: on ? 7 : 2),
      ),
      child: multi && on
          ? Icon(Icons.check_rounded, size: 15, color: theme.colors.surfaceRaised)
          : null,
    );
  }
}

/// Where a pick is tapped, announced as the radio or checkbox it is. Drawn as
/// content, and claiming no control, where nothing can be answered.
class _ChoicePress extends StatelessWidget {
  const _ChoicePress({
    required this.label,
    required this.on,
    required this.multi,
    required this.onTap,
    required this.child,
    this.pressedScale = 0.97,
  });

  final String label;
  final bool on;
  final bool multi;
  final VoidCallback? onTap;
  final Widget child;
  final double pressedScale;

  @override
  Widget build(BuildContext context) {
    if (onTap == null) {
      return Semantics(label: label, excludeSemantics: true, child: child);
    }
    return RendelPressable(
      semanticLabel: label,
      checked: on,
      exclusive: !multi,
      onTap: onTap,
      pressedScale: pressedScale,
      child: child,
    );
  }
}

/// The plate a list's rows share, divided by hairlines.
class _ChoicePlate extends StatelessWidget {
  const _ChoicePlate({required this.rows});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: theme.colors.surfaceRaised,
        border: Border.all(color: theme.hairline),
        borderRadius: BorderRadius.circular(20),
        boxShadow: _choiceShadow(theme),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++) _Divided(first: i == 0, child: rows[i]),
        ],
      ),
    );
  }
}

/// The soft shadow under a chip and a list, as under a screen's card.
List<BoxShadow> _choiceShadow(RendelTheme theme) => [
      BoxShadow(
        color: theme.colors.shadow.withValues(alpha: 0.45),
        offset: const Offset(0, 12),
        blurRadius: 26,
        spreadRadius: -20,
      ),
    ];

/// The `other` row opened, in place, into a field and its Send.
class _ChoiceWrite extends StatelessWidget {
  const _ChoiceWrite({
    required this.controller,
    required this.label,
    required this.placeholder,
    required this.send,
    required this.onSend,
  });

  final TextEditingController controller;
  final String label;
  final String? placeholder;
  final String send;
  final VoidCallback? onSend;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final style = theme.text.label.copyWith(fontSize: 15);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              alignment: AlignmentDirectional.centerStart,
              decoration: BoxDecoration(color: theme.tint, borderRadius: BorderRadius.circular(12)),
              child: Semantics(
                label: label,
                child: TextField(
                  controller: controller,
                  // Opened by a tap that asked to write, so the keyboard
                  // comes with it.
                  autofocus: true,
                  // What `other_text` takes on the wire.
                  maxLength: 300,
                  buildCounter: (_, {required currentLength, required isFocused, maxLength}) =>
                      null,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend?.call(),
                  style: style,
                  cursorColor: theme.colors.onSurface,
                  decoration: InputDecoration(
                    filled: false,
                    isDense: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    hintText: placeholder,
                    hintStyle: style.copyWith(color: theme.colors.onSurfaceFaint),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _ChoiceButton(label: send, height: 44, onTap: onSend),
        ],
      ),
    );
  }
}

/// The lit pill a `choice` is sent with: under a list of several picks, and
/// beside the answer written in. Faded, not tinted, while it has nothing to
/// send, as the prototype has it, so it reads as the same button waiting.
class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({
    required this.label,
    required this.height,
    this.expand = false,
    required this.onTap,
  });

  final String label;
  final double height;
  final bool expand;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final still = MediaQuery.disableAnimationsOf(context);
    return RendelPressable(
      semanticLabel: label,
      onTap: onTap,
      pressedScale: expand ? 0.98 : 0.97,
      child: AnimatedOpacity(
        opacity: onTap == null ? 0.35 : 1,
        duration: still ? Duration.zero : theme.motion.swap,
        child: Container(
          width: expand ? double.infinity : null,
          constraints: BoxConstraints(minHeight: height),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          alignment: Alignment.center,
          decoration: _lit(theme, BorderRadius.circular(999)),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.text.labelStrong.copyWith(fontSize: 15),
          ),
        ),
      ),
    );
  }
}

/// The quiet way to answer with no pick: underlined words under the block.
class _ChoiceSkip extends StatelessWidget {
  const _ChoiceSkip({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final soft = theme.colors.onSurfaceSoft;
    return RendelPressable(
      semanticLabel: label,
      onTap: onTap,
      // A Row, so the 44pt the press guarantees centres the words in it.
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                label,
                style: theme.text.body.copyWith(
                  fontWeight: FontWeight.w500,
                  color: soft,
                  decoration: TextDecoration.underline,
                  decorationColor: soft,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A `choice` answered, folded and read-only: the question over a check and
/// the answer, on a tinted plate.
class _ChoiceAnswered extends StatelessWidget {
  const _ChoiceAnswered({required this.question, required this.answer});

  final String question;
  final String answer;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: theme.tint, borderRadius: BorderRadius.circular(18)),
      child: MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(question, style: theme.text.body.copyWith(fontSize: 13.5, height: 1.35)),
            const SizedBox(height: 6),
            Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(color: theme.colors.onSurface, shape: BoxShape.circle),
                  child: Icon(Icons.check_rounded, size: 13, color: theme.colors.surfaceRaised),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    answer,
                    style: theme.text.label.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ————————————————————————— article_card —————————————————————————

/// A retrieved passage with its source named. The source line is the point:
/// it is what separates a grounded answer from a confident one.
Widget buildArticleCard(BuildContext context, WireBlock block, RendelDispatcher dispatch) {
  final theme = RendelThemeScope.of(context);
  final cta = _map(block.props['cta']);
  final updated = _str(block.props['updated']);
  final source = _str(block.props['source']);

  return _Plate(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _str(block.props['title']) ?? block.fallbackText,
          style: theme.text.title,

        ),
        SizedBox(height: theme.space.sm),
        Text(
          _str(block.props['excerpt']) ?? '',
          style: theme.text.body,
        ),
        if (source != null && source.isNotEmpty) ...[
          // The catalog's one divider, not a second one drawn by hand: every
          // other rule in the file is symmetric 8/8 and this was 16/12.
          const _Rule(strong: false),
          // Merged: read as two nodes the reader gets "help.example.com" and
          // then a bare "2 Sep 2026" with nothing saying it is the date the
          // page was last updated. Same rule as `_KeyValueRow` and the donut
          // legend.
          MergeSemantics(
            child: Row(
            children: [
              Expanded(
                child: Text(
                  source,

                  // label, not accent: the SDK has one accent role and no
                  // darker text tint, and raw accent as body-size ink is
                  // 3.3:1 on a light surface.
                  style: theme.text.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (updated != null && updated.isNotEmpty) ...[
                SizedBox(width: theme.space.md),
                // Capped like every other trailing value: at its 40-character
                // schema maximum this took the whole row and pushed the source
                // off the plate.
                _TrailingSlot(
                  child: Text(
                    updated,
                    style: theme.text.captionSoftTabular,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
            ),
          ),
        ],
        if (cta != null) ...[
          SizedBox(height: theme.space.lg),
          _actionButton(
            context,
            label: _str(cta['label']) ?? 'Read more',
            action: cta['action'],
            dispatch: dispatch,
            quiet: true,
          ),
        ],
      ],
    ),
  );
}

// ————————————————————————— pages —————————————————————————

/// Where a block sits on its page (`design/PAGES.md`). The thread screen puts
/// one around each block it draws. Outside one (the gallery, a test) a block
/// is drawn as on a page, keeping its plate, with no page padding to run out
/// through.
class RendelPage extends InheritedWidget {
  const RendelPage({
    super.key,
    required this.flat,
    required this.inset,
    this.lede = false,
    this.detail = false,
    this.onOpen,
    this.bar = 0,
    required super.child,
  });

  /// How far down the page the bar floating over it reaches: what a line
  /// pinned to the top of the page, such as a comparison's titles, sits
  /// under.
  final double bar;

  /// The block lies flat on the page: a block that only tells the reader
  /// something draws no plate. One that asks for an answer keeps it; see
  /// [readsFlatOnPage].
  final bool flat;

  /// The page's side padding. A rail runs out through it to the screen's
  /// edges, and the way on draws its hairline across it.
  final double inset;

  /// This is the page's first `text` block, set as its lede: on a detail,
  /// the centred summary under the head.
  final bool lede;

  /// The page is a card's detail, opened over the page it was on
  /// (`design/DETAIL.md`).
  final bool detail;

  /// Opens a card on this page over it, with the item's own reply text when
  /// it has one. Null on a detail, where a card's tap does what its action
  /// says.
  final void Function(RendelDetail card, String? reply)? onOpen;

  static RendelPage? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RendelPage>();

  @override
  bool updateShouldNotify(RendelPage oldWidget) =>
      oldWidget.flat != flat ||
      oldWidget.inset != inset ||
      oldWidget.lede != lede ||
      oldWidget.detail != detail ||
      oldWidget.bar != bar ||
      (oldWidget.onOpen == null) != (onOpen == null);
}

/// What a tap on [item] does on a page that opens cards: opens it, unless
/// its action is a link, which still opens the link. Null where it does what
/// it always did.
VoidCallback? _opens(
  BuildContext context,
  Map item, {
  required String? price,
}) {
  final open = RendelPage.maybeOf(context)?.onOpen;
  final action = UIAction.tryParse(item['action']);
  // A call, a copy or an event acts on the device, as a link does, and a
  // detail asked for instead would be a tap that did something else.
  if (open == null ||
      action is OpenUrlAction ||
      action is CallAction ||
      action is CopyAction ||
      action is AddToCalendarAction) {
    return null;
  }
  final picture = _str(item['image_url']);
  final card = RendelDetail(
    title: _str(item['title']) ?? '',
    subtitle: _str(item['subtitle']),
    price: price,
    images: {
      if (picture != null) picture,
      for (final more in _list(item['images']))
        if (_str(more) case final url?) url,
    }.toList(),
  );
  return () => open(card, action is ReplyAction ? action.text : null);
}

/// Whether a block of [type] lies flat on its page. The blocks that wait on
/// the reader keep their plate; it is the same list that gives them their
/// enclosure.
bool readsFlatOnPage(String type) => _enclosureFor(type) == _Enclosure.recorded;

/// A heading for the blocks after it: the section's title with its subtitle
/// under it.
Widget buildSection(BuildContext context, WireBlock block, RendelDispatcher dispatch) {
  final theme = RendelThemeScope.of(context);
  final title = _str(block.props['title']) ?? block.fallbackText;
  final subtitle = _str(block.props['subtitle']);
  return Semantics(
    header: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.text.title.copyWith(fontSize: 17, letterSpacing: -0.17),
        ),
        if (subtitle != null && subtitle.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(subtitle, style: theme.text.body.copyWith(height: 1.4)),
        ],
      ],
    ),
  );
}

/// A few points, each a line with an icon: the reasons behind a pick, or a
/// decision guide. An icon name this build does not know draws nothing and
/// keeps its column, so the titles still line up; points that name no icon
/// at all have no column.
Widget buildKeyPoints(BuildContext context, WireBlock block, RendelDispatcher dispatch) {
  final theme = RendelThemeScope.of(context);
  final items = _maps(block.props['items']);
  if (items.isEmpty) return _EmptyPlate(message: block.fallbackText);
  // A pro or a con draws its mark in the icon's column (`design/CATALOG-B6.md`).
  String? tone(Map item) {
    final named = _str(item['tone']);
    return named == 'positive' || named == 'negative' ? named : null;
  }
  final column = items.any((item) => _str(item['icon']) != null || tone(item) != null);

  return _Plate(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: 16),
          MergeSemantics(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (column) ...[
                  SizedBox(
                    width: 26,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: switch (_iconFor(_str(items[i]['icon']))) {
                        _ when tone(items[i]) != null => _ToneMark(positive: tone(items[i]) == 'positive'),
                        final icon? => Icon(
                            icon,
                            size: 20,
                            color: theme.colors.onSurfaceSoft,
                          ),
                        null => const SizedBox(height: 20),
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _str(items[i]['title']) ?? '',
                        style: theme.text.heading.copyWith(fontSize: 15, height: 1.35),
                      ),
                      if (_str(items[i]['body']) case final body?) ...[
                        const SizedBox(height: 2),
                        Text(body, style: theme.text.body.copyWith(height: 1.4)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    ),
  );
}

// ————————————————————————— details —————————————————————————

/// A few words that characterise one thing: chips with the hairline and no
/// fill. Centred under a detail's head (`design/DETAIL.md`), in a row
/// anywhere else.
Widget buildTags(BuildContext context, WireBlock block, RendelDispatcher dispatch) {
  final theme = RendelThemeScope.of(context);
  final tags = [
    for (final item in _list(block.props['items']))
      if (_str(item) case final tag? when tag.isNotEmpty) tag,
  ];
  if (tags.isEmpty) return buildFallback(context, block);
  final centred = RendelPage.maybeOf(context)?.detail ?? false;
  return SizedBox(
    width: double.infinity,
    child: Wrap(
      alignment: centred ? WrapAlignment.center : WrapAlignment.start,
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final tag in tags)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              border: Border.all(color: theme.hairline),
              borderRadius: BorderRadius.circular(theme.radius.control),
            ),
            child: Text(
              tag,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.text.label.copyWith(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
      ],
    ),
  );
}

/// One or two things to do about what is on screen, side by side. Under a
/// detail's head both are quiet, because the first is also lit beside the
/// microphone (`design/DETAIL.md`); anywhere else the first is the primary.
Widget buildActions(BuildContext context, WireBlock block, RendelDispatcher dispatch) {
  final theme = RendelThemeScope.of(context);
  final items = _maps(block.props['items']).take(2).toList();
  if (items.isEmpty) return buildFallback(context, block);
  final detail = RendelPage.maybeOf(context)?.detail ?? false;
  return Row(
    children: [
      for (var i = 0; i < items.length; i++) ...[
        if (i > 0) SizedBox(width: theme.space.sm),
        Expanded(
          child: detail
              ? _Acting(
                  action: items[i]['action'],
                  dispatch: dispatch,
                  builder: (context, onTap, copied) => _QuietAction(
                    label: copied
                        ? RendelStringsScope.of(context).copied
                        : _str(items[i]['label']) ?? '',
                    icon: copied ? Icons.check_rounded : _iconFor(_str(items[i]['icon'])),
                    onTap: onTap,
                  ),
                )
              : _actionButton(
                  context,
                  label: _str(items[i]['label']) ?? '',
                  action: items[i]['action'],
                  dispatch: dispatch,
                  quiet: i > 0,
                  expand: true,
                ),
        ),
      ],
    ],
  );
}

// ————————————————————————— screens —————————————————————————

/// Screens of the app to open (`design/NAVIGATE.md`): a card each, the
/// model's title over the route's own, so where a tap goes is on the card
/// before it is tapped, in the app's words. A route this build does not know
/// draws its card as content.
Widget buildScreens(BuildContext context, WireBlock block, RendelDispatcher dispatch) {
  final items = _maps(block.props['items']).take(4).toList();
  if (items.isEmpty) return buildFallback(context, block);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < items.length; i++) ...[
        if (i > 0) const SizedBox(height: 10),
        _ScreenCard(
          title: _str(items[i]['title']) ?? '',
          icon: _iconFor(_str(items[i]['icon'])),
          path: _sameWords(
            _str(items[i]['title']),
            switch (UIAction.tryParse(items[i]['action'])) {
              NavigateAction(:final route) => dispatch.routeTitle?.call(route),
              _ => null,
            },
          ),
          onTap: _tap(dispatch, items[i]['action']),
        ),
      ],
    ],
  );
}

/// [path] unless it says what [title] already does: "Cart" over "Cart"
/// (Grove report) is one word read twice.
String? _sameWords(String? title, String? path) =>
    path != null && title?.trim().toLowerCase() == path.trim().toLowerCase() ? null : path;

/// One screen of the app: the primary fill's tile with the item's icon, the
/// item's title over the route's own, and the way out at the end.
class _ScreenCard extends StatelessWidget {
  const _ScreenCard({required this.title, this.icon, this.path, this.onTap});

  final String title;
  final IconData? icon;

  /// The route's registered title. Null for a route this build does not know.
  final String? path;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final card = Container(
      constraints: const BoxConstraints(minHeight: 68),
      padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 14, 12),
      decoration: BoxDecoration(
        color: theme.colors.surfaceRaised,
        border: Border.all(color: theme.hairline),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: theme.colors.shadow.withValues(alpha: 0.45),
            offset: const Offset(0, 12),
            blurRadius: 26,
            spreadRadius: -20,
          ),
        ],
      ),
      child: Row(
        children: [
          // The app's tile, not the copilot's: the fill of the screen's own
          // primary button.
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: theme.litFill,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon ?? Icons.open_in_new_rounded, size: 20, color: theme.colors.onAccent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: theme.text.label.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                if (path != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    path!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.text.body.copyWith(fontSize: 13, color: theme.colors.onSurfaceSoft),
                  ),
                ],
              ],
            ),
          ),
          // An inert card keeps its shape and loses the one part that
          // promises a tap.
          if (onTap != null) ...[
            const SizedBox(width: 12),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: theme.tint, shape: BoxShape.circle),
              child: Icon(Icons.north_east_rounded, size: 15, color: theme.colors.onSurface),
            ),
          ],
        ],
      ),
    );
    final label = path == null ? title : '$title, $path';
    if (onTap == null) {
      return Semantics(label: label, excludeSemantics: true, child: card);
    }
    return RendelPressable(semanticLabel: label, onTap: onTap, pressedScale: 0.98, child: card);
  }
}

/// An action under a detail's head: the raised ground and the hairline, an
/// icon and the label.
class _QuietAction extends StatelessWidget {
  const _QuietAction({required this.label, this.icon, this.onTap});

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final ink = onTap == null ? theme.colors.onSurfaceFaint : theme.colors.onSurface;
    return RendelPressable(
      semanticLabel: label,
      onTap: onTap,
      child: Container(
        height: 48,
        padding: EdgeInsets.symmetric(horizontal: theme.space.md),
        decoration: BoxDecoration(
          color: theme.colors.surfaceRaised,
          border: Border.all(color: theme.hairline),
          borderRadius: BorderRadius.circular(theme.radius.control),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 17, color: ink),
              SizedBox(width: theme.space.sm),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.text.label.copyWith(fontSize: 15, color: ink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A `key_value` row on a page: the label and the value across a hairline,
/// as the facts of a thing are read.
class _Fact extends StatelessWidget {
  const _Fact({
    required this.label,
    required this.value,
    this.strong = false,
    this.tone,
    this.range,
    this.masked = false,
    this.copy = false,
    this.dispatch,
  });

  final String label;
  final String value;
  final bool strong;

  /// As on [_KeyValueRow].
  final String? tone;
  final String? range;
  final bool masked;
  final bool copy;
  final RendelDispatcher? dispatch;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final style = theme.text.labelTabular.copyWith(
      fontSize: 14.5,
      fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
    );
    final fact = MergeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              style: theme.text.body.copyWith(fontSize: 14.5, height: 1.35),
            ),
          ),
          SizedBox(width: theme.space.md),
          Flexible(
            child: _FactValue(
              value: value,
              style: tone == null ? style : style.copyWith(color: _toneInk(theme, tone)),
              masked: masked,
              range: range,
            ),
          ),
        ],
      ),
    );
    final button = copy && dispatch != null;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.hairline)),
      ),
      child: Padding(
        // The copy button's 44pt target takes the row's own padding rather
        // than adding to it.
        padding: EdgeInsets.symmetric(vertical: button ? 2 : 12),
        child: button
            ? Row(
                children: [
                  Expanded(child: fact),
                  _CopyButton(text: value, name: label, dispatch: dispatch!),
                ],
              )
            : fact,
      ),
    );
  }
}

/// A picture filling the box it is drawn in, with the skeleton a picture has
/// until it loads: the head of a card opened over its page.
class RendelPhoto extends StatelessWidget {
  const RendelPhoto({super.key, required this.url, required this.height, this.alt});

  final String url;
  final double height;
  final String? alt;

  @override
  Widget build(BuildContext context) =>
      _Thumbnail(url: url, height: height, radius: 0, alt: alt);
}

// ————————————————————————— catalog wave 4 —————————————————————————
//
// contact, rating, disclosure, checklist and timeline (`design/CATALOG-B4.md`).

/// A block's own heading in the v6 page language: 17 over the rest, as a
/// choice asks its question.
TextStyle _wave4Title(RendelTheme theme) => theme.text.title.copyWith(fontSize: 17, letterSpacing: -0.17);

/// How long a disclosure takes to open or shut: the brief's 220 ms, between
/// the theme's swap and its settle.
const Duration _revealDuration = Duration(milliseconds: 220);

/// How to reach a person at the app: the channels it listed in its console,
/// one button each, the first lit. The SDK opens the dialler, the mail app or
/// the page with the channel's value in it, and nothing more: nothing is
/// dialled, written or sent for the user, and nobody is promised.
Widget buildContact(BuildContext context, WireBlock block, RendelDispatcher dispatch) {
  final theme = RendelThemeScope.of(context);
  final title = _str(block.props['title']);
  final channels = [
    for (final channel in _maps(block.props['channels']))
      if (_str(channel['label']) != null && _str(channel['value']) != null) channel,
  ];
  if (title == null || channels.isEmpty) return buildFallback(context, block);
  final body = _str(block.props['body']);
  final hours = _str(block.props['hours_label']);
  // Its own raised plate on a page too: the one thing on it that says where
  // to go next, so it does not lie flat with the readouts.
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: theme.colors.surfaceRaised,
      border: Border.all(color: theme.hairline),
      borderRadius: BorderRadius.circular(20),
      boxShadow: _choiceShadow(theme),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(header: true, child: Text(title, style: _wave4Title(theme))),
        if (body != null && body.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(body, style: theme.text.body.copyWith(fontSize: 14, height: 1.45)),
        ],
        for (final (i, channel) in channels.indexed) ...[
          SizedBox(height: i == 0 ? 14 : 10),
          _contactButton(block, channel, quiet: i > 0, dispatch: dispatch),
        ],
        if (hours != null && hours.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            hours,
            textAlign: TextAlign.center,
            style: theme.text.body.copyWith(fontSize: 13, height: 1.4),
          ),
        ],
      ],
    ),
  );
}

/// One channel's button. A call and an email carry their number or address
/// on the button, so the user reads where a tap goes before making it; a
/// link reads as its label alone, since a URL is not something to read.
Widget _contactButton(WireBlock block, Map channel, {required bool quiet, required RendelDispatcher dispatch}) {
  final label = _str(channel['label'])!;
  final value = _str(channel['value'])!.trim();
  final (UIAction? action, String words) = switch (_str(channel['kind'])) {
    'call' => (CallAction(value, label: label), '$label $value'),
    'email' => (EmailAction(value), '$label $value'),
    // The protocol's own reading of a link, which takes https alone.
    'url' => (UIAction.tryParse({'kind': 'open_url', 'url': value}), label),
    _ => (null, label),
  };
  return RendelActionButton(
    label: words,
    // A channel this build cannot open is still drawn, as no button, rather
    // than left out: the app listed it, and the user can still read it.
    onTap: action != null && dispatch.canHandle(action)
        ? () {
            dispatch.onContactOpen?.call(block, _str(channel['kind'])!);
            dispatch.onAction(action);
          }
        : null,
    quiet: quiet,
    expand: true,
  );
}

/// The app's own question about how something went, answered with a tap and
/// recorded with no turn: no question over the screen, no new page. With a
/// comment, a field opens once the score is in; then the block folds into
/// its thanks.
Widget buildRating(BuildContext context, WireBlock block, RendelDispatcher dispatch) {
  final question = _str(block.props['question']);
  final scores = ratingScores(block.props);
  if (question == null || scores.isEmpty) return buildFallback(context, block);
  return _Rating(block: block, question: question, scores: scores, dispatch: dispatch);
}

class _Rating extends StatefulWidget {
  const _Rating({
    required this.block,
    required this.question,
    required this.scores,
    required this.dispatch,
  });

  final WireBlock block;
  final String question;
  final List<int> scores;
  final RendelDispatcher dispatch;

  @override
  State<_Rating> createState() => _RatingState();
}

class _RatingState extends State<_Rating> {
  final _comment = TextEditingController();

  /// The score on its way to the server, lit while it goes. One post at a
  /// time, so two quick taps cannot land in the wrong order.
  int? _posting;

  /// The comment is on its way.
  bool _sending = false;

  /// The last post did not land. Said under the block until the next tap.
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    // The Send beside the field wakes the moment there is something to send.
    _comment.addListener(_rebuild);
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _props => widget.block.props;
  String get _scale => _str(_props['scale']) ?? '';

  /// The score the server took. On the block rather than here, as a choice's
  /// picks are, so a rating stepped away from and back to is still answered.
  int? get _score => switch (_props[RendelLocalKeys.chosen]) {
        final int score => score,
        _ => null,
      };

  bool get _asksComment => _map(_props['comment']) != null;
  bool get _busy => _posting != null || _sending;

  Future<void> _pick(int score) async {
    final rate = widget.dispatch.onRate;
    if (rate == null || _busy) return;
    setState(() {
      _posting = score;
      _failed = false;
    });
    final took = await rate(widget.block, score);
    // Written before the mounted check, as a sent form's flag is: a rating
    // scrolled away while its post was in flight must not come back asking.
    if (took) {
      _props[RendelLocalKeys.chosen] = score;
      if (!_asksComment) _props[RendelLocalKeys.answered] = true;
    }
    if (!mounted) return;
    setState(() {
      _posting = null;
      _failed = !took;
    });
  }

  Future<void> _send() async {
    final rate = widget.dispatch.onRate;
    final score = _score;
    final text = _comment.text.trim();
    if (rate == null || score == null || text.isEmpty || _busy) return;
    setState(() {
      _sending = true;
      _failed = false;
    });
    final took = await rate(widget.block, score, comment: text);
    if (took) _props[RendelLocalKeys.answered] = true;
    if (!mounted) return;
    setState(() {
      _sending = false;
      _failed = !took;
    });
  }

  @override
  Widget build(BuildContext context) {
    final score = _score;
    final answered = _props[RendelLocalKeys.answered] == true && score != null;
    return RendelSwap(
      stateKey: answered ? 'thanks' : 'open',
      alignment: Alignment.topLeft,
      child: answered
          ? _RatingThanks(question: widget.question, scale: _scale, score: score)
          : _open(context),
    );
  }

  Widget _open(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final strings = RendelStringsScope.of(context);
    final live = widget.dispatch.onRate != null;
    final shown = _posting ?? _score;
    final low = _str(_props['low_label']);
    final high = _str(_props['high_label']);
    final placeholder = _str(_map(_props['comment'])?['placeholder']);
    final fieldStyle = theme.text.label.copyWith(fontSize: 15);

    // One score's control: a radio of the scale, or the same drawing as
    // content where nothing can be rated.
    Widget pick(int score, String label, Widget child) => live
        ? RendelPressable(
            semanticLabel: label,
            checked: shown == score,
            exclusive: true,
            onTap: () => _pick(score),
            child: child,
          )
        : Semantics(label: label, excludeSemantics: true, child: child);

    final Widget scale = switch (_scale) {
      'thumbs' => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            pick(0, strings.thumbsDown, _RatingThumb(up: false, on: shown == 0)),
            const SizedBox(width: 12),
            pick(1, strings.thumbsUp, _RatingThumb(up: true, on: shown == 1)),
          ],
        ),
      'nps_11' => _NpsScale(
          scores: widget.scores,
          shown: shown,
          cell: (score, child) => pick(score, '$score', child),
        ),
      _ => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final score in widget.scores)
              pick(
                score,
                strings.ratingStarsOf(score),
                SizedBox(
                  width: _starWidth,
                  height: _minTarget,
                  child: Icon(
                    Icons.star_rounded,
                    size: 40,
                    // In ink up to the score, as the web draws them; the rest
                    // on the rail.
                    color: shown != null && score <= shown ? theme.colors.onSurface : theme.rail,
                  ),
                ),
              ),
          ],
        ),
    };

    final endStyle = theme.text.body.copyWith(fontSize: 13, height: 1.35);
    final ends = (low == null && high == null) || _scale == 'thumbs'
        ? null
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(low ?? '', style: endStyle)),
              const SizedBox(width: 12),
              Expanded(child: Text(high ?? '', textAlign: TextAlign.end, style: endStyle)),
            ],
          );
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [scale, if (ends != null) ...[const SizedBox(height: 6), ends]],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(header: true, child: Text(widget.question, style: _wave4Title(theme))),
        const SizedBox(height: 12),
        // A radio group named by the question.
        Semantics(
          container: true,
          explicitChildNodes: true,
          label: widget.question,
          // Stars keep their labels under their own ends, not the page's.
          child: _scale == 'stars_5'
              ? SizedBox(width: _starWidth * widget.scores.length, child: column)
              : column,
        ),
        if (_asksComment && _score != null) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 44),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  alignment: AlignmentDirectional.centerStart,
                  decoration: BoxDecoration(color: theme.tint, borderRadius: BorderRadius.circular(12)),
                  child: TextField(
                    controller: _comment,
                    enabled: !_sending,
                    // What `comment` takes on the wire.
                    maxLength: 500,
                    buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    style: fieldStyle,
                    cursorColor: theme.colors.onSurface,
                    decoration: InputDecoration(
                      filled: false,
                      isDense: true,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      hintText: placeholder,
                      hintStyle: fieldStyle.copyWith(color: theme.colors.onSurfaceFaint),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              RendelActionButton(
                label: strings.choiceSend,
                quiet: true,
                onTap: live && !_busy && _comment.text.trim().isNotEmpty ? _send : null,
              ),
            ],
          ),
        ],
        // The form's error, in a slot of its own, so appearing does not
        // shove the scale out from under the finger that just missed.
        RendelSwap(
          stateKey: _failed ? 'failed' : 'none',
          alignment: Alignment.topLeft,
          child: !_failed
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      strings.turnFailed,
                      style: theme.text.caption.copyWith(color: theme.colors.onSurface),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

/// How wide one of a rating's five stars is: the 40 pt glyph and its share of
/// the gap.
const double _starWidth = 46;

/// A thumb, down or up: a round 52 pt button, white with the hairline, lit
/// once picked.
class _RatingThumb extends StatelessWidget {
  const _RatingThumb({required this.up, required this.on});

  final bool up;
  final bool on;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final still = MediaQuery.disableAnimationsOf(context);
    final round = BorderRadius.circular(26);
    return AnimatedContainer(
      duration: still ? Duration.zero : theme.motion.swap,
      curve: theme.motion.curve,
      width: 52,
      height: 52,
      decoration: on
          ? _lit(theme, round)
          : BoxDecoration(
              color: theme.colors.surfaceRaised,
              border: Border.all(color: theme.hairline),
              borderRadius: round,
              boxShadow: _choiceShadow(theme),
            ),
      child: Icon(
        switch ((up, on)) {
          (true, true) => Icons.thumb_up_rounded,
          (true, false) => Icons.thumb_up_outlined,
          (false, true) => Icons.thumb_down_rounded,
          (false, false) => Icons.thumb_down_outlined,
        },
        size: 22,
        color: on ? theme.colors.onAccent : theme.colors.onSurface,
      ),
    );
  }
}

/// 0 to 10 as rounded squares: one row where eleven fit at a finger's width,
/// otherwise two, 0–5 over 6–10, all the same size.
class _NpsScale extends StatelessWidget {
  const _NpsScale({required this.scores, required this.shown, required this.cell});

  final List<int> scores;
  final int? shown;

  /// Wraps a square in its control.
  final Widget Function(int score, Widget child) cell;

  static const double _gap = 6;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final still = MediaQuery.disableAnimationsOf(context);
    return LayoutBuilder(builder: (context, constraints) {
      final across = constraints.maxWidth;
      final oneRow = (across - (scores.length - 1) * _gap) / scores.length >= _minTarget;
      final perRow = oneRow ? scores.length : 6;
      // One size for every square, so the second row lines up under the
      // first. On the narrowest phones that is a point under a finger's
      // width, and the press takes the square's size rather than painting
      // past the page.
      final size = math.min(56.0, (across - (perRow - 1) * _gap) / perRow);
      Widget square(int score) {
        final on = shown == score;
        return cell(
          score,
          AnimatedContainer(
            duration: still ? Duration.zero : theme.motion.swap,
            curve: theme.motion.curve,
            width: size,
            height: math.max(size, _minTarget),
            alignment: Alignment.center,
            decoration: on
                ? _lit(theme, BorderRadius.circular(12))
                : BoxDecoration(
                    color: theme.colors.surfaceRaised,
                    border: Border.all(color: theme.hairline),
                    borderRadius: BorderRadius.circular(12),
                  ),
            child: Text(
              '$score',
              maxLines: 1,
              style: (on ? theme.text.labelStrong : theme.text.labelEmphasis).copyWith(fontSize: 15).tabular,
            ),
          ),
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var at = 0; at < scores.length; at += perRow) ...[
            if (at > 0) const SizedBox(height: _gap),
            Row(
              children: [
                for (var i = at; i < math.min(at + perRow, scores.length); i++) ...[
                  if (i > at) const SizedBox(width: _gap),
                  SizedBox(width: size, child: square(scores[i])),
                ],
              ],
            ),
          ],
        ],
      );
    });
  }
}

/// A rating answered, folded and read-only: the question over the score and
/// the thanks, on a tinted plate, as a choice folds into its answer.
class _RatingThanks extends StatelessWidget {
  const _RatingThanks({required this.question, required this.scale, required this.score});

  final String question;
  final String scale;
  final int score;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final strings = RendelStringsScope.of(context);
    final ink = theme.colors.onSurface;
    final (Widget mark, String said) = switch (scale) {
      'thumbs' => (
          Icon(score == 1 ? Icons.thumb_up_rounded : Icons.thumb_down_rounded, size: 18, color: ink),
          score == 1 ? strings.thumbsUp : strings.thumbsDown,
        ),
      'nps_11' => (
          Container(
            constraints: const BoxConstraints(minWidth: 26),
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            alignment: Alignment.center,
            decoration: _white(theme, 8),
            child: Text('$score', style: theme.text.labelEmphasis.copyWith(fontSize: 13).tabular),
          ),
          '$score',
        ),
      _ => (
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var n = 1; n <= 5; n++) Icon(Icons.star_rounded, size: 16, color: n <= score ? ink : theme.rail),
            ],
          ),
          strings.ratingStarsOf(score),
        ),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: theme.tint, borderRadius: BorderRadius.circular(18)),
      // One sentence: the question, the score as words, the thanks.
      child: Semantics(
        label: '$question, $said, ${strings.ratingThanks}',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(question, style: theme.text.body.copyWith(fontSize: 13.5, height: 1.35)),
            const SizedBox(height: 6),
            Row(
              children: [
                mark,
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    strings.ratingThanks,
                    style: theme.text.label.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Secondary detail folded under titles: FAQs, terms, "what's included".
/// Flat on the page, rows divided by hairlines, every one shut at first.
Widget buildDisclosure(BuildContext context, WireBlock block, RendelDispatcher dispatch) {
  final items = [
    for (final item in _maps(block.props['items']))
      if (_str(item['title']) != null && _str(item['body']) != null) item,
  ];
  if (items.isEmpty) return buildFallback(context, block);
  return _Disclosure(items: items, single: block.props['single_open'] == true);
}

class _Disclosure extends StatefulWidget {
  const _Disclosure({required this.items, required this.single});

  final List<Map> items;

  /// Opening one shuts the others.
  final bool single;

  @override
  State<_Disclosure> createState() => _DisclosureState();
}

class _DisclosureState extends State<_Disclosure> {
  /// Which rows are open. Here rather than on the block: what is open is how
  /// the page is being read right now, not something the user did to it.
  final Set<int> _open = {};

  void _toggle(int i) => setState(() {
        if (_open.remove(i)) return;
        if (widget.single) _open.clear();
        _open.add(i);
      });

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final strings = RendelStringsScope.of(context);
    final still = MediaQuery.disableAnimationsOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, item) in widget.items.indexed)
          _Divided(
            first: i == 0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                RendelPressable(
                  semanticLabel: _str(item['title'])!,
                  expanded: _open.contains(i),
                  tapHint: _open.contains(i) ? strings.collapse : strings.expand,
                  pressedScale: 0.98,
                  onTap: () => _toggle(i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _str(item['title'])!,
                            style: theme.text.label.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: 12),
                        AnimatedRotation(
                          turns: _open.contains(i) ? 0.5 : 0,
                          duration: still ? Duration.zero : _revealDuration,
                          curve: theme.motion.curve,
                          child: Icon(Icons.expand_more_rounded, size: 22, color: theme.colors.onSurfaceSoft),
                        ),
                      ],
                    ),
                  ),
                ),
                _Reveal(
                  open: _open.contains(i),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Text(
                      _str(item['body'])!,
                      style: theme.text.body.copyWith(fontSize: 14.5, height: 1.45),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// [child] while [open], grown into and faded in over 220 ms; nothing at all
/// while shut, so a screen reader does not read what is folded away. Under
/// reduced motion no animation widgets at all, for the reason [RendelSwap]
/// gives.
class _Reveal extends StatelessWidget {
  const _Reveal({required this.open, required this.child});

  final bool open;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    const shut = SizedBox(width: double.infinity);
    if (MediaQuery.disableAnimationsOf(context)) return open ? child : shut;
    return AnimatedSize(
      duration: _revealDuration,
      curve: theme.motion.curve,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: _revealDuration,
        switchInCurve: theme.motion.swapIn,
        switchOutCurve: theme.motion.swapOut,
        layoutBuilder: (current, previous) => Stack(
          alignment: AlignmentDirectional.topStart,
          children: [
            // The body on its way out is neither tappable nor read.
            for (final gone in previous) IgnorePointer(child: ExcludeSemantics(child: gone)),
            if (current != null) current,
          ],
        ),
        child: open
            ? KeyedSubtree(key: const ValueKey('open'), child: child)
            : const KeyedSubtree(key: ValueKey('shut'), child: shut),
      ),
    );
  }
}

/// Steps the user ticks off themselves. The ticks stay on the device, kept
/// with the block for as long as the conversation is; nothing is sent until
/// the user presses the finishing button, when there is one.
Widget buildChecklist(BuildContext context, WireBlock block, RendelDispatcher dispatch) {
  final items = [
    for (final item in _maps(block.props['items']))
      if (_str(item['id']) != null && _str(item['title']) != null) item,
  ];
  if (items.isEmpty) return buildFallback(context, block);
  return _Checklist(block: block, items: items, dispatch: dispatch);
}

class _Checklist extends StatefulWidget {
  const _Checklist({required this.block, required this.items, required this.dispatch});

  final WireBlock block;
  final List<Map> items;
  final RendelDispatcher dispatch;

  @override
  State<_Checklist> createState() => _ChecklistState();
}

class _ChecklistState extends State<_Checklist> {
  Map<String, dynamic> get _props => widget.block.props;

  /// The ids ticked: the user's, once they have ticked anything, and the
  /// items' own `done` until then. On the block, so a page stepped away from
  /// and back to keeps them.
  Set<String> get _ticked => switch (_props[RendelLocalKeys.chosen]) {
        final List kept => {
            for (final id in kept)
              if (id is String) id,
          },
        _ => {
            for (final item in widget.items)
              if (item['done'] == true) _str(item['id'])!,
          },
      };

  void _toggle(String id) {
    final ticked = _ticked;
    if (!ticked.remove(id)) ticked.add(id);
    setState(() => _props[RendelLocalKeys.chosen] = ticked.toList());
  }

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final title = _str(_props['title']);
    final ticked = _ticked;
    final complete = _map(_props['on_complete']);
    final label = _str(complete?['label']);
    final reply = _str(complete?['reply_text']);
    final ask = reply == null ? null : ReplyAction(reply);
    final finished = widget.items.every((item) => ticked.contains(_str(item['id'])));
    final offer = finished && label != null && ask != null && widget.dispatch.canHandle(ask);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null && title.isNotEmpty) ...[
          Semantics(header: true, child: Text(title, style: _wave4Title(theme))),
          const SizedBox(height: 6),
        ],
        for (final (i, item) in widget.items.indexed)
          _Divided(
            first: i == 0,
            child: _CheckRow(
              item: item,
              on: ticked.contains(_str(item['id'])),
              onTap: () => _toggle(_str(item['id'])!),
            ),
          ),
        // Only once every item is ticked, in a slot of its own, so it grows
        // in under the list rather than jumping in.
        RendelSwap(
          stateKey: offer ? 'finished' : 'open',
          child: !offer
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: RendelActionButton(
                    label: label,
                    expand: true,
                    onTap: () => widget.dispatch.onAction(ask),
                  ),
                ),
        ),
      ],
    );
  }
}

/// One step: the rounded box, the title (soft and struck through once
/// done), what it means under it, and its deadline as a pill at the end.
class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.item, required this.on, required this.onTap});

  final Map item;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final title = _str(item['title'])!;
    final body = _str(item['body']);
    final due = _str(item['due_label']);
    final soft = theme.colors.onSurfaceSoft;
    return RendelPressable(
      semanticLabel: _joinParts([title, body, due]),
      checked: on,
      pressedScale: 0.98,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              _ChoiceTick(on: on, multi: true),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: theme.text.label.copyWith(
                        fontSize: 15,
                        color: on ? soft : theme.colors.onSurface,
                        decoration: on ? TextDecoration.lineThrough : null,
                        decorationColor: soft,
                      ),
                    ),
                    if (body != null && body.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(body, style: theme.text.body.copyWith(fontSize: 13.5, height: 1.4)),
                    ],
                  ],
                ),
              ),
              if (due != null && due.isNotEmpty) ...[
                const SizedBox(width: 10),
                _TrailingSlot(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.highlight,
                      border: Border.all(color: theme.hairline),
                      borderRadius: BorderRadius.circular(theme.radius.control),
                    ),
                    child: Text(
                      due,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.text.captionSoftTabular.copyWith(fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Planned things in time order: a day's agenda, a trip's legs. A heading
/// per day, then rows on a rail; a row with an action is a control.
Widget buildTimeline(BuildContext context, WireBlock block, RendelDispatcher dispatch) {
  final theme = RendelThemeScope.of(context);
  final items = [
    for (final item in _maps(block.props['items']))
      if (_str(item['time_label']) != null && _str(item['title']) != null) item,
  ];
  if (items.isEmpty) return buildFallback(context, block);
  final groups = [for (final group in _maps(block.props['groups'])) _str(group['label']) ?? ''];
  // An item with no group, or naming a heading that is not there, sits
  // before the first heading rather than being dropped.
  final loose = <Map>[];
  final grouped = [for (final _ in groups) <Map>[]];
  for (final item in items) {
    final at = item['group_index'];
    if (at is int && at >= 0 && at < groups.length) {
      grouped[at].add(item);
    } else {
      loose.add(item);
    }
  }
  final title = _str(block.props['title']);
  final rows = <Widget>[
    for (final item in loose) _TimelineRow(item: item, dispatch: dispatch),
  ];
  for (final (i, group) in groups.indexed) {
    // A heading with nothing under it would be a day with no plan in it.
    if (grouped[i].isEmpty || group.isEmpty) continue;
    rows.add(Padding(
      padding: EdgeInsets.only(top: rows.isEmpty ? 0 : 18, bottom: 6),
      // As the words came, not in capitals: Dart's toUpperCase knows no
      // Turkish, and "Pazartesi" would read "PAZARTESI" without the dot.
      child: Semantics(
        header: true,
        child: Text(
          group,
          style: theme.text.caption.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 12 * 0.06,
            color: theme.colors.onSurfaceSoft,
          ),
        ),
      ),
    ));
    for (final item in grouped[i]) {
      rows.add(_TimelineRow(item: item, dispatch: dispatch));
    }
  }
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (title != null && title.isNotEmpty) ...[
        Semantics(header: true, child: Text(title, style: _wave4Title(theme))),
        const SizedBox(height: 12),
      ],
      ...rows,
    ],
  );
}

/// One planned thing on the rail: its time in a column of its own, then the
/// title, after its glyph, over its subtitle.
class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.item, required this.dispatch});

  final Map item;
  final RendelDispatcher dispatch;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final time = _str(item['time_label'])!;
    final title = _str(item['title'])!;
    final subtitle = _str(item['subtitle']);
    final icon = _iconFor(_str(item['icon']));
    final row = Container(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 0, 10),
      // The rail is each row's own start edge, so the rows of a day draw one
      // unbroken line and a heading breaks it between days.
      decoration: BoxDecoration(
        border: BorderDirectional(start: BorderSide(color: theme.rail, width: 2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: Text(
              time,
              style: theme.text.labelTabular.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 16, color: theme.colors.onSurfaceSoft),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(
                        title,
                        style: theme.text.label.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                if (subtitle != null && subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(subtitle, style: theme.text.body.copyWith(fontSize: 13, height: 1.35)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
    final onTap = _tap(dispatch, item['action']);
    if (onTap == null) return MergeSemantics(child: row);
    return RendelPressable(
      semanticLabel: _joinParts([time, title, subtitle]),
      pressedScale: 0.98,
      onTap: onTap,
      child: row,
    );
  }
}

// ————————————————————————— catalog wave 5 —————————————————————————
//
// place_card, map and pass (`design/CATALOG-B5.md`).

/// The plate a place and a pass sit on: the raised ground, the hairline and
/// the soft shadow, on a page too. Each is a thing of its own, a shop or a
/// ticket, and does not lie flat with the readouts around it.
BoxDecoration _thingPlate(RendelTheme theme) => BoxDecoration(
      color: theme.colors.surfaceRaised,
      border: Border.all(color: theme.hairline),
      borderRadius: BorderRadius.circular(20),
      boxShadow: _choiceShadow(theme),
    );

/// The way to a place in the maps app this device has (**Pick**): Apple's on
/// iOS, Google's on Android and the web. To the coordinates when there are
/// both, which find the door; to the address otherwise.
String _directionsUrl({double? lat, double? lng, String? address}) {
  final to = lat != null && lng != null ? '$lat,$lng' : Uri.encodeComponent(address ?? '');
  return !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS
      ? 'https://maps.apple.com/?daddr=$to'
      : 'https://www.google.com/maps/dir/?api=1&destination=$to';
}

/// A tap that hands [url] to the system, or null where this build cannot.
VoidCallback? _external(RendelDispatcher dispatch, String url) {
  final action = OpenUrlAction(url, external: true);
  return dispatch.canHandle(action) ? () => dispatch.onAction(action) : null;
}

/// A place someone can go to: a store with the item in stock, a branch, the
/// pharmacy on duty. Whether it is open, how far, and the way there, which
/// the SDK builds from the coordinates; a call; the website.
///
/// On an answer page its head opens it into its detail, as a product card
/// does (`design/DETAIL.md`), and there the week's hours show under the line.
Widget buildPlaceCard(BuildContext context, WireBlock block, RendelDispatcher dispatch) {
  final theme = RendelThemeScope.of(context);
  final strings = RendelStringsScope.of(context);
  final props = block.props;
  final name = _str(props['name']);
  final address = _str(props['address']);
  if (name == null || name.isEmpty || address == null || address.isEmpty) {
    return buildFallback(context, block);
  }
  final page = RendelPage.maybeOf(context);
  final picture = _str(props['image_url']);
  final where = [address, _str(props['distance_label'])]
      .whereType<String>()
      .where((part) => part.isNotEmpty)
      .join(' · ');
  final soft = theme.text.body.copyWith(fontSize: 13.5, height: 1.4);

  // Open now or Closed, today's hours, the stars: one line, each part only
  // when the wire has it.
  final open = switch (props['open_now']) {
    true => strings.openNow,
    false => strings.closed,
    _ => null,
  };
  final rating = _dbl(props['rating']);
  final count = _dbl(props['rating_count'])?.round();
  final line = <String>[
    if (_str(props['hours_today']) case final today? when today.isNotEmpty) today,
    if (rating != null)
      '★ ${rendelNumber(rating, strings.numberLocale, digits: 1)}${count == null ? '' : ' (${rendelNumber(count, strings.numberLocale, digits: 0)})'}',
  ];
  final hours = [
    for (final day in _maps(props['hours_week']))
      if ((_str(day['day']), _str(day['hours'])) case (final d?, final h?)) (d, h),
  ];

  final head = Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (picture != null) ...[
        LayoutBuilder(
          builder: (context, box) => _Thumbnail(
            url: picture,
            width: box.maxWidth,
            height: box.maxWidth * 9 / 16,
            radius: 14,
            alt: name,
          ),
        ),
        const SizedBox(height: 14),
      ],
      Text(name, style: _wave4Title(theme)),
      const SizedBox(height: 4),
      Text(where, style: soft),
      if (open != null || line.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text.rich(
          TextSpan(children: [
            if (open != null)
              TextSpan(
                text: open,
                style: TextStyle(color: theme.colors.onSurface, fontWeight: FontWeight.w600),
              ),
            for (final (i, part) in line.indexed)
              TextSpan(text: open == null && i == 0 ? part : ' · $part'),
          ]),
          style: soft,
        ),
      ],
      // The week's hours belong to the detail; on the card they would be
      // seven lines under every shop in a list of three.
      if ((page?.detail ?? false) && hours.isNotEmpty) ...[
        const SizedBox(height: 10),
        for (final (i, (day, time)) in hours.indexed)
          _Divided(
            first: i == 0,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Text(day, style: soft)),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      time,
                      textAlign: TextAlign.end,
                      style: theme.text.labelTabular.copyWith(fontSize: 13.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    ],
  );

  final onOpen = page?.onOpen;
  final opens = onOpen == null
      ? null
      : () => onOpen(
            RendelDetail(title: name, subtitle: where, images: [if (picture != null) picture]),
            null,
          );

  final lat = _dbl(props['lat']);
  final lng = _dbl(props['lng']);
  final phone = _str(props['phone']);
  final call = phone == null || phone.trim().isEmpty ? null : CallAction(phone);
  final buttons = <Widget>[
    if (props['directions'] == true)
      RendelActionButton(
        label: strings.directions,
        onTap: _external(dispatch, _directionsUrl(lat: lat, lng: lng, address: address)),
        expand: true,
      ),
    if (call != null)
      RendelActionButton(
        label: strings.call,
        onTap: dispatch.canHandle(call) ? () => dispatch.onAction(call) : null,
        quiet: true,
        expand: true,
      ),
  ];
  final site = UIAction.tryParse({'kind': 'open_url', 'url': props['website']});
  final siteTap = site != null && dispatch.canHandle(site) ? () => dispatch.onAction(site) : null;
  // The address the link goes to, not a word for "website": the user reads
  // where a tap goes before making it.
  final host = site is OpenUrlAction ? Uri.parse(site.url).host.replaceFirst(RegExp(r'^www\.'), '') : null;

  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: _thingPlate(theme),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (opens != null)
          RendelPressable(
            semanticLabel: _joinParts([name, where, [open, ...line].whereType<String>().join(' · ')]),
            pressedScale: 0.98,
            onTap: opens,
            child: head,
          )
        else
          MergeSemantics(child: head),
        if (buttons.isNotEmpty) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              for (final (i, button) in buttons.indexed) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(child: button),
              ],
            ],
          ),
        ],
        if (host != null && host.isNotEmpty) ...[
          SizedBox(height: buttons.isEmpty ? 10 : 4),
          Center(
            child: RendelPressable(
              semanticLabel: host,
              onTap: siteTap,
              child: Center(
                widthFactor: 1,
                child: Text(
                  host,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.text.label.copyWith(
                    fontSize: 14,
                    decoration: TextDecoration.underline,
                    decorationColor: theme.rail,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

/// A pin as the wire gives it, or nothing for one missing its coordinates
/// or its label.
typedef _Pin = ({double lat, double lng, String label, String? subtitle});

/// How far in from the sides the outermost pins stand: [least], or half the
/// widest label, which is centred over its point, so a pin at the edge keeps
/// its name on the map ("ove Parramatta", Grove report). Estimated from the
/// label's length (12 pt, at most 180 wide) and held to a quarter of [width]
/// each side, so a narrow map still has room to place them.
double _pinRoom(List<_Pin> pins, double width, double least) {
  var widest = 0.0;
  for (final pin in pins) {
    widest = math.max(widest, math.min(180.0, 20 + pin.label.length * 7.2));
  }
  return math.max(least, math.min(widest / 2, width / 4));
}

List<_Pin> _pinsOf(Map props) => [
      for (final pin in _maps(props['pins']))
        if ((_dbl(pin['lat']), _dbl(pin['lng']), _str(pin['label'])) case (final lat?, final lng?, final label?)
            when label.isNotEmpty)
          (lat: lat, lng: lng, label: label, subtitle: _str(pin['subtitle'])),
    ];

/// Places on a map: the stores near the user, a route's stops.
///
/// On the page a picture of where they are, which scrolls with the page and
/// takes no gesture (**Pick**: a map inside a scrolling page fights the
/// scroll); a tap anywhere opens it full screen, where it pans and zooms.
/// The ground is MapLibre over OpenFreeMap ([RendelMapEngine]); where that
/// cannot load, the pins as a list, each still opening in the maps app.
Widget buildMap(BuildContext context, WireBlock block, RendelDispatcher dispatch) {
  final pins = _pinsOf(block.props);
  if (pins.isEmpty) return buildFallback(context, block);
  return _MapBlock(block: block, pins: pins, dispatch: dispatch);
}

class _MapBlock extends StatefulWidget {
  const _MapBlock({required this.block, required this.pins, required this.dispatch});

  final WireBlock block;
  final List<_Pin> pins;
  final RendelDispatcher dispatch;

  @override
  State<_MapBlock> createState() => _MapBlockState();
}

class _MapBlockState extends State<_MapBlock> {
  /// The engine could not draw here. For as long as the block is on screen:
  /// a map that failed for want of a network is not retried under a reader.
  bool _failed = false;

  void _fail() {
    if (mounted && !_failed) setState(() => _failed = true);
  }

  Future<void> _fullScreen() {
    final theme = RendelThemeScope.of(context);
    final strings = RendelStringsScope.of(context);
    final still = MediaQuery.disableAnimationsOf(context);
    return Navigator.of(context).push(PageRouteBuilder<void>(
      // The detail sheet's timings: a 460 ms rise and a 320 ms fall.
      transitionDuration: still ? Duration.zero : const Duration(milliseconds: 460),
      reverseTransitionDuration: still ? Duration.zero : const Duration(milliseconds: 320),
      pageBuilder: (_, __, ___) => RendelThemeScope(
        theme: theme,
        child: RendelStringsScope(
          strings: strings,
          child: _MapScreen(pins: widget.pins, dispatch: widget.dispatch),
        ),
      ),
      transitionsBuilder: (_, animation, __, child) => SlideTransition(
        position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(CurvedAnimation(
          parent: animation,
          curve: rendelEase,
          reverseCurve: const Cubic(0.4, 0, 1, 1).flipped,
        )),
        child: child,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final caption = _str(widget.block.props['caption']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_failed)
          _PinList(pins: widget.pins, dispatch: widget.dispatch)
        else
          Container(
            height: 200,
            clipBehavior: Clip.antiAlias,
            foregroundDecoration: BoxDecoration(
              border: Border.all(color: theme.hairline),
              borderRadius: BorderRadius.circular(20),
            ),
            decoration: BoxDecoration(
              color: theme.colors.surfaceSunk,
              borderRadius: BorderRadius.circular(20),
            ),
            child: LayoutBuilder(builder: (context, box) {
              final size = box.biggest;
              final camera = RendelMapCamera.fit(
                [for (final pin in widget.pins) (lat: pin.lat, lng: pin.lng)],
                size,
                padding: EdgeInsets.symmetric(
                  horizontal: _pinRoom(widget.pins, size.width, 40),
                  vertical: 40,
                ),
              );
              return Stack(
                fit: StackFit.expand,
                children: [
                  RendelMapEngine.current.build(
                    camera: camera,
                    interactive: false,
                    onMove: (_) {},
                    onFailed: _fail,
                  ),
                  IgnorePointer(child: _PinLayer(pins: widget.pins, camera: camera, size: size)),
                  const _MapCredit(),
                  // Over the map rather than around it: the press gives no
                  // scale or fade to a platform view, which pays for both
                  // with a frame, and the map under it never sees a touch.
                  Positioned.fill(
                    child: RendelPressable(
                      semanticLabel: _joinParts([caption, ...widget.pins.map((pin) => pin.label)]),
                      pressedScale: 1,
                      onTap: _fullScreen,
                      child: const SizedBox.expand(),
                    ),
                  ),
                ],
              );
            }),
          ),
        if (caption != null && caption.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(caption, style: theme.text.body.copyWith(fontSize: 13.5, height: 1.4)),
        ],
      ],
    );
  }
}

/// The pins, each an ink pill with its label standing over its point.
class _PinLayer extends StatelessWidget {
  const _PinLayer({
    required this.pins,
    required this.camera,
    required this.size,
    this.selected,
    this.onTap,
  });

  final List<_Pin> pins;
  final RendelMapCamera camera;
  final Size size;

  /// Full screen: the pin whose callout is open, and what a tap on a pin does.
  final int? selected;
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        for (final (i, pin) in pins.indexed) _placed(camera.project(pin.lat, pin.lng, size), _pin(theme, i, pin)),
      ],
    );
  }

  /// [pin] centred over [at] and standing on it.
  Widget _placed(Offset at, Widget pin) => Positioned(
        left: at.dx,
        top: at.dy,
        child: FractionalTranslation(translation: const Offset(-0.5, -1), child: pin),
      );

  Widget _pin(RendelTheme theme, int i, _Pin pin) {
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colors.onSurface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        pin.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.text.label.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          height: 1.25,
          color: theme.colors.surfaceRaised,
        ),
      ),
    );
    final tap = onTap;
    if (tap == null) return ConstrainedBox(constraints: const BoxConstraints(maxWidth: 180), child: pill);
    final subtitle = pin.subtitle;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: RendelPressable(
        semanticLabel: _joinParts([pin.label, subtitle]),
        selected: i == selected,
        onTap: () => tap(i),
        // Standing on its point inside the 44 pt target, so the target's own
        // height does not lift the pill off it.
        child: Align(
          alignment: Alignment.bottomCenter,
          widthFactor: 1,
          heightFactor: 1,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (i == selected) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: _white(theme, 12).copyWith(boxShadow: _choiceShadow(theme)),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        pin.label,
                        textAlign: TextAlign.center,
                        style: theme.text.label.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      if (subtitle != null && subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          textAlign: TextAlign.center,
                          style: theme.text.body.copyWith(fontSize: 12.5, height: 1.35),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
              ],
              pill,
            ],
          ),
        ),
      ),
    );
  }
}

/// The map data's credit, which its licence requires and which is always in
/// sight: bottom right, over the map.
class _MapCredit extends StatelessWidget {
  const _MapCredit({this.bottom = 6});

  final double bottom;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    return PositionedDirectional(
      end: 8,
      bottom: bottom,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: theme.colors.surfaceRaised.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            '© OpenStreetMap',
            style: theme.text.caption.copyWith(fontSize: 10, color: theme.colors.onSurfaceSoft),
          ),
        ),
      ),
    );
  }
}

/// The pins as a plain list, for where the map cannot be drawn: each row
/// still opens its place in the maps app.
class _PinList extends StatelessWidget {
  const _PinList({required this.pins, required this.dispatch});

  final List<_Pin> pins;
  final RendelDispatcher dispatch;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      decoration: _thingPlate(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, pin) in pins.indexed)
            _Divided(
              first: i == 0,
              child: RendelPressable(
                semanticLabel: _joinParts([pin.label, pin.subtitle]),
                pressedScale: 0.98,
                onTap: _external(dispatch, _directionsUrl(lat: pin.lat, lng: pin.lng)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      Icon(Icons.place_outlined, size: 20, color: theme.colors.onSurfaceSoft),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(pin.label, style: theme.text.label.copyWith(fontWeight: FontWeight.w600)),
                            if (pin.subtitle case final subtitle? when subtitle.isNotEmpty)
                              Text(subtitle, style: theme.text.body.copyWith(fontSize: 13, height: 1.35)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.north_east_rounded, size: 18, color: theme.colors.onSurfaceSoft),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A map opened full screen, over everything, as a card's detail opens over
/// its page: ✕ at the top left, the map under a finger, the pins tappable
/// for their callout, and Open in Maps lit at the foot for the pin picked,
/// or the first.
class _MapScreen extends StatefulWidget {
  const _MapScreen({required this.pins, required this.dispatch});

  final List<_Pin> pins;
  final RendelDispatcher dispatch;

  @override
  State<_MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<_MapScreen> {
  /// Where the user has moved the map to; null until they move it.
  RendelMapCamera? _moved;
  int? _selected;
  bool _failed = false;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final strings = RendelStringsScope.of(context);
    final safe = MediaQuery.paddingOf(context);
    final pin = widget.pins[_selected ?? 0];
    // The foot the button stands in, which the pins are fitted clear of.
    final foot = safe.bottom + 16 + 52 + 16;
    final bar = safe.top + theme.space.lg + 40;
    return Material(
      color: theme.colors.surfaceRaised,
      child: LayoutBuilder(builder: (context, box) {
        final size = box.biggest;
        final fitted = RendelMapCamera.fit(
          [for (final pin in widget.pins) (lat: pin.lat, lng: pin.lng)],
          size,
          padding: EdgeInsets.fromLTRB(
            _pinRoom(widget.pins, size.width, 40),
            bar + 40,
            _pinRoom(widget.pins, size.width, 40),
            foot + 40,
          ),
        );
        return Stack(
          fit: StackFit.expand,
          children: [
            if (_failed)
              Padding(
                padding: EdgeInsets.fromLTRB(16, bar + 16, 16, foot),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: SingleChildScrollView(child: _PinList(pins: widget.pins, dispatch: widget.dispatch)),
                ),
              )
            else ...[
              RendelMapEngine.current.build(
                camera: fitted,
                interactive: true,
                onMove: (camera) {
                  if (mounted) setState(() => _moved = camera);
                },
                onFailed: () {
                  if (mounted) setState(() => _failed = true);
                },
              ),
              _PinLayer(
                pins: widget.pins,
                camera: _moved ?? fitted,
                size: size,
                selected: _selected,
                onTap: (i) => setState(() => _selected = i == _selected ? null : i),
              ),
              _MapCredit(bottom: foot + 6),
            ],
            PositionedDirectional(
              top: safe.top + theme.space.lg,
              start: theme.space.plate,
              child: _MapClose(label: strings.closeDetail, onTap: () => Navigator.of(context).maybePop()),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: safe.bottom + 16,
              child: RendelActionButton(
                label: strings.openInMaps,
                detail: _selected == null ? null : pin.label,
                onTap: _external(widget.dispatch, _directionsUrl(lat: pin.lat, lng: pin.lng)),
                expand: true,
              ),
            ),
          ],
        );
      }),
    );
  }
}

/// The full-screen map's ✕: the detail sheet's round glass button, 40 across.
class _MapClose extends StatelessWidget {
  const _MapClose({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    return Semantics(
      button: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ClipOval(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 9, sigmaY: 9),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colors.surfaceHigh.withValues(alpha: 0.72),
                border: Border.all(color: theme.hairline),
              ),
              child: Icon(Icons.close_rounded, size: 20, color: theme.colors.onSurface),
            ),
          ),
        ),
      ),
    );
  }
}

/// Something the user shows at a counter or a gate: a ticket, a boarding
/// pass, a pickup code. The fields, then the code the server drew, on white,
/// and the wallet's own button under it.
Widget buildPass(BuildContext context, WireBlock block, RendelDispatcher dispatch) {
  final theme = RendelThemeScope.of(context);
  final strings = RendelStringsScope.of(context);
  final props = block.props;
  final title = _str(props['title']);
  final kind = switch (_str(props['kind'])) {
    'boarding' => strings.passBoarding,
    'ticket' => strings.passTicket,
    'pickup' => strings.passPickup,
    'coupon' => strings.passCoupon,
    'membership' => strings.passMembership,
    _ => null,
  };
  if (title == null || title.isEmpty) return buildFallback(context, block);
  final subtitle = _str(props['subtitle']);
  final fields = [
    for (final field in _maps(props['fields']))
      if ((_str(field['label']), _str(field['value'])) case (final label?, final value?)) (label, value),
  ];
  final until = _instant(props['valid_until']);
  final code = _map(props['code']);
  final drawn = RendelPassCode.tryParse(code);
  final shown = _str(code?['display_text']);
  final wallet = _map(props['wallet']);
  final apple = _str(wallet?['apple_pkpass_url']);
  final google = _str(wallet?['google_save_url']);
  final iOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: _thingPlate(theme),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (kind != null) ...[
          RendelOverline(kind, color: theme.colors.onSurfaceSoft),
          const SizedBox(height: 4),
        ],
        Semantics(header: true, child: Text(title, style: _wave4Title(theme))),
        if (subtitle != null && subtitle.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(subtitle, style: theme.text.body.copyWith(fontSize: 14, height: 1.4)),
        ],
        if (fields.isNotEmpty) ...[
          const SizedBox(height: 14),
          _PassFields(fields: fields),
        ],
        if (until != null) ...[
          const SizedBox(height: 12),
          Text(
            strings.validUntilDate(_when(context, until)),
            style: theme.text.body.copyWith(fontSize: 13.5, height: 1.4),
          ),
        ],
        if (drawn != null) ...[
          const SizedBox(height: 18),
          Center(child: drawn),
        ],
        if (shown != null && shown.isNotEmpty) ...[
          SizedBox(height: drawn == null ? 14 : 10),
          SelectableText(
            shown,
            textAlign: TextAlign.center,
            style: theme.text.label.copyWith(
              fontSize: 16,
              fontFamily: 'monospace',
              // iOS has no face by that name; these are its own.
              fontFamilyFallback: const ['Menlo', 'Courier'],
              letterSpacing: 1.2,
            ),
          ),
        ],
        if (iOS && apple != null && apple.startsWith('https://')) ...[
          const SizedBox(height: 16),
          Center(child: _AppleWalletButton(url: apple)),
        ] else if (!iOS && google != null && google.startsWith('https://')) ...[
          const SizedBox(height: 16),
          Center(child: _GoogleWalletButton(onTap: _external(dispatch, google))),
        ],
      ],
    ),
  );
}

/// A pass's fields in a grid of up to three columns: the label over its
/// value.
class _PassFields extends StatelessWidget {
  const _PassFields({required this.fields});

  final List<(String, String)> fields;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final columns = math.min(3, fields.length);
    return LayoutBuilder(builder: (context, box) {
      const gap = 12.0;
      final width = (box.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: 12,
        children: [
          for (final (label, value) in fields)
            SizedBox(
              // A long value (a card number) takes the row: in a third of it
              // "6018 2900 4471 0038" broke over two lines (Grove report).
              width: value.length > 12 ? box.maxWidth : width,
              child: MergeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: theme.text.body.copyWith(fontSize: 12, height: 1.3)),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: theme.text.labelTabular.copyWith(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    });
  }
}

/// A pass's code as the server drew it, painted module by module.
///
/// `matrix`: a 2D code (QR, PDF417, Aztec) as rows of bits, most significant
/// first, each module `module_aspect` times as tall as it is wide. `bars`: a
/// code128 as bar and space widths, bar first. Always black on white, in a
/// dark theme too, since a scanner reads contrast and not a theme; with the
/// quiet zone a scanner needs around it, 4 modules for a 2D code and 10 for
/// code128; and every module a whole number of device pixels, unsmoothed, so
/// no edge is a grey a scanner has to guess at.
class RendelPassCode extends StatelessWidget {
  const RendelPassCode._({this.rows = 0, this.cols = 0, this.bits, this.aspect = 1, this.bars});

  /// The code the wire's `code` carries, or null where it carries none this
  /// build can paint: no matrix and no bars, or bits too few for its size.
  static RendelPassCode? tryParse(Map? code) {
    if (code == null) return null;
    final matrix = _map(code['matrix']);
    if (matrix != null) {
      final rows = _dbl(matrix['rows'])?.toInt() ?? 0;
      final cols = _dbl(matrix['cols'])?.toInt() ?? 0;
      final Uint8List bits;
      try {
        bits = base64.decode(_str(matrix['bits']) ?? '');
      } on FormatException {
        return null;
      }
      if (rows < 1 || cols < 1 || bits.length * 8 < rows * cols) return null;
      return RendelPassCode._(
        rows: rows,
        cols: cols,
        bits: bits,
        aspect: (_dbl(matrix['module_aspect']) ?? 1).clamp(1, 4).toDouble(),
      );
    }
    final bars = [for (final width in _list(code['bars'])) _dbl(width)?.toInt() ?? 0];
    if (bars.isEmpty || bars.any((width) => width < 1)) return null;
    return RendelPassCode._(bars: bars);
  }

  final int rows;
  final int cols;
  final Uint8List? bits;
  final double aspect;
  final List<int>? bars;

  bool get _linear => bars != null;

  /// The quiet zone, in modules: on every side of a 2D code, and to either
  /// side of a bar code, whose top and bottom need only a margin.
  int get quiet => _linear ? 10 : 4;
  int get _margin => _linear ? 4 : quiet;

  /// The code's width in modules, the quiet zone included.
  int get span => (_linear ? bars!.fold<int>(0, (sum, width) => sum + width) : cols) + 2 * quiet;

  @override
  Widget build(BuildContext context) {
    final ratio = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(builder: (context, box) {
      // As wide as the brief asks where the screen allows, in whole device
      // pixels a module; narrower only where the screen does not.
      final floor = _linear ? 280.0 : 160.0;
      final room = box.maxWidth.isFinite ? box.maxWidth * ratio : double.infinity;
      var module = (floor * ratio / span).ceil();
      if (module * span > room) module = math.max(1, (room / span).floor());
      // A 2D code's rows; a bar code's bars, a quarter of its width tall or
      // 64 pt, whichever is more. Whole pixels both.
      final row = math.max(1, (module * aspect).round());
      final body = _linear ? math.max((64 * ratio).ceil(), module * span ~/ 4) : rows * row;
      final height = body + 2 * _margin * module;
      final drawn = RepaintBoundary(
        child: CustomPaint(
          size: Size(module * span / ratio, height / ratio),
          painter: _CodePainter(
            code: this,
            module: module,
            row: row,
            body: body,
            ratio: ratio,
          ),
        ),
      );
      // Wider than the screen even at a pixel a module (the longest code128
      // the wire allows is 2,420 modules): scaled down to fit rather than
      // run off the plate. Smoothed then, which no module count that fits
      // ever is.
      if (module * span > room) return FittedBox(fit: BoxFit.scaleDown, child: drawn);
      return drawn;
    });
  }
}

class _CodePainter extends CustomPainter {
  const _CodePainter({
    required this.code,
    required this.module,
    required this.row,
    required this.body,
    required this.ratio,
  });

  final RendelPassCode code;

  /// In device pixels: a module's width, a 2D code's row height, and the
  /// height of the code inside its margins.
  final int module;
  final int row;
  final int body;
  final double ratio;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFFFFFFF));
    final ink = Paint()
      ..color = const Color(0xFF000000)
      ..isAntiAlias = false;
    // In device pixels, so every edge lands on one.
    canvas.save();
    canvas.scale(1 / ratio);
    final left = code.quiet * module;
    final top = code._margin * module;
    final bars = code.bars;
    if (bars != null) {
      var x = left;
      for (final (i, width) in bars.indexed) {
        if (i.isEven) {
          canvas.drawRect(
            Rect.fromLTWH(x.toDouble(), top.toDouble(), (width * module).toDouble(), body.toDouble()),
            ink,
          );
        }
        x += width * module;
      }
    } else {
      final bits = code.bits!;
      bool on(int i) => bits[i >> 3] & (0x80 >> (i & 7)) != 0;
      for (var r = 0; r < code.rows; r++) {
        // A run of dark modules is one rectangle: a 120-column PDF417 is
        // a few hundred draws rather than thousands.
        var c = 0;
        while (c < code.cols) {
          if (!on(r * code.cols + c)) {
            c++;
            continue;
          }
          final start = c;
          while (c < code.cols && on(r * code.cols + c)) {
            c++;
          }
          canvas.drawRect(
            Rect.fromLTWH(
              (left + start * module).toDouble(),
              (top + r * row).toDouble(),
              ((c - start) * module).toDouble(),
              row.toDouble(),
            ),
            ink,
          );
        }
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CodePainter old) =>
      !identical(old.code, code) || old.module != module || old.row != row || old.body != body || old.ratio != ratio;
}

/// Apple's own "Add to Apple Wallet" button: `PKAddPassButton`, drawn by iOS
/// in the user's language. The plugin's native half downloads the pass at
/// [url] when it is tapped and offers it in `PKAddPassesViewController`
/// (`RendelPlugin.swift`); the copilot hears nothing of it.
class _AppleWalletButton extends StatelessWidget {
  const _AppleWalletButton({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) => SizedBox(
        width: math.min(box.maxWidth, 260),
        height: 52,
        child: UiKitView(
          viewType: 'rendel/add-pass',
          creationParams: {'url': url},
          creationParamsCodec: const StandardMessageCodec(),
          // The button takes its tap; a drag that starts on it is still the
          // page's to scroll.
          gestureRecognizers: {Factory<OneSequenceGestureRecognizer>(TapGestureRecognizer.new)},
        ),
      ),
    );
  }
}

/// "Save to Google Wallet", opened externally: the save link takes the user
/// to Google Wallet, which adds the pass. Drawn as Google's badge is, black
/// with its words in white; the words are Google's, so they are not
/// translated here.
class _GoogleWalletButton extends StatelessWidget {
  const _GoogleWalletButton({required this.onTap});

  final VoidCallback? onTap;

  static const String words = 'Save to Google Wallet';

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    return RendelPressable(
      semanticLabel: words,
      onTap: onTap,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: const Color(0xFF1F1F1F),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFF747775)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.account_balance_wallet_outlined, size: 20, color: Color(0xFFFFFFFF)),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                words,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.text.label.copyWith(color: const Color(0xFFFFFFFF), fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ————————————————————————— catalog wave 6 —————————————————————————
//
// The P2 extensions and `code` (`design/CATALOG-B6.md`): a product card's
// fact chips, variants drawn as swatches or pictures, pros and cons, gallery
// captions and video posters, a receipt line's note and change, progress
// rings, bars along, and a block of code.

/// A product card's short facts as the wire gives them: four at most.
List<String> _productChips(Map item) => [
      for (final chip in _list(item['chips']).take(4))
        if (_str(chip) case final text? when text.isNotEmpty) text,
    ];

/// Short facts under a card's title ("3+1", "120 m²"): hairline pills on one
/// line. What does not fit is clipped at the card's edge rather than wrapped
/// onto a second line, so the cards in a rail keep one height.
class _FactChips extends StatelessWidget {
  const _FactChips(this.chips);

  final List<String> chips;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final style = theme.text.captionSoft.copyWith(fontWeight: FontWeight.w600);
    return ClipRect(
      // The row is laid out at its own width, past the card if it must be,
      // and the clip is what keeps it to the card.
      child: OverflowBox(
        maxWidth: double.infinity,
        alignment: AlignmentDirectional.centerStart,
        fit: OverflowBoxFit.deferToChild,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (i, chip) in chips.indexed) ...[
              if (i > 0) SizedBox(width: theme.space.xs),
              Container(
                padding: EdgeInsets.symmetric(horizontal: theme.space.sm, vertical: theme.space.hair),
                decoration: BoxDecoration(
                  border: Border.all(color: theme.hairline),
                  borderRadius: BorderRadius.circular(theme.radius.control),
                ),
                child: Text(chip, maxLines: 1, softWrap: false, style: style),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// `#RRGGBB` as a colour, or null for anything else.
Color? _hexColor(Object? value) {
  final hex = _str(value);
  if (hex == null || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(hex)) return null;
  return Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));
}

/// A variant drawn as itself: a 32 pt circle of its colour, or a 64 pt
/// picture at a 12 pt corner, with its label under it at 12.
///
/// The picked one is ringed in ink 2 pt out from it rather than filled, as a
/// chosen chip is, because the colour or the picture is the option and
/// cannot be painted over. A sold-out one stays on screen, dimmed and struck
/// through corner to corner, as a sold-out chip's label is struck.
class _VariantTile extends StatelessWidget {
  const _VariantTile({
    required this.label,
    required this.selected,
    required this.unavailable,
    required this.onTap,
    this.swatch,
    this.image,
  });

  final String label;
  final Color? swatch;
  final String? image;
  final bool selected;
  final bool unavailable;
  final VoidCallback? onTap;

  static const double _gap = 2;
  static const double _ring = 2;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final still = MediaQuery.disableAnimationsOf(context);
    final round = swatch != null;
    final side = round ? 32.0 : 64.0;
    final face = round
        ? Container(
            width: side,
            height: side,
            decoration: BoxDecoration(
              color: swatch,
              shape: BoxShape.circle,
              // A white swatch on a white plate still has an edge.
              border: Border.all(color: theme.hairline),
            ),
          )
        : _Thumbnail(url: image, width: side, height: side, radius: 12);
    final mark = AnimatedContainer(
      duration: still ? Duration.zero : theme.motion.swap,
      curve: theme.motion.curve,
      padding: const EdgeInsets.all(_gap),
      decoration: BoxDecoration(
        shape: round ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: round ? null : BorderRadius.circular(12 + _gap + _ring),
        // Drawn clear when not picked, so picking one moves nothing.
        border: Border.all(
          width: _ring,
          color: selected ? theme.colors.onSurface : const Color(0x00000000),
        ),
      ),
      child: unavailable
          ? CustomPaint(
              foregroundPainter: _Struck(
                plate: theme.colors.surfaceRaised,
                ink: theme.colors.onSurface.withValues(alpha: 0.55),
                round: round,
              ),
              child: Opacity(opacity: 0.55, child: face),
            )
          : face,
    );
    final base = selected ? theme.text.labelEmphasis : theme.text.captionSoft;
    final tile = SizedBox(
      // A swatch's label is wider than its circle; a picture's is its width.
      width: round ? 56 : side + 2 * (_gap + _ring),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          mark,
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: base.copyWith(
              fontSize: 12,
              height: 1.25,
              color: unavailable ? theme.colors.onSurfaceFaint : null,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) {
      // Announced as a chip that cannot be picked is: unavailable first.
      return Semantics(
        label: unavailable ? 'Unavailable, $label' : label,
        enabled: false,
        selected: selected,
        excludeSemantics: true,
        child: tile,
      );
    }
    return RendelPressable(semanticLabel: label, selected: selected, onTap: onTap, child: tile);
  }
}

/// The line through a sold-out swatch or picture: a stroke of the plate under
/// a thinner one of ink, so it shows on a black swatch and a white one alike.
class _Struck extends CustomPainter {
  const _Struck({required this.plate, required this.ink, required this.round});

  final Color plate;
  final Color ink;
  final bool round;

  @override
  void paint(Canvas canvas, Size size) {
    // On a circle, from where the diagonal meets its edge; on a picture, from
    // inside its rounded corners.
    final inset = round ? size.width * (1 - math.sqrt1_2) / 2 : 6.0;
    final from = Offset(size.width - inset, inset);
    final to = Offset(inset, size.height - inset);
    canvas
      ..drawLine(
        from,
        to,
        Paint()
          ..color = plate
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round,
      )
      ..drawLine(
        from,
        to,
        Paint()
          ..color = ink
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round,
      );
  }

  @override
  bool shouldRepaint(_Struck old) => old.plate != plate || old.ink != ink || old.round != round;
}

/// A pro's + in a small ink circle or a con's − in a faint one, in a key
/// point's icon column. Read out first, as "Pro:" or "Con:", so the reader
/// hears which side a point is on before the point.
class _ToneMark extends StatelessWidget {
  const _ToneMark({required this.positive});

  final bool positive;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final strings = RendelStringsScope.of(context);
    return Semantics(
      label: '${positive ? strings.pro : strings.con}:',
      child: Container(
        width: 20,
        height: 20,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: positive ? theme.colors.onSurface : theme.rail,
        ),
        child: Icon(
          positive ? Icons.add_rounded : Icons.remove_rounded,
          size: 14,
          color: positive ? theme.colors.surfaceRaised : theme.colors.onSurface,
        ),
      ),
    );
  }
}

/// A gallery picture, with its caption under it in the soft ink and, when it
/// is a video's poster, a play glyph over it.
///
/// The tap hands the video to the system (**Pick**): the platform's player,
/// or a new tab on the web. There is no player inside the SDK, which would be
/// a video dependency in every host app.
class _GalleryTile extends StatelessWidget {
  const _GalleryTile({
    required this.url,
    required this.alt,
    required this.width,
    required this.height,
    required this.dispatch,
    this.caption,
    this.video,
  });

  final String? url;
  final String alt;
  final double width;
  final double height;
  final RendelDispatcher dispatch;
  final String? caption;
  final String? video;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    Widget picture = _Thumbnail(url: url, width: width, height: height, alt: alt);
    if (video case final video?) {
      picture = RendelPressable(
        semanticLabel: '${RendelStringsScope.of(context).playVideo}, $alt',
        pressedScale: 0.98,
        onTap: _external(dispatch, video),
        child: Stack(
          alignment: Alignment.center,
          children: [
            picture,
            // A scrim of its own, because the picture under it can be any
            // colour at all.
            Container(
              width: _minTarget,
              height: _minTarget,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0x73000000)),
              child: const Icon(Icons.play_arrow_rounded, size: 28, color: Color(0xFFFFFFFF)),
            ),
          ],
        ),
      );
    }
    final words = caption;
    if (words == null || words.isEmpty) return picture;
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          picture,
          const SizedBox(height: 6),
          Text(
            words,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.text.body.copyWith(fontSize: 13, height: 1.35),
          ),
        ],
      ),
    );
  }
}

/// A receipt line with more to say than its amount: a note under the label
/// ("2 × 60 ml", "1–30 April"), and the change against the last one in a
/// small pill just before the amount, so the amounts still end in one column.
class _ReceiptLine extends StatelessWidget {
  const _ReceiptLine({required this.label, required this.amount, this.note, this.delta});

  final String label;
  final String amount;
  final String? note;
  final String? delta;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final note = this.note;
    final delta = this.delta;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: theme.space.hair),
      // One fact, as a plain line is.
      child: MergeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.text.caption),
                  if (note != null && note.isNotEmpty) ...[
                    SizedBox(height: theme.space.hair),
                    Text(note, style: theme.text.captionSoft),
                  ],
                ],
              ),
            ),
            SizedBox(width: theme.space.md),
            _TrailingSlot(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (delta != null && delta.isNotEmpty) ...[
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: theme.highlight,
                          border: Border.all(color: theme.hairline),
                          borderRadius: BorderRadius.circular(theme.radius.control),
                        ),
                        child: Text(
                          delta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.text.captionSoftTabular.copyWith(fontSize: 11.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(amount, textAlign: TextAlign.end, style: theme.text.captionSoftTabular),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One to three goals as rings side by side, 88 pt each or as many as fit
/// the plate: the track the v6 rail, the arc the accent, the value in the
/// middle and the label under it.
class _ProgressRings extends StatelessWidget {
  const _ProgressRings({required this.items});

  final List<Map> items;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        final gap = theme.space.md;
        final side = math.min(88.0, (box.maxWidth - gap * (items.length - 1)) / items.length);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (i, item) in items.indexed) ...[
              if (i > 0) SizedBox(width: gap),
              Expanded(child: _ProgressRing(item: item, side: side)),
            ],
          ],
        );
      },
    );
  }
}

class _ProgressRing extends StatelessWidget {
  const _ProgressRing({required this.item, required this.side});

  final Map item;
  final double side;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final value = _dbl(item['value']) ?? 0;
    final max = _dbl(item['max']) ?? 0;
    final fraction = max > 0 ? (value / max).clamp(0.0, 1.0) : 0.0;
    final percent = '${(fraction * 100).round()}%';
    final label = _str(item['label']) ?? '';
    final caption = _str(item['caption']);
    final valueLabel = _str(item['value_label']);
    final stroke = theme.size.trackHeight;
    return Semantics(
      label: [
        label,
        valueLabel ?? '${_num(value, RendelStringsScope.of(context).numberLocale)} / ${_num(max, RendelStringsScope.of(context).numberLocale)}',
        if (caption != null) caption,
      ].where((part) => part.isNotEmpty).join(', '),
      value: percent,
      excludeSemantics: true,
      child: Column(
        children: [
          SizedBox.square(
            dimension: side,
            child: CustomPaint(
              painter: _RingPainter(
                fraction: fraction,
                track: theme.rail,
                // The accent as the web's ring draws it, at the strength
                // that holds 3:1 on every ground (WCAG 1.4.11).
                arc: theme.accentEdge,
                stroke: stroke,
              ),
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(stroke + 6),
                  // Shrunk to fit, never cut: "3,710..." in place of the
                  // points a member has is a number they cannot read (Grove
                  // report P2-7).
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      // Without a value label of its own, a ring's middle says
                      // its share: "12.5 / 20" does not fit inside one of three
                      // rings on a phone. The figures are still read out.
                      valueLabel ?? percent,
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      // The brief's 650, at the nearest weight Flutter names.
                      style: theme.text.labelTabular.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: theme.space.sm),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.text.label.copyWith(fontSize: 13),
          ),
          if (caption != null && caption.isNotEmpty) ...[
            SizedBox(height: theme.space.hair),
            Text(
              caption,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.text.caption,
            ),
          ],
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.fraction,
    required this.track,
    required this.arc,
    required this.stroke,
  });

  final double fraction;
  final Color track;
  final Color arc;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = track);
    if (fraction <= 0) return;
    // From twelve o'clock, clockwise, with round ends.
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * fraction,
      false,
      paint
        ..color = arc
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction || old.track != track || old.arc != arc || old.stroke != stroke;
}

/// Bars along rather than up (`hbar`), for labels too long to stand under a
/// column: each label at the start of its own line, its bars beside it, one
/// per series in the series' ink, and with one series the value at the bar's
/// end. A value of nothing or less is a dot, as it is in `_Bars`.
class _HBars extends StatelessWidget {
  const _HBars({
    required this.labels,
    required this.series,
    required this.unit,
    required this.description,
  });

  final List<String> labels;
  final List<_Series> series;
  final String? unit;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final one = series.length == 1;
    final rows = series.map((s) => s.data.length).reduce(math.max);
    var peak = 0.0;
    for (final s in series) {
      for (final v in s.data) {
        peak = math.max(peak, v);
      }
    }
    final top = peak > 0 ? peak : 1.0;
    final said = _chartFormat([for (final s in series) ...s.data], unit, RendelStringsScope.of(context).numberLocale);
    final thickness = one ? 14.0 : 8.0;
    // One series has no legend to match, so it takes the readout's fill; more
    // take the inks their legend names.
    Color ink(int s) => one ? theme.readoutFill : _seriesColor(theme, s);

    Widget bar(int s, int i) {
      final data = series[s].data;
      if (i >= data.length) return SizedBox(height: thickness);
      final value = data[i];
      final mark = value <= 0
          ? Container(
              width: 6,
              height: 6,
              margin: EdgeInsets.symmetric(vertical: (thickness - 6) / 2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colors.onSurface.withValues(alpha: 0.18),
              ),
            )
          : FractionallySizedBox(
              alignment: AlignmentDirectional.centerStart,
              widthFactor: value / top,
              child: Container(
                height: thickness,
                decoration: BoxDecoration(
                  color: ink(s),
                  borderRadius: BorderRadius.circular(theme.radius.control),
                ),
              ),
            );
      final placed = Align(alignment: AlignmentDirectional.centerStart, child: mark);
      if (!one) return placed;
      return Row(
        children: [
          // Loose, so the value sits at the bar's end rather than the line's.
          Flexible(child: value <= 0 ? placed : mark),
          SizedBox(width: theme.space.sm),
          _TrailingSlot(
            child: Text(
              _withUnit(said(value), unit),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.text.captionTabular,
            ),
          ),
        ],
      );
    }

    return Semantics(
      label: description,
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, box) => Column(
          children: [
            for (var i = 0; i < rows; i++)
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : theme.space.md),
                child: Row(
                  children: [
                    SizedBox(
                      width: box.maxWidth * 0.38,
                      child: Text(
                        i < labels.length ? labels[i] : '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.text.caption,
                      ),
                    ),
                    SizedBox(width: theme.space.md),
                    Expanded(
                      child: Column(
                        children: [
                          for (var s = 0; s < series.length; s++) ...[
                            if (s > 0) const SizedBox(height: 3),
                            bar(s, i),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Code, a command or log lines, for developer tools.
///
/// A dark plate whatever the theme, as the landing page's code plate is: the
/// language and a Copy button on its head, the code monospaced under it and
/// scrolling sideways inside the plate only, so a long line never widens the
/// page. The caption sits under the plate. Copy is the `copy` action's own
/// behaviour, the check and "Copied" included.
Widget buildCode(BuildContext context, WireBlock block, RendelDispatcher dispatch) {
  final theme = RendelThemeScope.of(context);
  final strings = RendelStringsScope.of(context);
  final code = _str(block.props['code']);
  if (code == null || code.isEmpty) return buildFallback(context, block);
  final language = _str(block.props['language']);
  final caption = _str(block.props['caption']);
  const ink = Color(0xFFE8E6E1);

  final head = Container(
    padding: const EdgeInsetsDirectional.only(start: 14, end: 4),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: Color(0x14FFFFFF))),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            language ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.text.caption.copyWith(fontSize: 12, color: ink.withValues(alpha: 0.6)),
          ),
        ),
        _Acting(
          action: {'kind': 'copy', 'text': code},
          dispatch: dispatch,
          builder: (context, onTap, copied) => RendelPressable(
            semanticLabel: copied ? strings.copied : _joinParts([strings.copyCode, language]),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Center(
                widthFactor: 1,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (copied) ...[
                      const Icon(Icons.check_rounded, size: 14, color: ink),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      copied ? strings.copied : strings.copyCode,
                      style: theme.text.caption.copyWith(fontSize: 12, fontWeight: FontWeight.w600, color: ink),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: BorderRadius.circular(16),
        ),
        // A hairline of white, so the plate still has an edge on the deep
        // theme's ground, which is nearly the plate's own colour. Drawn over
        // the plate, so it moves nothing inside it.
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0x14FFFFFF)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            head,
            // Code reads left to right on any page, and starts at the left.
            Directionality(
              textDirection: TextDirection.ltr,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Text(
                  code,
                  softWrap: false,
                  style: theme.text.body.copyWith(
                    fontFamily: 'monospace',
                    // iOS has no face by that name; these are its own.
                    fontFamilyFallback: const ['Menlo', 'Courier'],
                    fontSize: 12.5,
                    height: 1.6,
                    color: ink,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      if (caption != null && caption.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(caption, style: theme.text.body.copyWith(fontSize: 13, height: 1.35)),
      ],
    ],
  );
}
