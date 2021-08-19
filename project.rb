-> {
    $lithium_options['v'] = 2
    $lithium_options['app_server_root'] = File.join($lithium_code, '..', 'tomcat', 'webapps')

    # REQUIRE  {
    #     puts ".............. #{@name}  '#{self.owner.nil?}' "
    #     DONE {
    #         puts ">>>>>>>>>>>>>>>>>>> #{self.name}"
    #         art = Directory.build('target')
    #         puts ">>>>>>>>>>>>>>>>>>> #{art.owner}"
    #     }
    # }

    Touch('touch:*')

    UglifiedJSFile('minjs:**/*.min.js')
    NodejsModule('npm:**/node_modules/*')

    RunMaven('mvn:*')

    CopyToDirectory("test") {
        @full_copy = true
        FileMaskSource('.lithium/lib/*')
        FileMaskSource('classes/com/**/*')
        MetaSourceFile('.lithium/meta/test.dir')
    }

    ZipFile("test.zip") {
        FileMaskSource('.lithium/lib/*', '.lithium/lib')
    }

    JarFile("test.jar") {
        FileMaskSource('.lithium/lib/*')
    }

    UglifiedJSFile("test.min.js") {
        FileMaskSource('.lithium/exa mples/easyoop.js')
    }

    MATCH("run:*") {
        RunJavaCode('.lithium/ext/java/lithium/src/*') {
            DefaultClasspath("li_run_class_path") {
                JOIN('.lithium/ext/java/lithium/classes')
                JOIN('.lithium/ext/java/lithium/lib/*.jar')
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
        CppCodeRunner    ('**/*.cpp')
        CppCodeRunner    ('**/*.c')
    }

    MATCH("test:*") {
        RunJavaCodeWithJUnit('**/*.java')
        RunJavaClassWithJUnit('**/*.class')
        RunMaven('**/pom.xml') {
            TARGETS('test')
        }
    }

    MATCH("compile:*") {
        JavaCompiler('.lithium/ext/java/lithium/src/*.java') {
            DefaultClasspath("li_run_class_path") {
                JOIN('.lithium/ext/java/lithium/classes')
                JOIN('.lithium/ext/java/lithium/lib/*.jar')
            }

            @destination = '.lithium/ext/java/lithium/classes'
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
        RunMakefile         ('**/Makefile')
        CppCompiler         ('**/*.cpp')
        CppCompiler         ('**/*.c')

        OTHERWISE { | path |
            Project.build("compile:#{path}")
        }
    }

    MATCH('check:*') {
        JavaCheckStyle('**/*.java')
        JavaScriptHint('**/*.js')

        OTHERWISE { | path |
            Project.build("check:#{path}")
        }
    }

    PMD('pmd:**/*.java')
    #MavenJarFile('mavenjar:**/*.jar')

    # TODO: grep class already fetch lithium arguments
    GREP('grep:') {
        @grep = $lithium_args[0] if $lithium_args.length > 0
    }
}
