-> {
    Touch('touch:*')

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
        RunJavaCode      ('**/*.java')
        RunNodejs        ('**/*.js')
        RunPythonScript  ('**/*.py')
        RunPhpScript     ('**/*.php')
        RunShell         ('**/*.sh')
        RunJAR           ('**/*.jar')
        RunMaven         ('**/pom.xml')
        RunGroovyScript  ('**/*.groovy')
        RunKotlinCode    ('**/*.kt')
        RunScalaCode     ('**/*.scala')
        RunJavaClass     ('**/*.class')
        RunRubyScript    ('**/*.rb') {
            DONE { | art |
                Touch.build('dsdsd')
            }
        }
    }

    ARTIFACT("test:*") {
        RunJavaTestCode('**/*.java')
        RunJavaTestClass('**/*.class')
        RunScalaTestCode('**/*.scala')
        RunKotlinTestCode('**/*.kt')
        RunMaven('**/pom.xml') {
            TARGETS('test')
        }
    }

    ARTIFACT("compile:*") {
        JavaCompiler      ('**/*.java')  { OPT "-Xlint:deprecation" }
        GroovyCompiler    ('**/*.groovy')
        CompileKotlin     ('**/*.kt')
        CompileScala      ('**/*.scala')
        ValidateRubyScript('**/*.rb')
        ValidatePhpScript ('**/*.php')

        ValidatePythonScript('**/*.py')
        CompileMaven        ('**/pom.xml')
        ValidateXML         ('**/*.xml')
        CompileTTGrammar    ('**/*.tt')
        CompileSass         ('**/*.sass')

        GroupByExtension('**/*') {
            DO { | ext |
                BUILD_ARTIFACT("compile:#{@name}#{ext}")
            }
        }
    }

    ARTIFACT('check:*') {
        JavaCheckStyle('**/*.java')
        JavaScriptHint('**/*.js')
    }

    ARTIFACT('pmd:**/*.java',        PMD)
    #ARTIFACT('mavenjar:**/*.jar', MavenJarFile)

    ARTIFACT('grep:', GREP) {
        @grep = $lithium_args[0] if $lithium_args.length > 0
    }
}