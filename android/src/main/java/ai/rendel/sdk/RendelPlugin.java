package ai.rendel.sdk;

import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.ContentResolver;
import android.content.Context;
import android.content.Intent;
import android.media.AudioAttributes;
import android.media.AudioFocusRequest;
import android.media.AudioManager;
import android.database.Cursor;
import android.net.Uri;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.provider.CalendarContract;
import android.provider.OpenableColumns;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.util.HashMap;
import java.util.Map;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.PluginRegistry;

/**
 * The copilot's native half on Android.
 *
 * Registered so the tool builds this module, and with it the manifest that
 * declares the copilot's permissions; there is no usage string to check the
 * way there is on iOS. What it does do is open the system's document picker
 * for the composer's Files tool. Here rather than in a picker package, for
 * the reason the iOS half gives: that picker needs no permission, and the
 * app only ever sees the one file somebody chose.
 *
 * And it opens the calendar app's new-event screen, filled in, for an
 * add_to_calendar button. The insert intent needs no calendar permission:
 * the calendar app writes the event, once the user saves it.
 */
public class RendelPlugin
    implements FlutterPlugin,
        MethodChannel.MethodCallHandler,
        ActivityAware,
        PluginRegistry.ActivityResultListener {
  /** "NC", so the result is recognisably ours among the host's own requests. */
  private static final int PICK_DOCUMENT = 0x4e43;

  private MethodChannel channel;
  @Nullable private ActivityPluginBinding activity;

  /** The answer owed to the picker that is open. One at a time. */
  @Nullable private MethodChannel.Result picking;

  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
    channel = new MethodChannel(binding.getBinaryMessenger(), "rendel/platform");
    context = binding.getApplicationContext();
    channel.setMethodCallHandler(this);
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
    channel.setMethodCallHandler(null);
  }

  @Override
  public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
    if (call.method.equals("pickDocument")) {
      pickDocument(result);
    } else if (call.method.equals("addToCalendar")) {
      addToCalendar(call, result);
    } else if (call.method.equals("voiceSession")) {
      voiceSession(Boolean.TRUE.equals(call.arguments), result);
    } else {
      result.notImplemented();
    }
  }

  @Nullable private Context context;
  @Nullable private AudioFocusRequest focus;

  /**
   * An answer read aloud asks for the sound while it speaks, and gives it back
   * after (Tuna 2026-10-23): transient focus that may duck, so music plays on
   * under the voice and comes back up when it ends.
   */
  private void voiceSession(boolean active, MethodChannel.Result result) {
    AudioManager audio = context == null ? null : (AudioManager) context.getSystemService(Context.AUDIO_SERVICE);
    if (audio == null || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
      result.success(null);
      return;
    }
    if (active) {
      if (focus == null) {
        focus = new AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
            .setAudioAttributes(new AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build())
            .build();
      }
      audio.requestAudioFocus(focus);
    } else if (focus != null) {
      audio.abandonAudioFocusRequest(focus);
    }
    result.success(null);
  }

  private void pickDocument(MethodChannel.Result result) {
    if (activity == null) {
      result.error("no_activity", "nothing on screen to open the picker from", null);
      return;
    }
    if (picking != null) {
      result.error("already_active", "a document picker is already open", null);
      return;
    }
    Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
    intent.addCategory(Intent.CATEGORY_OPENABLE);
    intent.setType("*/*");
    // What the upload accepts, and nothing else: a HEIC would be picked,
    // sent and refused.
    intent.putExtra(
        Intent.EXTRA_MIME_TYPES,
        new String[] {
          "application/pdf", "text/plain", "image/png", "image/jpeg", "image/webp", "image/gif"
        });
    picking = result;
    try {
      activity.getActivity().startActivityForResult(intent, PICK_DOCUMENT);
    } catch (ActivityNotFoundException e) {
      picking = null;
      result.error("no_picker", "this device has no document picker", null);
    }
  }

  private void addToCalendar(MethodCall call, MethodChannel.Result result) {
    String title = call.argument("title");
    Number start = call.argument("starts_at");
    if (title == null || start == null) {
      result.error("bad_args", "an event needs a title and a start", null);
      return;
    }
    if (activity == null) {
      result.error("no_activity", "nothing on screen to open the calendar from", null);
      return;
    }
    Intent intent =
        new Intent(Intent.ACTION_INSERT)
            .setData(CalendarContract.Events.CONTENT_URI)
            .putExtra(CalendarContract.Events.TITLE, title)
            .putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, start.longValue());
    // Numbers from Dart arrive as Integer or Long by size, so both are read
    // as a Number. A missing end is left to the calendar app's own default.
    Number end = call.argument("ends_at");
    if (end != null) intent.putExtra(CalendarContract.EXTRA_EVENT_END_TIME, end.longValue());
    String location = call.argument("location");
    if (location != null) intent.putExtra(CalendarContract.Events.EVENT_LOCATION, location);
    String notes = call.argument("notes");
    if (notes != null) intent.putExtra(CalendarContract.Events.DESCRIPTION, notes);
    try {
      activity.getActivity().startActivity(intent);
      result.success(true);
    } catch (ActivityNotFoundException e) {
      result.error("no_calendar", "this device has no calendar app", null);
    }
  }

  @Override
  public boolean onActivityResult(int requestCode, int resultCode, @Nullable Intent data) {
    if (requestCode != PICK_DOCUMENT) return false;
    MethodChannel.Result result = picking;
    picking = null;
    if (result == null) return true;
    Uri uri = data == null ? null : data.getData();
    if (resultCode != Activity.RESULT_OK || uri == null || activity == null) {
      result.success(null);
      return true;
    }
    ContentResolver resolver = activity.getActivity().getContentResolver();
    Handler main = new Handler(Looper.getMainLooper());
    // Off the main thread: a PDF can be megabytes, and a provider can be a
    // cloud drive that downloads it first.
    new Thread(
            () -> {
              try {
                Map<String, Object> file = new HashMap<>();
                file.put("name", nameOf(resolver, uri));
                file.put("type", resolver.getType(uri));
                file.put("bytes", read(resolver, uri));
                main.post(() -> result.success(file));
              } catch (Exception e) {
                main.post(() -> result.error("unreadable", e.getMessage(), null));
              }
            })
        .start();
    return true;
  }

  private static String nameOf(ContentResolver resolver, Uri uri) {
    try (Cursor cursor =
        resolver.query(uri, new String[] {OpenableColumns.DISPLAY_NAME}, null, null, null)) {
      if (cursor != null && cursor.moveToFirst()) {
        String name = cursor.getString(0);
        if (name != null) return name;
      }
    }
    String last = uri.getLastPathSegment();
    return last == null ? "file" : last;
  }

  private static byte[] read(ContentResolver resolver, Uri uri) throws Exception {
    try (InputStream in = resolver.openInputStream(uri)) {
      if (in == null) throw new IllegalStateException("the provider returned no stream");
      ByteArrayOutputStream out = new ByteArrayOutputStream();
      byte[] buffer = new byte[16 * 1024];
      int n;
      while ((n = in.read(buffer)) != -1) out.write(buffer, 0, n);
      return out.toByteArray();
    }
  }

  @Override
  public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
    activity = binding;
    binding.addActivityResultListener(this);
  }

  @Override
  public void onDetachedFromActivityForConfigChanges() {
    onDetachedFromActivity();
  }

  @Override
  public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) {
    onAttachedToActivity(binding);
  }

  @Override
  public void onDetachedFromActivity() {
    if (activity != null) activity.removeActivityResultListener(this);
    activity = null;
  }
}
