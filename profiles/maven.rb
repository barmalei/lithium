
-> {
    REQUIRE {
        Directory('target') {
            DONE {
                RunMaven.build('.', self.owner)
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
        puts "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
        @destination = 'target/classes'

        DONE {
            puts ("!!!!!!!!!!!!!!! #{self.class}: #{self.owner}")
        }
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
