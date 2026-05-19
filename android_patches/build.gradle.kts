plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.hijricalendar.hijri_calendar"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = "11"
    }

    defaultConfig {
        applicationId = "com.hijricalendar.hijri_calendar"
        minSdk = 23
        targetSdk = 34
        versionCode = 1
        versionName = "1.0.0"
        multiDexEnabled = true
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}

// ── Pin androidx.glance to last stable 1.x ──────────────────
// The `home_widget` Flutter plugin (0.9.x) declares an open
// version constraint on Glance:
//
//     implementation "androidx.glance:glance-appwidget:1.+"
//
// Gradle resolves `1.+` to the LATEST published 1.x, which is
// currently `1.3.0-alpha01`. That alpha:
//   * requires AGP 9.1 or higher;
//   * requires compileSdk 37;
//   * transitively drags in `androidx.compose.remote:
//     remote-creation-android:1.0.0-alpha11`, an experimental
//     Compose-for-RemoteViews artifact with the same AGP /
//     compileSdk requirements.
//
// Flutter 3.41.9 (our CI-pinned toolchain) bundles AGP 8.11.x,
// and our app compiles against compileSdk 36 — so the alpha
// stack fails the AAR-metadata check on `:app:checkRelease…`.
//
// Force every `androidx.glance:*` resolution to the last
// stable 1.x release (1.1.1, AGP 8.x compatible). That
// also drops the alpha `compose.remote` transitive because
// 1.1.1 doesn't depend on it.
configurations.all {
    resolutionStrategy.eachDependency {
        if (requested.group == "androidx.glance") {
            useVersion("1.1.1")
            because(
                "home_widget pulls 1.+ which Gradle resolves to alpha " +
                "that requires AGP 9 / compileSdk 37 — keep us on 1.x stable."
            )
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}
