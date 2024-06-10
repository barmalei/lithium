
-> {
    REQUIRE {
        Directory('build') {
            BUILT {
                ENCLOSE(RunGradle) {
                    TARGETS('build')
                }
            }
        }
    }

    JAVA {
        REQUIRE {
            DefaultClasspath {
                JOIN('build/classes/java/main')
                JOIN('build/classes/java/test')
            }
            GradleClasspath()
        }
    }

    KOTLIN {
        REQUIRE {
            DefaultClasspath {
                JOIN('build/classes/kotlin/main')
                JOIN('build/classes/kotlin/test')
            }
            GradleClasspath()
        }
    }

    KotlinCompiler("compile:src/main/kotlin/**/*.kt") {
        DESTINATION('build/classes/kotlin/main')
    }

    JavaCompiler("compile:src/main/java/**/*.java") {
        DESTINATION('build/classes/java/main')
    }

    KotlinCompiler("compile:src/test/java/**/*.java") {
        DESTINATION('build/classes/kotlin/test')
    }

    JavaCompiler("compile:src/test/java/**/*.java") {
        DESTINATION('build/classes/java/main')
    }

    Directory("apidoc") {
        REQUIRE {
            GenerateJavaDoc("src/main/java/**/*.java")
        }
    }
}
