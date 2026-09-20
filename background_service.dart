// background_service.dart
//
// Sets up flutter_background_service so Aster can keep the notification
// listener alive while the app isn't in the foreground.
//
// Note on what this does NOT give you: Android does not allow a background
// service to keep the microphone "always listening" cheaply or invisibly.
// This service intentionally does NOT touch the mic — it only keeps the
// notification buffer running. A true hands-free "Hey Aster" wake word needs
// a dedicated on-device wake-word engine (e.g. Picovoice Porcupine) and is a
// separate piece of work from what's built here.
//
// Android requires a persistent, visible notification for any foreground
// service — this is enforced by the OS itself, not a choice made here, and
// it's what keeps this transparent rather than hidden.

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'notification_buffer_service.dart';

const String kNotificationChannelId = 'aster_foreground';
const int kNotificationId = 4242;

Future<void> initializeBackgroundService() async {
  final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  const channel = AndroidNotificationChannel(
    kNotificationChannelId,
    'Aster running',
    description: 'Shows while Aster is active in the background.',
    importance: Importance.low,
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: _onServiceStart,
      autoStart: false, // ask the user before starting, don't launch silently
      isForegroundMode: true,
      notificationChannelId: kNotificationChannelId,
      initialNotificationTitle: 'Aster',
      initialNotificationContent: 'Watching for notifications you\'ve opted in',
      foregroundServiceNotificationId: kNotificationId,
      // 'specialUse' is Android's catch-all type for services (like this one)
      // that don't fit location/media/mic/camera/etc. It needs the matching
      // manifest entries shown in AndroidManifest_additions.xml. If your
      // installed flutter_background_service version doesn't have this exact
      // enum value, autocomplete on `AndroidForegroundType.` to see what's
      // available and swap it in.
      foregroundServiceTypes: [AndroidForegroundType.specialUse],
    ),
    iosConfiguration: IosConfiguration(),
  );
}

/// Runs in a separate isolate — keep this lightweight.
@pragma('vm:entry-point')
void _onServiceStart(ServiceInstance service) async {
  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
  }

  await NotificationBufferService.loadPersisted();
  NotificationBufferService.startListening();

  service.on('stopService').listen((event) {
    service.stopSelf();
  });
}

void startAsterBackgroundService() {
  FlutterBackgroundService().startService();
}

void stopAsterBackgroundService() {
  FlutterBackgroundService().invoke('stopService');
}

Future<bool> isAsterBackgroundServiceRunning() {
  return FlutterBackgroundService().isRunning();
}
