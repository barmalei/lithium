require 'lithium/core'
require 'lithium/file-artifact/command'
require 'lithium/java-artifact/runner'

class CPP < EnvArtifact
    include LogArtifactState
    include SelfRegisteredArtifact

    log_attr :destination

    def initialize(name)
        @create_destination = true
        super
        @destination ||= 'bin'
    end

    def destination
        unless @destination.nil?
            @destination = File.join(homedir, @destination) unless File.absolute_path?(@destination)
            if !File.exist?(@destination) && @create_destination
                puts_warning "Create destination '#{@destination}' folder"
                FileUtils.mkdir_p(@destination)
            end

            return @destination
        else
            return homedir
        end
    end

    def what_it_does() "Initialize C environment '#{@name}'" end
end

class CppRunTool < RunTool
    def initialize(name, &block)
        REQUIRE CPP
        super
    end

    def destination
        @cpp.destination
    end
end

class CppCompiler < CppRunTool
    def WITH
        'c++'
    end

    def WITH_OPTS
        fn = File.basename(fullpath, '.*')
        super.push('-o', "\"#{File.join(destination(), fn)}\"")
    end
end

class CppCodeRunner < CppRunTool
    @abbr = 'RCC'

    def WITH
        'exec'
    end

    def transform_target_path(path)
        File.join(destination, File.basename(path, '.*'))
    end
end

class RunMakefile < RunTool
    @abbr = 'RMF'

    def initialize(name, &block)
        super
        @targets ||= []
    end

    def build
        chdir(File.dirname(fullpath)) {
            Artifact.exec('make', @targets.join(' '))
        }
    end

    def what_it_does
        "Run make file for '#{@name}'"
    end
end

