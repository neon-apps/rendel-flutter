package ai.rendel.push;

import android.Manifest;
import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;

import androidx.annotation.NonNull;
import androidx.core.app.ActivityCompat;
import androidx.core.app.NotificationManagerCompat;
import androidx.core.content.ContextCompat;

import com.google.firebase.FirebaseApp;
import com.google.firebase.FirebaseOptions;
import com.google.firebase.messaging.FirebaseMessaging;

import java.util.HashMap;
import java.util.Map;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.PluginRegistry;

/**
 * Rendel's push on Android (design/plans/push-channels.md §3): Firebase Cloud
 * Messaging called from Java, so the app takes no Dart-side Firebase pin.
 *
 * An app with no Firebase of its own needs no google-services.json: Dart
 * passes the options Rendel read from the app's service account, and Firebase
 * is started with them here. An app that has Firebase keeps its own, and the
 * token is that project's.
 *
 * Taps: a notification Firebase showed while the app was in the background
 * opens the launch activity with the message's data as extras, whichever
 * service the app has. Rendel's are handed to Dart at launch and on every new
 * intent; anything else is left in the intent for the app.
 */
public class RendelPushPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware,
        PluginRegistry.NewIntentListener, PluginRegistry.RequestPermissionsResultListener {
    private static final int PERMISSION_REQUEST = 0x52e1;
    /** The plugin attached to an engine, for the messaging service's new tokens. */
    private static RendelPushPlugin attached;

    private MethodChannel channel;
    private Context context;
    private ActivityPluginBinding activity;
    private MethodChannel.Result asking;
    private final Handler main = new Handler(Looper.getMainLooper());

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        context = binding.getApplicationContext();
        channel = new MethodChannel(binding.getBinaryMessenger(), "rendel/push");
        channel.setMethodCallHandler(this);
        attached = this;
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        channel.setMethodCallHandler(null);
        if (attached == this) attached = null;
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        switch (call.method) {
            case "package":
                result.success(context.getPackageName());
                break;
            case "hasFirebase":
                result.success(hasDefaultApp());
                break;
            case "permission":
                Boolean ask = call.argument("ask");
                permission(ask == null || ask, result);
                break;
            case "token":
                Map<String, String> options = call.argument("firebase");
                token(options, result);
                break;
            case "launchTap":
                result.success(activity == null ? null : rendelData(activity.getActivity().getIntent()));
                break;
            default:
                result.notImplemented();
        }
    }

    private boolean hasDefaultApp() {
        for (FirebaseApp app : FirebaseApp.getApps(context)) {
            if (FirebaseApp.DEFAULT_APP_NAME.equals(app.getName())) return true;
        }
        return false;
    }

    private void permission(boolean ask, MethodChannel.Result result) {
        if (Build.VERSION.SDK_INT < 33) {
            result.success(NotificationManagerCompat.from(context).areNotificationsEnabled());
            return;
        }
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
            result.success(true);
            return;
        }
        if (!ask || activity == null || asking != null) {
            result.success(false);
            return;
        }
        asking = result;
        ActivityCompat.requestPermissions(activity.getActivity(), new String[] {Manifest.permission.POST_NOTIFICATIONS}, PERMISSION_REQUEST);
    }

    @Override
    public boolean onRequestPermissionsResult(int requestCode, @NonNull String[] permissions, @NonNull int[] grantResults) {
        if (requestCode != PERMISSION_REQUEST || asking == null) return false;
        MethodChannel.Result result = asking;
        asking = null;
        result.success(grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED);
        return true;
    }

    private void token(Map<String, String> options, MethodChannel.Result result) {
        try {
            if (!hasDefaultApp()) {
                if (options == null) {
                    result.error("push_no_firebase", "No Firebase options: push is not set up in Settings > Channels", null);
                    return;
                }
                FirebaseApp.initializeApp(context, new FirebaseOptions.Builder()
                        .setApplicationId(options.get("app_id"))
                        .setApiKey(options.get("api_key"))
                        .setProjectId(options.get("project_id"))
                        .setGcmSenderId(options.get("sender_id"))
                        .build());
            }
            FirebaseMessaging.getInstance().getToken().addOnCompleteListener(task -> main.post(() -> {
                if (!task.isSuccessful() || task.getResult() == null) {
                    Exception e = task.getException();
                    result.error("push_token", e == null ? "Firebase gave no token" : e.getMessage(), null);
                    return;
                }
                result.success(tokenMap(context, task.getResult()));
            }));
        } catch (RuntimeException e) {
            result.error("push_token", e.getMessage(), null);
        }
    }

    static Map<String, Object> tokenMap(Context context, String token) {
        Map<String, Object> map = new HashMap<>();
        map.put("token", token);
        map.put("provider", "fcm");
        map.put("bundleId", context.getPackageName());
        return map;
    }

    /** A new token from Firebase, while an engine is attached; at the next launch Dart asks for it anyway. */
    static void newToken(Context context, String token) {
        RendelPushPlugin plugin = attached;
        if (plugin == null) return;
        plugin.main.post(() -> plugin.channel.invokeMethod("token", tokenMap(context, token)));
    }

    /** Rendel's data in an intent, taken out of it so it is opened once. Null for any other intent. */
    static Map<String, Object> rendelData(Intent intent) {
        if (intent == null) return null;
        Bundle extras = intent.getExtras();
        if (extras == null || !"1".equals(extras.getString("rendel"))) return null;
        Map<String, Object> data = new HashMap<>();
        for (String key : extras.keySet()) {
            Object value = extras.get(key);
            if (value instanceof String && !key.startsWith("google.") && !key.startsWith("gcm.")) data.put(key, value);
        }
        intent.removeExtra("rendel");
        return data;
    }

    @Override
    public boolean onNewIntent(@NonNull Intent intent) {
        Map<String, Object> data = rendelData(intent);
        if (data == null) return false;
        channel.invokeMethod("tap", data);
        return true;
    }

    @Override
    public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
        activity = binding;
        binding.addOnNewIntentListener(this);
        binding.addRequestPermissionsResultListener(this);
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
        if (activity != null) {
            activity.removeOnNewIntentListener(this);
            activity.removeRequestPermissionsResultListener(this);
        }
        activity = null;
    }
}
