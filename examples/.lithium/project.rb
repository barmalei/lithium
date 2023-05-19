-> {
    JAVA {
        REQUIRE {
            DefaultClasspath() {
               JOIN('classes')
               JOIN('../ext/java/parser/*.jar')
            }
        }
    }

    KOTLIN {
        REQUIRE {
            DefaultClasspath() {
               JOIN('classes')
            }
        }
    }
}