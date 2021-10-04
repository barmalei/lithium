require 'fileutils'

require 'lithium/file-artifact/command'
require 'lithium/file-artifact/acquired'
require 'lithium/java-artifact/base'

class JavaCheckStyle < JavaFileRunner
    def initialize(*args)
        super

        @checkstyle_main_class ||= 'com.puppycrawl.tools.checkstyle.Main'

        unless @checkstyle_home
            @checkstyle_home = existing_dir($lithium_code, 'ext', 'java', 'checkstyle')
        end

        unless @checkstyle_config
            @checkstyle_config = existing_file(@checkstyle_home, "crystalloids_checks.xml")
        end

        unless File.exists?(@checkstyle_config)
            raise "Checkstyle config '#{@checkstyle_config}' cannot be found"
        end

        puts "Checkstyle home  : '#{@checkstyle_home}'\n           config: '#{@checkstyle_config}'"

        cp = File.join(@checkstyle_home, '*.jar')
        DefaultClasspath('checkstyle_def_classpath') {
            JOIN(cp)
        }
    end

    def run_with_target(src)
        [ @checkstyle_main_class , '-c', @checkstyle_config, super(src) ]
    end

    def classpath
        # only chackstyle classpath related JARs arer required
        return PATHS.new(project.homedir).JOIN(@classpaths)
    end

    def what_it_does() "Check '#{@name}' java code style" end

    def self.abbr() 'CHS' end
end

class UnusedJavaCheckStyle < JavaCheckStyle
    def initialize(*args)
        super
        @checkstyle_config = File.join(@checkstyle_home, "unused.xml")
    end
end

#  PMD code analyzer
class PMD < JavaFileRunner
    def initialize(*args)
        super
        @pmd_home = File.join($lithium_code, 'ext', 'java', 'pmd')
        raise "PMD home path cannot be found '#{@pmd_home}'" unless File.directory?(@pmd_home)

        @pmd_rules      ||= File.join('rulesets', 'java', 'quickstart.xml')
        @pmd_format     ||= 'text'
        @pmd_main_class ||= 'net.sourceforge.pmd.PMD'

        @source_as_file     = true
        @source_file_prefix = '-filelist '
        @source_list_prefix = '-d '

        cp = File.join(@pmd_home, 'lib', '*.jar')
        DefaultClasspath('pmd_def_classpath') {
            JOIN(cp)
        }
    end

    def classpath
        # only chackstyle classpath related JARs arer required
        return PATHS.new(project.homedir).JOIN(@classpaths)
    end

    def run_with_target(src)
        t = [ @pmd_main_class, '-f', @pmd_format, '-R', @pmd_rules ]
        t.concat(super(src))
        return t
    end

    def error_exit_code?(ec)
        ec.exitstatus != 0 && ec.exitstatus != 4
    end

    def what_it_does() "Validate '#{@name}' code applying PMD:#{@pmd_rules}" end

    def self.abbr() 'PMD' end
end

# TODO: complete the code !
class JsonSchemaToPojo < RunJAR
    def initialize(*args)
        super
        @jsonSchemaToPojo_home = File.join($lithium_code, 'ext', 'java', 'jsonschema2pojo')
        raise "JSON Schema to POJO home path cannot be found '#{@pmd_home}'" unless File.directory?(@jsonSchemaToPojo_home)

        cp = File.join(@jsonSchemaToPojo_home, 'lib', '*.jar')
        DefaultClasspath('jsonSchemaToPojo_def_classpath') {
            JOIN(cp)
        }
    end

    def run_with_target(src)
        t = t.concat(super(src))
        t = [ File.join(@jsonSchemaToPojo_home, 'jsonschema2pojo-cli-1.1.1.jar'), '--source', fullpath, '--target', 'java-gen' ]
        return t
    end
end

