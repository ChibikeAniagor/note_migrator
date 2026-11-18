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

// Some plugins still declare a compileSdk below what a dependency requires.
// Registered here, before evaluationDependsOn below evaluates plugin projects.
gradle.beforeProject {
    if (this == rootProject) {
        return@beforeProject
    }
    afterEvaluate {
        val android = extensions.findByName("android") ?: return@afterEvaluate
        val sdkSetter = android.javaClass.methods.find { method ->
            method.name == "setCompileSdk" &&
                method.parameterTypes.size == 1 &&
                (method.parameterTypes[0] == Int::class.javaPrimitiveType ||
                    method.parameterTypes[0] == Integer::class.java)
        }
        if (sdkSetter != null) {
            val current = android.javaClass.methods
                .find { it.name == "getCompileSdk" && it.parameterTypes.isEmpty() }
                ?.invoke(android) as? Int
            if (current == null || current < 36) {
                sdkSetter.invoke(android, 36)
            }
            return@afterEvaluate
        }
        val versionSetter = android.javaClass.methods.find { method ->
            method.name == "setCompileSdkVersion" &&
                method.parameterTypes.size == 1 &&
                (method.parameterTypes[0] == Int::class.javaPrimitiveType ||
                    method.parameterTypes[0] == Integer::class.java)
        } ?: return@afterEvaluate
        versionSetter.invoke(android, 36)
    }
}

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
