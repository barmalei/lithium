require 'lithium/java-artifact/runner'


module JUnit
    def junit_home(version = '4')
        raise 'Nil JUnit version' if version.nil?
        Files.assert_dir($lithium_code, 'ext', 'java', 'junit', version.to_s)
    end
end

class JUnitClasspath < DefaultClasspath
    include JUnit

    def initialize(name = nil, &block)
        super
        JOIN(File.join(junit_home(), '*.jar'))
    end
end

class JUnit4Classpath < JUnitClasspath
    default_name('.env/junit4/classpath')

    def junit_home()
        super('4')
    end
end

class JUnit5Classpath < JUnitClasspath
    default_name('.env/junit5/classpath')

    def junit_home()
        super('5')
    end
end

#
#  Run Java Unit test cases basing on automatic JUnit version detection
#
class RunJUnit < JavaFileRunner
    include JUnit

    @abbr = 'JUN'

    def initialize(name, &block)
        super
        @detected_version = nil
    end

    def before_build(is_expired)
        @detected_version, cp = nil, classpath()
        @detected_version = 4 if cp.INCLUDE?('**/junit-4*.jar')
        @detected_version = 5 if cp.INCLUDE?('**/junit-jupiter-*5*.jar')
        'JUnit version cannot be detected by classpath' if @detected_version.nil?
    end

    def WITH_OPTS
        if @detected_version == 4
            super + [ 'org.junit.runner.JUnitCore' ]
        elsif @detected_version == 5
            paths = Dir[File.join(junit_home('5'), 'junit-platform-console-standalone-*.jar')]
            raise 'JUnit5 standalone library cannot be found' if paths.empty?
            super + [
                '-jar', paths[0],
                'junit',
                'execute',
                '--disable-banner',
                # '--details=none',
                '--disable-ansi-colors',
                '--classpath', classpath(),
                '-c'
            ]
        else
            raise "Unsupported JUnit version '#{@detected_version}'"
        end
    end

    # disable passing class path for JUnit5 since it is expected to be passed as an option
    def WITH_CLASSPATH_OPT(opt_name = '-classpath')
        @detected_version == 5 ? [] : super()
    end
end

class RunJavaCodeWithJUnit < RunJUnit
    def transform_target_path(path)
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
    def transform_target_path(path)
        path.end_with?('.class') ? path[/[.]class$/] = '' : path
    end
end

