require 'lithium/utils'
require 'lithium/java-artifact/base'


class JavaFileRunner < FileCommand
    required JAVA

    def initialize(*args)
        super
        @args    ||= nil
        @options ||= ""
    end

    def build()
        go_to_homedir()
        if !@args.nil?
            args = @args
        else
            args = $arguments.join(' ')
        end
        raise "Running '#{@name}' failed." if exec4(cmd(), args) != 0
    end

    def cmd()
        clpath = build_classpath()
        target = build_target()
        runner = build_runner()
        if clpath
            return "#{runner} -classpath #{clpath} #{@options} #{target}"
        else
            return "#{runner} #{@options} #{target}"
        end
    end

    def build_target()
        @name
    end

    def build_classpath()
        java().classpath
    end

    def build_runner()
        java().java()
    end
end

class RunJavaClass < JavaFileRunner
    def build_target()
        n = @name.dup
        n[/[.]class/] = ''
        n
    end

    def what_it_does() "Run '#{name}' class" end
end

class RunJavaCode < JavaFileRunner
    def initialize(*args)
        super
        REQUIRE "compilejava:#{name}"
    end

    def build_target()
        file = fullpath()
        pkgname = FileUtil.grep(file, /^package[ \t]+([a-zA-Z0-9_.]+)[ \t]*;/)
        clname  = File.basename(file)
        clname[/\.java$/] = ''

        #clname  = FileUtil.grep(file, /\s*public\s+(static\s+)?(abstract\s+)?class\s+([a-zA-Z][a-zA-Z0-9_]*)/)

        raise 'Class name cannot be identified.' if clname.nil?
        puts_warning 'Package name is empty.' if pkgname.nil?

        pkgname = pkgname[1] if pkgname
        return (pkgname ? "#{pkgname}.#{clname}": clname)
    end

    def what_it_does() "Run JAVA code '#{@name}'" end
end

class RunJAR < JavaFileRunner
    def build_target()
        "-jar #{@name}"
    end

    def what_it_does()
        "Run JAR '#{@name}'"
    end
end

class RunGroovyScript < JavaFileRunner
    required GROOVY

    def initialize(*args)
        super
    end

    def build_classpath()
        CLASSPATH::join(groovy().classpath, java().classpath)
    end

    def build_target()
        fullpath()
    end

    def build_runner()
        groovy().groovy
    end

    def what_it_does()
        "Run groovy script '#{@name}'"
    end
end

class RunJavaCodeTests < RunJavaCode
    def build_target()
        "Test" + super
    end

    def what_it_does()
        "Run Java code test-cases for '#{@name}'"
    end
end

class RunJavaClassTests < RunJavaClass
    def build_target()
        "Test" + super
    end

    def what_it_does()
        "Run Java class test-cases for '#{@name}'"
    end
end

class RunKotlinCode < JavaFileRunner
    required KOTLIN

    def initialize(*args)
        super
        REQUIRE "compilekotlin:#{name}"
    end

    def build_classpath()
        CLASSPATH::join(kotlin().classpath, java().classpath)
    end

    def build_target()
        file = fullpath()

        pkg    = FileUtil.grep(file, /^package[ \t]+([a-zA-Z0-9_.]+)[ \t]*/)
        ext    = File.extname(file)
        name   = File.basename(file, ext)
        clname = name[0].upcase() + name[1..name.length-1]
        clname = clname + ext[1].upcase() + ext[2..ext.length-1] if ext

        puts_warning 'Package name is empty.' if pkg.nil?

        return pkg ? "#{pkg[1]}.#{clname}" : clname
    end

    def what_it_does()
        "Run Kotlin code '#{@name}' code"
    end
end

class RunScalaCode < JavaFileRunner
    required SCALA

    def initialize(*args)
        super
        REQUIRE "compilescala:#{name}"
    end

    def build_classpath()
        CLASSPATH::join(scala().classpath, java().classpath)
    end

    def build_target()
        file = fullpath()

        pkg    = FileUtil.grep(file, /^package[ \t]+([a-zA-Z0-9_.]+)[ \t]*/)
        cln    = FileUtil.grep(file, /^object[ \t]+([a-zA-Z0-9_.]+)[ \t]*/)
        puts_warning 'Package name is empty.' if pkg.nil?

        return pkg ? "#{pkg[1]}.#{cln[-1]}" : cln[-1]
    end

    def build_runner()
        scala().scala
    end

    def what_it_does()
        "Run Scala code '#{@name}' code"
    end
end
