
-> {
    JAVA {
        DefaultClasspath {
            JOIN('classes')
            JOIN('lib')
        }
    }

    JavaCompiler("compile:src/**/*.java") {
        @destination = 'classes'
    }
}
