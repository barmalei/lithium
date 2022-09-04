
-> {
    REQUIRE {
        Directory('target') {
            BUILT {
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

    PomFile('pom.xml')

    MavenClasspath()

    JavaCompiler("compile:src/main/java/**/*.java") {
        @destination = 'target/classes'
    }

#     MATCH("src/test/**/*.java") {
#         JAVA {
#             REQUIRE {
#                 DefaultClasspath {
#                     JOIN('target/classes')
#                     JOIN('target/test-classes2')
#                 }
# #                MavenClasspath()
#             }
#         }

#         JavaCompiler("compile:**/*.java") {
#             @destination = 'target/test-classes'
#         }
#     }

    JavaCompiler("compile:src/test/java/**/*.java") {
        @destination = 'target/test-classes'
    }

    Directory("apidoc") {
        REQUIRE {
            GenerateJavaDoc("src/main/java/**/*.java")
        }
    }
}
