Aster — Flutter build
Files in this delivery
lib/main.dart — app entry point
lib/secure_key_store.dart — encrypted API key storage + setup screen
lib/anthropic_service.dart — calls Anthropic's Messages API directly
lib/chat_screen.dart — the chat UI, mic input, settings sheet
lib/notification_buffer_service.dart — opt-in notification reading (local only)
lib/background_service.dart — keeps the notification listener alive
pubspec_additions.yaml — dependencies to add
AndroidManifest_additions.xml — permissions + services to merge in
Setup order
Copy the five lib/*.dart files into your project's lib/ folder (merge with or replace your existing MicScreen work from before).
Run the flutter pub add command from pubspec_additions.yaml.
Merge AndroidManifest_additions.xml into android/app/src/main/AndroidManifest.xml (permissions under <manifest>, both <service> blocks under <application>).
Open lib/notification_buffer_service.dart and add the package names of any apps you actually want summarized to allowedPackages — it starts empty on purpose (see Privacy below).
flutter pub get, then flutter run on a connected phone to test.
When ready for an installable file, flutter build apk --debug (or --release with signing, same keystore steps as before) → build/app/outputs/flutter-apk/.