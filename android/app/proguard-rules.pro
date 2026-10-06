# Navigator release hardening.
# Flutter and Android plugin keep rules are supplied by their own build tooling.
# Keep model classes that may be accessed reflectively by JSON/plugin code.
-keep class com.example.navigator.** { *; }
-dontwarn org.jetbrains.annotations.**
