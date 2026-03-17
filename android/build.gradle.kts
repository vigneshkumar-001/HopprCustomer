// android/build.gradle.kts

import org.gradle.api.tasks.Delete

plugins {
    id("com.android.application") apply false
    id("org.jetbrains.kotlin.android") apply false
    id("com.google.gms.google-services") apply false
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory) // ✅ avoids deprecated buildDir warning
}


//
//import org.gradle.api.tasks.Delete
//import org.gradle.api.Project
//import org.gradle.api.initialization.dsl.ScriptHandler
//import org.gradle.api.artifacts.dsl.RepositoryHandler
//import org.gradle.kotlin.dsl.*
//
//val newBuildDir = rootProject.layout.buildDirectory.dir("../../build").get()
//rootProject.layout.buildDirectory.value(newBuildDir)
//
//allprojects {
//    repositories {
//        google()
//        mavenCentral()
//    }
//}
//
//subprojects {
//    val newSubprojectBuildDir = newBuildDir.dir(project.name)
//    project.layout.buildDirectory.value(newSubprojectBuildDir)
//
//    // This ensures that all subprojects depend on app project evaluation (useful for plugins)
//    evaluationDependsOn(":app")
//}
//
//// Custom clean task
//tasks.register<Delete>("clean") {
//    delete(rootProject.layout.buildDirectory)
//}
