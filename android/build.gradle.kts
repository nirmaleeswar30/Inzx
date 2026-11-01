allprojects {
    repositories {
        google()
        mavenCentral()
    }
    // Every Media3 module at one version, for the app and every plugin
    // (just_audio, video_player…): Automix's audio sink, ported from
    // BitChord, is written against Media3 1.11's AudioSink API, and mixed
    // Media3 versions on one classpath break at runtime.
    configurations.all {
        resolutionStrategy.eachDependency {
            if (requested.group == "androidx.media3") useVersion("1.11.0")
        }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
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
