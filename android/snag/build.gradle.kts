import com.vanniktech.maven.publish.AndroidSingleVariantLibrary
import com.vanniktech.maven.publish.SonatypeHost

plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
    alias(libs.plugins.kotlinx.serialization)
    alias(libs.plugins.vanniktechMavenPublish)
}

mavenPublishing {
    coordinates("io.github.thanhcuong1990", "snag", "1.0.21")
    publishToMavenCentral(SonatypeHost.CENTRAL_PORTAL, automaticRelease = true)
    configure(AndroidSingleVariantLibrary())

    pom {
        packaging = "aar"
        name.set("Snag")
        description.set("Snag is a little native iOS/Android network debugger")
        url.set("https://github.com/thanhcuong1990/Snag.git")
        inceptionYear.set("2025")

        licenses {
            license {
                name.set("Apache License Version 2.0, January 2004")
                url.set("https://github.com/thanhcuong1990/Snag?tab=License-1-ov-file")
            }
        }

        developers {
            developer {
                id.set("thanhcuong1990")
                name.set("Cuong Lam")
                email.set("thanhcuong1990@gmail.com")
            }
        }

        scm {
            connection.set("scm:git@github.com:thanhcuong1990/Snag")
            developerConnection.set("scm:git@github.com:thanhcuong1990/Snag.git")
            url.set("https://github.com/thanhcuong1990/Snag.git")
        }
    }

    signAllPublications()
}

android {
    namespace = "com.snag"
    compileSdk = libs.versions.compileSdk.get().toInt()

    defaultConfig {
        minSdk = libs.versions.minSdk.get().toInt()
        compileSdk = libs.versions.compileSdk.get().toInt()

        aarMetadata {
            minCompileSdk = libs.versions.minSdk.get().toInt()
        }

        multiDexEnabled = true

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        consumerProguardFiles("consumer-rules.pro")
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.appcompat)
    implementation(libs.material)
    implementation(libs.androidx.startup.runtime)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.logging.interceptor)
    implementation(libs.timber)
    implementation(libs.socket.io.client)
    compileOnly("com.facebook.react:react-android:0.72.0")
    testImplementation(libs.junit)
    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.espresso.core)
}