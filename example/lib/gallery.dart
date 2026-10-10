import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:rendel/rendel.dart';

/// The catalog gallery: every RDUI/1 block, drawn by the real renderer, with
/// fixtures a sneaker shop would actually produce.
///
/// It exists because coaxing the model into emitting a donut chart is a poor
/// way to review a donut chart. Everything here goes through
/// `ComponentRegistry.build`, the renderer a page uses.
///
/// The token switch in the app bar is the point of the screen as much as the
/// blocks are: the SDK has no dark mode of its own, only the role map a host
/// hands it, so both maps have to be looked at.
class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  bool _dark = false;
  bool _loading = false;

  /// How many stand-in files the gallery has handed out, to name them apart.
  int _picks = 0;

  /// Built once. Blocks carry their own working state (a chosen slot, a
  /// half-filled form), so rebuilding the fixtures on every frame would wipe
  /// exactly the thing the gallery exists to let you try.
  late final List<(String, WireBlock)> _entries = galleryFixtures();

  // Held, not rebuilt. A RendelTheme resolves fourteen text styles and runs
  // two contrast searches on construction; building one per frame is exactly
  // the cost the "built once per theme" guarantee exists to avoid, in the
  // file hosts copy from.
  late final RendelTheme _lightTheme = RendelTheme.paper();
  // The published deep map, not an ad-hoc one. The SDK now ships both
  // grounds, so the gallery demonstrates the theme a host actually gets
  // rather than a token map invented for this screen.
  late final RendelTheme _darkTheme = RendelTheme.deep();

  RendelTheme get _theme => _dark ? _darkTheme : _lightTheme;

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
  }

  @override
  void initState() {
    super.initState();
    // Both maps are reviewed here, so both are audited here. `init` only ever
    // sees the one the host passed it.
    auditContrast(_lightTheme);
    auditContrast(_darkTheme);
  }

  @override
  Widget build(BuildContext context) {
    final theme = _theme;
    final dispatch = RendelDispatcher(
      onAction: (action) async {
        _say(switch (action) {
          ReplyAction(:final text) => 'reply: $text',
          AppActionRef(:final name) => 'app_action: $name',
          ConfirmAction() => 'confirm',
          CancelAction() => 'cancel',
          OpenUrlAction(:final url, :final external) => 'open_url${external ? ' (to the system)' : ''}: $url',
          NavigateAction(:final route, :final params) => 'navigate: $route $params',
          CallAction(:final phone) => 'call: $phone',
          EmailAction(:final address) => 'email: $address',
          CopyAction(:final text) => 'copy: $text',
          AddToCalendarAction(:final title, :final startsAt) => 'add_to_calendar: $title $startsAt',
        });
        // The gallery has no turn to be busy with, so every tap dispatches.
        return true;
      },
      // The gallery can honour everything, so every control draws as live.
      canHandle: (_) => true,
      // The words the app would have registered for its screens.
      routeTitle: (route) => const {
        'order_detail': 'Orders › Order',
        'delivery': 'Orders › Delivery',
      }[route],
      onSelect: (block, id, shown) async {
        // Marked here as the controller marks it, so a tap shows what it
        // picked.
        setState(() => block.props[RendelLocalKeys.chosen] = id);
        _say('selection: ${block.id} [$id] "$shown"');
        return true;
      },
      onChoose: (block, ids, shown, {otherText, lit = Duration.zero}) async {
        // Lit, then answered, as the controller does it, so a choice folds
        // into what was picked.
        setState(() => block.props[RendelLocalKeys.chosen] = ids);
        await Future<void>.delayed(lit);
        if (!mounted) return false;
        setState(() => block.props[RendelLocalKeys.answered] = {
              'ids': ids,
              if (otherText != null) 'other_text': otherText,
              'shown': shown,
            });
        _say('selection: ${block.id} $ids${otherText == null ? '' : ' "$otherText"'} "$shown"');
        return true;
      },
      onRate: (block, score, {comment}) async {
        // Taken at once, as the server takes it, so a rating folds into its
        // thanks; there is no server here to refuse one.
        _say('rating: ${block.id} $score${comment == null ? '' : ' "$comment"'}');
        return true;
      },
      onSubmitForm: (formId, values) async {
        await Future<void>.delayed(const Duration(milliseconds: 600));
        if (!mounted) return RendelSubmitOutcome.busy;
        _say('form_submission: $formId $values');
        return RendelSubmitOutcome.sent;
      },
      // There is no server here to upload to, so a form's upload field gets
      // a stand-in file and an id after a pause: enough to see the ring, the
      // thumbnail and the remove button, which is what this screen is for.
      onPickFile: (source) async => RendelAttachment(
        bytes: Uint8List.fromList(utf8.encode('A stand-in for a ${source.name} pick.')),
        name: '${source.name}-${++_picks}.txt',
        mediaType: 'text/plain',
      ),
      onUpload: (file) async {
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        return '00000000-0000-4000-8000-${_picks.toString().padLeft(12, '0')}';
      },
    );

    for (final entry in _entries) {
      entry.$2.ready = !_loading;
    }

    return RendelThemeScope(
      theme: theme,
      child: Scaffold(
        backgroundColor: theme.colors.surface,
        appBar: AppBar(
          backgroundColor: theme.colors.surface,
          foregroundColor: theme.colors.onSurface,
          surfaceTintColor: Colors.transparent,
          title: Text(
            'RDUI/1 · ${_entries.length} fixtures',
            style: theme.text.heading,
          ),
          actions: [
            TextButton(
              onPressed: () => setState(() => _loading = !_loading),
              child: Text(
                _loading ? 'Loaded' : 'Skeletons',
                style: theme.text.labelSoft,
              ),
            ),
            IconButton(
              tooltip: _dark ? 'Light tokens' : 'Dark tokens',
              onPressed: () => setState(() => _dark = !_dark),
              icon: Icon(
                _dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                color: theme.colors.onSurfaceFaint,
              ),
            ),
          ],
        ),
        body: ListView.builder(
          padding: EdgeInsets.fromLTRB(
            theme.space.plate,
            theme.space.md,
            theme.space.plate,
            theme.space.xl * 2,
          ),
          itemCount: _entries.length,
          itemBuilder: (context, index) {
            final entry = _entries[index];
            return Padding(
              padding: EdgeInsets.only(bottom: theme.space.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Not uppercased. `RendelOverline` stopped shouting, and the
                  // screen that exists to demonstrate the catalog should not
                  // be the one place still doing it: a fixture label reading
                  // TEXT · STREAMING over blocks set in sentence case makes
                  // the gallery look like a different product from the one it
                  // renders.
                  Text(entry.$1, style: theme.text.overline),
                  SizedBox(height: theme.space.md),
                  ComponentRegistry.build(context, entry.$2, dispatch),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

WireBlock _block(
  String id,
  String type,
  String fallback,
  Map<String, dynamic> props,
) =>
    WireBlock(id: id, type: type, fallbackText: fallback, props: props)..ready = true;

String _shot(String seed, int w, int h) => 'https://picsum.photos/seed/$seed/$w/$h';

/// Believable Neon Kicks data: real prices, real order numbers, real copy.
///
/// Public so `test/gallery_test.dart` can hold it against the registry: a
/// block type added to the catalog with no fixture here is a block nobody can
/// look at, which is the one thing this screen exists to prevent.
List<(String, WireBlock)> galleryFixtures() => [
      (
        'text',
        _block('g-text', 'text', 'Order 1042 is out for delivery.', {
          'markdown':
              'Order 1042 left the Rotterdam depot this morning and is out for '
                  'delivery. The courier gives a 14:00 to 18:00 window.',
        }),
      ),
      (
        'quick_replies',
        _block('g-chips', 'quick_replies', 'Track order, Sizes, Returns', {
          'items': [
            {
              'label': 'Track order 1042',
              'action': {'kind': 'reply', 'text': 'Where is order 1042?'},
            },
            {
              'label': 'Size guide',
              'action': {'kind': 'reply', 'text': 'Show the size guide'},
            },
            {
              'label': 'Start a return',
              'action': {'kind': 'reply', 'text': 'I want to return something'},
            },
          ],
        }),
      ),
      (
        'info_card',
        _block('g-info', 'info_card', 'Free returns within 30 days.', {
          'icon': 'truck',
          'title': 'Free returns within 30 days',
          'body':
              'Unworn shoes in the original box can go back at any pickup point. '
                  'Refunds land 3 to 5 days after the parcel is scanned.',
          'cta': {
            'label': 'Start a return',
            'action': {'kind': 'reply', 'text': 'Start a return for order 1042'},
          },
        }),
      ),
      (
        'item_list',
        _block('g-list', 'item_list', 'Three recent orders.', {
          'items': [
            {
              'image_url': _shot('aero-glide-2', 120, 120),
              'title': 'Aero Glide 2, size 43',
              'subtitle': 'Order 1042 · out for delivery',
              'trailing': '\$129',
              'action': {'kind': 'reply', 'text': 'Track order 1042'},
            },
            {
              'image_url': _shot('court-low', 120, 120),
              'title': 'Court Low, size 42',
              'subtitle': 'Order 1039 · delivered 12 Aug',
              'trailing': '\$95',
              'action': {'kind': 'reply', 'text': 'Return order 1039'},
            },
            {
              'image_url': _shot('trail-circuit', 120, 120),
              'title': 'Trail Circuit, size 44',
              'subtitle': 'Order 1017 · delivered 2 Jul',
              'trailing': '\$149',
            },
          ],
        }),
      ),
      (
        'product_cards',
        _block('g-products', 'product_cards', 'Four running shoes under \$150.', {
          'items': [
            {
              'title': 'Aero Glide 2',
              'subtitle': 'Road, neutral',
              'price': '\$129',
              'badge': 'Best seller',
              'image_url': _shot('aero-glide-2', 400, 300),
              'action': {'kind': 'reply', 'text': 'Add Aero Glide 2 in size 43'},
            },
            {
              'title': 'Court Low',
              'subtitle': 'Everyday, leather',
              'price': '\$95',
              'image_url': _shot('court-low', 400, 300),
              'action': {'kind': 'reply', 'text': 'Add Court Low in size 42'},
            },
            {
              'title': 'Trail Circuit',
              'subtitle': 'Trail, waterproof',
              'price': '\$149',
              'image_url': _shot('trail-circuit', 400, 300),
            },
            {
              'title': 'Metro Knit',
              'subtitle': 'Commute, knit upper',
              'price': '\$119',
              'image_url': _shot('metro-knit', 400, 300),
            },
          ],
        }),
      ),
      (
        'confirm_card · destructive',
        _block('g-confirm', 'confirm_card', 'Confirm cancelling order 1042.', {
          'invocation_id': 'inv_gallery_1',
          'action_name': 'cancel_order',
          'summary': 'Cancel order 1042 and refund \$129 to the original card?',
          'params': {'order_id': '1042'},
          'params_display': [
            {'label': 'Order', 'value': '1042'},
            {'label': 'Items', 'value': 'Aero Glide 2, size 43'},
            {'label': 'Refund', 'value': '\$129.00'},
          ],
          'risk': 'destructive',
          'confirm': {'kind': 'confirm', 'invocation_id': 'inv_gallery_1'},
          'cancel': {'kind': 'cancel', 'invocation_id': 'inv_gallery_1'},
        }),
      ),
      (
        'confirm_card · write',
        _block('g-confirm-w', 'confirm_card', 'Confirm applying promo KICKS10.', {
          'invocation_id': 'inv_gallery_2',
          'action_name': 'apply_promo_code',
          'summary': 'Apply promo code KICKS10 to your cart?',
          'params': {'code': 'KICKS10'},
          'params_display': [
            {'label': 'Code', 'value': 'KICKS10'},
            {'label': 'Discount', 'value': '10%'},
          ],
          'risk': 'write',
          'confirm': {'kind': 'confirm', 'invocation_id': 'inv_gallery_2'},
          'cancel': {'kind': 'cancel', 'invocation_id': 'inv_gallery_2'},
        }),
      ),
      (
        'status_banner · success',
        _block('g-banner-ok', 'status_banner', 'Promo applied.', {
          'tone': 'success',
          'title': 'KICKS10 applied',
          'body': '10% came off your cart. The code expires on 31 August.',
        }),
      ),
      (
        'status_banner · warning',
        _block('g-banner-warn', 'status_banner', 'Size 44 is low on stock.', {
          'tone': 'warning',
          'title': 'Only two pairs left in size 44',
          'body': 'Trail Circuit restocks in about three weeks.',
        }),
      ),
      (
        'stat_group',
        _block('g-stats', 'stat_group', 'Spend 1284 dollars, 9 orders.', {
          'items': [
            {'label': 'Spent', 'value': '\$1,284', 'delta': '18%', 'trend': 'up'},
            {'label': 'Orders', 'value': '9', 'delta': '2', 'trend': 'up'},
            {'label': 'Saved', 'value': '\$96', 'delta': 'no change', 'trend': 'flat'},
          ],
        }),
      ),
      (
        'progress',
        _block('g-progress', 'progress', 'Two of five pairs toward a free pair.', {
          'title': 'Kicks Club',
          'items': [
            {
              'label': 'Pairs toward a free pair',
              'value': 2,
              'max': 5,
              'value_label': '2 of 5',
              'caption': 'Resets every calendar year.',
            },
            {
              'label': 'Store credit used',
              'value': 18.5,
              'max': 40,
              'value_label': '\$18.50 of \$40',
            },
          ],
        }),
      ),
      (
        'order_tracker',
        _block('g-tracker', 'order_tracker', 'Order 1042 is out for delivery.', {
          'title': 'Order 1042',
          'steps': [
            {'label': 'Ordered', 'status': 'done', 'timestamp': '22 Aug, 09:14'},
            {'label': 'Packed in Rotterdam', 'status': 'done', 'timestamp': '23 Aug, 17:02'},
            {'label': 'Out for delivery', 'status': 'current', 'timestamp': '26 Aug, 07:40'},
            {'label': 'Delivered', 'status': 'pending'},
          ],
        }),
      ),
      (
        'receipt',
        _block('g-receipt', 'receipt', 'Order 1042 total 121 dollars 10.', {
          'title': 'Order 1042',
          'lines': [
            {'label': 'Aero Glide 2, size 43', 'amount': '\$129.00'},
            {'label': 'KICKS10 discount', 'amount': '-\$12.90'},
            {'label': 'Standard delivery', 'amount': '\$0.00'},
          ],
          'subtotal': '\$116.10',
          'tax': '\$5.00',
          'total': '\$121.10',
          'currency': 'USD',
        }),
      ),
      (
        'form',
        _block('g-form', 'form', 'Return request form.', {
          'form_id': 'return_request',
          'title': 'Start a return',
          'fields': [
            {
              'kind': 'text',
              'name': 'order_id',
              'label': 'Order number',
              'required': true,
              'placeholder': '1042',
            },
            {
              'kind': 'select',
              'name': 'reason',
              'label': 'Reason',
              'required': true,
              'options': [
                {'label': 'Too small', 'value': 'too_small'},
                {'label': 'Too large', 'value': 'too_large'},
                {'label': 'Not what I expected', 'value': 'not_expected'},
                {'label': 'Arrived damaged', 'value': 'damaged'},
              ],
            },
            {'kind': 'number', 'name': 'pairs', 'label': 'How many pairs', 'required': true},
            {'kind': 'date', 'name': 'pickup_date', 'label': 'Pickup date'},
            {'kind': 'time', 'name': 'pickup_from', 'label': 'Earliest pickup time'},
            {
              'kind': 'toggle',
              'name': 'keep_box',
              'label': 'I still have the original box',
            },
          ],
          'submit_label': 'Request pickup',
        }),
      ),
      (
        'form · a damaged delivery',
        _block('g-form-claim', 'form', 'Form to report a damaged delivery, with photos.', {
          'form_id': 'damage_claim',
          'title': 'Report a damaged delivery',
          'fields': [
            {
              'kind': 'upload',
              'name': 'photos',
              'label': 'Photos of the damage',
              'required': true,
              'accept': 'image',
              'max_files': 3,
            },
            {
              'kind': 'multi_select',
              'name': 'damaged',
              'label': 'What was damaged',
              'required': true,
              'value': ['box'],
              'options': [
                {'label': 'The box', 'value': 'box'},
                {'label': 'The shoes', 'value': 'shoes'},
                {'label': 'The laces', 'value': 'laces'},
                {'label': 'The insoles', 'value': 'insoles'},
              ],
            },
            {
              'kind': 'multiline',
              'name': 'what_happened',
              'label': 'What happened',
              'placeholder': 'The box arrived crushed on one corner…',
            },
            {
              'kind': 'number',
              'name': 'pairs',
              'label': 'Pairs affected',
              'stepper': true,
              'min': 1,
              'max': 4,
              'value': 1,
            },
            {'kind': 'upload', 'name': 'receipt', 'label': 'Delivery note', 'accept': 'document'},
          ],
          'submit_label': 'Send the claim',
        }),
      ),
      (
        'form · contact and dates',
        _block('g-form-contact', 'form', 'Form for contact details and a pickup window.', {
          'form_id': 'pickup_window',
          'title': 'When can we collect it?',
          'fields': [
            {'kind': 'text', 'name': 'name', 'label': 'Name', 'required': true, 'autofill': 'name'},
            {'kind': 'email', 'name': 'email', 'label': 'Email', 'required': true, 'autofill': 'email'},
            {'kind': 'tel', 'name': 'phone', 'label': 'Phone', 'autofill': 'tel'},
            {
              'kind': 'date_range',
              'name': 'window',
              'label': 'Pickup window',
              'required': true,
              'min_date': '2026-10-12',
              'max_date': '2026-11-30',
            },
            {
              'kind': 'select',
              'name': 'country',
              'label': 'Country',
              'required': true,
              'autofill': 'country',
              // Thirteen, one past where a select gets its search field.
              'options': [
                for (final (label, value) in [
                  ('Austria', 'at'), ('Belgium', 'be'), ('Denmark', 'dk'),
                  ('Finland', 'fi'), ('France', 'fr'), ('Germany', 'de'),
                  ('Ireland', 'ie'), ('Italy', 'it'), ('Netherlands', 'nl'),
                  ('Norway', 'no'), ('Portugal', 'pt'), ('Spain', 'es'),
                  ('Sweden', 'se'),
                ])
                  {'label': label, 'value': value},
              ],
            },
            {
              'kind': 'url',
              'name': 'tracking',
              'label': 'Tracking link',
              'placeholder': 'https://',
            },
            {
              'kind': 'number',
              'name': 'parcels',
              'label': 'Parcels',
              'min': 1,
              'max': 5,
            },
          ],
          'submit_label': 'Book the pickup',
        }),
      ),
      (
        'datetime_slots',
        _block('g-slots', 'datetime_slots', 'Six fitting slots across two days.', {
          'title': 'Fitting at Neon Kicks Amsterdam',
          'slots': [
            {'id': 's1', 'label': '10:00', 'starts_at': '2026-09-02T10:00:00Z'},
            {'id': 's2', 'label': '11:30', 'starts_at': '2026-09-02T11:30:00Z'},
            {'id': 's3', 'label': '15:00', 'starts_at': '2026-09-02T15:00:00Z'},
            {'id': 's4', 'label': '09:30', 'starts_at': '2026-09-03T09:30:00Z'},
            {'id': 's5', 'label': '13:00', 'starts_at': '2026-09-03T13:00:00Z'},
          ],
        }),
      ),
      (
        'booking_card',
        _block('g-booking', 'booking_card', 'Fitting on 2 September at 10:00.', {
          'title': 'Gait analysis and fitting',
          'subtitle': 'Neon Kicks Amsterdam, Haarlemmerstraat 24',
          'when': 'Wednesday 2 September, 10:00 to 10:45',
          'where': 'Fitting room 2, ground floor',
          'image_url': _shot('kicks-store-amsterdam', 800, 400),
          'lines': [
            {'label': 'Fitter', 'value': 'Meral Doğan'},
            {'label': 'Booking', 'value': 'FIT-2291'},
            {'label': 'Cost', 'value': 'Free for Kicks Club'},
          ],
          'cta': {
            'label': 'Confirm the fitting',
            'action': {'kind': 'reply', 'text': 'Confirm booking FIT-2291'},
          },
        }),
      ),
      (
        'chart · line',
        _block('g-chart-line', 'chart',
            'Monthly spend rose from 64 to 212 dollars between March and August.', {
          'kind': 'line',
          'title': 'Your spend this year',
          'unit': 'USD',
          'labels': ['Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug'],
          'series': [
            {
              'name': 'This year',
              'data': [64, 0, 129, 95, 148, 212],
            },
            {
              'name': 'Last year',
              'data': [88, 41, 96, 110, 102, 134],
            },
          ],
        }),
      ),
      (
        'chart · bar',
        _block('g-chart-bar', 'chart', 'Aug had 4 orders, the busiest month.', {
          'kind': 'bar',
          'title': 'Orders a month',
          'labels': ['Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug'],
          'series': [
            {
              'data': [1, 0, 2, 1, 2, 4],
            },
          ],
        }),
      ),
      (
        'chart · donut',
        _block('g-chart-donut', 'chart', 'Running is 46 percent of your spend.', {
          'kind': 'donut',
          'title': 'Spend by category',
          'labels': ['Running', 'Everyday', 'Trail', 'Accessories'],
          'series': [
            {
              'data': [592, 380, 149, 163],
            },
          ],
        }),
      ),
      (
        'table',
        _block('g-table', 'table', 'Size conversion for EU, UK, US and centimetres.', {
          'columns': ['EU', 'UK', 'US men', 'US women', 'Foot length'],
          'rows': [
            ['40', '6.5', '7.5', '9', '25.0 cm'],
            ['41', '7', '8', '9.5', '25.7 cm'],
            ['42', '8', '9', '10.5', '26.3 cm'],
            ['43', '9', '10', '11.5', '27.0 cm'],
            ['44', '9.5', '10.5', '12', '27.6 cm'],
          ],
        }),
      ),
      (
        'media_gallery · grid',
        _block('g-gallery', 'media_gallery', 'Five photographs of the Aero Glide 2.', {
          'layout': 'grid',
          'images': [
            {'url': _shot('aero-glide-side', 600, 600), 'alt': 'Aero Glide 2 from the side'},
            {'url': _shot('aero-glide-sole', 600, 600), 'alt': 'The outsole tread pattern'},
            {'url': _shot('aero-glide-heel', 600, 600), 'alt': 'Reflective heel counter'},
            {'url': _shot('aero-glide-top', 600, 600), 'alt': 'Knit upper from above'},
            {'url': _shot('aero-glide-worn', 600, 600), 'alt': 'The shoe worn on a wet road'},
          ],
        }),
      ),
      (
        'media_gallery · carousel',
        _block('g-carousel', 'media_gallery', 'Three colourways of the Court Low.', {
          'layout': 'carousel',
          'images': [
            {'url': _shot('court-low-bone', 800, 600), 'alt': 'Court Low in bone'},
            {'url': _shot('court-low-olive', 800, 600), 'alt': 'Court Low in olive'},
            {'url': _shot('court-low-black', 800, 600), 'alt': 'Court Low in black'},
          ],
        }),
      ),
      (
        'key_value',
        _block('g-kv', 'key_value', 'Order 1042: shipped, arriving 26 August.', {
          'title': 'Order 1042',
          'rows': [
            {'label': 'Placed', 'value': '22 August, 09:14'},
            {'label': 'Items', 'value': 'Aero Glide 2, size 43'},
            {'label': 'Courier', 'value': 'PostNL, 3SABCD1234567'},
            {'label': 'Arriving', 'value': 'Today, 14:00 to 18:00', 'emphasis': true},
          ],
          'cta': {
            'label': 'Track the parcel',
            'action': {
              'kind': 'open_url',
              'url': 'https://postnl.nl/tracktrace/3SABCD1234567',
            },
          },
        }),
      ),
      (
        'variant_picker',
        _block('g-variant', 'variant_picker',
            'EU sizes 40 to 45; 41 and 45 are out of stock.', {
          'title': 'Aero Glide 2',
          'label': 'Size (EU)',
          'selected_id': 'eu-43',
          'options': [
            {'id': 'eu-40', 'label': '40'},
            {'id': 'eu-41', 'label': '41', 'available': false},
            {'id': 'eu-42', 'label': '42'},
            {'id': 'eu-43', 'label': '43'},
            {'id': 'eu-44', 'label': '44'},
            {'id': 'eu-45', 'label': '45', 'available': false},
          ],
        }),
      ),
      (
        'article_card',
        _block('g-article', 'article_card',
            'Returns policy: unworn shoes go back within 30 days.', {
          'title': 'Returns and refunds',
          'excerpt':
              'Unworn shoes in their original box can be returned within 30 days of '
                  'delivery. Drop the parcel at any pickup point with the prepaid label; '
                  'refunds are issued to the original payment method 3 to 5 days after '
                  'the parcel is scanned.',
          'source': 'Returns policy',
          'updated': 'Updated 4 August',
          'cta': {
            'label': 'Start a return',
            'action': {'kind': 'reply', 'text': 'Start a return for order 1042'},
          },
        }),
      ),
      (
        'section',
        _block('g-section', 'section', 'Why this one: what matters most in the first weeks.', {
          'title': 'Why this one',
          'subtitle': 'What matters most in the first weeks.',
        }),
      ),
      (
        'key_points',
        _block('g-points', 'key_points',
            'Soft landing, light at 240 g, and size 43 in stock for Thursday.', {
          'items': [
            {
              'icon': 'heart',
              'title': 'Soft landing',
              'body': 'A thick foam sole is kind to your joints in the first kilometres.',
            },
            {'icon': 'star', 'title': 'Light', 'body': '240 g a shoe, so a run never drags.'},
            {
              'icon': 'truck',
              'title': 'Your size is ready',
              'body': 'Size 43 is in stock and at your door on Thursday.',
            },
          ],
        }),
      ),
      (
        'tags',
        _block('g-tags', 'tags', 'Soft, for beginners, 43 in stock.', {
          'items': ['Soft', 'For beginners', '43 in stock'],
        }),
      ),
      (
        'actions',
        _block('g-actions', 'actions', 'Add to cart, or choose a size.', {
          'items': [
            {
              'label': 'Add to cart',
              'icon': 'bag',
              'action': {'kind': 'reply', 'text': 'Add the Aero Glide 2 in size 43 to my cart'},
            },
            {
              'label': 'Choose a size',
              'action': {'kind': 'reply', 'text': 'Which sizes are there?'},
            },
          ],
        }),
      ),
      (
        'screens',
        _block('g-screens', 'screens', 'Open order 1042, or change its delivery, in the app.', {
          'items': [
            {
              'title': 'Order #1042',
              'icon': 'package',
              'action': {
                'kind': 'navigate',
                'route': 'order_detail',
                'params': {'order_id': '1042'},
              },
            },
            {
              'title': 'Change delivery',
              'icon': 'truck',
              'action': {
                'kind': 'navigate',
                'route': 'delivery',
                'params': {'order_id': '1042'},
              },
            },
          ],
        }),
      ),
      (
        'choice · chips',
        _block('g-choice-chips', 'choice', 'Where do you mostly run: road, trail, treadmill or mixed?', {
          'question': 'Where do you mostly run?',
          'mode': 'single',
          'options': [
            {'id': 'road', 'label': 'Road', 'icon': '🛣️'},
            {'id': 'trail', 'label': 'Trail', 'icon': '⛰️'},
            {'id': 'treadmill', 'label': 'Treadmill', 'icon': '🏃'},
            {'id': 'mixed', 'label': 'Mixed', 'icon': '🔀'},
          ],
          'skip': {'label': 'No preference'},
        }),
      ),
      (
        'choice · multi list',
        _block('g-choice-multi', 'choice', 'Which items from order 4821 are going back?', {
          'question': 'Which ones are you returning?',
          'hint': 'Order #4821 · delivered 7 Oct',
          'mode': 'multi',
          'options': [
            {
              'id': 'glide43',
              'label': 'Aero Glide 2',
              'subtitle': '43 · Volt · €129',
              'image_url': _shot('aero-glide-2', 120, 120),
            },
            {
              'id': 'court42',
              'label': 'Court Low',
              'subtitle': '42 · Bone · €95',
              'image_url': _shot('court-low', 120, 120),
            },
            {'id': 'socks', 'label': 'Running socks, 3 pack', 'subtitle': 'M · €12', 'icon': 'bag'},
          ],
          'submit_label': 'Return',
        }),
      ),
      (
        'choice · list with other',
        _block('g-choice-why', 'choice', 'Why are you returning it?', {
          'question': 'Why are you returning it?',
          'hint': 'Who pays for the label depends on it.',
          'mode': 'single',
          'style': 'list',
          'options': [
            {'id': 'size', 'label': 'It does not fit'},
            {'id': 'expect', 'label': 'Not what I expected'},
            {'id': 'damaged', 'label': 'It arrived damaged', 'icon': 'warning'},
          ],
          'other': {'label': 'Another reason', 'placeholder': 'In a few words'},
        }),
      ),
      ..._wave2(),
      ..._wave4(),
      ..._wave5(),
      ..._wave6(),
      (
        'unknown type · fallback',
        _block('g-unknown', 'hologram_viewer',
            'A component this build cannot draw falls back to its text.', {}),
      ),
    ];

/// An instant [from] now, as the wire writes one: what an action result
/// gives, so the ETA and the booking read as live in the gallery.
String _at(Duration from) => DateTime.now().toUtc().add(from).toIso8601String();

/// Catalog wave 2 (`design/CATALOG-B2.md`): comparison, the records' new
/// props, and the call, copy and calendar buttons.
List<(String, WireBlock)> _wave2() => [
      (
        'comparison · two shoes',
        _block('g-cmp-shoes', 'comparison', 'Aero Glide 2 is lighter; Trail Circuit is waterproof.', {
          'items': [
            {
              'title': 'Aero Glide 2',
              'image_url': _shot('aero-glide-2', 400, 300),
              'price': '\$129',
              'badge': 'Best seller',
              'action': {'kind': 'reply', 'text': 'Tell me about the Aero Glide 2'},
            },
            {
              'title': 'Trail Circuit',
              'image_url': _shot('trail-circuit', 400, 300),
              'price': '\$149',
              'action': {'kind': 'reply', 'text': 'Tell me about the Trail Circuit'},
            },
          ],
          'rows': [
            {'label': 'Weight', 'values': ['248 g', '296 g'], 'best_index': 0},
            {'label': 'Drop', 'values': ['8 mm', '6 mm']},
            {'label': 'Cushioning', 'values': ['High', 'Medium']},
            {'label': 'Outsole', 'values': ['Road rubber', '4 mm lugs']},
            {'label': 'Waterproof', 'values': ['no', 'yes'], 'kind': 'check'},
            {'label': 'Rating', 'values': ['4.7 (1,284)', '4.5 (612)'], 'best_index': 0},
            {'label': 'Size 43', 'values': ['In stock', 'Last 2']},
          ],
          'summary': 'On the road the Aero Glide is lighter and softer; on wet trails the Trail Circuit grips.',
        }),
      ),
      (
        'comparison · three plans',
        _block('g-cmp-plans', 'comparison', 'Plus covers your use; Pro adds unlimited data and a second line.', {
          'title': 'Three plans',
          'items': [
            {'title': 'Basic', 'price': '\$9/mo'},
            {'title': 'Plus', 'price': '\$15/mo', 'badge': 'Suggested'},
            {'title': 'Pro', 'price': '\$24/mo'},
          ],
          'rows': [
            {'label': 'Data', 'values': ['20 GB', '50 GB', 'Unlimited'], 'best_index': 2},
            {'label': 'Minutes', 'values': ['1000', 'Unlimited', 'Unlimited']},
            {'label': '5G', 'values': ['no', 'yes', 'yes'], 'kind': 'check'},
            {'label': 'Second line', 'values': ['no', 'no', 'yes'], 'kind': 'check'},
            {'label': 'Contract', 'values': ['None', '12 months', '12 months']},
          ],
          'summary': 'You use about 30 GB a month, so Plus is enough and \$9 cheaper than Pro.',
        }),
      ),
      (
        'item_list · transactions',
        _block('g-list-tx', 'item_list', 'Ten card transactions from today and last week.', {
          'items': [
            for (final (group, date, title, value, tone) in [
              ('Today', '09:12', 'Neon Kicks Amsterdam', '129.00', 'negative'),
              ('Today', '08:40', 'Refund · Court Low', '95.00', 'positive'),
              ('Last week', '7 Oct', 'Coffee Lab', '-4.20', 'negative'),
              ('Last week', '6 Oct', 'Salary', '+2,450.00', 'positive'),
              ('Last week', '6 Oct', 'Metro top-up', '20.00', 'negative'),
              ('Last week', '5 Oct', 'Transfer to savings', '300.00', 'neutral'),
              ('Last week', '4 Oct', 'Bookshop', '18.50', 'negative'),
              ('Last week', '4 Oct', 'Pharmacy', '12.10', 'negative'),
              ('Last week', '3 Oct', 'Cinema', '24.00', 'negative'),
              ('Last week', '3 Oct', 'Grocer', '41.75', 'negative'),
            ])
              {
                'group': group,
                'date_label': date,
                'title': title,
                'amount': {'value': '€$value', 'tone': tone},
                if (title.startsWith('Refund')) 'status': {'label': 'Pending', 'tone': 'warning'},
              },
          ],
        }),
      ),
      (
        'item_list · ranking',
        _block('g-list-rank', 'item_list', 'You are third in the October step challenge.', {
          'items': [
            {'rank': 1, 'title': 'Meral D.', 'trailing': '412,880'},
            {'rank': 2, 'title': 'Joris V.', 'trailing': '398,150'},
            {'rank': 3, 'title': 'You', 'trailing': '377,402', 'highlight': true},
            {'rank': 4, 'title': 'Sanne K.', 'trailing': '350,019'},
          ],
        }),
      ),
      (
        'item_list · documents',
        _block('g-list-docs', 'item_list', 'Three statements and an export.', {
          'items': [
            {
              'file_type': 'pdf',
              'title': 'September statement',
              'subtitle': '120 KB',
              'action': {'kind': 'open_url', 'url': 'https://example.com/statements/2026-09.pdf'},
            },
            {'file_type': 'pdf', 'title': 'August statement', 'subtitle': '118 KB'},
            {'file_type': 'csv', 'title': 'Transactions, Q3', 'subtitle': '42 KB'},
            {'file_type': 'image', 'title': 'Receipt, Neon Kicks', 'subtitle': '1.2 MB'},
          ],
        }),
      ),
      (
        'order_tracker · ETA',
        _block('g-tracker-eta', 'order_tracker', 'Order 1042 arrives in about 25 minutes.', {
          'title': 'Order 1042',
          'eta': _at(const Duration(minutes: 25)),
          'as_of': _at(const Duration(minutes: -2)),
          'steps': [
            {'label': 'Ordered', 'status': 'done', 'timestamp': '09:14'},
            {'label': 'Packed in Rotterdam', 'status': 'done', 'timestamp': '11:02'},
            {
              'label': 'Out for delivery',
              'status': 'current',
              'timestamp': '13:40',
              'note': 'Mehmet is three stops away',
            },
            {'label': 'Delivered', 'status': 'pending'},
          ],
          'reference': {'label': 'Tracking', 'value': '3SABCD1234567'},
        }),
      ),
      (
        'key_value · account',
        _block('g-kv-account', 'key_value', 'Current account details and the last HbA1c result.', {
          'title': 'Current account',
          'rows': [
            {'label': 'Account holder', 'value': 'Elif Yılmaz'},
            {'label': 'IBAN', 'value': 'NL91 ABNA 0417 1643 00', 'copy': true},
            {'label': 'Card number', 'value': '5355 4321 9876 4821', 'masked': true},
            {'label': 'Status', 'value': 'Active', 'tone': 'success'},
            {'label': 'HbA1c', 'value': '5.9 %', 'tone': 'warning', 'range_label': '4.0–5.6'},
          ],
        }),
      ),
      (
        'info_card · courier',
        _block('g-info-courier', 'info_card', 'Mehmet is bringing order 1042 in a white Egea.', {
          'avatar_url': _shot('courier-mehmet', 120, 120),
          'title': 'Mehmet is on his way',
          'meta': 'White Egea · 34 ABC 123',
          'body': 'He is three stops away and will ring the bell.',
          'actions': [
            {
              'label': 'Call',
              'icon': 'phone',
              'action': {'kind': 'call', 'phone': '+31 20 555 0134'},
            },
            {
              'label': 'Copy plate',
              'action': {'kind': 'copy', 'text': '34 ABC 123'},
            },
          ],
        }),
      ),
      (
        'info_card · document',
        _block('g-info-doc', 'info_card', 'Your September statement is ready.', {
          'file_type': 'pdf',
          'title': 'September statement',
          'meta': 'PDF · 120 KB · September 2026',
          'actions': [
            {
              'label': 'Open',
              'action': {'kind': 'open_url', 'url': 'https://example.com/statements/2026-09.pdf'},
            },
          ],
        }),
      ),
      (
        'stat_group · as of',
        _block('g-stats-asof', 'stat_group', 'Balance 2,184 euros, 9 transactions this week.', {
          'items': [
            {'label': 'Balance', 'value': '€2,184'},
            {'label': 'This week', 'value': '9', 'delta': '3', 'trend': 'up'},
          ],
          'as_of': _at(const Duration(minutes: -12)),
        }),
      ),
      (
        'booking_card · reference',
        _block('g-booking-ref', 'booking_card', 'Fitting booked in two hours, reference FIT-2291.', {
          'title': 'Gait analysis and fitting',
          'subtitle': 'Neon Kicks Amsterdam',
          'when': 'Today, in the afternoon',
          'where': 'Fitting room 2, ground floor',
          'starts_at': _at(const Duration(hours: 2)),
          'status': {'label': 'Confirmed', 'tone': 'success'},
          'reference': {'label': 'Booking', 'value': 'FIT-2291'},
          'cta': {
            'label': 'Add to calendar',
            'action': {
              'kind': 'add_to_calendar',
              'title': 'Gait analysis and fitting',
              'starts_at': _at(const Duration(hours: 2)),
              'ends_at': _at(const Duration(hours: 2, minutes: 45)),
              'location': 'Haarlemmerstraat 24, Amsterdam',
            },
          },
        }),
      ),
    ];

/// Catalog wave 4 (`design/CATALOG-B4.md`): contact, rating, disclosure,
/// checklist and timeline.
List<(String, WireBlock)> _wave4() => [
      (
        'contact',
        _block('g-contact', 'contact', 'Call +90 850 222 00 00 or email help@kicks.example, weekdays 9:00–18:00.', {
          'title': 'Talk to our support team',
          'body': 'They can change an order that has already shipped.',
          'channels': [
            {'kind': 'call', 'label': 'Call', 'value': '+90 850 222 00 00'},
            {'kind': 'email', 'label': 'Email', 'value': 'help@kicks.example'},
            {'kind': 'url', 'label': 'Open the help centre', 'value': 'https://example.com/help'},
          ],
          'hours_label': 'Weekdays 9:00–18:00',
        }),
      ),
      (
        'rating · stars',
        _block('g-rating-stars', 'rating', 'How was your delivery? Rate it from 1 to 5.', {
          'question': 'How was your delivery?',
          'scale': 'stars_5',
          'low_label': 'Poor',
          'high_label': 'Great',
        }),
      ),
      (
        'rating · thumbs with a comment',
        _block('g-rating-thumbs', 'rating', 'Did this help?', {
          'question': 'Did this help?',
          'scale': 'thumbs',
          'comment': {'placeholder': 'What could be better?'},
        }),
      ),
      (
        'rating · NPS',
        _block('g-rating-nps', 'rating', 'How likely are you to recommend Neon Kicks, from 0 to 10?', {
          'question': 'How likely are you to recommend Neon Kicks to a friend?',
          'scale': 'nps_11',
          'low_label': 'Not likely',
          'high_label': 'Very likely',
        }),
      ),
      (
        'disclosure · returns',
        _block('g-disclosure', 'disclosure', 'Returns: 30 days, free label, refunds in 5 working days.', {
          'items': [
            {
              'title': 'What is the return window?',
              'body': '30 days from delivery, unworn, in the original box.',
            },
            {
              'title': 'Who pays for the return?',
              'body': 'We do. The label in your order email is free at any parcel shop.',
            },
            {
              'title': 'How long does a refund take?',
              'body': 'Five working days after the shoes reach our warehouse, to the card you paid with.',
            },
          ],
          'single_open': true,
        }),
      ),
      (
        'checklist · before the fitting',
        _block('g-checklist', 'checklist', 'Bring your running shoes, wear shorts, and arrive 10 minutes early.', {
          'title': 'Before your fitting',
          'items': [
            {'id': 'shoes', 'title': 'Bring the shoes you run in now', 'done': true},
            {'id': 'shorts', 'title': 'Wear shorts', 'body': 'So the gait camera can see your knees.'},
            {'id': 'early', 'title': 'Arrive 10 minutes early', 'due_label': 'Wed 09:50'},
          ],
          'on_complete': {'label': 'All set', 'reply_text': 'I have everything for the fitting.'},
        }),
      ),
      (
        'timeline · race weekend',
        _block('g-timeline', 'timeline', 'Saturday: bib pick-up and shakeout run. Sunday: the race at 09:00.', {
          'title': 'Race weekend',
          'groups': [
            {'label': 'Saturday'},
            {'label': 'Sunday'},
          ],
          'items': [
            {
              'group_index': 0,
              'time_label': '11:00',
              'title': 'Bib pick-up',
              'subtitle': 'Neon Kicks Amsterdam',
              'icon': 'ticket',
              'action': {'kind': 'reply', 'text': 'Where do I pick up my bib?'},
            },
            {'group_index': 0, 'time_label': '17:30', 'title': 'Shakeout run', 'subtitle': '5 km, easy'},
            {'group_index': 1, 'time_label': '07:30', 'title': 'Breakfast', 'subtitle': 'Three hours before the start'},
            {'group_index': 1, 'time_label': '09:00', 'title': 'Start', 'subtitle': 'Museumplein, wave B', 'icon': 'location'},
          ],
        }),
      ),
    ];

/// Catalog wave 5 (`design/CATALOG-B5.md`): place_card, map and pass. The
/// passes' codes are the server's own drawings (`apps/api/src/lib/pass-code.ts`)
/// of the values beside them, so the gallery's QR scans.
List<(String, WireBlock)> _wave5() => [
      (
        'place_card · store with stock',
        _block('g-place', 'place_card', 'Neon Kicks Kadıköy, Bağdat Cd. 312, 1.2 km away, open until 21:00.', {
          'name': 'Neon Kicks Kadıköy',
          'address': 'Bağdat Cd. 312, Kadıköy, İstanbul',
          'lat': 40.9634,
          'lng': 29.0652,
          'distance_label': '1.2 km',
          'open_now': true,
          'hours_today': 'until 21:00',
          'hours_week': [
            {'day': 'Mon–Fri', 'hours': '10:00–21:00'},
            {'day': 'Sat', 'hours': '10:00–22:00'},
            {'day': 'Sun', 'hours': '11:00–20:00'},
          ],
          'phone': '+90 216 555 01 12',
          'rating': 4.6,
          'rating_count': 312,
          'image_url': _shot('kicks-store-kadikoy', 800, 450),
          'directions': true,
          'website': 'https://www.neonkicks.example/stores/kadikoy',
        }),
      ),
      (
        'place_card · closed, no picture',
        _block('g-place-closed', 'place_card', 'Neon Kicks Moda is closed now; it opens at 10:00.', {
          'name': 'Neon Kicks Moda',
          'address': 'Moda Cd. 88, Kadıköy, İstanbul',
          'distance_label': '2.4 km',
          'open_now': false,
          'hours_today': 'opens 10:00',
          'directions': true,
        }),
      ),
      (
        'map · two stores',
        _block('g-map', 'map', 'Two stores near you: Kadıköy (1.2 km) and Moda (2.4 km).', {
          'pins': [
            {'lat': 40.9634, 'lng': 29.0652, 'label': 'Kadıköy', 'subtitle': 'Bağdat Cd. 312 · open until 21:00'},
            {'lat': 40.9806, 'lng': 29.0262, 'label': 'Moda', 'subtitle': 'Moda Cd. 88 · opens 10:00'},
          ],
          'caption': 'Both have the Aero Glide 2 in a 42.',
        }),
      ),
      (
        'pass · pickup, QR, wallets',
        _block('g-pass-qr', 'pass', 'Pickup code RD-4821-XYZ for order 4821, at Neon Kicks Kadıköy.', {
          'kind': 'pickup',
          'title': 'Order 4821',
          'subtitle': 'Neon Kicks Kadıköy, at the counter',
          'fields': [
            {'label': 'Items', 'value': '2'},
            {'label': 'Name', 'value': 'T. Öztürk'},
            {'label': 'Shelf', 'value': 'B12'},
          ],
          'code': {
            'format': 'qr',
            'value': 'RD-4821-XYZ',
            'display_text': 'RD-4821-XYZ',
            'matrix': {
              'rows': 21,
              'cols': 21,
              'bits': '/nP8FxBukrt1JduvLsEVB/qv4B8AXvbVA2ZXtPUYYk654ABEX/lYMFO/uvI91couiNcFjS/jGwA=',
              'module_aspect': 1,
            },
          },
          'wallet': {
            'apple_pkpass_url': 'https://neonkicks.example/passes/4821.pkpass',
            'google_save_url': 'https://pay.google.com/gp/v/save/eyJhbGciOi',
          },
          'valid_until': '2026-10-17T21:00:00+03:00',
        }),
      ),
      (
        'pass · coupon, code128',
        _block('g-pass-bars', 'pass', 'Coupon 4821XYZ: 15% off your next pair.', {
          'kind': 'coupon',
          'title': '15% off your next pair',
          'subtitle': 'At the till, in any Neon Kicks store',
          'code': {
            'format': 'code128',
            'value': '4821XYZ',
            'display_text': '4821 XYZ',
            'bars': [2, 1, 1, 2, 3, 2, 3, 1, 3, 1, 2, 1, 2, 1, 3, 2, 1, 2, 1, 1, 4, 1, 3, 1, 3, 3, 1, 1, 2, 1, 3, 1, 2, 1, 1, 3, 3, 1, 2, 3, 1, 1, 1, 2, 2, 1, 3, 2, 2, 3, 3, 1, 1, 1, 2],
          },
          'valid_until': '2026-12-31T23:59:00+03:00',
        }),
      ),
      (
        'pass · boarding, PDF417',
        _block('g-pass-pdf', 'pass', 'Boarding pass TK 1723, Istanbul to Berlin, gate B12, seat 14C, boards 09:40.', {
          'kind': 'boarding',
          'title': 'IST → BER · TK 1723',
          'subtitle': 'Tuna Öztürk',
          'fields': [
            {'label': 'Gate', 'value': 'B12'},
            {'label': 'Seat', 'value': '14C'},
            {'label': 'Boards', 'value': '09:40'},
            {'label': 'Group', 'value': '3'},
          ],
          'code': {
            'format': 'pdf417',
            'value': 'M1OZTURK/TUNA EABC123 ISTBERTK 1723',
            'matrix': {
              // The ten rows its bits hold; see test/catalog_b5_test.dart.
              'rows': 10,
              'cols': 120,
              'bits': '/1R1ODXeGaQKYYfV8/op/1R9RiQeWZ6PNzfUw/op/1RU8DH228TIjfaj4/op/1RX3ycdHq8NGca8+/op/1RrhD1zlPht79a4g/op/1R9ezeWH15r0CevC/op/1RTnDsI2EFsmcdO+/op/1R6UCn7n7Frv0a/e/op/1R+mTJPnPLofaUx8/op/1RRgyjDHHRI57UYY/op',
              'module_aspect': 3,
            },
          },
        }),
      ),
      (
        'pass · membership, no code drawn',
        _block('g-pass-text', 'pass', 'Membership number NK 0042 7731.', {
          'kind': 'membership',
          'title': 'Neon Kicks Club',
          'subtitle': 'Gold since 2024',
          'code': {'format': 'aztec', 'value': 'NK00427731', 'display_text': 'NK 0042 7731'},
        }),
      ),
    ];

/// Catalog wave 6 (`design/CATALOG-B6.md`): the P2 extensions on the blocks
/// that already had a fixture, and `code`.
List<(String, WireBlock)> _wave6() => [
      (
        'product_cards · fact chips',
        _block('g-cards-chips', 'product_cards', 'Two flats in Kadıköy: Moda at ₺4.2M and Fenerbahçe at ₺5.1M.', {
          'items': [
            {
              'title': 'Moda, sea-view flat',
              'subtitle': 'Kadıköy',
              'price': '₺4.2M',
              'image_url': _shot('moda-flat', 320, 220),
              'chips': ['3+1', '120 m²', '2 baths'],
              'action': {'kind': 'reply', 'text': 'Tell me about the Moda flat'},
            },
            {
              'title': 'Fenerbahçe garden flat',
              'subtitle': 'Kadıköy',
              'price': '₺5.1M',
              'image_url': _shot('fenerbahce-flat', 320, 220),
              'chips': ['2+1', '95 m²', 'Garden', 'Parking'],
              'action': {'kind': 'reply', 'text': 'Tell me about the Fenerbahçe flat'},
            },
          ],
        }),
      ),
      (
        'variant_picker · swatches',
        _block('g-variant-swatches', 'variant_picker', 'Pick a colour: Midnight, Sand or Forest; Chalk is sold out.', {
          'title': 'Aero Glide 2',
          'label': 'Colour',
          'style': 'swatches',
          'options': [
            {'id': 'midnight', 'label': 'Midnight', 'swatch_hex': '#1F2A44'},
            {'id': 'sand', 'label': 'Sand', 'swatch_hex': '#D8C8A8'},
            {'id': 'forest', 'label': 'Forest', 'swatch_hex': '#2F5D46'},
            {'id': 'chalk', 'label': 'Chalk', 'swatch_hex': '#F4F2EE', 'available': false},
          ],
          'selected_id': 'midnight',
        }),
      ),
      (
        'variant_picker · pictures, one without',
        _block('g-variant-images', 'variant_picker', 'Pick a finish: Suede, Knit or Leather.', {
          'label': 'Finish',
          'style': 'images',
          'options': [
            {'id': 'suede', 'label': 'Suede', 'image_url': _shot('aero-suede', 128, 128)},
            {'id': 'knit', 'label': 'Knit', 'image_url': _shot('aero-knit', 128, 128)},
            {'id': 'leather', 'label': 'Leather'},
          ],
        }),
      ),
      (
        'key_points · pros and cons',
        _block('g-points-tones', 'key_points', 'Pros: light and cushioned. Con: runs half a size small.', {
          'items': [
            {'title': 'Light', 'body': '238 g in a 42, the lightest we stock.', 'tone': 'positive'},
            {'title': 'Cushioned', 'body': 'A thick foam midsole for long runs.', 'tone': 'positive'},
            {'title': 'Runs small', 'body': 'Most people go half a size up.', 'tone': 'negative'},
            {'icon': 'truck', 'title': 'Ships tomorrow', 'tone': 'neutral'},
          ],
        }),
      ),
      (
        'media_gallery · captions, a video',
        _block('g-gallery-video', 'media_gallery', 'The Moda flat: the living room, the view, and a video walkthrough.', {
          'images': [
            {'url': _shot('moda-living', 600, 600), 'alt': 'The living room', 'caption': 'Living room, south-facing'},
            {'url': _shot('moda-view', 600, 600), 'alt': 'The view from the balcony', 'caption': 'From the balcony'},
            {
              'url': _shot('moda-tour', 600, 600),
              'alt': 'A walkthrough of the flat',
              'caption': 'A minute round the flat',
              'video_url': 'https://neonkicks.example/videos/moda-tour.mp4',
            },
          ],
        }),
      ),
      (
        'receipt · notes and changes',
        _block('g-receipt-notes', 'receipt', 'November: rent ₺42,000 (up ₺2,000), service charge ₺1,200; ₺43,200 in all.', {
          'title': 'November statement',
          'lines': [
            {'label': 'Rent', 'amount': '₺42,000', 'note': '1–30 November', 'delta': '+₺2,000'},
            {'label': 'Service charge', 'amount': '₺1,200', 'note': 'Lift and cleaning'},
            {'label': 'Electricity', 'amount': '₺860', 'delta': '−12%'},
          ],
          'total': '₺44,060',
        }),
      ),
      (
        'progress · rings',
        _block('g-progress-rings', 'progress', 'Today: 6,400 of 10,000 steps, 1.5 of 2 litres, 25 of 30 active minutes.', {
          'title': 'Today',
          'style': 'ring',
          'items': [
            {'label': 'Steps', 'value': 6400, 'max': 10000},
            {'label': 'Water', 'value': 1.5, 'max': 2, 'value_label': '1.5 L'},
            {'label': 'Active', 'value': 25, 'max': 30, 'value_label': '25 min'},
          ],
        }),
      ),
      (
        'chart · area',
        _block('g-chart-area', 'chart', 'Weekly runs grew from 12 km to 31 km over eight weeks.', {
          'kind': 'area',
          'title': 'Weekly distance',
          'labels': ['W1', 'W2', 'W3', 'W4', 'W5', 'W6', 'W7', 'W8'],
          'series': [
            {'data': [12, 15, 14, 19, 22, 21, 27, 31]},
          ],
          'unit': 'km',
        }),
      ),
      (
        'chart · hbar',
        _block('g-chart-hbar', 'chart', 'Most returned: trail running shoes (34), then walking shoes (21) and sandals (9).', {
          'kind': 'hbar',
          'title': 'Returns this quarter',
          'labels': ['Trail running shoes', 'Everyday walking shoes', 'Summer sandals'],
          'series': [
            {'data': [34, 21, 9]},
          ],
          'unit': 'pairs',
        }),
      ),
      (
        'chart · stacked_bar',
        _block('g-chart-stacked', 'chart', 'Orders by channel, Jul–Oct: online grew from 120 to 190, stores stayed near 80.', {
          'kind': 'stacked_bar',
          'title': 'Orders by channel',
          'labels': ['Jul', 'Aug', 'Sep', 'Oct'],
          'series': [
            {'name': 'Online', 'data': [120, 140, 165, 190]},
            {'name': 'In store', 'data': [82, 78, 85, 80]},
          ],
        }),
      ),
      (
        'code · a command',
        _block('g-code', 'code', 'Check the API from a shell with curl and your test key.', {
          'language': 'bash',
          'code': "curl -H 'X-Rendel-Key: rd_pk_test_…' \\\n  https://api.rendel.ai/health",
          'caption': 'Your test key is under Settings → Keys.',
        }),
      ),
    ];
