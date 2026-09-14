plugins {
    id("com.android.application")
}

val keystorePath = providers.environmentVariable("ANDROID_KEYSTORE_PATH").orNull
val keystorePassword = providers.environmentVariable("ANDROID_KEYSTORE_PASSWORD").orNull
val keyAliasValue = providers.environmentVariable("ANDROID_KEY_ALIAS").orNull
val keyPasswordValue = providers.environmentVariable("ANDROID_KEY_PASSWORD").orNull

android {
    namespace = "com.undu.safeflame"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.qila.safeflame"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
    }

    signingConfigs {
        create("release") {
            if (keystorePath != null) {
                storeFile = file(keystorePath)
                storePassword = keystorePassword
                keyAlias = keyAliasValue
                keyPassword = keyPasswordValue
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName("release")
        }
    }

    androidResources {
        noCompress += "wav"
    }

    sourceSets["main"].assets.srcDir(file("../../files/SafeFlame/Resources"))
}
