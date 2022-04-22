require 'lithium/file-artifact/remote'

require 'fileutils'
require 'lithium/file-artifact/command'
require 'lithium/java-artifact/base'
require 'lithium/std-core'

# TODO: copy paste of MVN
class GRADLE < EnvArtifact
    include LogArtifactState
    include AutoRegisteredArtifact
    include OptionsSupport

    log_attr :gradle_home

    def initialize(name, &block)
        super

        unless @gradle_home
            @gradle_home = FileArtifact.which('gradle')
            @gradle_home = File.dirname(File.dirname(@gradle_home)) unless @gradle_home.nil?
        end
        raise "Gradle home '#{@gradle_home}' cannot be found" if @gradle_home.nil? || !File.exist?(@gradle_home)
        puts "Gradle home: '#{@gradle_home}'"
    end

    def expired?
        false
    end

    def what_it_does
        "Initialize Gradle environment '#{@name}'"
    end

    def gradle
        File.join(@gradle_home, 'bin', 'gradle')
    end

    def self.abbr
        'GRD'
    end
end

class GradleFile < ExistentFile
    include LogArtifactState
    include StdFormater
    include AssignableDependency

    def initialize(name = nil, &block)
        REQUIRE GRADLE
        name = homedir if name.nil?
        fp   = fullpath(name)
        gradle  = FileArtifact.look_file_up(fp, 'build.gradle.kts', homedir)
        gradle  = FileArtifact.look_file_up(fp, 'build.gradle', homedir) if  gradle.nil?
        raise "Gradle build file cannot be detected by '#{fp}' path" if  gradle.nil?
        super( gradle, &block)
    end

    def assign_me_to
        return 'gradle'
    end

    def self.abbr() 'GRD' end
end

class RunGradle < GradleFile
    include OptionsSupport

    def initialize(name, &block)
        super
        @targets ||= [ 'build' ]
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
        raise "Target gradle artifact cannot be found '#{path}'" unless File.exists?(path)
        chdir(File.dirname(path)) {
            if Artifact.exec(@gradle.gradle, @gradle.OPTS(), OPTS(), @targets.join(' ')).exitstatus != 0
                raise "Gradle [#{@targets.join(',')}] running failed"
            end
        }
    end

    def what_it_does
        "Run gradle: '#{@name}'\n    Targets = [ #{@targets.join(', ')} ]\n    OPTS    = '#{OPTS()}', '#{@gradle.OPTS()}'"
    end

    def self.abbr() 'RGR' end
end

class RunGradleTest < RunGradle
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
            puts "Single gradle test case '#{cls}' is detected"
        end
    end
end

class GradleCompiler < RunGradle
    def initialize(name)
        super
        TARGETS('compileJava')
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


class GradleClasspath < InFileClasspath
    include StdFormater

    log_attr :excludeGroupIds, :excludeTransitive

    default_name(".lithium/li_gradle_class_path")

    def initialize(name, &block)
        super
        REQUIRE GRADLE
        REQUIRE(GradleFile.new(homedir, owner:self.owner))
    end

    def build
        fp = fullpath
        chdir(File.dirname(@gradle.fullpath)) {
            Artifact.exec(["gradle", "hello", "--console", "plain", "-q"]) { | stdin, stdout, th |
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
            # raise "Gradle classpath '#{@name}' cannot be generated" if Artifact.exec(*cmd).exitstatus != 0
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
