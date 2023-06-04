require 'lithium/core-file-artifact'

class CPP < EnvArtifact
    include LogArtifactState

    def initialize(name)
        super
        DESTINATION('bin')
    end

    def DESTINATION(path)
        REQUIRE(path, DestinationDirectory)
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
            Files.exec('make', @targets.join(' '))
        }
    end

    def what_it_does
        "Run make file for '#{@name}'"
    end
end

