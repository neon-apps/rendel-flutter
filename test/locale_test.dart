import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/core/locale.dart';
import 'package:rendel/src/engine/conversation_controller.dart';
import 'package:rendel/src/protocol/protocol.dart';
import 'package:rendel/src/transport/api_client.dart';

/// Which language the copilot answers in, decided on this side of the wire.
///
/// `client.locale` is the only thing the server has to go on: `prompt.ts`
/// turns it into the reply-language line and `orchestrator.ts` has always used
/// it to pick a localized confirmation sentence. Both of those are dead code
/// if the handshake omits the field or sends an empty string, which is exactly
/// what a host passing `RendelConfig(locale: '')` — a language picker with nothing
/// selected yet — would otherwise produce.
class _ScriptedApi extends RendelApiClient {
  _ScriptedApi()
      : super(
          appKey: 'nc_pk_test_x',
          deviceId: 'd',
          config: const RendelConfig(),
        );

  final List<Map<String, dynamic>> sent = [];

  @override
  Stream<RendelWireEvent> chat(Map<String, dynamic> body) async* {
    sent.add(body);
    yield const TurnStart(conversationId: 'c1', messageId: 'm1', model: 'test');
    yield const TurnEnd(status: 'completed', pending: []);
  }
}

void main() {
  _spoken();

  /// The tag one turn actually put on the wire.
  Future<String?> sentLocale(String? hostLocale) async {
    final api = _ScriptedApi();
    final c = ConversationController(
      api: api,
      actions: const {},
      sdkVersion: 'flutter/test',
      locale: hostLocale,
    );
    await c.send('hi').timeout(const Duration(seconds: 5));
    c.dispose();
    return (api.sent.single['client'] as Map<String, dynamic>)['locale']
        as String?;
  }

  /// What the fallback has to land on, read from the same place the SDK reads
  /// it. `TestPlatformDispatcher.localeTestValue` cannot stand in here: it
  /// overrides the binding's dispatcher, and the handshake asks
  /// `PlatformDispatcher.instance` — the real one — directly.
  final deviceTag = PlatformDispatcher.instance.locale.toLanguageTag();

  test('the host\'s language wins over the device\'s', () async {
    // The case the field exists for: a Turkish app on an English phone.
    expect(await sentLocale('tr-TR'), 'tr-TR');
    expect(await sentLocale('pt-BR'), 'pt-BR');
    expect(await sentLocale('de'), 'de');
  });

  test('the device answers when the host has not chosen', () async {
    expect(await sentLocale(null), deviceTag);
    expect(deviceTag, isNotEmpty);
  });

  /// A host reading its own settings gets `''` before the user has picked, and
  /// a tag with a stray space from a config file. Neither is a language, and
  /// sending either would cost the turn the device's perfectly good answer —
  /// `Intl.DisplayNames` cannot name `' tr-TR'`, so the server would say
  /// nothing at all about the reply language.
  test('blank and padded tags do not reach the wire', () async {
    expect(await sentLocale(''), deviceTag);
    expect(await sentLocale('   '), deviceTag);
    expect(await sentLocale('  tr-TR  '), 'tr-TR');
  });

  test('every turn carries the field, however short', () async {
    final api = _ScriptedApi();
    final c = ConversationController(
      api: api,
      actions: const {},
      sdkVersion: 'flutter/test',
    );
    await c.send('one').timeout(const Duration(seconds: 5));
    await c.send('two').timeout(const Duration(seconds: 5));
    c.dispose();

    for (final body in api.sent) {
      final client = body['client'] as Map<String, dynamic>;
      expect(client['locale'], isA<String>());
      expect(client['locale'] as String, isNotEmpty);
    }
  });

  /// The host sets this in its own Dart and nothing else can move it. A
  /// `copyWith` that dropped it would put the copilot back on the device's
  /// locale the first time the console published anything at all.
  test('a published config cannot move the language', () {
    const config = RendelConfig(locale: 'tr-TR');
    expect(config.copyWith(assistantName: 'Yardimci').locale, 'tr-TR');
    expect(const RendelConfig().locale, isNull);
  });

  /// ——————————————————— the SDK's own words ———————————————————
  ///
  /// The answer arrives in the user's language and then the two buttons under
  /// it said "Confirm" and "Go back". `RendelStrings` could always fix that and
  /// every host had to do it by hand, in a field most never found.
  group('the SDK speaks the same language as the answer', () {
    test('a shipped language replaces the English defaults', () {
      expect(RendelStrings.forLocale('tr').confirm, 'Onayla');
      expect(RendelStrings.forLocale('tr').goBack, 'Vazgeç');
      expect(RendelStrings.forLocale('de').confirm, 'Bestätigen');
      expect(RendelStrings.forLocale('ar').confirm, 'تأكيد');
    });

    test('a region falls back to its language', () {
      expect(RendelStrings.forLocale('tr-TR').confirm, 'Onayla');
      expect(RendelStrings.forLocale('de-AT').confirm, 'Bestätigen');
      expect(RendelStrings.forLocale('es-419').confirm, 'Confirmar');
      // Underscores, because a host reading a platform locale gets `tr_TR`.
      expect(RendelStrings.forLocale('TR_tr').confirm, 'Onayla');
    });

    /// English is the fallback and always was. A language the SDK does not
    /// carry is not a broken copilot, it is the copilot people have today.
    test('an unshipped language stays English', () {
      expect(RendelStrings.forLocale('ja').confirm, const RendelStrings().confirm);
      expect(RendelStrings.forLocale('zz-ZZ').confirm, 'Confirm');
      expect(RendelStrings.forLocale(null).confirm, 'Confirm');
      expect(RendelStrings.forLocale('  ').confirm, 'Confirm');
    });

    /// The whole set moves together. A confirm card drawing its button from
    /// Turkish and its warning from English is the bug this replaces, not a
    /// smaller version of it.
    test('every field moves, not just the button', () {
      final tr = RendelStrings.forLocale('tr');
      const en = RendelStrings();
      expect(tr.irreversible, isNot(en.irreversible));
      expect(tr.statusThinking, isNot(en.statusThinking));
      expect(tr.composerHint, isNot(en.composerHint));
      expect(tr.retry, isNot(en.retry));
      expect(tr.noAnswer, isNot(en.noAnswer));
      expect(tr.dictationFailed, isNot(en.dictationFailed));
      expect(tr.turnFailed, isNot(en.turnFailed));
      expect(tr.copilotStalled, isNot(en.copilotStalled));
      expect(tr.attachFailed, isNot(en.attachFailed));
      expect(tr.streamDropped, isNot(en.streamDropped));
      expect(tr.required, isNot(en.required));
      expect(tr.send, isNot(en.send));
      expect(tr.testMode, isNot(en.testMode));
      expect(tr.total, isNot(en.total));
      expect(tr.speak, isNot(en.speak));
      expect(tr.yes, isNot(en.yes));
      expect(tr.no, isNot(en.no));
    });

    test('copyWith changes one word and keeps the language', () {
      final custom =
          RendelStrings.forLocale('tr').copyWith(confirm: 'Transferi onayla');
      expect(custom.confirm, 'Transferi onayla');
      expect(custom.goBack, 'Vazgeç', reason: 'the rest is still Turkish');
      expect(custom.irreversible, 'Bu geri alınamaz');
    });

    /// Null means "answer in the language you are answering in", and an
    /// explicitly passed set means "I own these words" — including English in
    /// an app whose locale says otherwise.
    test('the host can still take the words back', () {
      expect(const RendelConfig().strings, isNull);
      expect(const RendelConfig(locale: 'tr-TR').strings, isNull);
      const owned = RendelConfig(locale: 'tr-TR', strings: RendelStrings());
      expect(owned.strings?.confirm, 'Confirm');
    });
  });
}

/// The language the SDK's own words come out in, once an app has named the
/// ones it is willing to speak.
///
/// It used to come straight off the device, which put a Turkish composer
/// prompt and an English empty state on the same screen: two languages, and no
/// way for the reader to tell which was the mistake.
void _spoken() {
  group('resolveSpokenLocale', () {
    test('leaves the device alone when no languages are named', () {
      expect(resolveSpokenLocale('de-DE', const []), 'de-DE');
    });

    test('keeps the device language when it is one of them', () {
      expect(resolveSpokenLocale('ru-RU', const ['tr', 'ru']), 'ru-RU');
    });

    test('falls to the first named one otherwise', () {
      expect(resolveSpokenLocale('th-TH', const ['tr', 'en']), 'tr');
    });

    test('matches on the subtag, so a region does not miss the list', () {
      expect(resolveSpokenLocale('pt-BR', const ['pt']), 'pt-BR');
    });
  });
}
