require 'fileutils'

require 'lithium/file-artifact/command'
require 'lithium/java-artifact/base'
require 'lithium/std-core'

class MVN < SdkEnvironmen
    include SdkmanTool

    @tool_name = 'mvn'

    def mvn
        # # TODO: workaround to configure Maven JVM. It is expected JAVA set
        # # JAVA_HOME variable that is required by maven
        # #
        # # making JAVA as dependency brings to cyclic dep problem
        # # !
        jv = Project.artifact(JAVA)
        ENV['JAVA_HOME'] = jv.sdk_home unless jv.nil?
        tool_path(tool_name())
    end

    def SKIPTESTS
        OPT('-Dmaven.test.skip=true')
    end

    def PROFILE(name)
        OPT("-P#{name}")
    end

    def SDKMAN(version = nil)
        sdkman_pkg_home('maven', version)
    end
end

class PomFile < ExistentFile
    include LogArtifactState
    include AssignableDependency[:pom]

    default_name('pom.xml')

    def expired?
        false
    end
end

module MavenDependencyOptions
    include OptionsSupport

    def TRANSITIVE(flag)
        OPT("-DexcludeTransitive=#{flag}")
    end

    def GROUPS_OUT(*args)
        OPT("-DexcludeGroupIds=#{args.join(',')}")
    end

    def GROUPS_IN(*args)
        OPT("-DincludeGroupIds=#{args.join(',')}")
    end

    def SCOPES_OUT(*args)
        args.map { | e |  OPT("-DexcludeScope=#{e}") }
    end

    def SCOPES_IN(*args)
        args.map { | e |  OPT("-DincludeScope=#{e}") }
    end

    def INCLUDES(*args)
        OPT("-Dincludes=#{args.join(',')}")
    end
end

module MvnExecutor
    include ToolExecuter
    include StdFormater

    def WITH
        @mvn.mvn
    end

    def build
        go_to_homedir
        EXEC()
        super
    end
end

class MavenClasspath < InFileClasspath
    include MvnExecutor
    include MavenDependencyOptions

    default_name(".lithium/mvn/classpath")

    def initialize(name = nil, &block)
        super
        REQUIRE MVN
        REQUIRE PomFile
        TRANSITIVE(false)
    end

    # TODO: prevent passing command line arguments to the execution of maven
    # the problem can appear when MavenClasspath is a dependency of other artifact
    # that expects args
    def WITH_ARGS
        @arguments ||= []
        return @arguments
    end

    #def build
        #dir = File.dirname(fullpath())
        #FileUtils.mkdir_p(dir) unless File.exist?(dir)
     #   super
    #end

    def WITH_TARGETS
        [ "dependency:build-classpath" ]
    end

    def WITH_OPTS
        super + [ "-Dmdep.outputFile=#{q_fullpath}" ]
    end

    def what_it_does
        "Build maven classpath by '#{@pom.fullpath}' in '#{fullpath}'"
    end
end

#
# Build directory and copy maven dependencies to the folder
#
class MavenDependenciesDir < Directory
    include MvnExecutor
    include MavenDependencyOptions

    def initialize(name, &block)
        super
        REQUIRE MVN
        REQUIRE PomFile
    end

    def expired?
        true
    end

    def WITH_TARGETS
        [ "dependency:copy-dependencies" ]
    end

    def WITH_OPTS
        super + [ "-DoutputDirectory=\"#{fullpath}\"" ]
    end
end

class RunMaven < Artifact
    include MvnExecutor

    @abbr = 'RMV'

    default_name('.env/mvn/run')

    def initialize(name = nil, &block)
        REQUIRE MVN
        REQUIRE PomFile
        super
        @targets ||= [ 'clean', 'install' ]
    end

    def expired?
        false
    end

    def TARGETS(*args)
        @targets = []
        @targets.concat(args)
    end

    # TODO: replace with "WITH_COMMANDS"
    def WITH_TARGETS
        @targets
    end

    def WITH_OPTS
        @mvn.OPTS() + super
    end

    def what_it_does
        "Run maven: '#{@name}'\n    Targets = [ #{@targets.join(', ')} ]\n    OPTS    = '#{WITH_OPTS()}'"
    end
end

class RunMavenTest < RunMaven
    default_name('.env/mvn/test')

    def initialize(name = nil, &block)
        super
        TARGETS('test')
    end

    def TEST_CLASS(name)
        OPT("-Dtest=#{name}")
    end
end

class MavenCompiler < RunMaven
    default_name('.env/mvn/compile')

    def initialize(name = nil, &block)
        super
        TARGETS('compile')
    end
end

class ShowMavenArtifactTree < RunMaven
    include MavenDependencyOptions

    default_name('.env/mvn/deptree')

    def initialize(name, &block)
        super(File.dirname(name), &block)
        TARGETS('dependency:tree')
    end

    def expired?
        true
    end
end

