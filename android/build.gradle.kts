allprojects {
    repositories {
        google()
        mavenCentral()
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
// Some plugins (e.g. file_picker) still compile against an older Android API,
// which newer plugins reject. Force every Android subproject to compileSdk 36.
// Registered before evaluationDependsOn below, which would otherwise evaluate
// :app before this afterEvaluate could attach.
subprojects {
    afterEvaluate {
        extensions.findByName("android")?.withGroovyBuilder { "compileSdkVersion"(36) }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
