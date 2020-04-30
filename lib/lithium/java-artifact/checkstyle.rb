require 'fileutils'

require 'lithium/file-artifact/command'
require 'lithium/file-artifact/acquired'
require 'lithium/java-artifact/base'

class JavaCheckStyle < FileMask
    include OptionsSupport

    def initialize(*args)
        REQUIRE JAVA

        super
        @checkstyle_home = File.join($lithium_code, 'tools', 'java', 'checkstyle')  unless @checkstyle_home
        raise "Checkstyle home '#{@checkstyle_home}' is incorrect"                  unless File.directory?(@checkstyle_home)

        @checkstyle_config = File.join(@checkstyle_home, "default.xml")             unless @checkstyle_config
        raise "Checkstyle config '#{@checkstyle_config}' cannot be found"           unless File.exists?(@checkstyle_config)

        puts "Checkstyle home  : '#{@checkstyle_home}'\n           config: '#{@checkstyle_config}'"
    end

    def build_item(path, mt)
        raise "Cannot run check style" if Artifact.exec(@java.java,
                                                       '-cp', "\"#{@checkstyle_home}/checkstyle-8.16-all.jar\"",
                                                       'com.puppycrawl.tools.checkstyle.Main',
                                                       '-c', "\"#{@checkstyle_config}\"",
                                                       "\"#{fullpath(path)}\"") != 0
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
class PMD < FileMask
    include OptionsSupport

    def initialize(*args)
        super
        @pmd_path = File.join($lithium_code, 'tools', 'java', 'pmd')
        raise "Path cannot be found '#{@pmd_path}'" if !File.exists?(@pmd_path) || !File.directory?(@pmd_path)

        @pmd_rules  ||= File.join('rulesets', 'java', 'quickstart.xml')
        @pmd_format ||= 'text'
        @pmd_cmd    ||= 'run.sh'
    end

    def build_item(path, mt)
        fp = fullpath(path)
        raise "PMD target '#{fp}' cannot be found" unless File.exists?(fp)

        status = Artifact.exec(File.join(@pmd_path, 'bin', @pmd_cmd),
                            'pmd', '-d', "\"#{fp}\"",
                            '-format', @pmd_format,
                            '-R', @pmd_rules)

        ecode = status.exitstatus
        raise "PMD failed for '#{fp}' code = #{ecode}" if ecode != 0 && ecode != 4
    end

    def what_it_does() "Validate '#{@name}' code applying PMD:#{@pmd_rules}" end

    def self.abbr() 'PMD' end
end

