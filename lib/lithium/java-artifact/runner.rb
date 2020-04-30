require 'lithium/java-artifact/base'

class JavaFileRunner < FileCommand
    include OptionsSupport

    def initialize(*args)
        REQUIRE JAVA
        super
        @arguments ||= []
    end

    def build()
        go_to_homedir()
        raise "Running '#{@name}' failed" if Artifact.exec(*cmd()) != 0
    end

    def cmd()
        clpath = classpath()
        cmd = [ run_with() ]
        cmd.push('-classpath', "\"#{clpath}\"") unless clpath.nil?
        cmd.push(OPTS(), target(), @arguments.join(' '))
        return cmd
    end

    def target()
        @name
    end

    def classpath()
        @java.classpath
    end

    def run_with()
        @java.java
    end

    def grep_package(pattern = /^package[ \t]+([a-zA-Z0-9_.]+)[ \t]*/)
        return JVM.grep_package(fullpath, pattern)
    end

    def self.abbr() 'JVR' end
end

class RunJavaClass < JavaFileRunner
    def target()
        n = @name.dup
        n[/[.]class$/] = '' if n.end_with?('.class')
        n
    end

    def what_it_does() "Run '#{name}' class" end
end

class RunJavaCode < JavaFileRunner
    def initialize(*args)
        super
        # TODO: hardcoded artifact prefix
        REQUIRE "compile:#{name}"
    end

    def target()
        pkgname = grep_package()

        clname  = File.basename(fullpath)
        clname[/\.java$/] = '' if clname.end_with?('.java')
        raise 'Class name cannot be identified' if clname.nil?

        return pkgname.nil? ? clname : "#{pkgname}.#{clname}"
    end

    def what_it_does() "Run JAVA '#{@name}' code" end
end

class RunJAR < JavaFileRunner
    def target()
        "-jar #{@name}"
    end

    def what_it_does()
        "Run JAR '#{@name}'"
    end
end

class RunGroovyScript < JavaFileRunner
    def initialize(*args)
        REQUIRE GROOVY
        super
    end

    def classpath()
        JavaClasspath::join(@groovy.classpath, @java.classpath)
    end

    def target()
        "\"#{fullpath}\""
    end

    def run_with()
        @groovy.groovy
    end

    def what_it_does()
        "Run groovy '#{@name}' script"
    end
end

module RunJavaTestCase
    def target()
        st = super
        st.sub(/(([a-zA-Z_$][a-zA-Z0-9_$]*\.)*)([a-zA-Z_$][a-zA-Z0-9_$]*)/, '\1Test\3')
    end

    def what_it_does()
       "Run Java test-cases '#{target}'\n                for '#{@name}'"
    end
end

class RunJavaTestCode < RunJavaCode
    include RunJavaTestCase
end

class RunJavaTestClass < RunJavaClass
    include RunJavaTestCase
end

class RunKotlinCode < JavaFileRunner
    def initialize(*args)
        REQUIRE KOTLIN
        super
        REQUIRE "compile:#{name}"
    end

    def classpath()
        JavaClasspath::join(@kotlin.classpath, @java.classpath)
    end

    def target()
        fp = fullpath()

        pkg  = grep_package()
        ext  = File.extname(fp)
        name = File.basename(fp, ext)

        clname = name[0].upcase() + name[1..name.length - 1]
        clname = clname + ext[1].upcase() + ext[2..ext.length - 1] unless ext.nil?

        return pkg.nil? ? clname : "#{pkg}.#{clname}"
    end

    def what_it_does()
        "Run Kotlin '#{@name}' code"
    end
end

class RunKotlinTestCode < RunKotlinCode
    include RunJavaTestCase
end


class RunScalaCode < JavaFileRunner
    def initialize(*args)
        REQUIRE SCALA
        super
        REQUIRE "compile:#{name}"
    end

    def classpath()
        JavaClasspath::join(@scala.classpath, @java.classpath)
    end

    def target()
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

        return pkg.nil? ? cln[-1] : "#{pkg}.#{cln[-1]}"
    end

    def run_with()
        @scala.scala
    end

    def what_it_does()
        "Run Scala '#{@name}' code"
    end
end

class RunScalaTestCode < RunScalaCode
    include RunJavaTestCase
end
