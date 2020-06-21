
-> {
    JAVA {
        DefaultClasspath {
            JOIN('target/classes')
            JOIN('target/test-classes')
        }

        MavenClasspath()
    }

    JavaCompiler("compile:src/main/java/**/*.java") {
        Directory('target') {
            DONE {
               RunMaven.build('.')
            }
        }

        @destination = 'target/classes'
    }

    JavaCompiler("compile:src/test/java/**/*.java") {
        @destination = 'target/test-classes'
    }
}
