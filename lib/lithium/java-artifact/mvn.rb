require 'lithium/file-artifact/remote'

require 'fileutils'
require 'pathname'
require 'lithium/file-artifact/command'
require 'lithium/core-std'

class MVN < EnvArtifact
    include LogArtifactState
    include AutoRegisteredArtifact

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

    REQUIRE MVN

    def initialize(*args, &block)
        name = args.length > 0 && !args[0].nil? ? args[0] : homedir
        pom = FileArtifact.look_file_up(fullpath(name), 'pom.xml', homedir)
        raise "POM file cannot be detected by '#{fullpath(name)}'" if pom.nil?
        super(pom, &block)
    end

    def list_items()
        f = fullpath
        yield f, File.mtime(f).to_i
    end
end


class MavenClasspath < FileArtifact
    include StdFormater
    include LogArtifactState

    log_attr :excludeGroupIds, :excludeTransitive

    REQUIRE MVN

    default_name(File.join('.lithium', '.classpath', 'mvn_classpath'))


    def initialize(*args, &block)
        @excludeTransitive = false
        name = args.length == 0 || args[0].nil? ?  MavenClasspath.default_name : args[0]
        super(name, &block)
        raise "Classpath file points to existing directory '#{fullpath()}'" if File.directory?(fullpath())
        REQUIRE(POMFile.new(homedir)).TO(:pom)
        @excludeGroupIds ||= [ ]
    end

    def expired?()
        !File.exists?(fullpath)
    end

    def build()
        Dir.chdir(File.dirname(@pom.fullpath))
        raise "Failed '#{art}' cannot be copied" if 0 != Artifact.exec(@mvn.mvn,
                                                                       "dependency:build-classpath",
                                                                       "-DexcludeTransitive=#{@excludeTransitive}",
                                                                       @excludeGroupIds.length > 0 ? "-DexcludeGroupIds=#{@excludeGroupIds.join(',')}" : '',
                                                                       "-Dmdep.outputFile=#{fullpath}")
    end

    def what_it_does()
        "Store MVN classpath to '#{fullpath}'\n                   by '#{@pom.fullpath}'"
    end

    def classpath
        return File.exists?(fullpath) ? File.read(fullpath) : ''
    end
end

class POMDependenciesDir < FileArtifact
    include StdFormater

    REQUIRE MVN

    def initialize(name, &block)
        super(name, &block)

        fp = fullpath()
        raise "POMDependencies should point to file #{fp}" if File.exists?(fp) && !File.directory?(fp)

        REQUIRE(POMFile.new(@name)).TO(:pom)
        @excludeTransitive ||= true
        @excludeGroupIds   ||= [ ]
    end

    def build()
        Dir.chdir(File.dirname(@pom.fullpath))
        raise "Failed '#{art}' cannot be copied" if 0 != Artifact.exec(@mvn.mvn,
                                                                       "dependency:copy-dependencies",
                                                                       "-DexcludeTransitive=#{@excludeTransitive}",
                                                                       @excludeGroupIds.length > 0 ? "-DexcludeGroupIds=#{@excludeGroupIds.join(',')}" : '',
                                                                       "-DoutputDirectory=#{fullpath}")
    end

    def clean

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

    def build
        path = fullpath()
        raise "Target mvn artifact cannot be found '#{path}'" unless File.exists?(path)

        Dir.chdir(File.dirname(path));
        raise 'Maven running failed' if Artifact.exec(@mvn.mvn, OPTS(),  @targets.join(' ')) != 0
    end

    def what_it_does() "Run maven: '#{@target}'" end
end

class CompileMaven < RunMaven
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
