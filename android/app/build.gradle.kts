plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.flait.expenses"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.flait.expenses"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    val releaseKeyPath = System.getenv("FLAIT_KEYSTORE_PATH")
    signingConfigs {
        if (!releaseKeyPath.isNullOrBlank()) {
            create("production") {
                storeFile = file(releaseKeyPath)
                storePassword = System.getenv("FLAIT_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("FLAIT_KEY_ALIAS") ?: "flait-upload"
                keyPassword = System.getenv("FLAIT_KEY_PASSWORD") ?: System.getenv("FLAIT_KEYSTORE_PASSWORD")
            }
        }
    }
    buildTypes {
        release {
            if (!releaseKeyPath.isNullOrBlank()) {
                signingConfig = signingConfigs.getByName("production")
            } else if (System.getenv("FLAIT_TEST_BUILD") == "true") {
                // Explicit CI/device-test artifacts; never a Play production key.
                applicationIdSuffix = ".preview"
                signingConfig = signingConfigs.getByName("debug")
            } else {
                throw GradleException("Provide FLAIT_KEYSTORE_PATH and passwords for a production release, or explicitly set FLAIT_TEST_BUILD=true for test artifacts.")
            }
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
