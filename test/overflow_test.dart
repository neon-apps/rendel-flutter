// Every block, at the nastiest input its schema allows, in the environments
// a phone actually ships in.
//
// This is the suite that catches the defects nothing else does: a `Text` that
// was never given a flex share, a fixed height that was fine at the default
// font scale, a Row whose two children each assumed they had the whole width.
// Those do not fail a unit test and they do not fail `flutter analyze` — they
// paint a yellow-and-black overflow stripe on a customer's screen.
//
// Every fixture here satisfies the Zod schema in
// packages/protocol/src/blocks.ts, so anything that overflows is something the
// server is allowed to send today.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/ui/renderer/map_engine.dart';

import 'wire_schema.dart';

/// A map ground with no platform view behind it.
class _Ground extends RendelMapEngine {
  const _Ground();

  @override
  Widget build({
    required RendelMapCamera camera,
    required bool interactive,
    required ValueChanged<RendelMapCamera> onMove,
    required VoidCallback onFailed,
  }) =>
      const ColoredBox(color: Color(0xFFE7ECDF));
}

// ————————————————————————— string builders —————————————————————————

// n characters, no spaces: the nastiest legal string for a slot that expects
// a word or two, because nothing can wrap.
String solid(int n) {
  const alphabet = 'Mmwq';
  final b = StringBuffer();
  for (var i = 0; i < n; i++) {
    b.write(alphabet[i % alphabet.length]);
  }
  return b.toString();
}

/// n characters of ordinary prose, at the schema maximum.
String words(int n) {
  const w = 'Overnight delivery window confirmation reference ';
  final b = StringBuffer();
  while (b.length < n) {
    b.write(w);
  }
  return b.toString().substring(0, n);
}

/// n characters of Arabic (RTL).
String rtl(int n) {
  const w = 'تأكيد الحجز الخاص بك ';
  final b = StringBuffer();
  while (b.length < n) {
    b.write(w);
  }
  return b.toString().substring(0, n);
}

const broken = 'https://invalid.invalid/definitely-not-there.png';

Map<String, dynamic> get act =>
    {'kind': 'reply', 'text': 'hello there'};

// ————————————————————————— fixtures —————————————————————————

/// name -> (type, props). Every fixture satisfies the Zod schema in
/// packages/protocol/src/blocks.ts.
final fixtures = <String, ({String type, Map<String, dynamic> props})>{
  // ---- text
  'text/min': (type: 'text', props: {'markdown': 'a'}),
  'text/solid': (type: 'text', props: {'markdown': solid(400)}),
  'text/long': (type: 'text', props: {'markdown': words(4000)}),
  'text/rtl': (type: 'text', props: {'markdown': rtl(600)}),

  // ---- quick_replies
  'quick_replies/min': (
    type: 'quick_replies',
    props: {
      'items': [
        {'label': 'a', 'action': act}
      ]
    }
  ),
  'quick_replies/max': (
    type: 'quick_replies',
    props: {
      'items': [
        for (var i = 0; i < 6; i++) {'label': solid(40), 'action': act}
      ]
    }
  ),
  'quick_replies/rtl': (
    type: 'quick_replies',
    props: {
      'items': [
        for (var i = 0; i < 6; i++) {'label': rtl(40), 'action': act}
      ]
    }
  ),

  // ---- info_card
  'info_card/min': (type: 'info_card', props: {'title': 'a'}),
  'info_card/max': (
    type: 'info_card',
    props: {
      'icon': solid(40),
      'title': solid(120),
      'body': words(600),
      'cta': {'label': solid(60), 'action': act},
    }
  ),
  'info_card/knownicon': (
    type: 'info_card',
    props: {
      'icon': 'truck',
      'title': words(120),
      'body': words(600),
      'cta': {'label': words(60), 'action': act},
    }
  ),

  // ---- item_list
  'item_list/min': (
    type: 'item_list',
    props: {
      'items': [
        {'title': 'a'}
      ]
    }
  ),
  'item_list/max': (
    type: 'item_list',
    props: {
      'items': [
        for (var i = 0; i < 12; i++)
          {
            'image_url': broken,
            'title': solid(120),
            'subtitle': solid(200),
            'trailing': solid(40),
            'action': act,
          }
      ]
    }
  ),
  'item_list/trailing-only': (
    type: 'item_list',
    props: {
      'items': [
        {'title': 'a', 'trailing': solid(40)}
      ]
    }
  ),

  // ---- product_cards
  'product_cards/min': (
    type: 'product_cards',
    props: {
      'items': [
        {'title': 'a'}
      ]
    }
  ),
  'product_cards/one-max': (
    type: 'product_cards',
    props: {
      'items': [
        {
          'title': solid(120),
          'subtitle': solid(200),
          'price': solid(30),
          'badge': solid(30),
          'image_url': broken,
          'action': act,
        }
      ]
    }
  ),
  // Grove report P1-1: "★★★★ 3.9 (109)" overflowed a horizontal card by 4pt.
  'product_cards/rated-max': (
    type: 'product_cards',
    props: {
      'items': [
        for (var i = 0; i < 4; i++)
          {
            'title': 'INNER GOODNESS Soy Light Milk 1L',
            'subtitle': 'Soy Light · 1 L',
            'price': 'A\$1.59',
            'rating': 3.9,
            'rating_count': 100000000,
            'image_url': broken,
            'action': act,
          }
      ]
    }
  ),
  'product_cards/max': (
    type: 'product_cards',
    props: {
      'items': [
        for (var i = 0; i < 10; i++)
          {
            'title': solid(120),
            'subtitle': solid(200),
            'price': solid(30),
            'badge': solid(30),
            'image_url': broken,
            'action': act,
          }
      ]
    }
  ),

  // ---- confirm_card
  'confirm_card/min': (
    type: 'confirm_card',
    props: {
      'invocation_id': 'inv_1',
      'action_name': 'refund_order',
      'summary': 'a',
      'params': <String, dynamic>{},
      'params_display': <dynamic>[],
      'risk': 'write',
      'confirm': {'kind': 'confirm', 'invocation_id': 'inv_1'},
      'cancel': {'kind': 'cancel', 'invocation_id': 'inv_1'},
    }
  ),
  'confirm_card/max': (
    type: 'confirm_card',
    props: {
      'invocation_id': 'inv_1',
      'action_name': 'refund_order',
      'summary': words(300),
      'params': <String, dynamic>{},
      'params_display': [
        for (var i = 0; i < 12; i++) {'label': solid(60), 'value': solid(200)}
      ],
      'risk': 'destructive',
      'confirm': {'kind': 'confirm', 'invocation_id': 'inv_1'},
      'cancel': {'kind': 'cancel', 'invocation_id': 'inv_1'},
      'expires_at': '2026-09-01T10:00:00Z',
    }
  ),

  // ---- form
  'form/min': (
    type: 'form',
    props: {
      'form_id': 'f',
      'fields': [
        {'kind': 'text', 'name': 'a', 'label': 'a'}
      ],
      'submit_label': 'a',
    }
  ),
  'form/max': (
    type: 'form',
    props: {
      'form_id': solid(64),
      'title': solid(120),
      'fields': [
        {
          'kind': 'text',
          'name': 'f0',
          'label': solid(80),
          'required': true,
          'placeholder': solid(80),
          'value': solid(80),
        },
        {
          'kind': 'number',
          'name': 'f1',
          'label': solid(80),
          'required': true,
          'placeholder': solid(80),
          'value': 123456789,
        },
        {
          'kind': 'select',
          'name': 'f2',
          'label': solid(80),
          'required': true,
          'placeholder': solid(80),
          'value': 'v0',
          'options': [
            for (var i = 0; i < 20; i++) {'label': solid(60), 'value': 'v$i'}
          ],
        },
        {
          'kind': 'toggle',
          'name': 'f3',
          'label': solid(80),
          'required': true,
          'value': true,
        },
        {
          'kind': 'date',
          'name': 'f4',
          'label': solid(80),
          'placeholder': solid(80),
          'value': '2026-08-27',
        },
        {
          'kind': 'time',
          'name': 'f5',
          'label': solid(80),
          'placeholder': solid(80),
          'value': '09:30',
        },
        for (var i = 6; i < 10; i++)
          {
            'kind': 'text',
            'name': 'f$i',
            'label': words(80),
            'placeholder': words(80),
          },
      ],
      'submit_label': solid(40),
    }
  ),
  'form/rtl': (
    type: 'form',
    props: {
      'form_id': 'f',
      'title': rtl(120),
      'fields': [
        {
          'kind': 'select',
          'name': 'a',
          'label': rtl(80),
          'required': true,
          'options': [
            {'label': rtl(60), 'value': 'x'}
          ],
        },
        {'kind': 'toggle', 'name': 'b', 'label': rtl(80), 'required': true},
      ],
      'submit_label': rtl(40),
    }
  ),
  // Form v2's kinds, each at its longest.
  'form/v2-max': (
    type: 'form',
    props: {
      'form_id': 'f',
      'fields': [
        {
          'kind': 'multi_select',
          'name': 'a',
          'label': solid(80),
          'options': [
            for (var i = 0; i < 6; i++) {'label': solid(60), 'value': 'v$i'}
          ],
          'value': ['v0', 'v3'],
        },
        {'kind': 'multiline', 'name': 'b', 'label': solid(80), 'value': words(400)},
        {'kind': 'email', 'name': 'c', 'label': solid(80), 'value': solid(80), 'autofill': 'email'},
        {
          'kind': 'number',
          'name': 'd',
          'label': solid(80),
          'stepper': true,
          'value': 123456789012,
          'step': 0.25,
        },
        {
          'kind': 'date_range',
          'name': 'e',
          'label': solid(80),
          'value': ['2026-08-27', '2026-09-30'],
        },
        {'kind': 'upload', 'name': 'f', 'label': solid(80), 'accept': 'image', 'max_files': 4},
        {'kind': 'upload', 'name': 'g', 'label': solid(80), 'accept': 'document'},
      ],
      'submit_label': solid(40),
    }
  ),

  // ---- datetime_slots
  'datetime_slots/min': (
    type: 'datetime_slots',
    props: {
      'slots': [
        {'id': 's', 'label': 'a'}
      ]
    }
  ),
  'datetime_slots/max': (
    type: 'datetime_slots',
    props: {
      'title': solid(120),
      'slots': [
        for (var i = 0; i < 24; i++)
          {
            'id': solid(64),
            'label': solid(60),
            'starts_at': '2026-09-0${1 + (i % 8)}T0${i % 10}:00:00Z',
          }
      ],
    }
  ),
  'datetime_slots/no-timestamps': (
    type: 'datetime_slots',
    props: {
      'slots': [
        for (var i = 0; i < 24; i++)
          {'id': 's$i', 'label': words(60)}
      ],
    }
  ),

  // ---- booking_card
  'booking_card/min': (type: 'booking_card', props: {'title': 'a'}),
  'booking_card/max': (
    type: 'booking_card',
    props: {
      'title': solid(120),
      'subtitle': solid(200),
      'when': solid(80),
      'where': solid(120),
      'image_url': broken,
      'lines': [
        for (var i = 0; i < 8; i++) {'label': solid(60), 'value': solid(120)}
      ],
      'cta': {'label': solid(60), 'action': act},
    }
  ),

  // ---- stat_group
  'stat_group/min': (
    type: 'stat_group',
    props: {
      'items': [
        {'label': 'a', 'value': '1'}
      ]
    }
  ),
  'stat_group/three-max': (
    type: 'stat_group',
    props: {
      'items': [
        for (var i = 0; i < 3; i++)
          {
            'label': solid(60),
            'value': solid(30),
            'delta': solid(20),
            'trend': 'up',
          }
      ]
    }
  ),
  'stat_group/six-max': (
    type: 'stat_group',
    props: {
      'items': [
        for (var i = 0; i < 6; i++)
          {
            'label': solid(60),
            'value': solid(30),
            'delta': solid(20),
            'trend': i.isEven ? 'down' : 'flat',
          }
      ]
    }
  ),

  // ---- chart (numeric edges)
  'chart/line-single-point': (
    type: 'chart',
    props: {
      'kind': 'line',
      'labels': ['a'],
      'series': [
        {'data': [5]}
      ],
    }
  ),
  'chart/line-all-zero': (
    type: 'chart',
    props: {
      'kind': 'line',
      'labels': ['a', 'b', 'c'],
      'series': [
        {'data': [0, 0, 0]}
      ],
    }
  ),
  'chart/bar-identical': (
    type: 'chart',
    props: {
      'kind': 'bar',
      'labels': [for (var i = 0; i < 24; i++) solid(40)],
      'series': [
        {'data': [for (var i = 0; i < 24; i++) 7]}
      ],
      'unit': solid(12),
    }
  ),
  'chart/bar-negative': (
    type: 'chart',
    props: {
      'kind': 'bar',
      'title': solid(120),
      'labels': [for (var i = 0; i < 24; i++) solid(40)],
      'series': [
        for (var s = 0; s < 3; s++)
          {
            'name': solid(60),
            'data': [for (var i = 0; i < 24; i++) -1000000.5 - i]
          }
      ],
      'unit': solid(12),
    }
  ),
  'chart/line-three-named': (
    type: 'chart',
    props: {
      'kind': 'line',
      'title': words(120),
      'labels': [for (var i = 0; i < 24; i++) words(40)],
      'series': [
        for (var s = 0; s < 3; s++)
          {
            'name': solid(60),
            'data': [for (var i = 0; i < 24; i++) (i - 12) * 1e6]
          }
      ],
      'unit': solid(12),
    }
  ),
  'chart/donut-all-zero': (
    type: 'chart',
    props: {
      'kind': 'donut',
      'labels': ['a', 'b', 'c'],
      'series': [
        {'data': [0, 0, 0]}
      ],
    }
  ),
  'chart/donut-negative': (
    type: 'chart',
    props: {
      'kind': 'donut',
      'labels': [for (var i = 0; i < 24; i++) solid(40)],
      'series': [
        {'data': [for (var i = 0; i < 24; i++) -5.0]}
      ],
    }
  ),
  'chart/donut-max': (
    type: 'chart',
    props: {
      'kind': 'donut',
      'title': solid(120),
      'labels': [for (var i = 0; i < 24; i++) solid(40)],
      'series': [
        {'data': [for (var i = 0; i < 24; i++) i + 1]}
      ],
      'unit': solid(12),
    }
  ),
  'chart/donut-single': (
    type: 'chart',
    props: {
      'kind': 'donut',
      'labels': ['only'],
      'series': [
        {'data': [1]}
      ],
    }
  ),
  'chart/donut-unlabelled': (
    type: 'chart',
    props: {
      'kind': 'donut',
      'labels': ['a'],
      'series': [
        {'data': [1, 2, 3, 4, 5, 6, 7, 8]}
      ],
    }
  ),

  // ---- table
  'table/min': (
    type: 'table',
    props: {
      'columns': ['a'],
      'rows': [
        ['b']
      ],
    }
  ),
  'table/max': (
    type: 'table',
    props: {
      'columns': [for (var c = 0; c < 6; c++) solid(40)],
      'rows': [
        for (var r = 0; r < 20; r++) [for (var c = 0; c < 6; c++) solid(120)]
      ],
    }
  ),
  'table/ragged': (
    type: 'table',
    props: {
      'columns': [for (var c = 0; c < 6; c++) words(40)],
      'rows': [
        for (var r = 0; r < 20; r++)
          [for (var c = 0; c < 1 + (r % 6); c++) words(120)]
      ],
    }
  ),

  // ---- order_tracker
  'order_tracker/min': (
    type: 'order_tracker',
    props: {
      'steps': [
        {'label': 'a', 'status': 'done'},
        {'label': 'b', 'status': 'pending'},
      ]
    }
  ),
  'order_tracker/max': (
    type: 'order_tracker',
    props: {
      'title': solid(120),
      'steps': [
        for (var i = 0; i < 8; i++)
          {
            'label': solid(80),
            'status': ['done', 'current', 'pending'][i % 3],
            'timestamp': solid(40),
          }
      ],
    }
  ),

  // ---- receipt
  'receipt/min': (
    type: 'receipt',
    props: {
      'lines': [
        {'label': 'a', 'amount': '1'}
      ],
      'total': 'a',
    }
  ),
  'receipt/max': (
    type: 'receipt',
    props: {
      'title': solid(120),
      'lines': [
        for (var i = 0; i < 20; i++) {'label': solid(120), 'amount': solid(30)}
      ],
      'subtotal': solid(30),
      'tax': solid(30),
      'total': solid(30),
      'currency': solid(8),
    }
  ),
  'receipt/currency-only': (
    type: 'receipt',
    props: {
      'lines': [
        {'label': solid(120), 'amount': solid(30)}
      ],
      'total': solid(30),
      'currency': solid(8),
    }
  ),

  // ---- media_gallery
  'media_gallery/min': (
    type: 'media_gallery',
    props: {
      'images': [
        {'url': broken}
      ]
    }
  ),
  'media_gallery/grid-max': (
    type: 'media_gallery',
    props: {
      'images': [
        for (var i = 0; i < 12; i++) {'url': broken, 'alt': solid(160)}
      ],
      'layout': 'grid',
    }
  ),
  'media_gallery/grid-4': (
    type: 'media_gallery',
    props: {
      'images': [
        for (var i = 0; i < 4; i++) {'url': broken}
      ],
      'layout': 'grid',
    }
  ),
  'media_gallery/grid-5': (
    type: 'media_gallery',
    props: {
      'images': [
        for (var i = 0; i < 5; i++) {'url': broken}
      ],
      'layout': 'grid',
    }
  ),
  'media_gallery/carousel-max': (
    type: 'media_gallery',
    props: {
      'images': [
        for (var i = 0; i < 12; i++) {'url': broken, 'alt': solid(160)}
      ],
      'layout': 'carousel',
    }
  ),

  // ---- key_value
  'key_value/min': (
    type: 'key_value',
    props: {
      'rows': [
        {'label': 'a', 'value': 'b'}
      ]
    }
  ),
  'key_value/max': (
    type: 'key_value',
    props: {
      'title': solid(120),
      'rows': [
        for (var i = 0; i < 12; i++)
          {'label': solid(60), 'value': solid(200), 'emphasis': true}
      ],
      'cta': {'label': solid(60), 'action': act},
    }
  ),
  'key_value/rtl': (
    type: 'key_value',
    props: {
      'title': rtl(120),
      'rows': [
        for (var i = 0; i < 12; i++)
          {'label': rtl(60), 'value': rtl(200), 'emphasis': i == 0}
      ],
      'cta': {'label': rtl(60), 'action': act},
    }
  ),

  // ---- variant_picker
  'variant_picker/min': (
    type: 'variant_picker',
    props: {
      'options': [
        {'id': 'a', 'label': 'a'},
        {'id': 'b', 'label': 'b'},
      ]
    }
  ),
  'variant_picker/max': (
    type: 'variant_picker',
    props: {
      'title': solid(120),
      'label': solid(60),
      'options': [
        for (var i = 0; i < 24; i++)
          {
            'id': solid(64),
            'label': solid(24),
            'available': i.isEven,
          }
      ],
      'selected_id': solid(64),
    }
  ),

  // ---- choice
  'choice/min': (
    type: 'choice',
    props: {
      'question': 'a',
      'mode': 'single',
      'options': [
        {'id': 'a', 'label': 'a'},
        {'id': 'b', 'label': 'b'},
      ]
    }
  ),
  'choice/chips-max': (
    type: 'choice',
    props: {
      'question': solid(120),
      'hint': solid(160),
      'mode': 'single',
      'style': 'chips',
      'options': [
        for (var i = 0; i < 12; i++) {'id': 'o$i', 'label': solid(40), 'icon': '🛣️'}
      ],
      'other': {'label': solid(40), 'placeholder': solid(80)},
      'skip': {'label': solid(24)},
    }
  ),
  'choice/list-max': (
    type: 'choice',
    props: {
      'question': words(120),
      'hint': words(160),
      'mode': 'multi',
      'options': [
        for (var i = 0; i < 12; i++)
          {
            'id': 'o$i',
            'label': solid(40),
            'subtitle': solid(80),
            if (i.isEven) 'image_url': broken else 'icon': 'truck',
          }
      ],
      'min_selected': 2,
      'max_selected': 12,
      'other': {'label': solid(40), 'placeholder': solid(80)},
      'skip': {'label': solid(24)},
      'submit_label': solid(24),
    }
  ),
  'choice/rtl': (
    type: 'choice',
    props: {
      'question': rtl(120),
      'mode': 'single',
      'style': 'list',
      'options': [
        for (var i = 0; i < 4; i++) {'id': 'o$i', 'label': rtl(40), 'subtitle': rtl(80)}
      ],
      'other': {'label': rtl(40)},
    }
  ),

  // ---- catalog wave 2 (`design/CATALOG-B2.md`)
  'comparison/min': (
    type: 'comparison',
    props: {
      'items': [
        {'title': 'a'},
        {'title': 'b'},
      ],
      'rows': [
        {'label': 'c', 'values': ['', '']},
      ],
    }
  ),
  'comparison/max': (
    type: 'comparison',
    props: {
      'title': solid(80),
      'items': [
        for (var i = 0; i < 4; i++)
          {
            'title': solid(60),
            'subtitle': solid(80),
            'image_url': broken,
            'price': solid(30),
            'badge': solid(24),
            'action': act,
          }
      ],
      'rows': [
        for (var i = 0; i < 12; i++)
          i.isEven
              ? {'label': solid(40), 'values': [for (var j = 0; j < 4; j++) solid(60)], 'best_index': 3}
              : {'label': solid(40), 'values': ['yes', 'no', 'yes', 'no'], 'kind': 'check'},
      ],
      'summary': words(200),
    }
  ),
  'comparison/rtl': (
    type: 'comparison',
    props: {
      'items': [
        for (var i = 0; i < 3; i++) {'title': rtl(60), 'price': rtl(30), 'badge': rtl(24)}
      ],
      'rows': [
        {'label': rtl(40), 'values': [rtl(60), rtl(60), rtl(60)], 'best_index': 0},
        {'label': rtl(40), 'values': ['no', 'yes', 'no'], 'kind': 'check'},
      ],
      'summary': rtl(200),
    }
  ),
  // ---- catalog wave 4 (`design/CATALOG-B4.md`)
  'contact/min': (
    type: 'contact',
    props: {
      'title': 'a',
      'channels': [
        {'kind': 'call', 'label': 'a', 'value': '123'},
      ],
    }
  ),
  'contact/max': (
    type: 'contact',
    props: {
      'title': solid(80),
      'body': words(300),
      'channels': [
        {'kind': 'call', 'label': solid(40), 'value': solid(200)},
        {'kind': 'email', 'label': solid(40), 'value': solid(200)},
        {'kind': 'url', 'label': solid(40), 'value': 'https://${solid(192)}'},
      ],
      'hours_label': solid(60),
    }
  ),
  'contact/rtl': (
    type: 'contact',
    props: {
      'title': rtl(80),
      'body': rtl(300),
      'channels': [
        {'kind': 'call', 'label': rtl(40), 'value': '+90 850 222 00 00'},
        {'kind': 'email', 'label': rtl(40), 'value': 'help@kicks.example'},
      ],
      'hours_label': rtl(60),
    }
  ),
  'rating/stars-max': (
    type: 'rating',
    props: {
      'question': solid(120),
      'scale': 'stars_5',
      'low_label': solid(30),
      'high_label': solid(30),
      'comment': {'placeholder': solid(80)},
    }
  ),
  'rating/thumbs': (
    type: 'rating',
    props: {'question': 'a', 'scale': 'thumbs'}
  ),
  'rating/nps-max': (
    type: 'rating',
    props: {
      'question': words(120),
      'scale': 'nps_11',
      'low_label': solid(30),
      'high_label': solid(30),
    }
  ),
  'rating/nps-rtl': (
    type: 'rating',
    props: {
      'question': rtl(120),
      'scale': 'nps_11',
      'low_label': rtl(30),
      'high_label': rtl(30),
    }
  ),
  'disclosure/min': (
    type: 'disclosure',
    props: {
      'items': [
        {'title': 'a', 'body': 'b'},
      ],
    }
  ),
  'disclosure/max': (
    type: 'disclosure',
    props: {
      'items': [
        for (var i = 0; i < 8; i++) {'title': solid(100), 'body': words(800)}
      ],
      'single_open': true,
    }
  ),
  'checklist/max': (
    type: 'checklist',
    props: {
      'title': solid(80),
      'items': [
        // All done, so the finishing button is drawn as well.
        for (var i = 0; i < 10; i++)
          {'id': '${solid(60)}$i', 'title': solid(80), 'body': words(300), 'done': true, 'due_label': solid(24)}
      ],
      'on_complete': {'label': solid(40), 'reply_text': words(500)},
    }
  ),
  'checklist/rtl': (
    type: 'checklist',
    props: {
      'items': [
        for (var i = 0; i < 3; i++) {'id': 's$i', 'title': rtl(80), 'body': rtl(300), 'due_label': rtl(24)}
      ],
    }
  ),
  'timeline/max': (
    type: 'timeline',
    props: {
      'title': solid(80),
      'groups': [
        for (var i = 0; i < 7; i++) {'label': solid(40)}
      ],
      'items': [
        for (var i = 0; i < 16; i++)
          {
            if (i > 1) 'group_index': i % 7,
            'time_label': solid(24),
            'starts_at': '2026-10-14T10:00:00+02:00',
            'title': solid(80),
            'subtitle': solid(120),
            'icon': 'calendar',
            if (i.isEven) 'action': act,
          }
      ],
    }
  ),
  'timeline/rtl': (
    type: 'timeline',
    props: {
      'groups': [
        {'label': rtl(40)},
      ],
      'items': [
        for (var i = 0; i < 3; i++) {'group_index': 0, 'time_label': rtl(24), 'title': rtl(80), 'subtitle': rtl(120)}
      ],
    }
  ),
  // ---- catalog wave 5 (`design/CATALOG-B5.md`). The map is drawn on the
  // fake engine `main` installs: a widget test runs no platform view.
  'place_card/min': (type: 'place_card', props: {'name': 'a', 'address': 'b'}),
  'place_card/max': (
    type: 'place_card',
    props: {
      'name': solid(80),
      'address': solid(160),
      'lat': 89.9,
      'lng': -179.9,
      'distance_label': solid(20),
      'open_now': true,
      'hours_today': solid(40),
      'hours_week': [
        for (var i = 0; i < 7; i++) {'day': solid(12), 'hours': solid(40)}
      ],
      'phone': solid(32),
      'rating': 5,
      'rating_count': 9007199254740991,
      'image_url': broken,
      'directions': true,
      'website': 'https://${solid(200)}.example',
    }
  ),
  'place_card/rtl': (
    type: 'place_card',
    props: {
      'name': rtl(80),
      'address': rtl(160),
      'distance_label': rtl(20),
      'open_now': false,
      'hours_today': rtl(40),
      'phone': '+90 216 555 01 12',
      'directions': true,
    }
  ),
  'map/min': (
    type: 'map',
    props: {
      'pins': [
        {'lat': 0, 'lng': 0, 'label': 'a'}
      ],
    }
  ),
  'map/max': (
    type: 'map',
    props: {
      'pins': [
        for (var i = 0; i < 10; i++)
          {'lat': -85 + i * 17.0, 'lng': -180 + i * 36.0, 'label': solid(60), 'subtitle': solid(80)}
      ],
      'caption': solid(120),
    }
  ),
  'pass/max': (
    type: 'pass',
    props: {
      'kind': 'boarding',
      'title': solid(80),
      'subtitle': solid(120),
      'fields': [
        for (var i = 0; i < 8; i++) {'label': solid(30), 'value': solid(60)}
      ],
      'code': {
        'format': 'qr',
        'value': solid(500),
        'display_text': solid(60),
        // The largest grid the wire allows.
        'matrix': {'rows': 200, 'cols': 200, 'bits': 'A' * 6668, 'module_aspect': 1},
      },
      'wallet': {'apple_pkpass_url': 'https://example.com/p.pkpass', 'google_save_url': 'https://pay.google.com/x'},
      'valid_until': '2026-10-17T21:00:00+03:00',
    }
  ),
  'pass/code128-max': (
    type: 'pass',
    props: {
      'kind': 'coupon',
      'title': 'a',
      'code': {
        'format': 'code128',
        'value': solid(500),
        'bars': [for (var i = 0; i < 600; i++) 4],
      },
    }
  ),
  'pass/rtl': (
    type: 'pass',
    props: {
      'kind': 'ticket',
      'title': rtl(80),
      'subtitle': rtl(120),
      'fields': [
        for (var i = 0; i < 4; i++) {'label': rtl(30), 'value': rtl(60)}
      ],
      'code': {'format': 'aztec', 'value': 'x', 'display_text': rtl(60)},
    }
  ),
  'item_list/records-max': (
    type: 'item_list',
    props: {
      'items': [
        for (var i = 0; i < 20; i++)
          {
            'title': solid(120),
            'subtitle': solid(200),
            if (i.isEven) 'image_url': broken else 'file_type': 'pdf',
            'amount': {'value': solid(30), 'tone': ['positive', 'negative', 'neutral'][i % 3]},
            'date_label': solid(24),
            'status': {'label': solid(24), 'tone': 'warning'},
            'group': i < 10 ? solid(40) : words(40),
            'highlight': i == 3,
            'rank': 999,
            'action': act,
          }
      ],
    }
  ),
  'key_value/records-max': (
    type: 'key_value',
    props: {
      'title': solid(120),
      'rows': [
        for (var i = 0; i < 4; i++)
          {
            'label': solid(60),
            'value': solid(200),
            'emphasis': i == 0,
            'copy': true,
            'masked': i.isOdd,
            'tone': 'error',
            'range_label': solid(40),
          }
      ],
    }
  ),
  'info_card/records-max': (
    type: 'info_card',
    props: {
      'icon': 'person',
      'avatar_url': broken,
      'title': solid(120),
      'meta': solid(80),
      'body': words(600),
      'actions': [
        for (final action in [
          {'kind': 'call', 'phone': '+31 20 555 0134 0000 0000 0000 0', 'label': solid(40)},
          {'kind': 'copy', 'text': solid(500)},
          {'kind': 'add_to_calendar', 'title': solid(120), 'starts_at': '2026-10-14T10:00:00+02:00'},
        ])
          {'label': solid(40), 'icon': 'phone', 'action': action}
      ],
    }
  ),
  'info_card/document': (
    type: 'info_card',
    props: {
      'file_type': 'doc',
      'title': solid(120),
      'meta': solid(80),
      'cta': {'label': solid(60), 'action': act},
    }
  ),
  'order_tracker/records-max': (
    type: 'order_tracker',
    props: {
      'title': solid(120),
      'steps': [
        for (var i = 0; i < 12; i++)
          {
            'label': solid(80),
            'status': i < 5 ? 'done' : (i == 5 ? 'current' : 'pending'),
            'timestamp': solid(40),
            'note': words(160),
          }
      ],
      'eta': '2026-10-09T14:20:00+02:00',
      'eta_label': solid(40),
      'as_of': '2026-10-09T14:02:00+02:00',
      'reference': {'label': solid(30), 'value': solid(40)},
    }
  ),
  'stat_group/as-of': (
    type: 'stat_group',
    props: {
      'items': [
        for (var i = 0; i < 6; i++) {'label': solid(60), 'value': solid(30)}
      ],
      'as_of': '2026-10-09T14:02:00+02:00',
    }
  ),
  'booking_card/records-max': (
    type: 'booking_card',
    props: {
      'title': solid(120),
      'subtitle': solid(160),
      'when': solid(80),
      'where': solid(120),
      'starts_at': '2030-01-01T10:00:00+00:00',
      'status': {'label': solid(24), 'tone': 'success'},
      'reference': {'label': solid(30), 'value': solid(40)},
      'lines': [
        for (var i = 0; i < 8; i++) {'label': solid(40), 'value': solid(120)}
      ],
      'cta': {
        'label': solid(60),
        'action': {
          'kind': 'add_to_calendar',
          'title': solid(120),
          'starts_at': '2030-01-01T10:00:00+00:00',
          'ends_at': '2030-01-01T11:00:00+00:00',
          'location': solid(160),
          'notes': solid(500),
        },
      },
    }
  ),

  // ---- article_card
  'article_card/min': (
    type: 'article_card',
    props: {'title': 'a', 'excerpt': 'b', 'source': 'c'}
  ),
  'article_card/max': (
    type: 'article_card',
    props: {
      'title': solid(120),
      'excerpt': words(400),
      'source': solid(80),
      'updated': solid(40),
      'cta': {'label': solid(60), 'action': act},
    }
  ),
  'article_card/prose-max': (
    type: 'article_card',
    props: {
      'title': words(120),
      'excerpt': words(400),
      'source': words(80),
      'updated': words(40),
      'cta': {'label': words(60), 'action': act},
    }
  ),
  'article_card/rtl': (
    type: 'article_card',
    props: {
      'title': rtl(120),
      'excerpt': rtl(400),
      'source': rtl(80),
      'updated': rtl(40),
      'cta': {'label': rtl(60), 'action': act},
    }
  ),

  // ---- status_banner
  'status_banner/min': (
    type: 'status_banner',
    props: {'tone': 'info', 'title': 'a'}
  ),
  'status_banner/max': (
    type: 'status_banner',
    props: {'tone': 'error', 'title': solid(120), 'body': words(400)}
  ),

  // ---- progress
  'progress/min': (
    type: 'progress',
    props: {
      'items': [
        {'label': 'a', 'value': 0, 'max': 1}
      ]
    }
  ),
  'progress/max': (
    type: 'progress',
    props: {
      'title': solid(120),
      'items': [
        for (var i = 0; i < 6; i++)
          {
            'label': solid(60),
            'value': 12.5,
            'max': 20,
            'value_label': solid(40),
            'caption': solid(120),
          }
      ],
    }
  ),
  'progress/over-max': (
    type: 'progress',
    props: {
      'items': [
        {'label': solid(60), 'value': 1e9, 'max': 0.0001},
        {'label': 'zero', 'value': 0, 'max': 1e9},
        {'label': 'tiny', 'value': 0.00001, 'max': 0.00002},
        {'label': 'negative', 'value': -50, 'max': 10},
        {'label': 'fractional', 'value': 1.3333333, 'max': 3.7777777},
        {'label': 'huge', 'value': 1e18, 'max': 1e18},
      ],
    }
  ),

  // ---- catalog wave 6 (`design/CATALOG-B6.md`): every new prop at its
  // maximum, beside the props it shares a line with at theirs.
  'product_cards/chips-max': (
    type: 'product_cards',
    props: {
      'items': [
        for (var i = 0; i < 10; i++)
          {
            'title': solid(120),
            'subtitle': solid(200),
            'price': solid(30),
            'badge': solid(30),
            'image_url': broken,
            'action': act,
            'chips': [for (var c = 0; c < 4; c++) solid(20)],
          }
      ]
    }
  ),
  'product_cards/chips-rtl': (
    type: 'product_cards',
    props: {
      'items': [
        for (var i = 0; i < 3; i++)
          {
            'title': rtl(120),
            'price': rtl(30),
            'chips': [for (var c = 0; c < 4; c++) rtl(20)],
          }
      ]
    }
  ),
  'variant_picker/swatches-max': (
    type: 'variant_picker',
    props: {
      'title': solid(120),
      'label': solid(60),
      'style': 'swatches',
      'options': [
        for (var i = 0; i < 24; i++)
          {
            'id': '${solid(60)}$i',
            'label': solid(24),
            'available': i % 3 != 0,
            // Every fourth has no swatch and falls back to a chip.
            if (i % 4 != 0) 'swatch_hex': i.isEven ? '#FFFFFF' : '#0A0A0A',
          }
      ],
      'selected_id': '${solid(60)}1',
    }
  ),
  'variant_picker/images-max': (
    type: 'variant_picker',
    props: {
      'title': solid(120),
      'label': solid(60),
      'style': 'images',
      'options': [
        for (var i = 0; i < 24; i++)
          {
            'id': '${solid(60)}$i',
            'label': solid(24),
            'available': i % 3 != 0,
            if (i % 4 != 0) 'image_url': broken,
          }
      ],
      'selected_id': '${solid(60)}1',
    }
  ),
  'variant_picker/swatches-rtl': (
    type: 'variant_picker',
    props: {
      'label': rtl(60),
      'style': 'swatches',
      'options': [
        for (var i = 0; i < 6; i++) {'id': 'o$i', 'label': rtl(24), 'swatch_hex': '#3A5F8C'}
      ],
      'selected_id': 'o2',
    }
  ),
  'key_points/tones-max': (
    type: 'key_points',
    props: {
      'items': [
        for (var i = 0; i < 8; i++)
          {
            'icon': i == 7 ? solid(40) : 'check',
            'title': solid(80),
            'body': words(240),
            'tone': ['positive', 'negative', 'neutral'][i % 3],
          }
      ],
    }
  ),
  'media_gallery/grid-captions-max': (
    type: 'media_gallery',
    props: {
      'images': [
        for (var i = 0; i < 12; i++)
          {'url': broken, 'alt': solid(160), 'caption': solid(120), 'video_url': 'https://example.com/v$i.mp4'}
      ],
      'layout': 'grid',
    }
  ),
  'media_gallery/carousel-captions-max': (
    type: 'media_gallery',
    props: {
      'images': [
        for (var i = 0; i < 12; i++)
          {
            'url': broken,
            'alt': solid(160),
            if (i.isOdd) 'caption': rtl(120),
            if (i.isEven) 'video_url': 'https://example.com/v$i.mp4',
          }
      ],
      'layout': 'carousel',
    }
  ),
  'receipt/notes-max': (
    type: 'receipt',
    props: {
      'title': solid(120),
      'lines': [
        for (var i = 0; i < 20; i++)
          {'label': solid(120), 'amount': solid(30), 'note': solid(80), 'delta': solid(20)}
      ],
      'subtotal': solid(30),
      'tax': solid(30),
      'total': solid(30),
      'currency': solid(8),
    }
  ),
  'receipt/notes-rtl': (
    type: 'receipt',
    props: {
      'lines': [
        for (var i = 0; i < 4; i++)
          {'label': rtl(120), 'amount': rtl(30), if (i.isEven) 'note': rtl(80), if (i.isOdd) 'delta': rtl(20)}
      ],
      'total': rtl(30),
    }
  ),
  'progress/ring-max': (
    type: 'progress',
    props: {
      'title': solid(120),
      'style': 'ring',
      'items': [
        for (var i = 0; i < 3; i++)
          {'label': solid(60), 'value': 1e18, 'max': 0.0001, 'value_label': solid(40), 'caption': solid(120)}
      ],
    }
  ),
  'progress/ring-one': (
    type: 'progress',
    props: {
      'style': 'ring',
      'items': [
        {'label': 'a', 'value': -5, 'max': 10},
      ],
    }
  ),
  'progress/ring-six': (
    type: 'progress',
    props: {
      'style': 'ring',
      'items': [
        for (var i = 0; i < 6; i++)
          {'label': solid(60), 'value': i * 4, 'max': 20, 'value_label': solid(40), 'caption': solid(120)}
      ],
    }
  ),
  for (final kind in ['area', 'hbar', 'stacked_bar']) ...{
    'chart/$kind-max': (
      type: 'chart',
      props: {
        'kind': kind,
        'title': words(120),
        'labels': [for (var i = 0; i < 24; i++) solid(40)],
        'series': [
          for (var s = 0; s < 3; s++)
            {
              'name': solid(60),
              'data': [for (var i = 0; i < 24; i++) (i - 12) * 1e6]
            }
        ],
        'unit': solid(12),
      }
    ),
    'chart/$kind-single': (
      type: 'chart',
      props: {
        'kind': kind,
        'labels': [for (var i = 0; i < 24; i++) rtl(40)],
        'series': [
          {
            'data': [for (var i = 0; i < 24; i++) i * 1e15]
          }
        ],
        'unit': solid(12),
      }
    ),
    'chart/$kind-one-point': (
      type: 'chart',
      props: {
        'kind': kind,
        'labels': ['a'],
        'series': [
          {'data': [0]},
          {'data': [0]},
        ],
      }
    ),
  },
  'code/min': (type: 'code', props: {'code': 'a'}),
  'code/max': (
    type: 'code',
    props: {
      'language': solid(24),
      // One line 400 characters long, then short ones to the 4000 allowed.
      'code': '${solid(400)}\n${List.filled(120, solid(34)).join('\n')}'.substring(0, 4000),
      'caption': solid(120),
    }
  ),
  'code/rtl': (
    type: 'code',
    props: {'language': rtl(24), 'code': rtl(4000), 'caption': rtl(120)}
  ),
};

void main() {
  setUpAll(() => RendelMapEngine.current = const _Ground());
  tearDownAll(() => RendelMapEngine.current = const MapLibreEngine());

  final dispatch = RendelDispatcher(
    onAction: (_) async => true,
    onSubmitForm: (_, __) async => RendelSubmitOutcome.sent,
    canHandle: (_) => true,
  );

  WireBlock block(String type, Map<String, dynamic> props, {bool ready = true}) =>
      WireBlock(
        id: 'b_$type',
        type: type,
        fallbackText: 'A $type block.',
        props: Map<String, dynamic>.from(props),
      )..ready = ready;

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    double width = 320,
    double scale = 1.0,
    TextDirection direction = TextDirection.ltr,
    RendelTheme? theme,
  }) async {
    tester.view.physicalSize = Size(width * 3, 4000 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(
          size: Size(width, 4000),
          devicePixelRatio: 3,
          textScaler: TextScaler.linear(scale),
        ),
        // Inside the MaterialApp, not outside it. A MaterialApp installs its
        // own Directionality from its locale, so an outer one is overridden
        // and every RTL fixture silently rendered LTR — an entire environment
        // this suite believed it was covering.
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Directionality(
            textDirection: direction,
            child: RendelThemeScope(
              theme: theme ?? RendelTheme.paper(),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
  }

  // The header's promise, held: each fixture against the protocol's own
  // wire schema, so the nastiest input here is one the server would send.
  test('every fixture satisfies the wire schema', () {
    for (final f in fixtures.entries) {
      final errors = wireBlockErrors({
        'id': 'b_${f.value.type}',
        'type': f.value.type,
        'fallback_text': 'A ${f.value.type} block.',
        'props': f.value.props,
      });
      expect(errors, isEmpty, reason: f.key);
    }
  });

  final envs = <String, ({double width, double scale, TextDirection dir})>{
    '320@1.0': (width: 320, scale: 1.0, dir: TextDirection.ltr),
    '320@2.0': (width: 320, scale: 2.0, dir: TextDirection.ltr),
    '320@1.0-rtl': (width: 320, scale: 1.0, dir: TextDirection.rtl),
    '390@2.0': (width: 390, scale: 2.0, dir: TextDirection.ltr),
  };

  for (final env in envs.entries) {
    group('env ${env.key}', () {
      for (final f in fixtures.entries) {
        testWidgets(f.key, (tester) async {
          await pump(
            tester,
            Builder(
              builder: (c) => ComponentRegistry.build(
                c,
                block(f.value.type, f.value.props),
                dispatch,
              ),
            ),
            width: env.value.width,
            scale: env.value.scale,
            direction: env.value.dir,
          );
          expect(tester.takeException(), isNull, reason: '${f.key} @ ${env.key}');
        });
      }

      // The looks a customer can publish (`theme.style`), at the same inputs.
      // An outline is a point of border on every side of every plate, and the
      // other two lay their block out from scratch.
      for (final look in <String, (Map<String, String>, String?)>{
        'outlined': ({'card': 'outlined', 'button': 'outlined'}, null),
        'row': ({'product': 'row'}, 'product_cards'),
        'photo': ({'product': 'photo'}, 'product_cards'),
        'horizontal': ({'tracker': 'horizontal'}, 'order_tracker'),
        'bar': ({'tracker': 'bar'}, 'order_tracker'),
      }.entries) {
        final (style, only) = look.value;
        final theme = RendelRemoteConfig.tryParse(
          jsonEncode({
            'config': {
              'theme': {'style': style},
            },
          }),
        )!
            .applyTo(RendelTheme.paper());
        for (final f in fixtures.entries) {
          if (only != null && f.value.type != only) continue;
          testWidgets('${look.key}/${f.key}', (tester) async {
            await pump(
              tester,
              Builder(
                builder: (c) => ComponentRegistry.build(
                  c,
                  block(f.value.type, f.value.props),
                  dispatch,
                ),
              ),
              width: env.value.width,
              scale: env.value.scale,
              direction: env.value.dir,
              theme: theme,
            );
            expect(tester.takeException(), isNull,
                reason: '${look.key} ${f.key} @ ${env.key}');
          });
        }
      }

      // skeletons: every registered type plus an unregistered one
      for (final type in [...ComponentRegistry.registeredTypes, 'brand_new_type']) {
        testWidgets('skeleton/$type', (tester) async {
          await pump(
            tester,
            Builder(
              builder: (c) => ComponentRegistry.build(
                c,
                block(type, {}, ready: false),
                dispatch,
              ),
            ),
            width: env.value.width,
            scale: env.value.scale,
            direction: env.value.dir,
          );
          expect(tester.takeException(), isNull, reason: 'skeleton $type @ ${env.key}');
        });
      }

      testWidgets('unknown-type fallback', (tester) async {
        await pump(
          tester,
          Builder(
            builder: (c) => ComponentRegistry.build(
              c,
              block('brand_new_type', {'anything': 1}),
              dispatch,
            ),
          ),
          width: env.value.width,
          scale: env.value.scale,
          direction: env.value.dir,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('unknown-type fallback, empty fallback_text', (tester) async {
        final b = WireBlock(
          id: 'x',
          type: 'brand_new_type',
          fallbackText: '',
          props: {},
        )..ready = true;
        await pump(
          tester,
          Builder(builder: (c) => ComponentRegistry.build(c, b, dispatch)),
          width: env.value.width,
          scale: env.value.scale,
          direction: env.value.dir,
        );
        expect(tester.takeException(), isNull);
      });
    });
  }
}
