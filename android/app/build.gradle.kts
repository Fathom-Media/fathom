import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Fathom signing: load the (gitignored) key.properties if present. When it's
// there, BOTH debug and release builds sign with the Fathom release key so an
// app installed while testing updates cleanly to the release build (same
// signature = no uninstall/data reset). Without it (e.g. a fresh clone or CI
// without the secret), builds fall back to the standard debug key.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseSigning = keystorePropertiesFile.exists()
if (hasReleaseSigning) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "app.fathom.fathom"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // Matches the desktop app ID; also the package autofill/password managers
        // key off (so Bitwarden shows "Fathom", not a server URL).
        applicationId = "app.fathom.player"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("fathom") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        val signing = if (hasReleaseSigning) {
            signingConfigs.getByName("fathom")
        } else {
            signingConfigs.getByName("debug")
        }
        getByName("debug") {
            signingConfig = signing
        }
        getByName("release") {
            signingConfig = signing
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // Google Cast SDK for native Chromecast support. mediarouter is the
    // discovery layer we drive directly (rather than the AppCompat-only
    // MediaRouteButton), so we can render the device picker in Flutter.
    implementation("com.google.android.gms:play-services-cast-framework:21.5.0")
    implementation("androidx.mediarouter:mediarouter:1.6.0")
    // Media3 ExoPlayer — the native, hardware-tunneled Android TV video backend
    // (selectable alongside media_kit). Tunneling + MediaCodec keeps 1080p/4K
    // 10-bit HEVC HDR smooth on low-power TV sticks where media_kit's copy-back
    // texture path drops frames.
    val media3 = "1.4.1"
    implementation("androidx.media3:media3-exoplayer:$media3")
    implementation("androidx.media3:media3-exoplayer-hls:$media3")
    implementation("androidx.media3:media3-ui:$media3")
}
