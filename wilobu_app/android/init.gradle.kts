allprojects {
    afterEvaluate {
        // Ensure Android plugin configurations exist before Flutter plugin tries to access them
        if (project.hasProperty("android")) {
            val android = project.extensions.findByName("android")
            if (android != null) {
                project.logger.lifecycle("Android extension found for ${project.name}")
            }
        }
    }
}
