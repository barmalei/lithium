require 'fileutils'
require 'tempfile'

require 'lithium/core'
require 'lithium/file-artifact/command'
require 'lithium/file-artifact/acquired'
require 'lithium/java-artifact/base'

class ExtractJAR < FileCommand
    required JAVA

    def initialize(*args)
        super
        @destination ||= 'tmp'
    end

    def build()
        FileUtils.mkdir_p(@destination) if !File.exists?(@destination)
        Dir.chdir(@destination)
        `jar -xfv '#{fullpath()}'`.each { |i|
            puts " :: #{i.chomp}"
        }
    end

    def what_it_does() "Extract files from '#{@name}' to '#{@destination}'" end
end

class FindInJAR < FileCommand
    required JAVA

    def build()
        c = 0
        @class_name = @class_name.gsub('.', '/')
        `jar -ft '#{fullpath()}'`.each { |item|
            index = item.chomp.index(@class_name)
            if index == 0
                puts "#{@name}:#{@class_name}:"
                c += 1
            end
        }
    end

    def what_it_does() "Try to find #{@class_name} class in '#{@name}'" end
end

class CreateJAR < FileMask
    required JAVA
    include LogArtifactState

    log_attr :destination, :base, :manifest

    def initialize(*args)
        super
        @destination ||= $lithium_args.length > 0 ? $lithium_args[0] : "result.jar"
        @manifest    ||= nil
        @ignore_dirs = true
        @base        ||= $lithium_args.length > 1 ? $lithium_args[1] : nil

        @base = fullpath("lib") if !@base
        raise "Invalid base directory '#{@base}'" if !File.exists?(@base) || !File.directory?(@base)

        if @manifest
            @manifest = fullpath(@manifest)
            raise "Manifest file '#{@manifest}' cannot be found" if !File.exists?(@manifest)
            raise "Manifest file '#{@manifest}'' is a directory" if  File.directory?(@manifest)
        end
    end

    def build()
        dest = fullpath(@destination)
        list = paths_to_list(@base).join(' ')

        Dir.chdir(@base)
        if @manifest
            r = exec4(java().jar, "cfm", "'#{dest}'", "'#{@manifest}'", "-C '#{@base}'", list)
        else
            r = exec4(java().jar, "cf", "'#{dest}'",  list)
        end
        raise "JAR #{dest} creation error" if r != 0
    end

    def what_it_does()
        return "Create JAR '#{@destination}' by '#{name}' relatively to '#{@base}'"
    end
end

# TODO: this is copy paste of CreateJAR
class JarFile < FileArtifact
    required JAVA

    include LogArtifactState

    log_attr :destination, :base, :manifest

    def initialize(*args)
        super

        @destination ||= $lithium_args.length > 0 ? $lithium_args[0] : "result.jar"
        @manifest    ||= nil
        @ignore_dirs = true
        @base        ||= $lithium_args.length > 1 ? $lithium_args[1] : nil

        @base = fullpath("lib") if !@base
        raise "Invalid base directory '#{@base}'" if !File.exists?(@base) || !File.directory?(@base)

        if @manifest
            @manifest = fullpath(@manifest)
            raise "Manifest file '#{@manifest}' cannot be found" if !File.exists?(@manifest)
            raise "Manifest file '#{@manifest}'' is a directory" if  File.directory?(@manifest)
        end
    end

    def build()
        dest = fullpath(@destination)
        list = paths_to_list(@base).join(' ')

        Dir.chdir(@base)
        if @manifest
            r = exec4(java().jar, "cfm", "'#{dest}'", "'#{@manifest}'", "-C '#{@base}'", list)
        else
            r = exec4(java().jar, "cf", "'#{dest}'",  list)
        end
        raise "JAR #{dest} creation error" if r != 0
    end

    def what_it_does()
        return "Create JAR '#{@destination}' by '#{name}' relatively to '#{@base}'"
    end
end



