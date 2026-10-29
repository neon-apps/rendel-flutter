import 'package:flutter/services.dart';

/// Streams 16-bit PCM to the speaker as it arrives, for reading answers
/// aloud. The native halves are `flutter_pcm_sound` 3.3.3's (public domain),
/// carried inside this package's own plugin since 0.69.1: that package builds
/// against Android 33, which current Flutter refuses (its embedding needs 34),
/// so every host app had to force a newer compileSdk on it. Here it builds
/// with the host's `flutter.compileSdkVersion`, on a channel of its own, so an
/// app that also uses `flutter_pcm_sound` is unaffected.
class RendelPcmSound {
  RendelPcmSound._();

  static const MethodChannel _channel = MethodChannel('rendel/pcm/methods');

  static void Function(int remainingFrames)? _onFeed;

  /// Mono or stereo at [sampleRate]; on iOS the audio session is set to playback.
  static Future<void> setup({required int sampleRate, required int channelCount}) => _channel.invokeMethod('setup', {
        'sample_rate': sampleRate,
        'num_channels': channelCount,
        'ios_audio_category': 'playback',
        'ios_allow_background_audio': false,
      });

  /// Queues 16-bit little-endian samples: exactly [s16le]'s bytes.
  static Future<void> feed(Uint8List s16le) => _channel.invokeMethod('feed', {'buffer': s16le});

  /// Below this many queued frames, the feed callback runs once per feed.
  static Future<void> setFeedThreshold(int frames) => _channel.invokeMethod('setFeedThreshold', {'feed_threshold': frames});

  /// Called once per feed when the queue falls below the threshold, and once
  /// when it is empty (`remainingFrames == 0`).
  static void setFeedCallback(void Function(int remainingFrames)? callback) {
    _onFeed = callback;
    _channel.setMethodCallHandler(callback == null ? null : _handle);
  }

  static Future<void> release() => _channel.invokeMethod('release');

  static Future<void> _handle(MethodCall call) async {
    if (call.method != 'OnFeedSamples') return;
    final remaining = (call.arguments as Map)['remaining_frames'];
    if (remaining is int) _onFeed?.call(remaining);
  }

  /// For tests: what the native side would report.
  static void debugFeedEvent(int remainingFrames) => _onFeed?.call(remainingFrames);
}
