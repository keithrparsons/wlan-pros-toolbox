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

    // flutter_icmp_ping (the Android native side of dart_ping_ios) pins
    // compileSdk = 33, but its transitive AndroidX deps (fragment 1.7.1,
    // core 1.13.1, lifecycle 2.7.0, ...) require the consuming library to
    // compile against SDK 34+, so :flutter_icmp_ping:checkDebugAarMetadata
    // fails. Bump any Android library subproject that compiles below 34 up to
    // the app's compileSdk (36). Documented Flutter pattern for an out-of-date
    // plugin compileSdk: it overrides at evaluation time and does NOT edit
    // plugin source. compileSdk only widens the available API surface — it does
    // not change runtime behavior (targetSdk) or install range (minSdk) — so it
    // is safe here. Registered in THIS block (before the evaluationDependsOn
    // block below forces evaluation) and done reflectively so the root script
    // needs no compile-time dependency on AGP types.
    afterEvaluate {
        val androidExt = extensions.findByName("android") ?: return@afterEvaluate
        runCatching {
            val getter = androidExt.javaClass.methods.firstOrNull {
                it.name == "getCompileSdk" && it.parameterCount == 0
            }
            val current = getter?.invoke(androidExt) as? Int
            if (current != null && current < 34) {
                val setter = androidExt.javaClass.methods.firstOrNull {
                    it.name == "setCompileSdk" && it.parameterCount == 1
                }
                setter?.invoke(androidExt, 36)
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
