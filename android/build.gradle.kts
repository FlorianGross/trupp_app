allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

subprojects {
    // Wir greifen auf jedes Subprojekt zu.
    if (name == "disable_battery_optimization") {
        // afterEvaluate, damit wir NACH der Plugin-Initialisierung überschreiben.
        afterEvaluate {
            // Nur wenn es wirklich ein Android Library Modul ist.
            if (plugins.hasPlugin("com.android.library")) {

                // Zugriff auf die Android-Extension in Kotlin DSL:
                // in AGP 8 ist das com.android.build.gradle.LibraryExtension
                extensions.findByName("android")?.let { ext ->
                    @Suppress("UNCHECKED_CAST")
                    val androidExt = ext as com.android.build.gradle.LibraryExtension

                    // compileSdkVersion / defaultConfig / compileOptions überschreiben
                    androidExt.apply {
                        compileSdk = 34

                        defaultConfig {
                            targetSdk = 34
                            // minSdk lassen wir, das setzt das Plugin selber
                        }

                        compileOptions {
                            sourceCompatibility = JavaVersion.VERSION_11
                            targetCompatibility = JavaVersion.VERSION_11
                        }
                    }
                }
            }
        }
    }
}