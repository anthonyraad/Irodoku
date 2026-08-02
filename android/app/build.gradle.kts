import java.io.File
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
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

    signingConfigs {
        create("release") {
            if (!keystorePropertiesFile.exists()) {
                error(
                    "Missing android/key.properties. Create it from your upload keystore " +
                        "(see Flutter release signing docs).",
                )
            }
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            storePassword = keystoreProperties.getProperty("storePassword")
            storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}

// After every release APK build: copy Irodoku.apk, upload to Drive, open Explorer.
afterEvaluate {
    val prepareIrodokuReleaseApk = tasks.register("prepareIrodokuReleaseApk") {
        // Always run after assembleRelease (even when that task is UP-TO-DATE).
        outputs.upToDateWhen { false }
        doLast {
            val buildDirFile = layout.buildDirectory.get().asFile
            val releaseDir = buildDirFile.resolve("outputs/apk/release")
            val flutterApkDir = buildDirFile.resolve("outputs/flutter-apk")
            // Flutter may place the final APK one level above the app build dir.
            val projectFlutterApk =
                rootProject.projectDir.parentFile?.resolve("build/app/outputs/flutter-apk")

            val src = sequenceOf(
                releaseDir.resolve("app-release.apk"),
                flutterApkDir.resolve("app-release.apk"),
                projectFlutterApk?.resolve("app-release.apk"),
            ).filterNotNull().firstOrNull { it.exists() }

            if (src == null) {
                val msg = "Irodoku: release APK not found under ${buildDirFile.resolve("outputs")}"
                logger.warn(msg)
                println(msg)
                return@doLast
            }

            val destinations = listOfNotNull(
                src.parentFile.resolve("Irodoku.apk"),
                flutterApkDir.resolve("Irodoku.apk"),
                releaseDir.resolve("Irodoku.apk"),
                projectFlutterApk?.resolve("Irodoku.apk"),
            ).distinctBy { it.absolutePath }

            var reveal: File? = null
            for (dest in destinations) {
                dest.parentFile?.mkdirs()
                src.copyTo(dest, overwrite = true)
                if (reveal == null) reveal = dest
            }

            val apk = reveal ?: src
            val readyMsg = "Irodoku: release APK ready at ${apk.absolutePath}"
            logger.lifecycle(readyMsg)
            println(readyMsg)

            val ci = System.getenv("CI")?.equals("true", ignoreCase = true) == true ||
                System.getenv("GITHUB_ACTIONS") != null
            if (ci) return@doLast

            val driveDest = "gdrive:AppBuilds/Irodoku.apk"
            println("Irodoku: uploading to $driveDest ...")
            try {
                val rclone = resolveRcloneExecutable()
                println("Irodoku: using rclone at $rclone")
                val process = ProcessBuilder(
                    rclone,
                    "copyto",
                    src.absolutePath,
                    driveDest,
                ).redirectErrorStream(true).start()
                val output = process.inputStream.bufferedReader().readText()
                val code = process.waitFor()
                if (code != 0) {
                    throw IllegalStateException("rclone exited $code: $output")
                }
                val ok = "Irodoku: uploaded to $driveDest"
                logger.lifecycle(ok)
                println(ok)
            } catch (e: Exception) {
                val warn = "Irodoku: Drive upload skipped — ${e.message}"
                logger.warn(warn)
                println(warn)
            }

            try {
                ProcessBuilder("explorer.exe", "/select,${apk.absolutePath}").start()
            } catch (e: Exception) {
                logger.warn("Irodoku: could not open APK location: ${e.message}")
            }
        }
    }

    tasks.named("assembleRelease").configure {
        finalizedBy(prepareIrodokuReleaseApk)
    }
}

/**
 * Find a real rclone.exe. Ignores broken extensionless 0-byte shims
 * (e.g. C:\Windows\System32\rclone) that shadow the real binary on PATH.
 */
fun resolveRcloneExecutable(): String {
    val isWindows =
        System.getProperty("os.name").lowercase().contains("windows")

    fun isValidRclone(file: File): Boolean =
        file.isFile &&
            file.name.equals("rclone.exe", ignoreCase = true) &&
            file.length() > 1_000_000L

    fun runWhere(): String? {
        if (!isWindows) return null
        val process = ProcessBuilder("cmd", "/c", "where rclone.exe")
            .redirectErrorStream(true)
            .start()
        val output = process.inputStream.bufferedReader().readText()
        if (process.waitFor() != 0) return null
        return output.lineSequence()
            .map { it.trim() }
            .map { File(it) }
            .firstOrNull { isValidRclone(it) }
            ?.absolutePath
    }

    runWhere()?.let { return it }

    val exeName = if (isWindows) "rclone.exe" else "rclone"
    val pathEnv = System.getenv("PATH") ?: ""
    for (dir in pathEnv.split(File.pathSeparatorChar)) {
        if (dir.isBlank()) continue
        val candidate = File(dir, exeName)
        if (isValidRclone(candidate) || (!isWindows && candidate.isFile)) {
            return candidate.absolutePath
        }
    }

    if (isWindows) {
        val userProfile = System.getenv("USERPROFILE")
        if (userProfile != null) {
            val fixed = listOf(
                File(userProfile, "scoop\\shims\\rclone.exe"),
                File(userProfile, "AppData\\Local\\Microsoft\\WinGet\\Links\\rclone.exe"),
                File("C:\\Program Files\\rclone\\rclone.exe"),
            )
            for (candidate in fixed) {
                if (isValidRclone(candidate)) return candidate.absolutePath
            }

            // Portable unzip under Documents\rclone-*\rclone.exe
            val documents = File(userProfile, "Documents")
            val dirs = documents.listFiles()
                ?.filter { it.isDirectory && it.name.startsWith("rclone-") }
                .orEmpty()
            for (dir in dirs) {
                val candidate = File(dir, "rclone.exe")
                if (isValidRclone(candidate)) return candidate.absolutePath
            }
        }
    }

    throw IllegalStateException(
        "rclone.exe not found. Install rclone or add it to PATH " +
            "(a broken C:\\Windows\\System32\\rclone stub may be hiding it).",
    )
}
