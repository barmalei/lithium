-> {
    JAVA {
        REQUIRE {
            DefaultClasspath {
                JOIN('classes')
                JOIN('lib/*.jar')
            }
        }
    }

    JavaCheckStyle("check:**/*.java") {
        @checkstyle_version = "8"
    }

    EnvArtifact('.env/DEPLOY') {
        REQUIRE {
            MavenDependenciesDir("lib")
        }
    }
}
