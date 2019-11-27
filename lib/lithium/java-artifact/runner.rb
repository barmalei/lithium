require 'lithium/java-artifact/base'


class JavaFileRunner < FileCommand
    include OptionsSupport

    REQUIRE JAVA

    def initialize(*args)
        super
        @arguments ||= []
    end

    def build()
        go_to_homedir()
        raise "Running '#{@name}' failed" if Artifact.exec(*cmd()) != 0
    end

    def cmd()
        clpath = build_classpath()

        cmd = [ build_runner() ]
        cmd.push('-classpath', "\"#{clpath}\"") unless clpath.nil?
        cmd.push(OPTS(), build_target(), @arguments.join(' '))
        return cmd
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

    def grep_package(pattern = /^package[ \t]+([a-zA-Z0-9_.]+)[ \t]*;/)
        res = FileArtifact.grep_file(fullpath, pattern)

        if res.length == 0
            puts_warning 'Package name is empty'
            return nil
        elsif res.length > 1
            raise "Ambiguous package detection '#{res}'"
        else
            return res[0][:matched_part]
        end
    end
end

class RunJavaClass < JavaFileRunner
    REQUIRE JAVA

    def build_target()
        n = @name.dup
        n[/[.]class$/] = '' if n.end_with?('.class')
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
        pkgname = grep_package()

        clname  = File.basename(fullpath)
        clname[/\.java$/] = '' if clname.end_with?('.java')
        raise 'Class name cannot be identified' if clname.nil?

        return pkgname.nil? ? clname : "#{pkgname}.#{clname}"
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
        fp = fullpath()

        pkg  = grep_package()
        ext  = File.extname(fp)
        name = File.basename(fp, ext)

        clname = name[0].upcase() + name[1..name.length - 1]
        clname = clname + ext[1].upcase() + ext[2..ext.length - 1] unless ext.nil?

        return pkg.nil? ? clname : "#{pkg[1]}.#{clname}"
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
        pkg = grep_package()
        cln = nil
        res = FileArtifact.grep_file(fullpath, /^object[ \t]+([a-zA-Z0-9_.]+)[ \t]*/)

        if res.length > 1
            raise "Ambiguous class name detection '#{res}'"
        elsif res.length == 1
            cln = res[0][:matched_part]
        else
            raise 'Class name cannot be detected'
        end

        return pkg.nil? ? cln[-1] : "#{pkg[1]}.#{cln[-1]}"
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
