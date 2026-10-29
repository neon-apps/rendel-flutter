import 'dart:async';
import 'dart:io' show Directory, File;
import 'dart:typed_data' show Uint8List;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, ValueNotifier, defaultTargetPlatform, kIsWeb, visibleForTesting;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../protocol/protocol.dart' show WireBlock;
import 'log.dart';
import 'pcm_sound.dart';
import 'platform.dart';

/// What is read aloud of an answer: its opening paragraph, as words.
///
/// An answer page opens with a sentence that says the answer ("Bugün hava
/// ılık ama akşama doğru yağmur var") and goes on into cards and detail. The
/// voice says that sentence, as Monogram's does (Tuna 2026-10-23), not the
/// page. Null when the answer opens with no prose to say. A date is said in
/// full in [lang] ("Mon 12 Oct" is "Monday 12 October"), as the web SDK's
/// `spokenLead` says it.
String? spokenLead(List<WireBlock> blocks, {String lang = ''}) {
  for (final block in blocks) {
    if (block.type != 'text') continue;
    final markdown = block.props['markdown'];
    if (markdown is! String) continue;
    final paragraph = markdown
        .split(RegExp(r'\n\s*\n'))
        .map(_plain)
        .firstWhere((p) => p.isNotEmpty, orElse: () => '');
    if (paragraph.isEmpty) continue;
    return _short(spokenDates(paragraph, lang));
  }
  return null;
}

/// Weekdays and months as a page shortens them, and the words a voice says
/// for them, in the SDK's languages: (weekdays, months). A month that is
/// never shortened is listed as itself, so a weekday before it is known.
/// Arabic writes them in full. The web SDK's `DATE_WORDS`.
const _dateWords = <String, (Map<String, String>, Map<String, String>)>{
  'en': (
    {'Mon': 'Monday', 'Tue': 'Tuesday', 'Tues': 'Tuesday', 'Wed': 'Wednesday', 'Thu': 'Thursday', 'Thur': 'Thursday', 'Thurs': 'Thursday', 'Fri': 'Friday', 'Sat': 'Saturday', 'Sun': 'Sunday'},
    {'Jan': 'January', 'Feb': 'February', 'Mar': 'March', 'Apr': 'April', 'May': 'May', 'Jun': 'June', 'Jul': 'July', 'Aug': 'August', 'Sep': 'September', 'Sept': 'September', 'Oct': 'October', 'Nov': 'November', 'Dec': 'December'},
  ),
  'tr': (
    {'Pzt': 'Pazartesi', 'Sal': 'Salı', 'Çar': 'Çarşamba', 'Per': 'Perşembe', 'Cum': 'Cuma', 'Cmt': 'Cumartesi', 'Paz': 'Pazar'},
    {'Oca': 'Ocak', 'Şub': 'Şubat', 'Mar': 'Mart', 'Nis': 'Nisan', 'May': 'Mayıs', 'Haz': 'Haziran', 'Tem': 'Temmuz', 'Ağu': 'Ağustos', 'Eyl': 'Eylül', 'Eki': 'Ekim', 'Kas': 'Kasım', 'Ara': 'Aralık'},
  ),
  'de': (
    {'Mo': 'Montag', 'Di': 'Dienstag', 'Mi': 'Mittwoch', 'Do': 'Donnerstag', 'Fr': 'Freitag', 'Sa': 'Samstag', 'So': 'Sonntag'},
    {'Jan': 'Januar', 'Feb': 'Februar', 'Mär': 'März', 'Apr': 'April', 'Mai': 'Mai', 'Jun': 'Juni', 'Jul': 'Juli', 'Aug': 'August', 'Sep': 'September', 'Sept': 'September', 'Okt': 'Oktober', 'Nov': 'November', 'Dez': 'Dezember'},
  ),
  'fr': (
    {'lun': 'lundi', 'mar': 'mardi', 'mer': 'mercredi', 'jeu': 'jeudi', 'ven': 'vendredi', 'sam': 'samedi', 'dim': 'dimanche'},
    {'janv': 'janvier', 'févr': 'février', 'mars': 'mars', 'avr': 'avril', 'mai': 'mai', 'juin': 'juin', 'juil': 'juillet', 'août': 'août', 'sept': 'septembre', 'oct': 'octobre', 'nov': 'novembre', 'déc': 'décembre'},
  ),
  'es': (
    {'lun': 'lunes', 'mar': 'martes', 'mié': 'miércoles', 'jue': 'jueves', 'vie': 'viernes', 'sáb': 'sábado', 'dom': 'domingo'},
    {'ene': 'enero', 'feb': 'febrero', 'mar': 'marzo', 'abr': 'abril', 'may': 'mayo', 'jun': 'junio', 'jul': 'julio', 'ago': 'agosto', 'sep': 'septiembre', 'sept': 'septiembre', 'oct': 'octubre', 'nov': 'noviembre', 'dic': 'diciembre'},
  ),
};

String _upperFirst(String word) => word.isEmpty ? word : word[0].toUpperCase() + word.substring(1);

/// [text] with the weekdays and months of its dates said in full, in [lang]:
/// "Pzt 12 Eki" is "Pazartesi 12 Ekim", "Mon, Oct 12" is "Monday, October
/// 12". Only beside a day's number or a month, so "May I" and "the Sun deck"
/// stay as they are. A stop that was the abbreviation's own is dropped, and
/// kept where it also ended the sentence. The web SDK's `spokenDates`.
String spokenDates(String text, String lang) {
  final words = _dateWords[lang.toLowerCase().split(RegExp('[-_]')).first];
  if (words == null) return text;
  final (days, months) = words;
  String alternation(Iterable<String> keys) {
    final all = {for (final k in keys) ...[k, _upperFirst(k)]}.toList()..sort((a, b) => b.length.compareTo(a.length));
    return all.join('|');
  }

  String say(Map<String, String> map, String abbr) {
    final word = map[abbr] ?? map[abbr[0].toLowerCase() + abbr.substring(1)]!;
    return abbr[0] == abbr[0].toLowerCase() ? word : _upperFirst(word);
  }

  final sentenceGoesOn = RegExp(r'^(\s*$|\s+\p{Lu})', unicode: true);
  String Function(Match) swap(Map<String, String> map, String all) => (m) {
        final dot = m[3]!.isNotEmpty && sentenceGoesOn.hasMatch(all.substring(m.end)) ? '.' : '';
        return '${m[1]}${say(map, m[2]!)}$dot';
      };
  final monthAbbr = alternation(months.keys);
  final dayAbbr = alternation(days.keys);
  final monthWord = alternation(months.values);
  RegExp re(String source) => RegExp(source, unicode: true);
  // A month after a day's number: "12 Oct", "12. Okt."; in English before it too: "Oct 12".
  var out = text;
  out = out.replaceAllMapped(re('(\\d\\.?\\s+)($monthAbbr)(\\.?)(?!\\p{L})'), swap(months, out));
  if (lang.toLowerCase().startsWith('en')) {
    out = out.replaceAllMapped(re('(^|[^\\p{L}\\p{N}])($monthAbbr)(\\.?)(?=\\s+\\d)'), swap(months, out));
  }
  // A weekday before a day's number or a month ("Pzt 12", "Mon, October 12"), or after a month ("12 Ekim Pzt").
  out = out.replaceAllMapped(
      re('(^|[^\\p{L}\\p{N}])($dayAbbr)(\\.?)(?=,?\\s+(?:\\d|(?:$monthWord)(?!\\p{L})))'), swap(days, out));
  out = out.replaceAllMapped(re('((?:$monthWord)\\.?,?\\s+)($dayAbbr)(\\.?)(?!\\p{L})'), swap(days, out));
  return out;
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

/// Words that end in a full stop without ending the sentence. Lower case, without the stop.
const _abbreviations = {
  'dr', 'prof', 'doç', 'av', 'op', 'uzm', 'yrd', 'sn', 'vb', 'vs', 'örn', 'bkz', 'no', 'tel', //
  'mah', 'cad', 'sok', 'apt', 'blv', 'şti', 'ltd', 'st', 'mr', 'mrs', 'ms', 'e.g', 'i.e', 'etc',
};

/// The sentences of [text], cut as the server cuts them (`speakable.ts`): at
/// `.!?…` and closing quotes before a space and anything but a lower-case
/// letter, never inside a number ("1.299,90"), after an abbreviation ("Dr.
/// Ayşe") or an initial, or after an ordinal going on in lower case ("3. kat").
List<String> sentences(String text) {
  const ends = '.!?…';
  const closers = '"”’)»\'';
  final lower = RegExp(r'\p{Ll}', unicode: true);
  final out = <String>[];
  var start = 0;
  var i = 0;
  while (i < text.length) {
    if (!ends.contains(text[i])) {
      i++;
      continue;
    }
    final runStart = i;
    while (i < text.length && ends.contains(text[i])) {
      i++;
    }
    while (i < text.length && closers.contains(text[i])) {
      i++;
    }
    final runEnd = i;
    if (runEnd < text.length && text[runEnd].trim().isNotEmpty) continue;
    var next = runEnd;
    while (next < text.length && text[next].trim().isEmpty) {
      next++;
    }
    if (next < text.length && lower.hasMatch(text[next])) continue;
    if (next < text.length && text.substring(runStart, runEnd) == '.') {
      final word = RegExp(r'[\p{L}\p{N}.]+$', unicode: true).firstMatch(text.substring(start, runStart))?.group(0) ?? '';
      final initial = RegExp(r'^\p{Lu}$', unicode: true).hasMatch(word);
      if (initial || _abbreviations.contains(word.toLowerCase())) continue;
    }
    out.add(text.substring(start, runEnd).trim());
    start = runEnd;
  }
  final tail = text.substring(start).trim();
  if (tail.isNotEmpty) out.add(tail);
  return out.where((s) => s.isNotEmpty).toList();
}

/// Two sentences at most, and never a minute of speech.
String _short(String text) {
  var said = '';
  for (final sentence in sentences(text).take(2)) {
    if (said.isNotEmpty && said.length + sentence.length > 280) break;
    said = said.isEmpty ? sentence : '$said $sentence';
  }
  if (said.length <= 320) return said;
  final cut = said.substring(0, 320);
  final space = cut.lastIndexOf(' ');
  return '${space > 200 ? cut.substring(0, space) : cut}…';
}

/// Where the voice's PCM goes: the speaker. One answer at a time.
abstract class RendelPcmOut {
  /// Ready to play mono 16-bit PCM at [sampleRate].
  Future<void> open(int sampleRate);

  /// Queues [s16le] (an even number of bytes) behind what is playing.
  Future<void> feed(Uint8List s16le);

  /// Done when everything fed has been heard.
  Future<void> drained();

  /// Silent at once, what is queued dropped.
  Future<void> close();

  /// Whether the speaker has played everything fed and waits: the voice fell
  /// behind. False where a speaker cannot say.
  bool get dry => false;
}

/// [RendelPcmOut] on the plugin's own PCM output ([RendelPcmSound]).
class _PluginPcmOut implements RendelPcmOut {
  Completer<void>? _drained;
  var _ending = false;

  /// The buffer ran dry after the last feed: the zero event comes once a feed.
  var _dry = false;

  @override
  bool get dry => _dry;

  @override
  Future<void> open(int sampleRate) async {
    // Playback, said outright: the plugin sets the session's category itself.
    await RendelPcmSound.setup(sampleRate: sampleRate, channelCount: 1);
    await RendelPcmSound.setFeedThreshold(sampleRate ~/ 10);
    _drained = Completer<void>();
    _ending = false;
    _dry = false;
    RendelPcmSound.setFeedCallback((remaining) {
      if (remaining > 0) return;
      _dry = true;
      if (_ending && !(_drained?.isCompleted ?? true)) _drained!.complete();
    });
  }

  @override
  Future<void> feed(Uint8List s16le) {
    _dry = false;
    // A copy of exactly these bytes: a piece cut from a longer buffer once
    // went out whole, played its odd byte twice and every sample after it a
    // byte out, as loud static (Tuna 2026-10-26, "cızırtılı").
    return RendelPcmSound.feed(Uint8List.fromList(s16le));
  }

  @override
  Future<void> drained() {
    _ending = true;
    final drained = _drained;
    if (drained == null) return Future.value();
    if (_dry && !drained.isCompleted) drained.complete();
    return drained.future;
  }

  @override
  Future<void> close() async {
    final drained = _drained;
    if (drained != null && !drained.isCompleted) drained.complete();
    RendelPcmSound.setFeedCallback(null);
    await RendelPcmSound.release();
  }
}

/// No first bytes by then, or no next piece before the first sound: silence
/// rather than a voice that is late (Tuna 2026-10-23).
const _firstSound = Duration(seconds: 3);

/// PCM is fed in pieces of at least this many bytes: a tenth of a second at 24 kHz.
const _minPiece = 4800;

/// The first sound waits for this much of the voice. The stream sends a fifth
/// of a second, pauses for up to half a second, then the rest faster than it is
/// spoken (measured on api.rendel.ai, 2026-10-23); begun on the first fifth, the
/// voice broke off inside its first word. A stream that stalls before then
/// stays silent under [_firstSound], as one did for 18 seconds.
const _startHeld = Duration(milliseconds: 500);

/// The SDK's own voice: OpenAI's natural one, streamed from `/v1/speech` as it
/// is made and fed to the speaker as it arrives, so the first words are heard
/// while the rest is still spoken (Tuna 2026-10-23). A server that turns the
/// stream away is played the whole file; a phone's own voice (`flutter_tts`,
/// a woman's where the phone names one) reads only where the server has no
/// voice at all. A voice that made no sound in three seconds stays silent: the
/// answer is on the screen.
///
/// [on] is the header's switch: whether every answer is read by itself as its
/// opening is written, remembered between launches (Tuna 2026-10-26: no
/// Listen button to press first). The last answer read is kept, so reading it
/// again does not fetch it again.
class RendelVoice {
  RendelVoice({RendelPcmOut? out, http.Client Function()? client})
      : _out = out ?? _PluginPcmOut(),
        _client = client ?? http.Client.new;

  /// A new name since 0.59.9: the old switch meant answers to spoken
  /// questions only, so its setting is not carried over to this one.
  static const _key = 'rendel_read_answers';

  /// Whether answers are read by themselves. On until the person turns it off.
  final on = ValueNotifier<bool>(true);

  /// The answer being read, by the key it was read under; null when quiet.
  final playing = ValueNotifier<String?>(null);

  /// When the answer being read was first heard; null until a sound is made.
  DateTime? _heardAt;

  /// How long the answer being read has been heard: zero while its voice is
  /// still on its way, and when nothing is read. The Listen pill shows it.
  Duration get elapsed {
    final at = _heardAt;
    return playing.value == null || at == null ? Duration.zero : DateTime.now().difference(at);
  }

  final RendelPcmOut _out;
  final http.Client Function() _client;
  http.Client? _fetching;

  /// The speaker is open and the audio session ours: only then is either let
  /// go, so a stop never cuts the host app's own sound.
  var _holding = false;

  /// The speaker first: its plugin sets a bare playback category of its own,
  /// so ours, spoken audio with other sound ducked under it, is set after it
  /// and is the one that holds.
  Future<void> _hold(int rate) async {
    await _out.open(rate);
    if (!_holding) {
      _holding = true;
      await RendelPlatform.voiceSession(true);
    }
  }

  Future<void> _release() async {
    if (!_holding) return;
    _holding = false;
    try {
      await _out.close();
    } catch (_) {}
    await RendelPlatform.voiceSession(false);
  }

  /// The last answer's voice as it was played, for a second tap.
  ({String key, int rate, List<Uint8List> pieces})? _kept;

  FlutterTts? _tts;
  AudioPlayer? _player;

  /// The last answer's voice on disk, removed when the next answer is read.
  final _spoken = <File>[];

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
  /// from [url] in the natural voice when the server sent one, else on the
  /// phone. [key] names the answer, for [playing] and a second tap.
  Future<void> speak(String text, String locale, {String? url, String? key}) async {
    await _load();
    if (kIsWeb) return;
    await stop();
    final turn = _turn;
    final name = key ?? text;
    if (url == null) return _phone(text, locale, name, turn);
    playing.value = name;
    final kept = _kept;
    if (kept != null && kept.key == name) {
      await _play(kept.rate, kept.pieces, turn);
      return;
    }
    final next = await _stream(url, name, turn);
    if (turn != _turn) return;
    if (next == _Next.file) {
      await _file(url, turn);
    } else if (next == _Next.silent) {
      _quiet(turn);
    }
  }

  /// The voice as it is made: fetched as PCM, begun once half a second of it
  /// is in, then fed to the speaker in pieces of a tenth of a second or more.
  Future<_Next> _stream(String url, String key, int turn) async {
    final client = _fetching = _client();
    var late = false;
    var opened = false;
    Timer? deadline;
    // The first bytes, and each piece until the first sound, within
    // [_firstSound] of the last: a voice slow to begin is waited for, one that
    // stalls stays silent. Once the speaker is open nothing is cut. The clock
    // used to run from the request to the first feed, and the first answer
    // after a cold start had its half second in at 2.8 s, opened the speaker
    // past 3, and was cut after one breath (Özlem 2026-10-28).
    void waitForMore() {
      deadline?.cancel();
      deadline = Timer(_firstSound, () {
        late = true;
        client.close();
      });
    }

    waitForMore();
    final pieces = <Uint8List>[];
    try {
      final request = http.Request('GET', Uri.parse('$url${url.contains('?') ? '&' : '?'}f=pcm'));
      final response = await client.send(request);
      if (response.statusCode == 404) {
        deadline?.cancel();
        return _Next.file;
      }
      if (response.statusCode != 200) {
        deadline?.cancel();
        return _Next.silent;
      }
      final rate = int.tryParse(RegExp(r'rate=(\d+)').firstMatch(response.headers['content-type'] ?? '')?.group(1) ?? '') ?? 24000;
      final start = rate * 2 * _startHeld.inMilliseconds ~/ 1000;
      var held = Uint8List(0);
      Future<void> play(Uint8List bytes) async {
        if (!opened) {
          opened = true;
          deadline?.cancel();
          await _hold(rate);
          _heardAt = DateTime.now();
        }
        pieces.add(bytes);
        await _out.feed(bytes);
      }

      await for (final chunk in response.stream) {
        if (turn != _turn) return _Next.played;
        if (!opened) waitForMore();
        held = Uint8List.fromList([...held, ...chunk]);
        // Begun on half a second of the voice, and begun again on as much
        // once the speaker ran dry: a stream that fell behind was fed a tenth
        // of a second at a time and heard as a crackle (Özlem 2026-10-28, a
        // 288 ms hole mid-word on a recording), so a stall is one pause.
        if (held.length >= (!opened || _out.dry ? start : _minPiece)) {
          final even = held.length - held.length % 2;
          await play(Uint8List.sublistView(held, 0, even));
          held = Uint8List.fromList(held.sublist(even));
        }
      }
      if (held.length > 1 && turn == _turn) await play(Uint8List.sublistView(held, 0, held.length - held.length % 2));
      deadline?.cancel();
      if (pieces.isEmpty) return _Next.silent;
      _kept = (key: key, rate: rate, pieces: pieces);
      await _finish(turn);
      return _Next.played;
    } catch (err) {
      deadline?.cancel();
      if (turn != _turn) return _Next.played;
      if (pieces.isNotEmpty) {
        await _finish(turn);
        return _Next.played;
      }
      if (!late) RendelLog.warn('read_aloud_stream_failed', 'the natural voice did not play: $err');
      return _Next.silent;
    } finally {
      if (identical(_fetching, client)) _fetching = null;
      client.close();
    }
  }

  /// Plays what was kept, without asking the server again.
  Future<void> _play(int rate, List<Uint8List> pieces, int turn) async {
    await _hold(rate);
    _heardAt = DateTime.now();
    for (final piece in pieces) {
      if (turn != _turn) return;
      await _out.feed(piece);
    }
    await _finish(turn);
  }

  /// Waits for the last piece to be heard, then gives the audio back.
  Future<void> _finish(int turn) async {
    await _out.drained();
    if (turn != _turn) return;
    await _release();
    _quiet(turn);
  }

  /// The whole file, for a server that turned the stream away (switched off there).
  Future<void> _file(String url, int turn) async {
    try {
      final response = await _client().get(Uri.parse(url)).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty || turn != _turn) return _quiet(turn);
      // Played from a file: a real iPhone's AVPlayer does not play a stream
      // with no length, and audioplayers cannot play bytes on iOS.
      final file = File('${Directory.systemTemp.path}/rendel_answer_$turn.mp3');
      await file.writeAsBytes(response.bodyBytes, flush: true);
      _spoken.add(file);
      if (turn != _turn) return;
      final player = _player ??= AudioPlayer();
      final done = player.onPlayerComplete.first;
      await player.play(
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
      );
      if (turn != _turn) {
        await player.stop();
        return;
      }
      _heardAt = DateTime.now();
      await done.timeout(const Duration(seconds: 60));
    } catch (err) {
      RendelLog.warn('read_aloud_failed', 'the natural voice did not play: $err');
    }
    _quiet(turn);
  }

  /// A server with no natural voice: the phone's own. Said to be playing for
  /// as long as it speaks, so the answer's pill shows the time and stops it,
  /// as it does for the natural voice.
  Future<void> _phone(String text, String locale, String key, int turn) async {
    playing.value = key;
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
      if (turn != _turn) return;
      _heardAt = DateTime.now();
      // Returns once it has been said (`awaitSpeakCompletion`), or stopped.
      await tts.speak(text);
    } catch (err) {
      RendelLog.warn('read_aloud_failed', 'could not read the answer aloud: $err');
    }
    _quiet(turn);
  }

  void _quiet(int turn) {
    if (turn != _turn) return;
    playing.value = null;
    _heardAt = null;
  }

  Future<void> stop() async {
    _turn++;
    playing.value = null;
    _heardAt = null;
    _fetching?.close();
    _fetching = null;
    for (final file in _spoken) {
      file.delete().ignore();
    }
    _spoken.clear();
    await _release();
    try {
      await _player?.stop();
    } catch (_) {}
    try {
      await _tts?.stop();
    } catch (_) {}
  }

  /// For tests: what a second tap would play from.
  @visibleForTesting
  String? get keptKey => _kept?.key;

  static bool get _iOS => defaultTargetPlatform == TargetPlatform.iOS;

  static const _home = {'en': 'en-us', 'es': 'es-es', 'fr': 'fr-fr', 'de': 'de-de', 'pt': 'pt-br', 'it': 'it-it', 'ar': 'ar-sa', 'tr': 'tr-tr'};

  Future<FlutterTts> _engine() async {
    final tts = FlutterTts();
    // The engines' own "normal" is brisk on iOS; this is a calm reading pace.
    await tts.setSpeechRate(_iOS ? 0.5 : 0.95);
    // `speak` returns when the words are said, so the pill knows when to stop counting.
    await tts.awaitSpeakCompletion(true);
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

enum _Next { played, file, silent }
