package ai.rendel.push;

import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.os.Build;

import androidx.annotation.NonNull;
import androidx.core.app.NotificationCompat;
import androidx.core.app.NotificationManagerCompat;

import com.google.firebase.messaging.FirebaseMessagingService;
import com.google.firebase.messaging.RemoteMessage;

import java.util.Map;

/**
 * Firebase's messages for an app with no messaging service of its own (the
 * manifest gives this one the lowest priority). In the background Firebase
 * shows a notification itself and never calls this; in the foreground it
 * does, and a Rendel push is shown here the same way, its tap opening the
 * launch activity with the data, as Firebase's own does.
 */
public class RendelMessagingService extends FirebaseMessagingService {
    private static final String CHANNEL = "rendel";

    @Override
    public void onNewToken(@NonNull String token) {
        RendelPushPlugin.newToken(getApplicationContext(), token);
    }

    @Override
    public void onMessageReceived(@NonNull RemoteMessage message) {
        Map<String, String> data = message.getData();
        RemoteMessage.Notification notification = message.getNotification();
        if (!"1".equals(data.get("rendel")) || notification == null) return;
        Context context = getApplicationContext();
        Intent launch = context.getPackageManager().getLaunchIntentForPackage(context.getPackageName());
        if (launch == null) return;
        launch.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP);
        for (Map.Entry<String, String> entry : data.entrySet()) launch.putExtra(entry.getKey(), entry.getValue());
        int id = (data.containsKey("rendel_followup") ? data.get("rendel_followup") : String.valueOf(System.currentTimeMillis())).hashCode();
        PendingIntent open = PendingIntent.getActivity(context, id, launch, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);

        if (Build.VERSION.SDK_INT >= 26) {
            NotificationManager manager = context.getSystemService(NotificationManager.class);
            if (manager.getNotificationChannel(CHANNEL) == null) {
                manager.createNotificationChannel(new NotificationChannel(CHANNEL, appName(context), NotificationManager.IMPORTANCE_HIGH));
            }
        }
        NotificationCompat.Builder built = new NotificationCompat.Builder(context, CHANNEL)
                .setSmallIcon(context.getApplicationInfo().icon)
                .setContentTitle(notification.getTitle())
                .setContentText(notification.getBody())
                .setStyle(new NotificationCompat.BigTextStyle().bigText(notification.getBody()))
                .setAutoCancel(true)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setContentIntent(open);
        try {
            NotificationManagerCompat.from(context).notify(id, built.build());
        } catch (SecurityException ignored) {
            // The person turned notifications off since the token was sent.
        }
    }

    private static String appName(Context context) {
        CharSequence label = context.getApplicationInfo().loadLabel(context.getPackageManager());
        return label == null ? "Notifications" : label.toString();
    }
}
