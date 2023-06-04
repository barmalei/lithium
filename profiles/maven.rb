
-> {
    REQUIRE {
        Directory('target') {
            BUILT {
                ENCLOSE(RunMaven) {
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

    MavenClasspath()

    JavaCompiler("compile:src/main/java/**/*.java") {
        DESTINATION('target/classes')
        # REQUIRE {
        #     DestinationDirectory('target/classes')
        # }
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

    Directory("apidoc") {
        REQUIRE {
            GenerateJavaDoc("src/main/java/**/*.java")
        }
    }
}
