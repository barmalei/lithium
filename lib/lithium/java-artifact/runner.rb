require 'lithium/java-artifact/base'

class JavaFileRunner < RunJavaTool
    def run_with
        @java.java
    end

    def self.abbr() 'JVR' end
end

class RunJavaClass < JavaFileRunner
    def transform_source_path(path)
        n = paths.dup
        n[/[.]class$/] = '' if n.end_with?('.class')
        n
    end

    def what_it_does() "Run '#{name}' class" end
end

class RunJavaCode < JavaFileRunner
    def initialize(name, &block)
        super
        # TODO: hard-coded artifact prefix
        REQUIRE "compile:#{name}"
    end

    def transform_source_path(path)
        JVM.grep_classname(path)
    end

    def what_it_does() "Run JAVA '#{@name}' code" end

    def self.abbr() 'JRF' end
end

class RunJUnit < JavaFileRunner
    def initialize(name, &block)
        super
        @junit_home ||= File.join($lithium_code, 'ext', 'java', 'junit')
        raise "JUnit tool directory '#{@junit_home}' doesn't exist" unless File.directory?(@junit_home)
    end

    def classpath
        cp = super
        juv = detect_junit_version(cp) if juv.nil?

        if juv == 5
            unless cp.INCLUDE?("**/junit-platform-console-standalone*.jar")
                cp.JOIN(File.join(@junit_home, 'junit-platform-console-standalone-1.7.2.jar'))
            end
        else
            cp.JOIN(File.join(@junit_home, 'junit-4.11.jar'))        unless cp.INCLUDE?("**/junit-*.jar")
            cp.JOIN(File.join(@junit_home, 'hamcrest-core-1.3.jar')) unless cp.INCLUDE?("**/hamcrest-core-*.jar")
        end

        return cp
    end

    def run_with_target(src)
        juv = detect_junit_version()
        if juv == 5
            return [
                '-jar',
                File.join(@junit_home, 'junit-platform-console-standalone-1.7.2.jar'),
                '--disable-banner',
                '--details=none',
                '-c'
            ].concat(super(src)).concat([ '--classpath', classpath() ])

        else
            return [ 'org.junit.runner.JUnitCore', super(src) ]
        end
    end

    def detect_junit_version(cp = nil)
        cp = method(:classpath).super_method.call if cp.nil?
        return 4 if cp.INCLUDE?('**/junit-4*.jar')
        return 5 if cp.INCLUDE?('**/junit-jupiter-*5*.jar')
        return nil
    end

    def abbr() 'JUN' end

    def what_it_does() "Run JAVA '#{@name}' with JUnit ('#{detect_junit_version}') code" end
end

class RunJavaCodeWithJUnit < RunJUnit
    def transform_source_path(path)
        cn  = JVM.grep_classname(path)
        res = FileArtifact.grep(path, '@Test')
        if res.nil? || res.length == 0
            unless cn.end_with?('Test.java')
                puts_warning "Tests cannot be found in '#{cn}'class, try to run '#{cn}Test'"
                return "#{cn}Test"
            else
                raise "Test case cannot be detected in '#{path}' name"
            end
        end
        return cn
    end
end

class RunJavaClassWithJUnit < RunJUnit
    def transform_source_path(path)
        n = paths.dup
        n[/[.]class$/] = '' if n.end_with?('.class')
        n
    end
end

class RunJAR < JavaFileRunner
    def run_with_target(src)
        t = [ '-jar' ]
        t.concat(super(src))
        return t
    end

    def what_it_does
        "Run JAR '#{@name}'"
    end
end

class RunGroovyScript < JavaFileRunner
    def initialize(name, &block)
        REQUIRE GROOVY
        super
    end

    def classpath
        super.JOIN(@groovy.classpaths)
    end

    def run_with
        @groovy.groovy
    end

    def what_it_does
        "Run groovy '#{@name}' script"
    end
end

class RunKotlinCode < JavaFileRunner
    def initialize(name, &block)
        REQUIRE KOTLIN
        super
        REQUIRE "compile:#{name}"
    end

    def classpath
        super.JOIN(@kotlin.classpaths)
    end

    def transform_source_path(path)
        pkg  = JVM.grep_package(path)
        ext  = File.extname(path)
        name = File.basename(path, ext)

        clname = name[0].upcase() + name[1..name.length - 1]
        clname = clname + ext[1].upcase() + ext[2..ext.length - 1] unless ext.nil?
        return pkg.nil? ? clname : "#{pkg}.#{clname}"
    end

    def what_it_does()
        "Run Kotlin '#{@name}' code"
    end
end

class RunScalaCode < JavaFileRunner
    def initialize(name, &block)
        REQUIRE SCALA
        super
        REQUIRE "compile:#{name}"
    end

    def classpath
        super.JOIN(@scala.classpaths)
    end

    def transform_source_path(path)
        pkg = JVM.grep_package(path)
        cln = nil
        res = FileArtifact.grep_file(path, /^object[ \t]+([a-zA-Z0-9_.]+)[ \t]*/)

        if res.length > 1
            raise "Ambiguous class name detection '#{res}'"
        elsif res.length == 1
            cln = res[0][:matched_part]
        else
            raise 'Class name cannot be detected'
        end

        return pkg.nil? ? cln : "#{pkg}.#{cln}"
    end

    def run_with
        @scala.scala
    end

    def what_it_does
        "Run Scala '#{@name}' code"
    end
end
