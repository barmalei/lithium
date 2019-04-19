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

    ARTIFACT("a/a.txt", FileArtifact)
    ARTIFACT("a/a.ru", FileArtifact)
    ARTIFACT("a/*", FileArtifact)


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
        ARTIFACT('**/*.rb',  RunRubyScript)

        ARTIFACT("*") {
            ARTIFACT('**/*.rb',  RunRubyScript)
            ARTIFACT('**/*.java',  RunRubyScript)
        }
    }

    ARTIFACT("compile:*") {
        ARTIFACT('**/*.java',   JavaCompiler)  { @options = "-Xlint:deprecation" }
        ARTIFACT('**/*.groovy', GroovyCompiler) {
            puts "GROOVY COMPILER for #{@name}"
        }
        ARTIFACT('**/*.kt',     CompileKotlin)
        ARTIFACT('**/*.scala',  CompileScala)
        ARTIFACT('**/*.rb',     ValidateRubyScript)
        ARTIFACT('**/*.php',    ValidatePhpScript)

        ARTIFACT('**/*.py',    ValidatePythonScript)
        ARTIFACT('**/*.xml',   ValidateXML)
        ARTIFACT('**/pom.xml', MavenCompile)
        ARTIFACT('**/*.tt',    CompileTTGrammar)
        ARTIFACT('**/*.sass',  CompileSass)

        #ARTIFACT('**/*', TestFileMask) {
         #   puts ">>>>>>>>>>> #{name}"

            # ['*.java', '*.kt']

            # REQUIRE "compile:**/*.java"
            # REQUIRE "compile:**/*.groovy"
            # REQUIRE "compile:**/*.kt"
        #}
    }

    # ARTIFACT("build:*", '.') {
    #     ARTIFACT('**/*.java',  MavenCompile)
    # }

    ARTIFACT('checkstyle:**/*.java', CheckStyle)
    ARTIFACT('pmd:**/*.java',        PMD)

    ARTIFACT('mavenjar:**/*.jar', MavenJarFile)

    ARTIFACT('grep:', GREP) {
        @grep = $lithium_args[0] if $lithium_args.length > 0
    }

    ARTIFACT('inspect:*',  INSPECT)
    ARTIFACT('tree:*',  TREE)
    ARTIFACT('require:*', REQUIRE)
    ARTIFACT('cleanup:*', CLEANUP)
    ARTIFACT('meta:*',  META)

    ARTIFACT('INSTALL:', INSTALL)

    ARTIFACT('init:', '.', INIT)
}