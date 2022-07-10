require 'fileutils'

require 'lithium/file-artifact/command'
require 'lithium/file-artifact/acquired'
require 'lithium/java-artifact/base'

class JavaCheckStyle < JavaFileRunner
    @abbr = 'CHS'

    def initialize(name, &block)
        super

        @checkstyle_main_class ||= 'com.puppycrawl.tools.checkstyle.Main'

        unless @checkstyle_home
            @checkstyle_home = assert_dirs($lithium_code, 'ext', 'java', 'checkstyle')
        end

        unless @checkstyle_config
            @checkstyle_config = assert_files(@checkstyle_home, "crystalloids_checks.xml")
        end

        unless File.exists?(@checkstyle_config)
            raise "Checkstyle config '#{@checkstyle_config}' cannot be found"
        end

        puts "Checkstyle home: '#{@checkstyle_home}'\n           config: '#{@checkstyle_config}'"

        cp = File.join(@checkstyle_home, '*.jar')
        REQUIRE {
            DefaultClasspath('.env/checkstyle_classpath') {
                JOIN(cp)
            }
        }
    end

    def WITH_TARGETS(src)
        [ @checkstyle_main_class , '-c', @checkstyle_config, super(src) ]
    end

    def classpath
        # only chackstyle classpath related JARs arer required
        PATHS.new(homedir).JOIN(@classpaths)
    end
end

class UnusedJavaCheckStyle < JavaCheckStyle
    def initialize(name, &block)
        super
        @checkstyle_config = File.join(@checkstyle_home, "unused.xml")
    end
end

#  PMD code analyzer
class PMD < JavaFileRunner
    @abbr = 'PMD'

    def initialize(name, &block)
        super
        @pmd_home ||= File.join($lithium_code, 'ext', 'java', 'pmd')
        raise "PMD home path cannot be found '#{@pmd_home}'" unless File.directory?(@pmd_home)

        @pmd_rules      ||= File.join('rulesets', 'java', 'quickstart.xml')
        @pmd_format     ||= 'text'
        @pmd_main_class ||= 'net.sourceforge.pmd.PMD'

        @targets_from_file = true

        cp = File.join(@pmd_home, 'lib', '*.jar')
        REQUIRE {
            DefaultClasspath('.env/pmd_classpath') {
                JOIN(cp)
            }
        }
    end

    def classpath
        # only PMD classpath related JARs are required
        PATHS.new(homedir).JOIN(@classpaths)
    end

    def WITH_OPTS
        super + [ @pmd_main_class, '-f', @pmd_format, '-R', @pmd_rules, '-filelist' ]
    end

    def error_exit_code?(ec)
        ec.exitstatus != 0 && ec.exitstatus != 4
    end
end

# TODO: complete the code !
class JsonSchemaToPojo < RunJAR
    def initialize(name, &block)
        super
        @jsonSchemaToPojo_home = File.join($lithium_code, 'ext', 'java', 'jsonschema2pojo')
        raise "JSON Schema to POJO home path cannot be found '#{@pmd_home}'" unless File.directory?(@jsonSchemaToPojo_home)

        cp = File.join(@jsonSchemaToPojo_home, 'lib', '*.jar')
        REQUIRE {
            DefaultClasspath('.env/jsonSchemaToPojo_classpath') {
                JOIN(cp)
            }
        }
    end

    def WITH_TARGETS(src)
        t = t.concat(super(src))
        t = [ File.join(@jsonSchemaToPojo_home, 'jsonschema2pojo-cli-1.1.1.jar'), '--source', fullpath, '--target', 'java-gen' ]
        return t
    end
end

