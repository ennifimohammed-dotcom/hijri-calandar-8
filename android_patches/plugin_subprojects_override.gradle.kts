// ── Forced compileSdk override for plugin subprojects ─────────
//
// Appended by CI onto the END of the Flutter-generated
// android/build.gradle.kts (project-level, NOT app-level).
// Standard Flutter-community workaround for the AGP 9 +
// flutter_plugin_android_lifecycle 2.x deadlock — many
// still-popular plugins (file_picker, home_widget, share_plus,
// shared_preferences_android, ...) ship Android sources
// compiled at compileSdk 34, but their transitive dep
// flutter_plugin_android_lifecycle has bumped its minimum to
// 36, so AGP 9 fails the AAR-metadata check.
//
// Forces every Android plugin module to compile at the same
// compileSdk as the app. Build-time only — no runtime impact,
// no minSdk / targetSdk change, no manifest change.

subprojects {
    afterEvaluate {
        plugins.withId("com.android.library") {
            (extensions.getByName("android")
                    as com.android.build.api.dsl.LibraryExtension)
                .compileSdk = 36
        }
        plugins.withId("com.android.application") {
            (extensions.getByName("android")
                    as com.android.build.api.dsl.ApplicationExtension)
                .compileSdk = 36
        }
    }
}
