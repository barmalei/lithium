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

    JAVA {
        DefaultClasspath {
            JOIN('.lithium/ext/java/lithium/classes')
        }
    }


    Touch('touch:*')

    UglifiedJSFile('minjs:**/*.min.js')
    NodejsModule('npm:**/node_modules/*')

    #RunMaven('mvn:*')

    GeneratedDirectory("test") {
        @full_copy = true
        FileMask('.lithium/lib/*')
        FileMask('classes/com/**/*')
        MetaFile('.lithium/meta/test.dir')
    }

    ZipFile("test.zip") {
        SOURCES {
            FileMask('.lithium/lib/*').BASE('.lithium/lib')
        }
    }

    JarFile("test.jar") {
        FileMaskSource('.lithium/lib/*')
    }

    UglifiedJSFile("test.min.js") {
        FileMaskSource('.lithium/exa mples/easyoop.js')
    }

    MATCH("run:*") {
        RunJavaCode      ('**/*.java')
        RunNodejs        ('**/*.js')
        RunPythonScript  ('**/*.py')
        RunPhpScript     ('**/*.php')
        RunShell         ('**/*.sh')
        RunJAR           ('**/*.jar')
        RunMaven         ('**/pom.xml')
        RunGradle        ('**/build.gradle.kts')
        RunGradle        ('**/build.gradle')
        RunGroovyScript  ('**/*.groovy')
        RunKotlinCode    ('**/*.kt')
        RunScalaCode     ('**/*.scala')
        RunJavaClass     ('**/*.class')
        RunHtml          ('**/*.html')
        RunRubyScript    ('**/*.rb') 
        CppCodeRunner    ('**/*.cpp')
        CppCodeRunner    ('**/*.c')
        RunDartCode      ('**/*.dart')
        RunDartPub       ('**/pubspec.yaml')
    }

    MATCH("test:*") {
        RunJavaCodeWithJUnit('**/*.java')
        RunJavaClassWithJUnit('**/*.class')
        RunMaven('**/pom.xml') {
            TARGETS('test')
        }
    }

    MATCH("compile:*") {
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
        GradleCompiler      ('**/build.gradle.kts')
        GradleCompiler      ('**/build.gradle')
        ValidateXML         ('**/*.xml')
        CompileTTGrammar    ('**/*.tt')
        CompileSass         ('**/*.sass')
        BuildVaadinSass     ('VAADIN/**/*.scss')
        RunMakefile         ('**/Makefile')
        CppCompiler         ('**/*.cpp')
        CppCompiler         ('**/*.c')
        RunDartPubBuild     ('**/pubspec.yaml')

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
