require 'lithium/java-artifact/base'


class JavaFileRunner < FileCommand
    include OptionsSupport

    REQUIRE JAVA

    def build()
        go_to_homedir()
        raise "Running '#{@name}' failed" if Artifact.exec(*cmd()) != 0
    end

    def cmd()
        clpath = build_classpath()
        target = build_target()
        runner = build_runner()
        if clpath
            return [runner, '-classpath', "\"#{clpath}\"", OPTS(), target]
        else
            return [runner, OPTS(), target]
        end
    end

    def build_target()
        @name
    end

    def build_classpath()
        @java.classpath
    end

    def build_runner()
        @java.java
    end
end

class RunJavaClass < JavaFileRunner
    REQUIRE JAVA

    def build_target()
        n = @name.dup
        n[/[.]class/] = ''
        n
    end

    def what_it_does() "Run '#{name}' class" end
end

class RunJavaCode < JavaFileRunner
    REQUIRE JAVA

    def initialize(*args)
        super
        # TODO: hardcoded artifact prefix
        REQUIRE "compile:#{name}"
    end

    def build_target()
        file = fullpath()
        pkgname = FileArtifact.grep(file, /^package[ \t]+([a-zA-Z0-9_.]+)[ \t]*;/)
        clname  = File.basename(file)
        clname[/\.java$/] = ''

        raise 'Class name cannot be identified' if clname.nil?
        puts_warning 'Package name is empty' if pkgname.nil?

        pkgname = pkgname[1] if pkgname
        return (pkgname ? "#{pkgname}.#{clname}": clname)
    end

    def what_it_does() "Run JAVA '#{@name}' code" end
end

class RunJAR < JavaFileRunner
    REQUIRE JAVA

    def build_target()
        "-jar #{@name}"
    end

    def what_it_does()
        "Run JAR '#{@name}'"
    end
end

class RunGroovyScript < JavaFileRunner
    REQUIRE JAVA
    REQUIRE GROOVY

    def build_classpath()
        JavaClasspath::join(@groovy.classpath, @java.classpath)
    end

    def build_target()
        fullpath()
    end

    def build_runner()
        @groovy.groovy
    end

    def what_it_does()
        "Run groovy '#{@name}' script"
    end
end

module RunJavaTestCase
    def build_target()
        st = super
        st.sub(/(([a-zA-Z_$][a-zA-Z0-9_$]*\.)*)([a-zA-Z_$][a-zA-Z0-9_$]*)/, '\1Test\3')
    end

    def what_it_does()
       "Run Java test-cases '#{build_target}'\n                for '#{@name}'"
    end
end

class RunJavaTestCode < RunJavaCode
    REQUIRE JAVA
    include RunJavaTestCase
end

class RunJavaTestClass < RunJavaClass
    REQUIRE JAVA
    include RunJavaTestCase
end

class RunKotlinCode < JavaFileRunner
    REQUIRE JAVA
    REQUIRE KOTLIN

    def initialize(*args)
        super
        REQUIRE "compile:#{name}"
    end

    def build_classpath()
        JavaClasspath::join(@kotlin.classpath, @java.classpath)
    end

    def build_target()
        file = fullpath()

        pkg    = FileArtifact.grep(file, /^package[ \t]+([a-zA-Z0-9_.]+)[ \t]*/)
        ext    = File.extname(file)
        name   = File.basename(file, ext)
        clname = name[0].upcase() + name[1..name.length-1]
        clname = clname + ext[1].upcase() + ext[2..ext.length-1] if ext

        puts_warning 'Package name is empty.' if pkg.nil?

        return pkg ? "#{pkg[1]}.#{clname}" : clname
    end

    def what_it_does()
        "Run Kotlin '#{@name}' code"
    end
end

class RunKotlinTestCode < RunKotlinCode
    REQUIRE JAVA
    REQUIRE KOTLIN

    include RunJavaTestCase
end


class RunScalaCode < JavaFileRunner
    REQUIRE JAVA
    REQUIRE SCALA

    def initialize(*args)
        super
        REQUIRE "compile:#{name}"
    end

    def build_classpath()
        JavaClasspath::join(@scala.classpath, @java.classpath)
    end

    def build_target()
        file = fullpath()

        pkg    = FileArtifact.grep(file, /^package[ \t]+([a-zA-Z0-9_.]+)[ \t]*/)
        cln    = FileArtifact.grep(file, /^object[ \t]+([a-zA-Z0-9_.]+)[ \t]*/)
        puts_warning 'Package name is empty.' if pkg.nil?

        return pkg ? "#{pkg[1]}.#{cln[-1]}" : cln[-1]
    end

    def build_runner()
        @scala.scala
    end

    def what_it_does()
        "Run Scala '#{@name}' code"
    end
end

class RunScalaTestCode < RunScalaCode
    REQUIRE JAVA
    REQUIRE SCALA

    include RunJavaTestCase
end

