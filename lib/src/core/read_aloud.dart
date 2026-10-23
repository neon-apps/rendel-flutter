import 'dart:async';
import 'dart:io' show Directory, File;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, ValueNotifier, defaultTargetPlatform, kIsWeb;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../protocol/protocol.dart' show WireBlock;
import 'log.dart';

/// What is read aloud of an answer: its opening paragraph, as words.
///
/// An answer page opens with a sentence that says the answer ("Bugün hava
/// ılık ama akşama doğru yağmur var") and goes on into cards and detail. The
/// voice says that sentence, as Monogram's does (Tuna 2026-10-23), not the
/// page. Null when the answer opens with no prose to say.
String? spokenLead(List<WireBlock> blocks) {
  for (final block in blocks) {
    if (block.type != 'text') continue;
    final markdown = block.props['markdown'];
    if (markdown is! String) continue;
    final paragraph = markdown
        .split(RegExp(r'\n\s*\n'))
        .map(_plain)
        .firstWhere((p) => p.isNotEmpty, orElse: () => '');
    if (paragraph.isEmpty) continue;
    return _short(paragraph);
  }
  return null;
}

/// Markdown as it is heard: no marks, links by their words, a list as a line.
String _plain(String markdown) => markdown
    .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), '')
    .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (m) => m[1]!)
    .replaceAll(RegExp(r'https?://\S+'), '')
    .replaceAll(RegExp(r'^\s{0,3}(#{1,6}|>|[-*+]|\d+[.)])\s+', multiLine: true), '')
    .replaceAll(RegExp(r'\*\*|__|==|~~|`|\*'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Two sentences at most, and never a minute of speech.
String _short(String text) {
  final sentences = RegExp(r'[^.!?…]+[.!?…]+["”’)]*|[^.!?…]+$').allMatches(text).map((m) => m[0]!.trim());
  var said = '';
  for (final sentence in sentences.take(2)) {
    if (said.isNotEmpty && said.length + sentence.length > 280) break;
    said = said.isEmpty ? sentence : '$said $sentence';
  }
  if (said.length <= 320) return said;
  final cut = said.substring(0, 320);
  final space = cut.lastIndexOf(' ');
  return '${space > 200 ? cut.substring(0, space) : cut}…';
}

/// The SDK's own voice: OpenAI's natural one, streamed from `/v1/speech`
/// when the server sends a token for the answer, and the phone's own speech
/// engine (`flutter_tts`, a woman's voice where the phone names one) when it
/// does not or the stream fails.
///
/// The phone's voice came first and read as robotic (Tuna 2026-10-23).
/// Whether it reads at all is the person's, remembered between launches: the
/// header's speaker turns it off.
class RendelVoice {
  RendelVoice();

  static const _key = 'rendel_read_aloud';

  /// Whether answers are read aloud. On until the person turns it off.
  final on = ValueNotifier<bool>(true);

  FlutterTts? _tts;
  AudioPlayer? _player;

  /// The last answer's voice on disk, removed when the next one is written.
  File? _spoken;

  /// Bumped by every speak and stop, so a stream that loads after the person
  /// moved on is not played over them.
  var _turn = 0;
  final _voiceFor = <String, Map<String, String>?>{};
  var _loaded = false;

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final saved = (await SharedPreferences.getInstance()).getBool(_key);
      if (saved != null) on.value = saved;
    } catch (_) {
      // No storage: on, as for anyone who never touched the speaker.
    }
  }

  /// Read before the first answer, so a person who turned it off is not
  /// read to once at the start of every launch.
  Future<void> prepare() => _load();

  Future<void> setOn(bool value) async {
    on.value = value;
    if (!value) await stop();
    try {
      await (await SharedPreferences.getInstance()).setBool(_key, value);
    } catch (_) {}
  }

  /// Says [text] in [locale] (`tr`, `en-US`…), over anything still being said:
  /// from [url] in the natural voice when there is one, else on the phone.
  Future<void> speak(String text, String locale, {String? url}) async {
    await _load();
    if (!on.value || kIsWeb) return;
    await stop();
    final turn = _turn;
    if (url != null) {
      try {
        // Fetched whole, then played from a file. Played from the URL, the
        // server's stream reached a real iPhone (both requests 200) and was
        // never heard: AVPlayer wants byte ranges and a length, a stream has
        // neither, and audioplayers cannot play bytes on iOS (Tuna
        // 2026-10-23). One request, too, where AVPlayer made two and each
        // was a voice paid for.
        final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
        if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
          throw StateError('the voice answered ${response.statusCode}');
        }
        if (turn != _turn) return;
        final file = File('${Directory.systemTemp.path}/rendel_answer_$turn.mp3');
        await file.writeAsBytes(response.bodyBytes, flush: true);
        _spoken?.delete().ignore();
        _spoken = file;
        if (turn != _turn) return;
        final player = _player ??= AudioPlayer();
        await player
            .play(
              DeviceFileSource(file.path, mimeType: 'audio/mpeg'),
              // Heard with the silent switch on, other sound ducked under it
              // (the lesson of 0.57.1).
              ctx: AudioContext(
                iOS: AudioContextIOS(
                  category: AVAudioSessionCategory.playback,
                  options: const {AVAudioSessionOptions.duckOthers},
                ),
                android: const AudioContextAndroid(
                  contentType: AndroidContentType.speech,
                  // The media volume, the one people turn up to hear.
                  usageType: AndroidUsageType.media,
                  audioFocus: AndroidAudioFocus.gainTransientMayDuck,
                ),
              ),
            )
            .timeout(const Duration(seconds: 10));
        // Stopped while it was still loading: it must not start after all.
        if (turn != _turn) await player.stop();
        return;
      } catch (err) {
        RendelLog.warn('read_aloud_stream_failed', 'the natural voice did not play, reading on the phone: $err');
        try {
          await _player?.stop();
        } catch (_) {}
        if (turn != _turn || !on.value) return;
      }
    }
    try {
      final tts = _tts ??= await _engine();
      await tts.stop();
      if (_iOS) {
        // Playback, set on every answer: ambient was silenced by the phone's
        // silent switch, and a real iPhone read nothing (Tuna 2026-10-23, on
        // Protein Ocean; the simulator has no switch). Set each time because
        // the microphone puts back whatever category it found and switches
        // the session off. Others' audio is ducked under the voice, and
        // flutter_tts hands it back when the voice is done.
        await tts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playback,
          const [IosTextToSpeechAudioCategoryOptions.duckOthers],
          IosTextToSpeechAudioMode.spokenAudio,
        );
        await tts.setSharedInstance(true);
      }
      final lang = locale.replaceAll('_', '-');
      await tts.setLanguage(lang);
      final voice = _voiceFor.containsKey(lang) ? _voiceFor[lang] : (_voiceFor[lang] = await _woman(tts, lang));
      if (voice != null) await tts.setVoice(voice);
      await tts.speak(text);
    } catch (err) {
      RendelLog.warn('read_aloud_failed', 'could not read the answer aloud: $err');
    }
  }

  Future<void> stop() async {
    _turn++;
    try {
      await _player?.stop();
    } catch (_) {}
    try {
      await _tts?.stop();
    } catch (_) {}
  }

  static bool get _iOS => defaultTargetPlatform == TargetPlatform.iOS;

  static const _home = {'en': 'en-us', 'es': 'es-es', 'fr': 'fr-fr', 'de': 'de-de', 'pt': 'pt-br', 'it': 'it-it', 'ar': 'ar-sa', 'tr': 'tr-tr'};

  Future<FlutterTts> _engine() async {
    final tts = FlutterTts();
    // The engines' own "normal" is brisk on iOS; this is a calm reading pace.
    await tts.setSpeechRate(_iOS ? 0.5 : 0.95);
    return tts;
  }

  /// A woman's voice for [lang], the best the phone has. iOS names each
  /// voice's gender; Android does not, and its default voice for a language
  /// is a woman's for every language Google ships, so it keeps that unless a
  /// voice says it is female.
  Future<Map<String, String>?> _woman(FlutterTts tts, String lang) async {
    final all = await tts.getVoices;
    if (all is! List) return null;
    final asked = lang.toLowerCase();
    final want = asked.split('-').first;
    // The server names `en`; an American voice is the one people expect.
    final home = asked.contains('-') ? asked : (_home[want] ?? asked);
    final voices = all
        .whereType<Map>()
        .map((v) => v.map((key, value) => MapEntry('$key', '$value')))
        .where((v) => (v['locale'] ?? '').toLowerCase().replaceAll('_', '-').split('-').first == want)
        .where((v) => (v['gender'] ?? '').toLowerCase() == 'female' || (v['name'] ?? '').toLowerCase().contains('female'))
        .toList();
    if (voices.isEmpty) return null;
    // The home region first (en-US over en-AU), then the best quality, and
    // never a novelty voice (Eloquence's Grandma, Bubbles) over a real one.
    int rank(Map<String, String> v) =>
        ((v['locale'] ?? '').toLowerCase().replaceAll('_', '-') == home ? 10 : 0) +
        switch ((v['quality'] ?? '').toLowerCase()) { 'premium' => 2, 'enhanced' => 1, _ => 0 } -
        (RegExp(r'eloquence|speech\.synthesis').hasMatch(v['identifier'] ?? '') ? 5 : 0);
    voices.sort((a, b) => rank(b) - rank(a));
    final pick = voices.first;
    return {'name': pick['name'] ?? '', 'locale': pick['locale'] ?? lang, if (pick['identifier'] != null) 'identifier': pick['identifier']!};
  }
}
