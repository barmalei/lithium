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
    include AssignableDependency[:gradle]

    default_name('build.gradle.kts')

    @abbr = 'GRF'

    def expired?
        false
    end
end

class RunGradle < Artifact
    include ToolExecuter

    @abbr = 'RGR'

    default_name('.env/gradle/run')

    def initialize(name = nil, &block)
        REQUIRE GradleFile
        REQUIRE GRADLE
        super
        @targets ||= [ 'build' ]
    end

    def WITH
        @gradle.gradle
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

    def build
        super
        go_to_homedir()
        EXEC()
    end

    def what_it_does
        "Run gradle: '#{@name}'\n    Targets = [ #{@targets.join(', ')} ]\n    OPTS    = '#{OPTS()}', '#{@gradle.OPTS()}'"
    end
end

# TODO: revise, not completed code
class RunGradleTest < RunGradle
    default_name('.env/gradle/test')

    def initialize(name = nil, &block)
        fp = fullpath(name)
        super
        TARGETS('test')
        if fp.end_with?('.java')
            pkg = JVM.grep_package(fp)
            fp  = File.basename(fp)
            fp[/\.java$/] = ''
            cls = pkg + '.' + fp
            OPT("-Dtest=#{cls}")
            puts "Single gradle test case '#{cls}' is detected"
        end
    end
end

class GradleCompiler < RunGradle
    default_name('.env/gradle/test')

    def initialize(name = nil, &block)
        super
        TARGETS('compileJava')
    end

    def expired?
        false
    end
end

# TODO: not completed
class GradleClasspath < InFileClasspath
    include StdFormater

    log_attr :excludeGroupIds, :excludeTransitive

    default_name(".lithium/gradle/classpath")

    def initialize(name, &block)
        super
        REQUIRE { 
            GRADLE()
            GradleFile(homedir)
        }
    end

    def build
        fp = fullpath
        # TODO: test code
        chdir(File.dirname(@gradle.fullpath)) {
            Files.exec(["gradle", "hello", "--console", "plain", "-q"]) { | stdin, stdout, th |
                stdin.close
                while line = stdout.gets do
                    #$stdout.puts line
                    line = line.chomp
                    File.open(fp, 'w') { | f |
                        f.print(line)
                    }
                end
            }

            # cmd = GRADLE_CMD()
            # cmd.push("-Dmdep.outputFile=\"#{fullpath}\"")
            # raise "Gradle classpath '#{@name}' cannot be generated" if Files.exec(*cmd).exitstatus != 0
        }
        super
    end

    def GRADLE_CMD
        [  @gradle.gradle ]
    end

    def what_it_does
        "Build gradle classpath by '#{@gradle.fullpath}' in '#{fullpath}'"
    end
end
