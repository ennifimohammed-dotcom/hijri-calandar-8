// Flutter 3.44 (AGP 9) ships a Kotlin script compiler that
// treats the legacy `kotlinOptions { jvmTarget = "11" }` DSL —
// AND the implicit `android { ... }` extension function — as
// hard errors instead of mere deprecation warnings. We migrate
// to the new `kotlin { compilerOptions { ... } }` DSL (per
// https://kotl.in/u1r8ln) and silence the remaining DSL
// deprecations at the file level so the script keeps compiling
// while still building against JVM 11 byte code (matching the
// Java compileOptions below).
@file:Suppress("DEPRECATION")

import org.jetbrains.kotlin.gradle.dsl.JvmTarget

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

// New-DSL replacement for the in-`android` `kotlinOptions {}`
// block (removed for AGP 9). Same effective configuration —
// Kotlin emits JVM 11 byte code, matching `compileOptions` above
// so the Java/Kotlin halves of the project agree.
kotlin {
    compilerOptions {
        jvmTarget = JvmTarget.JVM_11
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}
