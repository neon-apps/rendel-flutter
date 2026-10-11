import 'package:flutter/material.dart';

import '../../core/config.dart' show RendelAttachment, RendelAttachSource;
import '../../engine/conversation_controller.dart' show RendelSubmitOutcome;
import '../../protocol/protocol.dart';
import '../theme.dart';
import 'blocks.dart';

typedef ComponentBuilder = Widget Function(
  BuildContext context,
  WireBlock block,
  RendelDispatcher dispatch,
);

/// How rendered blocks talk back: chip taps, confirmations, cancellations and
/// form submissions.
///
/// Both callbacks are supplied by the SDK. A custom builder registered through
/// [ComponentRegistry.register] receives this object; it never constructs one.
class RendelDispatcher {
  const RendelDispatcher({
    required this.onAction,
    required this.onSubmitForm,
    required this.canHandle,
    this.onSelect,
    this.onChoose,
    this.onRate,
    this.routeTitle,
    this.onPickFile,
    this.fileSources = RendelAttachSource.values,
    this.onUpload,
    this.onEditCard,
  });

  /// Sends values the user changed on [card], a `confirm_card`, to be
  /// checked and the card redrawn. Resolves null when it was; otherwise what
  /// was wrong, by parameter, `''` for a change that did not get there. Null
  /// where nothing can be changed: the card's values are drawn as text.
  final Future<Map<String, String>?> Function(WireBlock card, Map<String, dynamic> edits)? onEditCard;

  /// Picks a file for a form's `upload` field from [source]: the composer's
  /// own picker, the host's when it brought one. Resolves null when the user
  /// backs out. Null, or with no [onUpload], where nothing can be attached:
  /// the field is drawn, and its add tile does nothing.
  final Future<RendelAttachment?> Function(RendelAttachSource source)? onPickFile;

  /// Where [onPickFile] can pick from, as the composer's "+" offers them. One
  /// source is a host's own picker, which stands in for all three.
  final List<RendelAttachSource> fileSources;

  /// Uploads [file] (`POST /v1/uploads`, the composer's path) and resolves
  /// with its upload id, which is what the field submits. Throws what the
  /// upload threw, a `RendelUploadFailure` carrying the server's sentence.
  final Future<String> Function(RendelAttachment file)? onUpload;

  /// The app's own words for one of its screens, as it registered the route:
  /// what a `screens` card says under the model's title. Null for a route
  /// this build does not know, and where nothing can be looked up.
  final String? Function(String route)? routeTitle;

  /// Picks the option [id] on [block], a `variant_picker` or `datetime_slots`,
  /// and sends it as a `selection`, with [shown] as the question written over
  /// the screen.
  ///
  /// Resolves false when nothing was sent. The option is marked chosen by
  /// whoever sends it, at once, so the renderer only draws what it finds.
  /// Null where nothing can be picked: the options are drawn as content.
  final Future<bool> Function(WireBlock block, String id, String shown)? onSelect;

  /// Answers [block], a `choice`, with the option [ids] picked; or, with no
  /// ids, with [otherText] written in its `other` row, or with nothing for
  /// its `skip`. Sent as a `selection`, with [shown] as the question written
  /// over the screen, after a single pick has stayed lit for [lit].
  ///
  /// Resolves false when nothing was sent. Whoever sends it lights the pick
  /// and marks the block answered (`RendelLocalKeys`), so the block folds
  /// only into an answer that went. Null where nothing can be answered: the
  /// options are drawn as content.
  final Future<bool> Function(
    WireBlock block,
    List<String> ids,
    String shown, {
    String? otherText,
    Duration lit,
  })? onChoose;

  /// Answers [block], a `rating`, with [score], and with [comment] once the
  /// user wrote one: posted to `/v1/ratings` at once, with no turn.
  ///
  /// Resolves whether the server took it. The block marks the score and folds
  /// only on true, and says so under itself on false, so a tap that did not
  /// land can be made again. Null where nothing can be rated: the scale is
  /// drawn as content.
  final Future<bool> Function(WireBlock block, int score, {String? comment})? onRate;

  /// Fires a parsed [UIAction] from an interactive prop.
  ///
  /// Resolves false when the tap was dropped rather than dispatched — the
  /// previous turn was still open, or the host wired no URL handler. A
  /// renderer that marks its own state on tap has to wait for true.
  final Future<bool> Function(UIAction action) onAction;

  /// Whether this build can actually carry out [action].
  ///
  /// A renderer asks before it draws a tap surface, so a control whose action
  /// the SDK cannot execute is drawn as content: no button role, no press
  /// response, nothing that promises something will happen.
  final bool Function(UIAction action) canHandle;

  /// Sends a completed form as a `form_submission` continuation request.
  /// Values are `String`, `num`, `bool` or `List<String>` — a multi_select's
  /// picks, an upload's ids — which is what the wire schema accepts.
  ///
  /// The outcome tells the form three different things apart, because they
  /// call for three different sentences: nothing was sent because the turn was
  /// still open; the request went out and the turn then failed; the request
  /// went out and the turn finished.
  final Future<RendelSubmitOutcome> Function(String formId, Map<String, Object> values)
      onSubmitForm;
}

/// Block type → widget builder. All built-ins register through the same path
/// a host-registered custom component will use later; unknown types render
/// their fallback text (protocol rule: never break on new types).
class ComponentRegistry {
  ComponentRegistry._();

  static final Map<String, ComponentBuilder> _builders = {
    'text': buildTextBlock,
    'quick_replies': buildQuickReplies,
    'info_card': buildInfoCard,
    'item_list': buildItemList,
    'product_cards': buildProductCards,
    'confirm_card': buildConfirmCard,
    'status_banner': buildStatusBanner,
    'stat_group': buildStatGroup,
    'order_tracker': buildOrderTracker,
    'receipt': buildReceipt,
    'form': buildForm,
    'datetime_slots': buildDatetimeSlots,
    'booking_card': buildBookingCard,
    'chart': buildChart,
    'table': buildTable,
    'media_gallery': buildMediaGallery,
    'progress': buildProgress,
    'key_value': buildKeyValue,
    'variant_picker': buildVariantPicker,
    'article_card': buildArticleCard,
    'section': buildSection,
    'key_points': buildKeyPoints,
    'actions': buildActions,
    'tags': buildTags,
    'screens': buildScreens,
    'choice': buildChoice,
    'comparison': buildComparison,
    'contact': buildContact,
    'rating': buildRating,
    'disclosure': buildDisclosure,
    'checklist': buildChecklist,
    'timeline': buildTimeline,
    'place_card': buildPlaceCard,
    'map': buildMap,
    'pass': buildPass,
    'code': buildCode,
  };

  static void register(String type, ComponentBuilder builder) {
    _builders[type] = builder;
  }

  /// Every type this build has a renderer for, sorted.
  ///
  /// Public because the catalog is declared in three places — the protocol
  /// package, `supportedComponents`, and this map — and a set that cannot be
  /// read is a set that cannot be checked. `test/catalog_test.dart` holds all
  /// three against each other.
  static List<String> get registeredTypes => _builders.keys.toList()..sort();

  static Widget build(BuildContext context, WireBlock block, RendelDispatcher dispatch) {
    // Between block.start and block.ready the props are empty. Every type but
    // `text` is block-atomic, so it draws its own typed skeleton rather than
    // rendering an empty plate that re-flows a frame later.
    if (!block.ready && block.type != 'text') {
      return buildSkeleton(context, block.type);
    }
    final builder = _builders[block.type];
    if (builder == null) return buildFallback(context, block);
    // A kind of card the theme sets apart is drawn in its own theme: the same
    // one with that card's plate, well, corner and build.
    final theme = RendelThemeScope.of(context);
    final own = theme.forCard(block.type);
    if (identical(own, theme)) return builder(context, block, dispatch);
    return RendelThemeScope(
      theme: own,
      child: Builder(builder: (context) => builder(context, block, dispatch)),
    );
  }
}
