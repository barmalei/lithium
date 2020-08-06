
-> {
    REQUIRE {
        Directory('target') {
            puts "!!!!"
            DONE {
                puts ">>>"
                RunMaven.build('.')
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
}
