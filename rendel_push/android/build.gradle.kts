group = "ai.rendel.push"
version = "1.0"

// The same toolchain as `rendel` itself.
buildscript {
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:8.13.1")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    id("com.android.library")
}

android {
    namespace = "ai.rendel.push"
    compileSdk = flutter.compileSdkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        minSdk = 24
    }
}

dependencies {
    // A range, not a pin (design/plans/push-channels.md §3): an app with
    // Firebase of its own, or its BoM, picks the version inside it, and one
    // without gets the preferred one. Java, so no Kotlin plugin version
    // comes with it either.
    implementation("com.google.firebase:firebase-messaging") {
        version {
            require("[23.0.0, 27.0.0)")
            prefer("25.1.3")
        }
    }
    implementation("androidx.core:core:1.13.1")
}
