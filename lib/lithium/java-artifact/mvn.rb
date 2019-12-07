require 'lithium/file-artifact/remote'

require 'fileutils'
require 'pathname'
require 'lithium/file-artifact/command'
require 'lithium/java-artifact/base'
require 'lithium/std-core'

class MVN < EnvArtifact
    include LogArtifactState
    include AutoRegisteredArtifact
    include OptionsSupport

    log_attr :mvn_home

    def initialize(*args)
        super

        unless @mvn_home
            @mvn_home = FileArtifact.which('mvn')
            @mvn_home = File.dirname(File.dirname(@mvn_home)) unless @mvn_home.nil?
        end
        raise "Maven home '#{@mvn_home}' cannot be found" if @mvn_home.nil? || !File.exist?(@mvn_home)
        puts "Maven home: '#{@mvn_home}'"
    end

    def expired?() false end

    def what_it_does() "Initialize Maven environment '#{@name}'" end

    def mvn() File.join(@mvn_home, 'bin', 'mvn') end

    def self.parse_name(name)
        name = File.dirname(name) == '.' ? name : File.basename(name)
        m = /(.*)\-(\d+\.\d+)(\.\d+)?([-.]\w+)?\.[a-zA-Z]+$/.match(name)
        raise "Incorrect maven artifact name '#{name}'" if m.nil? || m.length < 3
        id     = m[1]
        group  = m[1].tr('.', '/')
        ver    = m[2] + (m[3] ? m[3] : '') +  (m[4] ? m[4] : '')

        return group, id, ver
    end
end

class MavenArtifact < CopyOfFile
    include StdFormater

    REQUIRE MVN

    def initialize(*args)
        super

        unless @source
            group, id, ver = MVN.parse_name(@name)
            raise "Group, if or version cannot be figured out by artifact name '#{name}'" if group.nil? || id.nil? || ver.nil?
            @source = "#{group}:#{id}:#{ver}"
        end
    end

    def expired?
        src = validate_source()
        return !File.exists?(fullpath)
    end

    def validate_source()
        raise 'Source is not defined' if @source.nil?
        return @source
    end

    def fetch()
        raise "Artifact '#{@source}' cannot be copied" if 0 != Artifact.exec(@mvn.mvn(),
                                                                            "dependency:copy",  "-Dartifact=#{@source}",
                                                                            "-DoutputDirectory=#{File.dirname(fullpath)}")
    end
end

class POMFile < PermanentFile
    include LogArtifactState
    include StdFormater
    include AssignableDependency

    REQUIRE MVN

    def initialize(*args, &block)
        name = args.length > 0 && !args[0].nil? ? args[0] : homedir
        pom = FileArtifact.look_file_up(fullpath(name), 'pom.xml', homedir)
        raise "POM '#{fullpath(name)}' not found" if pom.nil?
        super(pom, &block)
    end

    def assign_me_to()
        return 'pom'
    end

    def list_items()
        f = fullpath
        yield f, File.mtime(f).to_i
    end
end

class MavenClasspath < InFileClasspath
    REQUIRE MVN

    include StdFormater

    log_attr :excludeGroupIds, :excludeTransitive

    def initialize(*args, &block)
        @excludeTransitive = false
        super(*args, &block)
        REQUIRE(POMFile.new(homedir))
        @excludeGroupIds ||= []
    end

    def build()
        Dir.chdir(File.dirname(@pom.fullpath))
        raise "Failed '#{art}' cannot be copied" if 0 != Artifact.exec(@mvn.mvn,
                                                                       "dependency:build-classpath",
                                                                       "-DexcludeTransitive=#{@excludeTransitive}",
                                                                       @excludeGroupIds.length > 0 ? "-DexcludeGroupIds=#{@excludeGroupIds.join(',')}" : '',
                                                                       "-Dmdep.outputFile=#{fullpath}")
        super
    end

    def what_it_does()
        "Build maven classpath by #{@pom.fullpath}"
    end
end

class MavenDependenciesDir < FileArtifact
    include StdFormater

    REQUIRE MVN

    def initialize(name, &block)
        @excludeTransitive = false

        super(name, &block)

        fp = fullpath()
        raise "POMDependencies should point to file #{fp}" if File.exists?(fp) && !File.directory?(fp)

        REQUIRE(POMFile.new(@name))
        @excludeGroupIds   ||= [ ]
    end

    def expired?
        true
    end

    def build()
        Dir.chdir(File.dirname(@pom.fullpath))
        raise "Failed '#{art}' cannot be copied" if 0 != Artifact.exec(@mvn.mvn,
                                                                       "dependency:copy-dependencies",
                                                                       "-DexcludeTransitive=#{@excludeTransitive}",
                                                                       @excludeGroupIds.length > 0 ? "-DexcludeGroupIds=#{@excludeGroupIds.join(',')}" : '',
                                                                       "-DoutputDirectory=#{fullpath}")
    end
end


class RunMaven < POMFile
    include OptionsSupport

    REQUIRE MVN

    def initialize(name, &block)
        super
        @targets ||= [ 'clean', 'install' ]
    end

    def expired?
        true
    end

    def TARGETS(*args)
        @targets = []
        args.each { | target |
            @targets.push(target)
        }
    end

    def build
        path = fullpath()
        raise "Target mvn artifact cannot be found '#{path}'" unless File.exists?(path)
        Dir.chdir(File.dirname(path));
        raise 'Maven running failed' if Artifact.exec(@mvn.mvn, @mvn.OPTS(),  @targets.join(' ')) != 0
    end

    def what_it_does() "Run maven: '#{@name}' #{@targets.join(' ')} OPTS=#{@mvn.OPTS()}" end
end

class CompileMaven < RunMaven
    REQUIRE MVN

    def initialize(*args)
        super
        @targets = [ 'compile' ]
    end

    def expired?
        false
    end

    def list_items()
        dir = File.join(File.dirname(fullpath()), 'src', '**', '*')
        FileMask.new(dir).list_items { |f, t|
            yield f, t
        }

        super { |f, t|
            yield f, t
        }
    end
end
