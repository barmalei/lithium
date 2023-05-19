require 'fileutils'

require 'lithium/file-artifact/command'
require 'lithium/file-artifact/acquired'
require 'lithium/java-artifact/base'
require 'lithium/java-artifact/runner'


class JavaCheckStyle < JavaFileRunner
    @abbr = 'CHS'

    def initialize(name, &block)
        super

        @checkstyle_main_class ||= 'com.puppycrawl.tools.checkstyle.Main'
        @checkstyle_version    ||= '8'
        @checkstyle_home = FileArtifact.assert_dir($lithium_code, 'ext', 'java', 'checkstyle', @checkstyle_version)
        FileArtifact.assert_dir(@checkstyle_home)

        @checkstyle_config ||= DEFAULT()
        @checkstyle_config   = FileArtifact.assert_file(@checkstyle_config)

        puts "Java Checkstyle (v='#{@checkstyle_version}')\n    home:   '#{@checkstyle_home}'\n    config: '#{@checkstyle_config}'"

        cp = File.join(@checkstyle_home, '*.jar')
        REQUIRE {
            DefaultClasspath('.env/checkstyle_classpath') {
                JOIN(cp)
            }
        }
    end

    def CONFIG(*args)
        @checkstyle_config = FileArtifact.assert_file(*args)
        return @checkstyle_config
    end

    def GOOGLE
        CONFIG(@checkstyle_home, "google_checkstyle.xml")
    end

    def DEFAULT
        CONFIG(@checkstyle_home, "default_checkstyle.xml")
    end

    def WITH_TARGETS(src)
        [ @checkstyle_main_class , '-c', @checkstyle_config, super(src) ]
    end

    def classpath
        # only checkstyle classpath related JARs are required
        PATHS.new(homedir).JOIN(@classpaths)
    end
end

class UnusedJavaCheckStyle < JavaCheckStyle
    def initialize(name, &block)
        super
        CONFIG(@checkstyle_home, "unused.xml")
    end
end

#  PMD code analyzer
class PMD < JavaFileRunner
    def initialize(name, &block)
        super

        @checkstyle_version ||= '7'
        @pmd_format     ||= 'text'
        @pmd_main_class ||= 'net.sourceforge.pmd.PMD'

        @pmd_home ||= FileArtifact.assert_dir($lithium_code, 'ext', 'java', 'pmd', @checkstyle_version)
        raise "PMD '#{@pmd_home}' home path cannot be found" unless File.directory?(@pmd_home)

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
        ext = File.extname(fullpath).downcase[1..-1]
        ext = 'ruby'   if ext == 'rb'
        ext = 'python' if ext == 'py'
        pmd_rules = File.join('rulesets', ext, 'quickstart.xml')
        super + [ @pmd_main_class, '-f', @pmd_format, '-R', pmd_rules, '-filelist' ]
    end

    def error_exit_code?(ec)
        ec.exitstatus != 0 && ec.exitstatus != 4
    end
end

# TODO: complete the code !
class JsonSchemaToPojo < RunJAR
    def initialize(name, &block)
        super
        @jsonSchemaToPojo_home = FileArtifact.assert_dir($lithium_code, 'ext', 'java', 'jsonschema2pojo')
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

