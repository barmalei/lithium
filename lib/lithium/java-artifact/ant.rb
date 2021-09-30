require 'lithium/core'
require 'lithium/java-artifact/base'

#
# ANT Environment
#
class ANT < EnvArtifact
    include LogArtifactState
    include AutoRegisteredArtifact

    log_attr :ant_home

    def initialize(*args)
        super

        unless @ant_home
            @ant_home = FileArtifact.which('ant')
            @ant_home = File.dirname(File.dirname(@ant_home)) unless @ant_home.nil?
        end
        raise "ANT home '#{@ant_home}' cannot be found" if @ant_home.nil? || !File.exist?(@ant_home)
        puts "ANT home: '#{@ant_home}'"
    end

    def what_it_does() "Initialize ANT environment '#{@name}'" end

    def ant() File.join(@ant_home, 'bin', 'ant') end

    def self.abbr() 'ANT' end
end

# Simple ant runner
class RunANT < FileCommand
    include OptionsSupport

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

    def self.abbr() 'RAN' end
end

