
-> {
    REQUIRES {
        Directory('target') {
            DONE {
                RunMaven {
                    TARGETS('compile')
                }
            }
        }
    }

    JAVA {
        REQUIRES {
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
        REQUIRES {
            GenerateJavaDoc("src/main/java/**/*.java")
        }

        # BUILD {
        #     DONE {

        #     }
        # }

        # DONE {
        #     GenerateJavaDoc.build("src/main/java/**/*.java")
        # }
    }
}
