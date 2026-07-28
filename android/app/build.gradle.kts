plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.irodoku.irodoku"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.irodoku.irodoku"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
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

flutter {
    source = "../.."
}

// After every release APK build: write Irodoku.apk and reveal it in Explorer.
afterEvaluate {
    tasks.named("assembleRelease").configure {
        doLast {
            val buildDirFile = layout.buildDirectory.get().asFile
            val releaseDir = buildDirFile.resolve("outputs/apk/release")
            val src = sequenceOf(
                releaseDir.resolve("app-release.apk"),
                buildDirFile.resolve("outputs/flutter-apk/app-release.apk"),
            ).firstOrNull { it.exists() }

            if (src == null) {
                logger.warn("Irodoku: release APK not found under ${buildDirFile.resolve("outputs")}")
                return@doLast
            }

            val destinations = listOf(
                src.parentFile.resolve("Irodoku.apk"),
                buildDirFile.resolve("outputs/flutter-apk/Irodoku.apk"),
                releaseDir.resolve("Irodoku.apk"),
            ).distinctBy { it.absolutePath }

            var reveal: java.io.File? = null
            for (dest in destinations) {
                dest.parentFile?.mkdirs()
                src.copyTo(dest, overwrite = true)
                if (reveal == null) reveal = dest
            }

            val apk = reveal ?: return@doLast
            logger.lifecycle("Irodoku: release APK ready at ${apk.absolutePath}")

            val ci = System.getenv("CI")?.equals("true", ignoreCase = true) == true ||
                System.getenv("GITHUB_ACTIONS") != null
            if (ci) return@doLast

            try {
                ProcessBuilder("explorer.exe", "/select,${apk.absolutePath}").start()
            } catch (e: Exception) {
                logger.warn("Irodoku: could not open APK location: ${e.message}")
            }
        }
    }
}
