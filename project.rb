-> {
    #$lithium_options['v'] = 2
    $lithium_options['app_server_root'] = File.join($lithium_code, '..', 'tomcat', 'webapps')

    Touch('touch:*')

    UglifiedJSFile('minjs:**/*.min.js')
    NodejsModule('npm:**/node_modules/*')

    RunMaven('mvn:*')

    MATCH("run:*") {
        RunJavaCode('.lithium/lib/JavaTools.java') {
            DefaultClasspath {
                JOIN('.lithium/classes')
            }
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
        RunRubyScript    ('**/*.rb') 
    }

    MATCH("test:*") {
        RunJavaCodeWithJUnit('**/*.java')
        RunJavaClassWithJUnit('**/*.class')
        RunMaven('**/pom.xml') {
            TARGETS('test')
        }
    }

    MATCH("compile:*") {
        JavaCompiler('.lithium/lib/JavaTools.java') {
            @destination = '.lithium/classes'
        }

        JavaCompiler        ('**/*.java')
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
                Project.build("compile:#{@name}#{ext}")
            }
        }
    }

    MATCH('check:*') {
        JavaCheckStyle('**/*.java')
        JavaScriptHint('**/*.js')

        GroupByExtension('**/*') {
            DO { | ext |
                Project.build("check:#{@name}#{ext}")
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
