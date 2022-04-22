require 'lithium/file-artifact/remote'

require 'fileutils'
require 'lithium/file-artifact/command'
require 'lithium/java-artifact/base'
require 'lithium/std-core'

class MVN < EnvArtifact
    include LogArtifactState
    include AutoRegisteredArtifact
    include OptionsSupport

    log_attr :mvn_home

    def initialize(name, &block)
        super

        unless @mvn_home
            @mvn_home = FileArtifact.which('mvn')
            @mvn_home = File.dirname(File.dirname(@mvn_home)) unless @mvn_home.nil?
        end

        if @mvn_home.nil? || !File.exist?(@mvn_home)
            puts_error "Maven home '#{@mvn_home}' cannot be found"
            puts_error 'Configure/install MAVEN if it is required for your project'
        else
            puts "Maven home: '#{@mvn_home}'"
        end
    end

    def expired?
        false
    end

    def what_it_does
        "Initialize Maven environment '#{@name}'"
    end

    def mvn
        File.join(@mvn_home, 'bin', 'mvn')
    end

    def self.abbr
        'MVN'
    end
end

module MavenDependencyPlugin
    def TRANSITIVE(flag)
        @excludeTransitive = flag
    end

    def GROUPS_OUT(*args)
        @excludeGroupIds = []
        @excludeGroupIds.concat(args)
    end

    def GROUPS_IN(*args)
        @includeGroupIds = []
        @includeGroupIds.concat(args)
    end

    def SCOPES_OUT(*args)
        @excludeScopes = []
        @excludeScopes.concat(args)
    end

    def SCOPES_IN(*args)
        @includeScopes = []
        @includeScopes.concat(args)
    end

    def DEP_TARGET(target)
        @depTarget = target
    end

    def MVN_CMD
        raise 'Maven dependency target was not defined' if @depTarget.nil?

        cmd = [ @mvn.mvn, "dependency:#{@depTarget}" ]
        cmd.push("-DexcludeTransitive=#{@excludeTransitive}")       unless @excludeTransitive.nil?
        cmd.push("-DexcludeGroupIds=#{@excludeGroupIds.join(',')}") unless @excludeGroupIds.nil? || @excludeGroupIds.length == 0
        cmd.push("-DincludeGroupIds=#{@includeGroupIds.join(',')}") unless @includeGroupIds.nil? || @includeGroupIds.length == 0

        unless @includeScopes.nil? || @includeScopes.length == 0
            cmd.concat(@includeScopes.map { | e |  "-DincludeScope=#{e}" })
        end

        unless @excludeScopes.nil? || @excludeScopes.length == 0
            cmd.concat(@excludeScopes.map { | e |  "-DexcludeScope=#{e}" })
        end

        return cmd
    end
end

class MavenRepoArtifact < FileArtifact
    include StdFormater
    include MavenDependencyPlugin

    def initialize(name, &block)
        REQUIRE MVN

        r = /\[([^\[\/\]]+)\/([^\[\/\]]+)\/([^\[\/\]]+)\]$/
        m = r.match(name)
        raise "Invalid artifact name '#{name}'" if m.nil?

        @group, @id, @ver = m[1], m[2], m[3]
        name[r] = ''
        super

        DEP_TARGET('copy')
    end

    def expired?
        return !File.exists?(File.join(fullpath, "#{@id}-#{@ver}.jar"))
    end

    def clean
        path = File.join(fullpath, "#{@id}-#{@ver}.jar")
        File.delete(path) if File.file?(path)
    end

    def build
        chdir(File.dirname(@pom.fullpath)) {
            cmd = MVN_CMD()
            cmd.push("-Dartifact=#{@group}:#{@id}:#{@ver}")
            cmd.push("-DoutputDirectory=\"#{fullpath}\"")
            raise "Artifact '#{@group}:#{@id}:#{@ver}' cannot be copied" if 0 != Artifact.exec(*cmd)
        }
    end

    def what_it_does
        "Fetch '#{@group}:#{@id}:#{@ver}' maven artifact\n   to '#{@name}'"
    end
end

class PomFile < ExistentFile
    include LogArtifactState
    include StdFormater
    include AssignableDependency

    def initialize(name = nil, &block)
        REQUIRE MVN
        name = homedir if name.nil?
        fp   = fullpath(name)
        pom  = FileArtifact.look_file_up(fp, 'pom.xml', homedir)
        raise "POM cannot be detected by '#{fp}' path" if pom.nil?
        super(pom, &block)
    end

    def assign_me_to
        return 'pom'
    end

    def self.abbr() 'POM' end
end

class MavenClasspath < InFileClasspath
    include StdFormater
    include MavenDependencyPlugin

    log_attr :excludeGroupIds, :excludeTransitive

    default_name(".lithium/li_maven_class_path")

    def initialize(name, &block)
        super
        REQUIRE MVN
        REQUIRE(PomFile.new(homedir, owner:self.owner))
        DEP_TARGET('build-classpath')
        TRANSITIVE(false)
    end

    def build
        chdir(File.dirname(@pom.fullpath)) {
            cmd = MVN_CMD()
            cmd.push("-Dmdep.outputFile=\"#{fullpath}\"")
            raise "Maven classpath '#{@name}' cannot be generated" if Artifact.exec(*cmd).exitstatus != 0
        }
        super
    end

    def what_it_does
        "Build maven classpath by '#{@pom.fullpath}' in '#{fullpath}'"
    end
end

#
# Build directory and copy maven dependencies to the folder
#
class MavenDependenciesDir < Directory
    include StdFormater
    include MavenDependencyPlugin

    def initialize(name, &block)
        super
        REQUIRE MVN
        REQUIRE(PomFile.new(@name, owner:self.owner))
        DEP_TARGET('copy-dependencies')
    end

    def expired?
        true
    end

    def build
        super
        chdir(File.dirname(@pom.fullpath)) {
            cmd = MVN_CMD()
            cmd.push("-DoutputDirectory=\"#{fullpath}\"")
            raise "Dependency directory '#{@name}' cannot be created" if Artifact.exec(*cmd).exitstatus != 0
        }
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
        @targets.concat(args)
    end

    def build
        path = fullpath
        raise "Target mvn artifact cannot be found '#{path}'" unless File.exists?(path)
        chdir(File.dirname(path)) {
            if Artifact.exec(@mvn.mvn, @mvn.OPTS(), OPTS(), @targets.join(' ')).exitstatus != 0
                raise "Maven [#{@targets.join(',')}] running failed"
            end
        }
    end

    def what_it_does
        "Run maven: '#{@name}'\n    Targets = [ #{@targets.join(', ')} ]\n    OPTS    = '#{OPTS()}', '#{@mvn.OPTS()}'"
    end

    def self.abbr() 'RMV' end
end

class RunMavenTest < RunMaven
    def initialize(name, &block)
        fp = fullpath(name)
        super
        TARGETS('test')
        if fp.end_with?('.java')
            pkg = JVM.grep_package(fp)
            fp  = File.basename(fp)
            fp[/\.java$/] = ''
            cls = pkg + '.' + fp
            OPT("-Dtest=#{cls}")
            puts "Single maven test case '#{cls}' is detected"
        end
    end
end

class MavenCompiler < RunMaven
    def initialize(name)
        super
        TARGETS('compile')
    end

    def expired?
        false
    end

    def list_items
        dir = File.join(File.dirname(fullpath), 'src', '**', '*')
        FileMask.new(dir, owner:self.owner).list_items { | f, t |
            yield f, t
        }

        super { | f, t |
            yield f, t
        }
    end
end