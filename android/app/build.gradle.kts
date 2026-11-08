import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

// «Поколение» uses the local Android debug keystore for test/release builds unless a
// dedicated release key.properties file is supplied. This prevents generating
// an unsigned APK (which Android reports as INSTALL_PARSE_FAILED_NO_CERTIFICATES).
val releaseKeyPropertiesFile = rootProject.file("key.properties")
val releaseKeyProperties = Properties()
if (releaseKeyPropertiesFile.exists()) {
    releaseKeyPropertiesFile.inputStream().use { releaseKeyProperties.load(it) }
}

android {
    namespace = "ru.pokolenie.navigator"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }

    defaultConfig {
        applicationId = "ru.pokolenie.navigator"
        minSdk = 23
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["appAuthRedirectScheme"] = "ru.pokolenie.navigator"
    }

    signingConfigs {
        // The debug key is deliberately used only when no dedicated release key
        // is configured. A locally generated key.properties file takes priority.
        getByName("debug")

        create("pokolenieRelease") {
            if (releaseKeyPropertiesFile.exists()) {
                val storePath = releaseKeyProperties.getProperty("storeFile")
                if (!storePath.isNullOrBlank()) {
                    storeFile = file(storePath)
                    storePassword = releaseKeyProperties.getProperty("storePassword")
                    keyAlias = releaseKeyProperties.getProperty("keyAlias")
                    keyPassword = releaseKeyProperties.getProperty("keyPassword")
                }
            }
        }
    }

    buildTypes {
        getByName("release") {
            signingConfig = if (releaseKeyPropertiesFile.exists()) {
                signingConfigs.getByName("pokolenieRelease")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

kotlin {
    // Compile with the installed JDK while keeping Android-compatible Java 21 bytecode.
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_21
    }
}

flutter {
    source = "../.."
}
