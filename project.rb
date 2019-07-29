-> {
    ARTIFACT('touch:*', Touch)

    ARTIFACT('minjs:**/*.js',      CompressJavaScript)
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
        ARTIFACT('**/*.groovy', RunGroovyScript)
        ARTIFACT('**/*.kt',     RunKotlinCode)
        ARTIFACT('**/*.scala',  RunScalaCode)
        ARTIFACT('**/*.class',  RunJavaClass)
        ARTIFACT('**/*.rb',     RunRubyScript)
    }

    ARTIFACT("compile:*") {
        ARTIFACT('**/*.java',   JavaCompiler)  { OPT "-Xlint:deprecation" }
        ARTIFACT('**/*.groovy', GroovyCompiler)
        ARTIFACT('**/*.kt',     CompileKotlin)
        ARTIFACT('**/*.scala',  CompileScala)
        ARTIFACT('**/*.rb',     ValidateRubyScript)
        ARTIFACT('**/*.php',    ValidatePhpScript)

        ARTIFACT('**/*.py',    ValidatePythonScript)
        ARTIFACT('**/*.xml',   ValidateXML)
        ARTIFACT('**/pom.xml', CompileMaven)
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

    ARTIFACT('inspect:*',  INSPECT)
    ARTIFACT('tree:*',     TREE)
    ARTIFACT('require:*',  REQUIRE)
    ARTIFACT('cleanup:*',  CLEANUP)
    ARTIFACT('meta:*',     META)

    ARTIFACT('INSTALL:', INSTALL)


    ARTIFACT('init:', INIT)
}