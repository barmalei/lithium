-> {
    ARTIFACT('touch:*', Touch)

    ARTIFACT('runjava:**/*.java',  RunJavaCode) { }

    ARTIFACT('runjar:**/*.java',      RunJAR)
    ARTIFACT('rungroovy:**/*.groovy', RunGroovyScript)
    ARTIFACT('runkotlin:**/*.kt',     RunKotlinCode)
    ARTIFACT('runscala:**/*.scala',   RunScalaCode)
    ARTIFACT('runclass:**/*.class',   RunJavaClass)
    ARTIFACT('runrb:**/*.rb',         RunRubyScript)

    ARTIFACT('minjs:**/*.js',     CompressJavaScript)
    ARTIFACT('runjs:**/*.js',     RunNodejs)
    ARTIFACT('runpy:**/*.py',     RunPythonScript)
    ARTIFACT('runphp:**/*.php',    RunPhpScript)
    ARTIFACT('openhtml:**/*.html',  OpenHTML)
    ARTIFACT('runsh:**/*.sh',     RunShell)
    ARTIFACT('mvn:*',  RunMaven)
    ARTIFACT('buildsass:**/*.sass', BuildVaadinSass)

    ARTIFACT('runpystr:', RunPythonString) {
        @script = $arguments.length > 0 ? $arguments.join(' ') : $stdin.read.strip
    }

    ARTIFACT('runrbstr:', RunRubyString) {
        @script = $arguments.length > 0 ? $arguments.join(' ') : $stdin.read.strip
    }


    ARTIFACT('compilejava:**/*.java',     JavaCompiler) { @options = "-Xlint:deprecation" }
    ARTIFACT('compilegroovy:**/*.groovy', GroovyCompiler)
    ARTIFACT('compilekotlin:**/*.kt',    CompileKotlin)
    ARTIFACT('compilescala:**/*.scala',  CompileScala)
    ARTIFACT('compilerb:**/*.rb',     ValidateRubyScript)
    ARTIFACT('compilephp:**/*.php', ValidatePhpScript)

    ARTIFACT('compilepy:**/*.py', ValidatePythonScript)
    ARTIFACT('compilexml:**/*.xml', ValidateXML)
    ARTIFACT('compilett:**/*.tt', CompileTTGrammar)
    ARTIFACT('compilesass:**/*.sass', CompileSass)

    ARTIFACT('checkstyle:**/*.java', CheckStyle)
    ARTIFACT('pmd:**/*.java',        PMD)

    ARTIFACT('run:**/*', ArtifactSelector) {
        @map = {
          '\.java$'   => 'runjava',
          '\.class$'  => 'runclass',
          '\.kt$'     => 'runkotlin',
          '\.scala$'  => 'runscala',
          '\.jar$'    => 'runjar',
          '\.rb$'     => 'runrb',
          '\.py$'     => 'runpy',
          '\.js$'     => 'runjs',
          '\.sh$'     => 'runsh',
          '\.html$'   => 'openhtml',
          '\.php$'    => 'runphp',
          '\.groovy$' => 'rungroovy'
        }
    }

    ARTIFACT('compile:**/*', ArtifactSelector) {
        @map =  {
          '\.java$'    => 'compilejava',
          '\.rb$'      => 'compilerb',
          '\.py$'      => 'compilepy',
          '\.xml$'     => 'compilexml',
          '\.kt$'      => 'compilekotlin',
          '\.scala$'   => 'compilescala',
          '\.groovy$'  => 'compilegroovy',
          '\.c$'       => 'make',
          '\.cpp$'     => 'make',
          'pom\.xml$'  => 'mvn',
          '\.php$'     => 'compilephp',
          '\.tt$'      => 'compilett',
          '\.treetop$' => 'compilett',
       #   '\.scss$'   => 'compilesass',
          '\.scss$'    => 'buildsass'  }
    }

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