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

    JAVA('.env/junit5/java') {
        REQUIRE {
            DefaultClasspath() { JOIN('classes') }
            JUnit5Classpath()
        }
    }

    JAVA('.env/junit4/java') {
        REQUIRE {
            DefaultClasspath() { JOIN('classes') }
            JUnit4Classpath()
        }
    }

    JDTCompiler('compile:JDTCode.java') {
        REQUIRE {
            JAVA(".env/java17")  {
                SDKMAN("17")
            }
        }
    }

    JavaCompiler('compile:JUnit5Test.java') {
        REQUIRE '.env/junit5/java'
    }

    RunJavaCodeWithJUnit('test:JUnit5Test.java') {
        REQUIRE '.env/junit5/java'
    }

    JavaCompiler('compile:JUnit4Test.java') {
        REQUIRE '.env/junit4/java'
    }

    RunJavaCodeWithJUnit('test:JUnit4Test.java') {
        REQUIRE '.env/junit4/java'
    }
}