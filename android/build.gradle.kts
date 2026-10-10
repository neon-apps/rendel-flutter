group = "ai.rendel.sdk"
version = "1.0"

// The same toolchain `image_picker_android` builds with. The SDK already
// depends on it, so a host that builds with it builds with this.
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
    namespace = "ai.rendel.sdk"
    compileSdk = flutter.compileSdkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // `image_picker_android`'s floor, which a host already meets.
        minSdk = 24
    }
}
