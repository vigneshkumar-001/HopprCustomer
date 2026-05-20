// android/app/build.gradle.kts

import java.io.File
import java.io.FileInputStream
import java.util.Properties
import org.gradle.api.GradleException

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services") apply false
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

val isReleaseTaskRequested =
    gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }

android {
    namespace = "com.hopper.customer.hopper"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.hopper.customer.hopper"
        minSdk = 24
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["firebaseMessagingAutoInitEnabled"] = "true"
    }

    signingConfigs {
        create("release") {
            val requiredKeys = listOf("keyAlias", "keyPassword", "storeFile", "storePassword")
            val missing = buildList {
                if (!keystorePropertiesFile.exists()) {
                    add("key.properties (file missing)")
                } else {
                    for (k in requiredKeys) {
                        if (keystoreProperties.getProperty(k).isNullOrBlank()) add(k)
                    }

                    // Fail fast if key.properties exists but the referenced keystore file doesn't.
                    val storeFileProp = keystoreProperties.getProperty("storeFile")?.trim()
                    if (!storeFileProp.isNullOrBlank()) {
                        val resolvedStoreFile = file(storeFileProp)
                        if (!resolvedStoreFile.exists()) {
                            add("storeFile (not found at ${resolvedStoreFile.absolutePath})")
                        }
                    }
                }
            }

            if (missing.isNotEmpty()) {
                if (isReleaseTaskRequested) {
                    throw GradleException(
                        "Release signing config is incomplete. Missing: ${missing.joinToString(", ")}"
                    )
                } else {
                    // Allow debug builds without requiring release signing credentials.
                    logger.warn(
                        "Release signing config not set (missing: ${missing.joinToString(", ")}). " +
                            "Debug builds will still work; release builds will fail until configured."
                    )
                    return@create
                }
            }

            keyAlias = keystoreProperties.getProperty("keyAlias").trim()
            keyPassword = keystoreProperties.getProperty("keyPassword")
            storeFile = file(keystoreProperties.getProperty("storeFile").trim())
            storePassword = keystoreProperties.getProperty("storePassword")
        }
    }

    buildTypes {
        debug {
            isDebuggable = true
        }
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "11"
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }
}

flutter {
    source = "../.."
}

// Apply Google Services only when google-services.json exists.
// This prevents debug builds from failing in environments where the file isn't present.
val googleServicesCandidates = listOf(
    file("google-services.json"),
    file("src/google-services.json"),
    file("src/debug/google-services.json"),
    file("src/release/google-services.json"),
)
if (googleServicesCandidates.any { it.exists() }) {
    apply(plugin = "com.google.gms.google-services")
} else {
    logger.warn("google-services.json not found; skipping com.google.gms.google-services plugin.")
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.3")

    implementation(platform("com.google.firebase:firebase-bom:33.13.0"))
    implementation("com.google.firebase:firebase-messaging")
    implementation("com.google.firebase:firebase-analytics")

    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("com.google.android.material:material:1.12.0")
}

/**
 * ✅ DEBUG APK -> copy to Flutter expected folder
 * Flutter expects: build/app/outputs/flutter-apk/app-debug.apk
 */
val copyDebugApk = tasks.register("copyDebugApk") {
    dependsOn("assembleDebug")

    doLast {
        val apkDir = layout.buildDirectory.dir("outputs/apk/debug").get().asFile

        // Try direct then fallback search
        val direct = File(apkDir, "app-debug.apk")
        val apk = if (direct.exists()) direct
        else fileTree(apkDir).matching { include("**/*.apk") }.files.firstOrNull()

        if (apk == null || !apk.exists()) {
            println("❌ No DEBUG APK found in: ${apkDir.absolutePath}")
            return@doLast
        }

        val flutterOutDir = File(projectDir, "../../build/app/outputs/flutter-apk")
        flutterOutDir.mkdirs()

        val destApk = File(flutterOutDir, "app-debug.apk")

        copy {
            from(apk)
            into(flutterOutDir)
            rename { "app-debug.apk" }
        }

        println("✅ Copied DEBUG APK for Flutter tools:")
        println("   From: ${apk.absolutePath}")
        println("   To  : ${destApk.absolutePath}")
    }
}

// Auto-run copy after assembleDebug
tasks.matching { it.name == "assembleDebug" }.configureEach {
    finalizedBy(copyDebugApk)
}

/**
 * ✅ RELEASE APK -> copy to Flutter expected folder
 * Fixes: "Gradle build failed to produce an .apk file..." after assembleRelease
 * Flutter expects: build/app/outputs/flutter-apk/app-release.apk
 */
val copyReleaseApk = tasks.register("copyReleaseApk") {
    dependsOn("assembleRelease")

    doLast {
        val apkDir = layout.buildDirectory.dir("outputs/apk/release").get().asFile

        // Try direct then fallback search
        val direct = File(apkDir, "app-release.apk")
        val apk = if (direct.exists()) direct
        else fileTree(apkDir).matching { include("**/*.apk") }.files.firstOrNull()

        if (apk == null || !apk.exists()) {
            println("❌ No RELEASE APK found in: ${apkDir.absolutePath}")
            return@doLast
        }

        val flutterOutDir = File(projectDir, "../../build/app/outputs/flutter-apk")
        flutterOutDir.mkdirs()

        val destApk = File(flutterOutDir, "app-release.apk")

        copy {
            from(apk)
            into(flutterOutDir)
            rename { "app-release.apk" }
        }

        println("✅ Copied RELEASE APK for Flutter tools:")
        println("   From: ${apk.absolutePath}")
        println("   To  : ${destApk.absolutePath}")
    }
}

// Auto-run copy after assembleRelease
tasks.matching { it.name == "assembleRelease" }.configureEach {
    finalizedBy(copyReleaseApk)
}

/**
 * ✅ IMPORTANT:
 * You are building AAB with: flutter build appbundle --release
 * Sometimes Flutter fails to detect the .aab even though Gradle created it in:
 * android/app/build/outputs/bundle/...
 *
 * This helper copies it to Flutter's expected folder:
 * build/app/outputs/bundle/release/
 */
tasks.matching { it.name == "bundleRelease" }.configureEach {
    doLast {
        val direct = layout.buildDirectory.file("outputs/bundle/release/app-release.aab").get().asFile

        fun copyToFlutter(aabFile: File) {
            val destDir = file("$projectDir/../../build/app/outputs/bundle/release")
            destDir.mkdirs()
            copy {
                from(aabFile)
                into(destDir)
            }
            println("✅ Copied AAB to: ${destDir.absolutePath}\\${aabFile.name}")
        }

        if (direct.exists()) {
            copyToFlutter(direct)
        } else {
            val found = fileTree(layout.buildDirectory.dir("outputs/bundle").get().asFile)
                .matching { include("**/*.aab") }
                .files
                .firstOrNull()

            if (found != null) {
                copyToFlutter(found)
            } else {
                println("❌ No AAB found under: ${layout.buildDirectory.dir("outputs/bundle").get().asFile.absolutePath}")
                println("   Run: cd android; .\\gradlew bundleRelease --stacktrace")
            }
        }
    }
}


//
//plugins {
//    id("com.android.application")
//    id("kotlin-android")
//    id("dev.flutter.flutter-gradle-plugin")
//    id("com.google.gms.google-services")
//}
//
//import java.util.Properties
//        import java.io.FileInputStream
//
//val keystoreProperties = Properties()
//val keystorePropertiesFile = rootProject.file("key.properties")
//if (keystorePropertiesFile.exists()) {
//    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
//}
//
//android {
//    namespace = "com.hopper.customer.hopper"
//    compileSdk = 35
//
//    defaultConfig {
//        applicationId = "com.hopper.customer.hopper"
//        minSdk = 24
//        targetSdk = 35
//        versionCode = flutter.versionCode
//        versionName = flutter.versionName
//
//        // FCM auto init
//        manifestPlaceholders["firebaseMessagingAutoInitEnabled"] = "true"
//    }
//
//    signingConfigs {
//        create("release") {
//            // ✅ Safe validation (avoids "null cannot be cast to String")
//            if (!keystorePropertiesFile.exists()) {
//                throw GradleException("key.properties not found in android/. Cannot build release.")
//            }
//
//            fun req(key: String): String =
//                (keystoreProperties.getProperty(key)
//                    ?: throw GradleException("Missing '$key' in key.properties"))
//
//            keyAlias = req("keyAlias")
//            keyPassword = req("keyPassword")
//            storeFile = file(req("storeFile"))
//            storePassword = req("storePassword")
//        }
//    }
//
//    buildTypes {
//        getByName("debug") {
//            isDebuggable = true
//        }
//
//        getByName("release") {
//            signingConfig = signingConfigs.getByName("release")
//            isMinifyEnabled = false
//            isShrinkResources = false
//        }
//    }
//
//    // ✅ Java / Kotlin setup
//    compileOptions {
//        sourceCompatibility = JavaVersion.VERSION_11
//        targetCompatibility = JavaVersion.VERSION_11
//        isCoreLibraryDesugaringEnabled = true
//    }
//
//    kotlinOptions {
//        jvmTarget = "11"
//    }
//
//    // Optional but safe for many native libs
//    packaging {
//        jniLibs {
//            useLegacyPackaging = true
//        }
//    }
//}
//
//flutter {
//    source = "../.."
//}
//
//dependencies {
//    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.3")
//
//    implementation(platform("com.google.firebase:firebase-bom:33.13.0"))
//    implementation("com.google.firebase:firebase-messaging")
//    implementation("com.google.firebase:firebase-analytics")
//
//    implementation("androidx.core:core-ktx:1.13.1")
//    implementation("androidx.appcompat:appcompat:1.7.0")
//    implementation("com.google.android.material:material:1.12.0")
//}
//
///**
// * ✅ IMPORTANT:
// * You are building AAB with: flutter build appbundle --release
// * Sometimes Flutter fails to detect the .aab even though Gradle created it in:
// * android/app/build/outputs/bundle/...
// *
// * This helper copies it to Flutter's expected folder:
// * build/app/outputs/bundle/release/
// */
//tasks.matching { it.name == "bundleRelease" }.configureEach {
//    doLast {
//        val direct = file("$buildDir/outputs/bundle/release/app-release.aab")
//
//        fun copyToFlutter(aabFile: java.io.File) {
//            val destDir = file("$projectDir/../../build/app/outputs/bundle/release")
//            destDir.mkdirs()
//            copy {
//                from(aabFile)
//                into(destDir)
//            }
//            println("✅ Copied AAB to: ${destDir.absolutePath}\\${aabFile.name}")
//        }
//
//        if (direct.exists()) {
//            copyToFlutter(direct)
//        } else {
//            // Fallback: search any .aab (handles flavors / variant naming)
//            val found = fileTree("$buildDir/outputs/bundle")
//                .matching { include("**/*.aab") }
//                .files
//                .firstOrNull()
//
//            if (found != null) {
//                copyToFlutter(found)
//            } else {
//                println("❌ No AAB found under: $buildDir/outputs/bundle")
//                println("   Check Gradle errors above or run: cd android; .\\gradlew bundleRelease --stacktrace")
//            }
//        }
//    }
//}


//import com.android.build.gradle.internal.cxx.configure.gradleLocalProperties
//
//plugins {
//    id("com.android.application")
//    id("kotlin-android")
//    id("dev.flutter.flutter-gradle-plugin")
//    id("com.google.gms.google-services")
//}
//
//import java.util.Properties
//        import java.io.FileInputStream
//
//val keystoreProperties = Properties()
//val keystorePropertiesFile = rootProject.file("key.properties")
//if (keystorePropertiesFile.exists()) {
//    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
//}
//
//android {
//    namespace = "com.hopper.customer.hopper"
//
//    // ✅ Your requirement
//    compileSdk = 35
//
//    defaultConfig {
//        applicationId = "com.hopper.customer.hopper"
//        minSdk = 24
//        targetSdk = 35
//        versionCode = flutter.versionCode
//        versionName = flutter.versionName
//
//        // FCM auto init
//        manifestPlaceholders["firebaseMessagingAutoInitEnabled"] = "true"
//    }
//    signingConfigs {
//        create("release") {
//            keyAlias = keystoreProperties["keyAlias"] as String
//            keyPassword = keystoreProperties["keyPassword"] as String
//            storeFile = file(keystoreProperties["storeFile"] as String)
//            storePassword = keystoreProperties["storePassword"] as String
//        }
//    }
//
//    buildTypes {
//        getByName("debug") {
//            isDebuggable = true
//        }
//
//        getByName("release") {
//            signingConfig = signingConfigs.getByName("release")
//            isMinifyEnabled = false
//            isShrinkResources = false
//        }
//    }
//
//    // ✅ Java / Kotlin setup
//    compileOptions {
//        sourceCompatibility = JavaVersion.VERSION_11
//        targetCompatibility = JavaVersion.VERSION_11
//        isCoreLibraryDesugaringEnabled = true
//    }
//
//    kotlinOptions {
//        jvmTarget = "11"
//    }
//
//    // Optional but safe for many native libs
//    packaging {
//        jniLibs {
//            useLegacyPackaging = true
//        }
//    }
//}
//
//flutter {
//    source = "../.."
//}
//
//dependencies {
//    implementation("org.jetbrains.kotlin:kotlin-stdlib:1.9.23")
//
//    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.3")
//
//    implementation(platform("com.google.firebase:firebase-bom:33.13.0"))
//    implementation("com.google.firebase:firebase-messaging")
//    implementation("com.google.firebase:firebase-analytics")
//
//    implementation("androidx.core:core-ktx:1.13.1")
//    implementation("androidx.appcompat:appcompat:1.7.0")
//    implementation("com.google.android.material:material:1.12.0")
//}
//
//// Helper so Flutter finds the RELEASE APK in expected path
//tasks.matching { it.name == "assembleRelease" }.configureEach {
//    doLast {
//        val src = file("$buildDir/outputs/apk/release/app-release.apk")
//        if (src.exists()) {
//            // Go from android/app -> project root -> build/app/outputs/flutter-apk
//            val destDir = file("$projectDir/../../build/app/outputs/flutter-apk")
//            destDir.mkdirs()
//            copy {
//                from(src)
//                into(destDir)
//            }
//            println("✅ Copied release APK to: $destDir")
//        } else {
//            println("⚠️ WARNING: app-release.apk not found at: $src")
//        }
//    }
//}
//
//// Helper so Flutter finds the DEBUG APK in expected path
//tasks.matching { it.name == "assembleDebug" }.configureEach {
//    doLast {
//        // Where the raw debug APK is usually generated by AGP
//        val src = file("$buildDir/outputs/apk/debug/app-debug.apk")
//        if (src.exists()) {
//            // Flutter expects: build/app/outputs/flutter-apk
//            val destDir = file("$projectDir/../../build/app/outputs/flutter-apk")
//            destDir.mkdirs()
//            copy {
//                from(src)
//                into(destDir)
//            }
//            println("✅ Copied debug APK to: $destDir")
//        } else {
//            println("⚠️ WARNING: app-debug.apk not found at: $src")
//        }
//    }
//}

