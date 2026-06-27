plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.csc4602.machinelearning_app"
    compileSdk = flutter.compileSdkVersion
    // Plugins (camera, tflite_flutter, permission_handler, path_provider)
    // all require NDK 27.0.12077973; NDK versions are backward-compatible.
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.csc4602.machinelearning_app"

        // TFLite and the camera plugin both require API 21 minimum.
        minSdk = 21
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Limit native builds to the two ABIs that tflite_flutter ships
        // pre-built binaries for. This keeps APK size smaller.
        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a")
        }
    }

    // Prevent the Gradle packager from compressing the .tflite model file.
    // TFLite needs to memory-map the model directly from the APK; compression
    // breaks that and causes a runtime crash.
    aaptOptions {
        noCompress += "tflite"
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
