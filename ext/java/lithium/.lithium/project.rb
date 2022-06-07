-> {
    JAVA {
        REQUIRE {
            DefaultClasspath {
                JOIN('classes')
                JOIN('lib/*.jar')
            }
        }
    }
}
