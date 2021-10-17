require 'lithium/core'
require 'lithium/file-artifact/command'
require 'lithium/java-artifact/runner'

class CPP < EnvArtifact
    include AutoRegisteredArtifact

    def initialize(name)
        @create_destination = true
        super
        @destination ||= 'bin'
    end

    def destination
        unless @destination.nil?
            @destination = File.join(homedir, @destination) unless File.absolute_path?(@destination)
            if !File.exists?(@destination) && @create_destination
                puts_warning "Create destination '#{@destination}' folder"
                FileUtils.mkdir_p(@destination)
            end

            return @destination
        else
            return homedir
        end
    end

    def what_it_does() "Initialize C environment '#{@name}'" end

    def expired?
        false
    end
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
    def initialize(name, &block)
        super
        @run_with ||= 'c++'
    end

    def run_with_options(opts)
        dst = destination
        fn  = File.basename(fullpath, '.*')
        opts.push('-o', "\"#{File.join(dst, fn)}\"")
        return opts
    end

    def self.abbr() 'CCC' end
end

class CppCodeRunner < CppRunTool
    def initialize(name, &block)
        super
        @run_with ||= 'exec'
    end

    def transform_source_path(path)
        return File.join(destination, File.basename(path, '.*'))
    end

    def self.abbr() 'RCC' end
end


class RunMakefile < RunTool
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

    def self.abbr() 'RMF' end
end

