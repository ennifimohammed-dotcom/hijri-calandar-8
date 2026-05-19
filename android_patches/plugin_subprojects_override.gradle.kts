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
//
// Implementation note: we DO NOT use `afterEvaluate { ... }`
// here. Flutter's `dev.flutter.flutter-gradle-plugin` adds
// plugin subprojects late in the configuration phase via a
// settings-evaluated hook, by which point some of those
// subprojects have already been evaluated — calling
// `Project.afterEvaluate(Action)` on an already-evaluated
// project is a hard error in Gradle. `plugins.withId(...)`
// is safe in both directions: it fires immediately if the
// plugin is already applied to the subproject, and registers
// a normal apply-time callback otherwise. In both cases the
// `compileSdk = 36` write lands before AGP reads the value
// for the AAR-metadata check.

subprojects {
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
