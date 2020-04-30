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

    def self.abbr() 'MVN' end
end

class MavenRepoArtifact < FileArtifact
    include StdFormater

    def initialize(name, &block)
        REQUIRE MVN

        r = /\[([^\[\/\]]+)\/([^\[\/\]]+)\/([^\[\/\]]+)\]$/
        m = r.match(name)
        raise "Invalid artifact name '#{name}'" if m.nil?

        @group, @id, @ver = m[1], m[2], m[3]
        name[r] = ''
        super(name, &block)
    end

    def expired?
        return !File.exists?(File.join(fullpath, "#{@id}-#{@ver}.jar"))
    end

    def clean()
        path = File.join(fullpath, "#{@id}-#{@ver}.jar")
        File.delete(path) if File.file?(path)
    end

    def build()
        raise "Artifact '#{@group}:#{@id}:#{@ver}' cannot be copied" if 0 != Artifact.exec(
            @mvn.mvn,
            "dependency:copy",
            "-Dartifact=#{@group}:#{@id}:#{@ver}",
            "-DoutputDirectory=\"#{fullpath}\""
        )
    end

    def what_it_does()
        "Fetch '#{@group}:#{@id}:#{@ver}' maven artifact\n   to '#{@name}'"
    end
end

class PomFile < PermanentFile
    include LogArtifactState
    include StdFormater
    include AssignableDependency

    def initialize(*args, &block)
        REQUIRE MVN
        name = args.length > 0 && !args[0].nil? ? args[0] : homedir
        fp   = fullpath(name)
        pom  = FileArtifact.look_file_up(fp, 'pom.xml', homedir)
        raise "POM cannot be detected by '#{fp}' path" if pom.nil?
        super(pom, &block)
    end

    def assign_me_to()
        return 'pom'
    end

    def list_items()
        f = fullpath
        yield f, File.mtime(f).to_i
    end

    def self.abbr() 'POM' end
end

class MavenClasspath < InFileClasspath
    include StdFormater

    log_attr :excludeGroupIds, :excludeTransitive

    default_name(".li_maven_class_path")

    def initialize(*args, &block)
        puts "homedir = #{homedir}, #{owner} "

        REQUIRE MVN
        @excludeTransitive = false
        super(*args, &block)
        REQUIRE(PomFile.new(homedir))
        @excludeGroupIds ||= []
    end

    def build()
        Dir.chdir(File.dirname(@pom.fullpath))
        raise "Failed '#{art}' cannot be copied" if 0 != Artifact.exec(
            @mvn.mvn,
            "dependency:build-classpath",
            "-DexcludeTransitive=#{@excludeTransitive}",
            @excludeGroupIds.length > 0 ? "-DexcludeGroupIds=#{@excludeGroupIds.join(',')}" : '',
            "-Dmdep.outputFile=\"#{fullpath}\""
        )
        super
    end

    def what_it_does()
#        "Build maven classpath by '#{@pom.fullpath}' in '#{fullpath}'"
    end
end

class MavenDependenciesDir < FileArtifact
    include StdFormater

    def initialize(name, &block)
        REQUIRE MVN
        @excludeTransitive = false
        @excludeGroupIds   = []

        super(name, &block)

        fp = fullpath()
        raise "Invalid dependency dir '#{fp}'" unless File.directory?(fp)

        REQUIRE(PomFile.new(@name))
    end

    def EXCLUDE(groupId)
        @excludeGroupIds.push(groupId)
    end

    def expired?
        true
    end

    def build()
        Dir.chdir(File.dirname(@pom.fullpath))
        raise "Failed '#{art}' cannot be copied" if 0 != Artifact.exec(
            @mvn.mvn,
           "dependency:copy-dependencies",
           "-DexcludeTransitive=#{@excludeTransitive}",
           @excludeGroupIds.length > 0 ? "-DexcludeGroupIds=#{@excludeGroupIds.join(',')}" : '',
           "-DoutputDirectory=#{fullpath}"
        )
    end
end


class RunMaven < PomFile
    include OptionsSupport

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
        raise 'Maven running failed' if Artifact.exec(@mvn.mvn, @mvn.OPTS(), @targets.join(' ')) != 0
    end

    def what_it_does() "Run maven: '#{@name}'\n    Targets = [ #{@targets.join(', ')} ]\n    OPTS    = '#{@mvn.OPTS()}'" end

    def self.abbr() 'RMV' end
end

class RunMavenTest < RunMaven
    def initialize(name, &block)
        super
        TARGETS('test')
    end
end

class MavenCompiler < RunMaven
    def initialize(*args)
        super
        TARGETS('compile')
    end

    def expired?
        false
    end

    def list_items()
        dir = File.join(File.dirname(fullpath), 'src', '**', '*')
        FileMask.new(dir).list_items { |f, t|
            yield f, t
        }

        super { | f, t |
            yield f, t
        }
    end
end

