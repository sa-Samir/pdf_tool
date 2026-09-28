plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.samir.pdf_toolbox"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.samir.pdf_toolbox"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // requirements.md 2: Android 8.0 / API 26+ avoids a long tail of storage and camera bugs.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    // ML Kit Document Scanner (requirements.md 3.10). Delivered through Google
    // Play services: the module is downloaded on first use, which is why the
    // app checks availability before offering the tool at all and why scanning
    // is a documented exception to "works fully offline" (requirements.md 7).
    // Still a beta artifact upstream; pinned rather than ranged.
    implementation("com.google.android.gms:play-services-mlkit-document-scanner:16.0.0-beta1")
}

flutter {
    source = "../.."
}
