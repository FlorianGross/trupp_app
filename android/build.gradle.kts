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

// WICHTIG: afterEvaluate-Hooks MÜSSEN vor evaluationDependsOn(":app") registriert
// werden. Letzteres triggert die Evaluation der Plugin-Subprojekte sofort, und
// danach lässt sich afterEvaluate auf bereits evaluierten Projekten nicht mehr
// aufrufen ("Cannot run Project.afterEvaluate(Action) when the project is already
// evaluated").
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

        // Kotlin jvmTarget ebenfalls auf 11 zwingen — sonst kommt es zu
        // "Inconsistent JVM-target compatibility" wenn ein Plugin (z.B.
        // battery_plus) intern jvmTarget = 17 setzt.
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions {
                jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11)
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}