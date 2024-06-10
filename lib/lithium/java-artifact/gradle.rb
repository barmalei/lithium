require 'fileutils'
require 'lithium/java-artifact/base'
require 'lithium/std-core'

class GRADLE < SdkEnvironmen
    @tool_name = 'gradle'
    @abbr      = 'GRD'

    def gradle
        tool_path(tool_name())
    end
end

class GradleFile < ExistentFile
    include LogArtifactState
    include StdFormater
    include AssignableDependency[:gradlefile]

    default_name('build.gradle')

    @abbr = 'GRF'

    def expired?
        false
    end
end

module GradleExecutor
    include ToolExecuter
    include StdFormater

    def WITH
        @gradle.gradle
    end

    def build
        go_to_homedir
        EXEC()
        super
    end
end

class RunGradle < Artifact
    include GradleExecutor

    @abbr = 'RGR'

    default_name('@gradle/run')

    def initialize(name = nil, &block)
        REQUIRE GradleFile
        REQUIRE GRADLE
        super
        @targets ||= [ 'build' ]
    end

    def WITH_OPTS
        @gradle.OPTS() + super
    end


    def TARGETS(*args)
        @targets = []
        @targets.concat(args)
    end

    # TODO: replace with WITH_COMMANDS
    def WITH_TARGETS
        @targets
    end

    def what_it_does
        "Run gradle: '#{@name}'\n    Targets = [ #{@targets.join(', ')} ]\n    OPTS    = '#{OPTS()}', '#{@gradle.OPTS()}'"
    end
end

class RunGradleTest < RunGradle
    default_name('@gradle/test')

    def initialize(name = nil, &block)
        super
        TARGETS('test')
    end
end

class GradleCompiler < RunGradle
    default_name('@gradle/test')

    def initialize(name = nil, &block)
        super
        TARGETS('compileJava')
    end

    def expired?
        false
    end
end

class GradleClasspath < InFileClasspath
    include GradleExecutor

    default_name(".lithium/gradle/classpath")

    def initialize(name, &block)
        super
        REQUIRE GRADLE
        REQUIRE GradleFile
    end

    def WITH_OPTS
        [ '-q', "-I #{File.join($lithium_code, 'ext', 'java', 'gradle', 'init.gradle')}" ]
    end

    def WITH_TARGETS
        super + [ 'classpath' ]
    end

    def build
        go_to_homedir
        class_path = []
        EXEC { | stdin, stdout, thread |
            while line = stdout.gets do
                class_path.push(line.chomp)
            end
            stdout.close
        }

        fp  = fullpath
        dir = File.dirname(fp)
        FileUtils.mkdir_p(dir) unless File.directory?(dir)
        File.open(fp, 'w') { | f |
            f.write(class_path.join(File::PATH_SEPARATOR))
        }
    end

    def what_it_does
        "Build gradle classpath by '#{@gradlefile.fullpath}' in '#{fullpath}'"
    end
end
