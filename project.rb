-> {
    ARTIFACT('touch:*', Touch)

    ARTIFACT('minjs:**/*.min.js',  UglifiedJSFile)
    ARTIFACT('npm:**/node_modules/*',  NodejsModule)

    ARTIFACT('openhtml:**/*.html', OpenHTML)

    ARTIFACT('mvn:*', RunMaven)
    ARTIFACT('buildsass:**/*.sass', BuildVaadinSass)

    ARTIFACT('runpystr:', RunPythonString)  {
        @script = $lithium_args.length > 0 ? $lithium_args.join(' ') : $stdin.read.strip
    }

    ARTIFACT('runrbstr:', RunRubyString) {
        @script = $lithium_args.length > 0 ? $lithium_args.join(' ') : $stdin.read.strip
    }

    ARTIFACT(".lithium/lib/test.jar", CopyOfFile) {
        @source = "jnc-easy/jnc-easy-1.1.1/test.jar"
    }

    ARTIFACT("run:*") {
        ARTIFACT('**/*.java',   RunJavaCode)
        ARTIFACT('**/*.js',     RunNodejs)
        ARTIFACT('**/*.py',     RunPythonScript)
        ARTIFACT('**/*.php',    RunPhpScript)
        ARTIFACT('**/*.sh',     RunShell)
        ARTIFACT('**/*.jar',    RunJAR)
        ARTIFACT('**/pom.xml',  RunMaven)
        ARTIFACT('**/*.groovy', RunGroovyScript)
        ARTIFACT('**/*.kt',     RunKotlinCode)
        ARTIFACT('**/*.scala',  RunScalaCode)
        ARTIFACT('**/*.class',  RunJavaClass)
        ARTIFACT('**/*.rb',     RunRubyScript) {
            DONE { | art |
                Touch.build('dsdsd')
            }
        }
    }

    ARTIFACT("test:*") {
        ARTIFACT('**/*.java', RunJavaTestCode)
        ARTIFACT('**/*.class', RunJavaTestClass)
        ARTIFACT('**/*.scala', RunScalaTestCode)
        ARTIFACT('**/*.kt', RunKotlinTestCode)
        ARTIFACT('**/pom.xml', RunMaven) {
            @targets = [ 'test' ]
        }
    }

    ARTIFACT("compile:*") {
        ARTIFACT('**/*.java',   JavaCompiler)  { OPT "-Xlint:deprecation" }
        ARTIFACT('**/*.groovy', GroovyCompiler)
        ARTIFACT('**/*.kt',     CompileKotlin)
        ARTIFACT('**/*.scala',  CompileScala)
        ARTIFACT('**/*.rb',     ValidateRubyScript)
        ARTIFACT('**/*.php',    ValidatePhpScript)

        ARTIFACT('**/*.py',    ValidatePythonScript)
        ARTIFACT('**/pom.xml', CompileMaven)
        ARTIFACT('**/*.xml',   ValidateXML)
        ARTIFACT('**/*.tt',    CompileTTGrammar)
        ARTIFACT('**/*.sass',  CompileSass)

        ARTIFACT('**/*', GroupByExtension) {
            DO { | ext |
                BUILD_ARTIFACT("compile:#{@name}#{ext}")
            }
        }
    }

    ARTIFACT('check:**/*.java', CheckStyle)
    ARTIFACT('pmd:**/*.java',        PMD)
    #ARTIFACT('mavenjar:**/*.jar', MavenJarFile)

    ARTIFACT('grep:', GREP) {
        @grep = $lithium_args[0] if $lithium_args.length > 0
    }
}