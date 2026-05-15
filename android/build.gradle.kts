allprojects {
    repositories {
        google()
        mavenCentral()
        // --- SERVIDOR ESPEJO COMUNITARIO PARA FFMPEG-KIT 6.0-2 ---
        maven { url = uri("https://raw.githubusercontent.com/DucLQ92/ffmpeg-kit-audio/main") }
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

// --- SCRIPT MAESTRO PARA PARCHEAR PLUGINS REBELDES ---
subprojects {
    afterEvaluate {
        project.extensions.findByName("android")?.let { androidExt ->
            // 1. Parche de Namespace (Para FFmpeg)
            try {
                val getNamespace = androidExt.javaClass.getMethod("getNamespace")
                val currentNamespace = getNamespace.invoke(androidExt) as? String

                if (currentNamespace == null || currentNamespace.isEmpty()) {
                    var fallbackNamespace = project.group.toString()
                    if (fallbackNamespace.isEmpty() || fallbackNamespace == "unspecified") {
                        val safeName = project.name.replace(Regex("[^a-zA-Z0-9_]"), "_")
                        fallbackNamespace = "com.patched.$safeName"
                    }
                    val setNamespace = androidExt.javaClass.getMethod("setNamespace", String::class.java)
                    setNamespace.invoke(androidExt, fallbackNamespace)
                }
            } catch (e: Exception) {}

            // 2. Forzar compatibilidad de Java a versión 17
            try {
                val compileOptions = androidExt.javaClass.getMethod("getCompileOptions").invoke(androidExt)
                compileOptions.javaClass.getMethod("setSourceCompatibility", JavaVersion::class.java).invoke(compileOptions, JavaVersion.VERSION_17)
                compileOptions.javaClass.getMethod("setTargetCompatibility", JavaVersion::class.java).invoke(compileOptions, JavaVersion.VERSION_17)
            } catch (e: Exception) {}
        }
    }

    // 3. Forzar compatibilidad de Kotlin a versión 17
    tasks.configureEach {
        if (name.startsWith("compile") && name.endsWith("Kotlin")) {
            try {
                val kotlinOptions = javaClass.getMethod("getKotlinOptions").invoke(this)
                kotlinOptions.javaClass.getMethod("setJvmTarget", String::class.java).invoke(kotlinOptions, "17")
            } catch (e: Exception) {}
        }
    }
}
// --------------------------------------------------------------------

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}