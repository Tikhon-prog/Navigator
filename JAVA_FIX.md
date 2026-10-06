# Build fix

The project uses Gradle/Android tooling with Java 21. If another Java version is selected globally, set JAVA_HOME to the Java 21 installation before building.

Then run:
cd C:\Navigator
flutter pub get
flutter analyze
flutter build apk --release
