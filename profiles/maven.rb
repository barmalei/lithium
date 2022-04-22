
-> {
    REQUIRE {
        Directory('target') {
            DONE {
                RunMaven {
                    TARGETS('compile')
                }
            }
        }
    }

    JAVA {
        DefaultClasspath {
            JOIN('target/classes')
            JOIN('target/test-classes')
        }

        MavenClasspath()
    }

    JavaCompiler("compile:src/main/java/**/*.java") {
        @destination = 'target/classes'
    }

    JavaCompiler("compile:src/test/java/**/*.java") {
        @destination = 'target/test-classes'
    }

    Directory("apidoc") {
        GenerateJavaDoc("src/main/java/**/*.java")
        # DONE {
        #     GenerateJavaDoc.build("src/main/java/**/*.java")
        # }
    }
}
