
-> {
    REQUIRE {
        Directory('target') {
            BUILT {
                ENCLOSE('pom.xml', RunMaven) {
                    TARGETS('compile')
                }
            }
        }
    }

    java_version = self['java_version']
    JAVA {
        REQUIRE {
            DefaultClasspath {
                JOIN('target/classes')
                JOIN('target/test-classes')
            }

            MavenClasspath()
        }

        SDKMAN(java_version) unless java_version.nil?
    }

    PomFile('pom.xml')

#    MavenClasspath()

    JavaCompiler("compile:src/main/java/**/*.java") {
        DESTINATION('target/classes')
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
        DESTINATION('target/test-classes')
    }

    # Artifact("gendoc") {
    #     REQUIRE {
    #         GenerateJavaDoc("src/main/java/**/*.java")
    #     }
    # }
}
