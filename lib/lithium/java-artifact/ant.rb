require 'lithium/core'
require 'lithium/java-artifact/base'

#
# ANT Environment
#
class ANT < SdkEnvironmen
    @tool_name = 'ant'
    @abbr      = 'ANT'

    def what_it_does() "Initialize ANT environment '#{@name}'" end

    def ant
        tool_path('ant')
    end
end

# Simple ant runner
class RunANT < ExistentFile
    include OptionsSupport

    @abbr = 'RAN'

    def initialize(name, &block)
        REQUIRE ANT
        ant_build = FileArtifact.look_file_up(fullpath(name), 'build.xml', homedir)
        raise "ANT build file cannot be detected by '#{fullpath(name)}'" if ant_build.nil?
        super(ant_build, &block)
    end

    def build()
        fp = fullpath()
        chdir(File.dirname(fp)) {
            raise 'ANT error' if 0 != Artifact.exec(@ant.ant, '-buildfile', "\"#{fp}\"", OPTS())
        }
    end

    def what_it_does() "Run ANT '#{fullpath()}'" end
end

