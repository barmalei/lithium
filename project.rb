-> {
    VERBOSE()

    $lithium_options['app_server_root'] = File.join($lithium_code, '..', 'tomcat', 'webapps')

    Touch('touch:*')

    UglifiedJSFile('minjs:**/*.min.js')
    NodejsModule('npm:**/node_modules/*')

    #RunMaven('mvn:*')

    GeneratedDirectory("test22") {
        @full_copy = true
        REQUIRE {
            FileMaskSource('.lithium/lib/*')
            FileMaskSource('classes/com/**/*')
        }
    }

    ZipFile("test.zip") {
        REQUIRE('.lithium/lib/**/*', FileMaskSource) {
            BASE('.lithium/lib')
        }
    }

    JarFile("test.jar") {
        REQUIRE('.lithium/lib/*', FileMaskSource)
    }

    UglifiedJSFile("test.min.js") {
        REQUIRE { FileMaskSource('.lithium/examples/easyoop.js') }
    }

    PYTHON {
        @tool_name = 'python3.10'
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
        InstallNodeJsPackage('**/package.json')
        BuildWithTsConf  ('**/tsconfig.json')
        DeployGoogleApp  ('**/appengine-*.xml')
        DeployGoogleApp  ('**/app*.yaml')

        # REQUIRE {
        #     Directory(".lithium") {
        #     }
        # }
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
        #ValidatePythonScript('**/*.py')
        RunPyFlake          ('**/*.py')
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
        ValidateDartCode    ('**/*.dart')

        # OTHERWISE
        # OTHERWISE {
        #     puts("!!!!!!!! #{fullpath}")
        # }
    }

    MATCH('check:*') {
        JavaCheckStyle('**/*.java')
        JavaScriptHint('**/*.js')
    }

    PMD('pmd:**/*.*')
    #MavenJarFile('mavenjar:**/*.jar')

    GREP('grep:')

    REGREP('regrep:')
}
