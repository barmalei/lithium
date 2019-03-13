require 'fileutils'
require 'tempfile'

require 'lithium/file-artifact/command'
require 'lithium/file-artifact/acquired'
require 'lithium/java-artifact/base'

class CheckStyle < FileMask
    required JAVA

    def initialize(*args)
        super
        @checkstyle_home = "#{$lithium_code}/tools/java/checkstyle"       if !@checkstyle_home
        raise "Checkstyle home '#{@checkstyle_home}' is incorrect"        if !File.directory?(@checkstyle_home)
        @checkstyle_config = "#{@checkstyle_home}/jnet.xml"               if !@checkstyle_config
        raise "Checkstyle config '#{@checkstyle_config}' cannot be found" if !File.exists?(@checkstyle_config)
    end

    def build_item(path, mt)
        j = java()
        cmd  = "#{j.java()} -cp #{@checkstyle_home}/checkstyle-8.16-all.jar com.puppycrawl.tools.checkstyle.Main -c #{@checkstyle_config} #{fullpath(path)}"
        raise "Cannot run check style" if !exec4(cmd, "")
    end

    def what_it_does() "Check '#{@name}' java code style" end
end

#
#  PMD code analyzer
#
class PMD < FileCommand
    def initialize(*args)
        super
        @pmd_path = "#{$lithium_code}/tools/pmd"
        raise "Path cannot be found '#{@pmd_path}'" if !File.exists?(@pmd_path) || !File.directory?(@pmd_path)

        @pmd_rules   ||= 'rulesets/java/quickstart.xml'
        @pmd_format  ||= 'text'
        @pmd_cmd     ||= 'run.sh'
    end

    def build()
        super

        fp = fullpath()
        raise "PMD target '#{fp}' cannot be found" if !File.exists?(fp)
        cmd = File.join(@pmd_path, 'bin', @pmd_cmd)
        r = exec4(cmd, 'pmd', "-d \'#{fp}\'", "-format #{@pmd_format}", "-R #{@pmd_rules}")
        raise "PMD failed for '#{fp}'" if r != 0
    end

    def what_it_does() "Validate '#{@name}' code applying PMD:#{@pmd_rules}" end
end
