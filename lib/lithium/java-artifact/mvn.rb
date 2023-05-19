require 'lithium/file-artifact/remote'

require 'fileutils'
require 'lithium/file-artifact/command'
require 'lithium/java-artifact/base'
require 'lithium/std-core'

class MVN < JVM
    @tool_name = 'mvn'

    def mvn
        # TODO: workaround to configure Maven JVM. It is expected JAVA set 
        # JAVA_HOME variable that is required by maven 
        # 
        # making JAVA as dependecy brings to cyclic dep problem
        # !
        #jv = Project.artifact(JAVA)
        # ENV['JAVA_HOME'] = jv.sdk_home unless jv.nil?

        tool_path(tool_name())
    end

    def SKIPTESTS
        OPT("-Dmaven.test.skip=true")
    end

    def PROFILE(name)
        OPT("-P#{name}")
    end

    def SDKMAN(*args)
        candidate = 'maven'
        version   = nil
        if args.length == 2
            candidate = args[0]
            version   = args[1]
        elsif args.length == 1
            version = args[0]
        elsif args.length == 0  
            version = nil
        else
            raise "Invalid number of arguments"
        end

        super(candidate, version)
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

class PomFile < ExistentFile
    include LogArtifactState
    include AssignableDependency[:pom]

    def initialize(name = nil, &block)
        REQUIRE MVN
        name = FileArtifact.look_file_up(homedir, 'pom.xml', homedir) if name.nil?
        super
    end

    def expired?
        false
    end
end

class MavenClasspath < InFileClasspath
    include StdFormater
    include MavenDependencyPlugin

    log_attr :excludeGroupIds, :excludeTransitive

    default_name(".lithium/mvn_classpath")

    def initialize(name, &block)
        super
        REQUIRE MVN
        REQUIRE 'pom.xml'
        DEP_TARGET('build-classpath')
        TRANSITIVE(false)
    end

    def build
        chdir(File.dirname(@pom.fullpath)) {
            cmd = MVN_CMD()
            cmd.push(@mvn.OPTS())
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
        REQUIRE 'pom.xml'
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
    include StdFormater

    @abbr = 'RMV'

    def initialize(name = nil, &block)
        super
        @targets ||= [ 'clean', 'install' ]
    end

    def TARGETS(*args)
        @targets = []
        @targets.concat(args)
    end

    def build
        path = fullpath
        raise "Target mvn artifact cannot be found '#{path}'" unless File.exist?(path)
        chdir(File.dirname(path)) {
            if Artifact.exec(@mvn.mvn, @mvn.OPTS(), OPTS(), @targets.join(' ')).exitstatus != 0
                raise "Maven [#{@targets.join(',')}] running failed"
            end
        }
    end

    def what_it_does
        "Run maven: '#{@name}'\n    Targets = [ #{@targets.join(', ')} ]\n    OPTS    = '#{OPTS()}', '#{@mvn.OPTS()}'"
    end
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

class MavenDependency < RunMaven
    def initialize(name)
        TARGETS('dependency:build-classpath')
    end

    def TRANSITIVE(flag)
        self['DexcludeTransitive', flag]
    end

    def EXCLUDE_GROUP(*args)
        self['DexcludeTransitive', flag]

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


class BuildMavenClasspath < RunMaven
    def initialize(name)
        super
        OPT('-DexcludeTransitive=false')
        TARGETS('dependency:build-classpath')
    end
end

class ShowMavenArtifactTree < RunMaven
    def initialize(name, &block)
        @artifact = File.basename(name)
        super(File.dirname(name), &block)
        TARGETS('dependency:tree')
        OPT("-Dincludes=#{@artifact}")
    end

    def expired?
        true
    end
end
