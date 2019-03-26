-> {
    ARTIFACT('touch:*', Touch)

    ARTIFACT('minjs:**/*.js',     CompressJavaScript)
    ARTIFACT('openhtml:**/*.html',  OpenHTML)

    ARTIFACT('mvn:*',  RunMaven)
    ARTIFACT('buildsass:**/*.sass', BuildVaadinSass)

    ARTIFACT('runpystr:', RunPythonString) {
        @script = $arguments.length > 0 ? $arguments.join(' ') : $stdin.read.strip
    }

    ARTIFACT('runrbstr:', RunRubyString) {
        @script = $arguments.length > 0 ? $arguments.join(' ') : $stdin.read.strip
    }

    ARTIFACT("run:*", FileMaskContainer) {
        ARTIFACT('**/*.java',   RunJavaCode)
        ARTIFACT('run:**/*.js',     RunNodejs)
        ARTIFACT('run:**/*.py',     RunPythonScript)
        ARTIFACT('run:**/*.php',    RunPhpScript)
        ARTIFACT('run:**/*.sh',     RunShell)
        ARTIFACT('run:**/*.jar',    RunJAR)
        ARTIFACT('run:**/*.groovy', RunGroovyScript)
        ARTIFACT('run:**/*.kt',     RunKotlinCode)
        ARTIFACT('run:**/*.scala',  RunScalaCode)
        ARTIFACT('run:**/*.class',  RunJavaClass)
        ARTIFACT('**/*.rb',  RunRubyScript)
    }

    ARTIFACT("compile:*", FileMaskContainer) {
        ARTIFACT('**/*.java',   JavaCompiler) { @options = "-Xlint:deprecation" }
        ARTIFACT('**/*.groovy', GroovyCompiler)
        ARTIFACT('**/*.kt',     CompileKotlin)
        ARTIFACT('**/*.scala',  CompileScala)
        ARTIFACT('**/*.rb',     ValidateRubyScript)
        ARTIFACT('**/*.php',    ValidatePhpScript)

        ARTIFACT('**/*.py',   ValidatePythonScript)
        ARTIFACT('**/*.xml',  ValidateXML)
        ARTIFACT('**/*.tt',   CompileTTGrammar)
        ARTIFACT('**/*.sass', CompileSass)
    }

    ARTIFACT('checkstyle:**/*.java', CheckStyle)
    ARTIFACT('pmd:**/*.java',        PMD)

    ARTIFACT('mavenjar:**/*.jar', MavenJarFile)

    ARTIFACT('grep:', GREP) {
        @grep = $arguments[0] if $arguments.length > 0
    }

    ARTIFACT('info:*',  INSPECT)
    ARTIFACT('tree:*',  TREE)
    ARTIFACT('require:*', REQUIRE)
    ARTIFACT('cleanup:*', CLEANUP)
    ARTIFACT('list:.',    LIST)

    ARTIFACT('INSTALL:', INSTALL)

    ARTIFACT('init:', '.', INIT)
}