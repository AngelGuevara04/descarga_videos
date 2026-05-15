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

// --- SCRIPT PARA PARCHEAR NAMESPACES (EN EL ORDEN CORRECTO) ---
subprojects {
    afterEvaluate {
        project.extensions.findByName("android")?.let { androidExt ->
            try {
                val getNamespace = androidExt.javaClass.getMethod("getNamespace")
                val currentNamespace = getNamespace.invoke(androidExt) as? String

                // Si el namespace no existe o está vacío
                if (currentNamespace == null || currentNamespace.isEmpty()) {
                    var fallbackNamespace = project.group.toString()

                    // Si el grupo también está vacío o dice "unspecified", creamos uno válido
                    if (fallbackNamespace.isEmpty() || fallbackNamespace == "unspecified") {
                        val safeName = project.name.replace(Regex("[^a-zA-Z0-9_]"), "_")
                        fallbackNamespace = "com.patched.$safeName"
                    }

                    val setNamespace = androidExt.javaClass.getMethod("setNamespace", String::class.java)
                    setNamespace.invoke(androidExt, fallbackNamespace)
                }
            } catch (e: Exception) {
                // Ignorar si la librería no tiene esta configuración
            }
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