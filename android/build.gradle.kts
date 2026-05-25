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
    afterEvaluate {
        // Spezialfall: disable_battery_optimization braucht außerdem ältere SDK-Levels.
        if (name == "disable_battery_optimization" && plugins.hasPlugin("com.android.library")) {
            extensions.findByName("android")?.let { ext ->
                val androidExt = ext as com.android.build.gradle.LibraryExtension
                androidExt.apply {
                    compileSdk = 34
                    defaultConfig {
                        targetSdk = 34
                    }
                }
            }
        }

        // Alle Android-Module (Library oder Application) auf Java 11 zwingen,
        // damit veraltete Plugin-Defaults (source/target = 8) keine
        // "Quellwert 8 ist veraltet"-Warnungen mehr erzeugen.
        plugins.withId("com.android.library") {
            extensions.findByName("android")?.let { ext ->
                val androidExt = ext as com.android.build.gradle.LibraryExtension
                androidExt.compileOptions.sourceCompatibility = JavaVersion.VERSION_11
                androidExt.compileOptions.targetCompatibility = JavaVersion.VERSION_11
            }
        }
        plugins.withId("com.android.application") {
            extensions.findByName("android")?.let { ext ->
                val androidExt = ext as com.android.build.gradle.AppExtension
                androidExt.compileOptions.sourceCompatibility = JavaVersion.VERSION_11
                androidExt.compileOptions.targetCompatibility = JavaVersion.VERSION_11
            }
        }

    }
}