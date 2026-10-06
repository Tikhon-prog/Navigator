# Navigator 1.4 — build

1. Open this folder in VS Code.
2. If `android/gradle/wrapper/gradle-wrapper.jar` is absent, run `setup_project.bat` once. It uses the installed Flutter SDK to restore the standard Android wrapper files without changing the app source.
3. Then run `flutter pub get`.
4. Run `flutter analyze` and fix any analyzer errors before building.
5. Build with `flutter build apk --release`.

The archive contains the Android application source, maps, school PDF, data and project configuration. A 100 MB APK is not required for a complete application; intentionally padding the APK would only waste storage.
