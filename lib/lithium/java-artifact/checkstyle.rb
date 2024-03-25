require 'fileutils'

require 'lithium/java-artifact/runner'

class JavaCheckStyle < JavaFileRunner
    @abbr = 'CHS'

    def initialize(name, &block)
        super

        @checkstyle_main_class ||= 'com.puppycrawl.tools.checkstyle.Main'
        @checkstyle_version    ||= '10'
        @checkstyle_home = Files.assert_dir($lithium_code, 'ext', 'java', 'checkstyle', @checkstyle_version)
        Files.assert_dir(@checkstyle_home)

        @checkstyle_config ||= DEFAULT()
        @checkstyle_config   = Files.assert_file(@checkstyle_config)

        puts "Java Checkstyle (v='#{@checkstyle_version}')\n    home:   '#{@checkstyle_home}'\n    config: '#{@checkstyle_config}'"

        cp = File.join(@checkstyle_home, '*.jar')
        REQUIRE {
            DefaultClasspath('.env/checkstyle_classpath') {
                JOIN(cp)
            }
        }
    end

    def CONFIG(*args)
        @checkstyle_config = Files.assert_file(*args)
        return @checkstyle_config
    end

    def GOOGLE
        CONFIG(@checkstyle_home, "google_checkstyle.xml")
    end

    def DEFAULT
        CONFIG(@checkstyle_home, "default_checkstyle.xml")
    end

    def WITH_TARGETS
        [ @checkstyle_main_class , '-c', @checkstyle_config ] + super()
    end
end

class UnusedJavaCheckStyle < JavaCheckStyle
    def initialize(name, &block)
        super
        CONFIG(@checkstyle_home, "unused.xml")
    end
end


# TODO: complete or remove this code !
class JsonSchemaToPojo < RunJAR
    def initialize(name, &block)
        super
        @jsonSchemaToPojo_home = Files.assert_dir($lithium_code, 'ext', 'java', 'jsonschema2pojo')
        raise "JSON Schema to POJO home path cannot be found '#{@pmd_home}'" unless File.directory?(@jsonSchemaToPojo_home)

        cp = File.join(@jsonSchemaToPojo_home, 'lib', '*.jar')
        REQUIRE {
            DefaultClasspath('.env/jsonSchemaToPojo_classpath') {
                JOIN(cp)
            }
        }
    end

    def WITH_TARGETS
        t = t.concat(super())
        t = [ File.join(@jsonSchemaToPojo_home, 'jsonschema2pojo-cli-1.1.1.jar'), '--source', fullpath, '--target', 'java-gen' ]
        return t
    end
end


