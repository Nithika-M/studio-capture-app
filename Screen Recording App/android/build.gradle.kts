val baseBuildDir = file("C:/Users/KAVIB/.flutter_builds/screen_recorder")

allprojects {
    repositories {
        google()
        mavenCentral()
    }
    layout.buildDirectory.set(baseBuildDir.resolve(project.name))
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
