
-> {
    REQUIRE {
        Directory('target') {
            DONE {
                RunMaven(homedir) {
                    TARGETS('compile')
                }
            }
        }
    }

    JAVA {
        REQUIRE {
            DefaultClasspath {
                JOIN('target/classes')
                JOIN('target/test-classes')
            }
            MavenClasspath()
        }
    }

    JavaCompiler("compile:src/main/java/**/*.java") {
        @destination = 'target/classes'
    }

    JavaCompiler("compile:src/test/java/**/*.java") {
        @destination = 'target/test-classes'
    }

    Directory("apidoc") {
        REQUIRE {
            GenerateJavaDoc("src/main/java/**/*.java")
        }
    }
}
