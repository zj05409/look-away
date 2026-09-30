import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

// Shares the marketing version with the macOS app; CI passes the commit count as versionCode.
val appVersion = rootProject.file("../VERSION").readText().trim()
val appVersionCode = (findProperty("versionCode") as String?)?.toIntOrNull() ?: 1

// Release signing comes from the environment (GitHub Actions secrets), never from the repo.
// Without it, release APKs are signed with the build machine's debug key.
val releaseKeystore = System.getenv("LOOKAWAY_KEYSTORE_FILE")?.let { file(it) }?.takeIf { it.exists() }

android {
    namespace = "io.github.zj05409.lookaway"
    compileSdk = 35

    defaultConfig {
        applicationId = "io.github.zj05409.lookaway"
        minSdk = 26
        targetSdk = 35
        versionCode = appVersionCode
        versionName = appVersion
    }

    signingConfigs {
        if (releaseKeystore != null) {
            create("release") {
                storeFile = releaseKeystore
                storePassword = System.getenv("LOOKAWAY_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("LOOKAWAY_KEY_ALIAS") ?: "lookaway"
                keyPassword = System.getenv("LOOKAWAY_KEY_PASSWORD") ?: System.getenv("LOOKAWAY_KEYSTORE_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = if (releaseKeystore != null) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    lint {
        checkReleaseBuilds = false
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

dependencies {
    testImplementation("junit:junit:4.13.2")
}
