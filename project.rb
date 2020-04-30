-> {
    Touch('touch:*')

    UglifiedJSFile('minjs:**/*.min.js')
    NodejsModule('npm:**/node_modules/*')

    RunMaven('mvn:*')

    # TODO: ?
    RunPythonString('runpystr:')  {
        @script = $lithium_args.length > 0 ? $lithium_args.join(' ') : $stdin.read.strip
    }

    # TODO: ?
    RunRubyString('runrbstr:') {
        @script = $lithium_args.length > 0 ? $lithium_args.join(' ') : $stdin.read.strip
    }

    # TODO: should be removed
    CopyOfFile(".lithium/lib/test.jar") {
        @source = "jnc-easy/jnc-easy-1.1.1/test.jar"
    }

    ARTIFACT("run:*") {
        ARTIFACT('.lithium/**/*.java') {

            puts ">>>>>>>>>>>>>>>>>>>>>>>>>>"
            DefaultClasspath {
                PATH('.lithium/classes')
            }

            RunJavaCode('**/*.java')
        }

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
        RunHtml          ('**/*.html')
        RunRubyScript    ('**/*.rb') {
            # TODO: remove after documenting
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
        ARTIFACT('.lithium/**/*.java') {
            DefaultClasspath {
                PATH('.lithium/classes')
            }

            JDTCompiler('**/*.java') {
                @destination = '.lithium/classes'
            }
        }

        JavaCompiler('**/*.java')  { OPT '-Xlint:deprecation' }

        GroovyCompiler      ('**/*.groovy')
        KotlinCompiler      ('**/*.kt')
        ScalaCompiler       ('**/*.scala')
        ValidateRubyScript  ('**/*.rb')
        ValidatePhpScript   ('**/*.php')
        TypeScriptCompiler  ('**/*.ts')
        RunNodejs           ('**/*.js') { OPT '--check'  }
        ValidatePythonScript('**/*.py')
        MavenCompiler       ('**/pom.xml')
        ValidateXML         ('**/*.xml')
        CompileTTGrammar    ('**/*.tt')
        CompileSass         ('**/*.sass')
        BuildVaadinSass     ('VAADIN/**/*.scss')

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

    # TODO: grep class already fetch lithium arguments
    GREP('grep:') {
        @grep = $lithium_args[0] if $lithium_args.length > 0
    }
}