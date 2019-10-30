-> {
    Touch('touch:*')

    UglifiedJSFile('minjs:**/*.min.js')
    NodejsModule('npm:**/node_modules/*')

    OpenHTML('openhtml:**/*.html')

    RunMaven('mvn:*')
    BuildVaadinSass('buildsass:**/*.sass')

    RunPythonString('runpystr:')  {
        @script = $lithium_args.length > 0 ? $lithium_args.join(' ') : $stdin.read.strip
    }

    RunRubyString('runrbstr:') {
        @script = $lithium_args.length > 0 ? $lithium_args.join(' ') : $stdin.read.strip
    }

    CopyOfFile(".lithium/lib/test.jar") {
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

        GroupByExtension('**/*') {
            DO { | ext |
                BUILD_ARTIFACT("check:#{@name}#{ext}")
            }
        }
    }

    PMD('pmd:**/*.java')
    #MavenJarFile('mavenjar:**/*.jar')

    GREP('grep:') {
        @grep = $lithium_args[0] if $lithium_args.length > 0
    }
}