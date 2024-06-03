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
            DefaultClasspath() { JOIN('classes') }
        }
    }

    JAVA('@junit5/java') {
        REQUIRE {
            DefaultClasspath() { JOIN('classes') }
            JUnit5Classpath()
        }
    }

    JAVA('@junit4/java') {
        REQUIRE {
            DefaultClasspath() { JOIN('classes') }
            JUnit4Classpath()
        }
    }

    JDTCompiler('compile:JDTCode.java') {
        REQUIRE {
            JAVA("@java17")  {
                SDKMAN("17")
            }
        }
    }

    JavaCompiler('compile:JUnit5Test.java') {
        REQUIRE '@junit5/java'
    }

    RunJavaCodeWithJUnit('test:JUnit5Test.java') {
        REQUIRE '@junit5/java'
    }

    JavaCompiler('compile:JUnit4Test.java') {
        REQUIRE '@junit4/java'
    }

    RunJavaCodeWithJUnit('test:JUnit4Test.java') {
        REQUIRE '@junit4/java'
    }
}