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
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

// --- FIX PARA NAMESPACE EN LIBRERÍAS ANTIGUAS (VERSIÓN KOTLIN) ---
subprojects {
    afterEvaluate {
        project.extensions.findByName("android")?.let { androidExt ->
            try {
                // Buscamos si la librería tiene la propiedad namespace vacía y se la asignamos
                val getNamespace = androidExt.javaClass.getMethod("getNamespace")
                if (getNamespace.invoke(androidExt) == null) {
                    val setNamespace = androidExt.javaClass.getMethod("setNamespace", String::class.java)
                    setNamespace.invoke(androidExt, project.group.toString())
                }
            } catch (e: Exception) {
                // Si la librería no tiene esta estructura, la ignoramos silenciosamente
            }
        }
    }
}