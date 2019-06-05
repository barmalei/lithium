require 'fileutils'

require 'lithium/core'
require 'lithium/file-artifact/command'
require 'lithium/file-artifact/acquired'
require 'lithium/java-artifact/base'

class ExtractJAR < FileCommand
    REQUIRE JAVA

    def initialize(*args)
        super
        @destination ||= 'tmp'
    end

    def build()
        FileUtils.mkdir_p(@destination) unless File.exists?(@destination)
        Dir.chdir(@destination)
        `jar -xfv '#{fullpath()}'`.each { |i|
            puts " :: #{i.chomp}"
        }
    end

    def what_it_does() "Extract files from '#{@name}' to '#{@destination}'" end
end

class FindInJAR < FileCommand
    REQUIRE JAVA

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
    REQUIRE JAVA
    include LogArtifactState

    log_attr :destination, :base, :manifest

    def initialize(*args)
        super
        @destination ||= $lithium_args.length > 0 ? $lithium_args[0] : 'result.jar'
        @manifest    ||= nil
        @ignore_dirs = true
        @base        ||= $lithium_args.length > 1 ? $lithium_args[1] : nil

        @base = fullpath('lib') if !@base
        raise "Invalid base directory '#{@base}'" if !File.exists?(@base) || !File.directory?(@base)

        if @manifest
            @manifest = fullpath(@manifest)
            raise "Manifest file '#{@manifest}' cannot be found" if !File.exists?(@manifest)
            raise "Manifest file '#{@manifest}'' is a directory" if  File.directory?(@manifest)
        end
    end

    def build()
        dest = fullpath(@destination)
        list = list_items_to_array(@base).join(' ')

        Dir.chdir(@base)
        if @manifest
            r = Artifact.exec(@java.jar, 'cfm', "\"#{dest}\"", "\"#{@manifest}\"", "-C \"#{@base}\"", list)
        else
            r = Artifact.exec(@java.jar, "cf", "\"#{dest}\"",  list)
        end
        raise "JAR #{dest} creation error" if r != 0
    end

    def what_it_does()
        return "Create JAR '#{@destination}' by '#{name}' relatively to '#{@base}'"
    end
end

# TODO: this is copy paste of CreateJAR
class JarFile < FileArtifact
    REQUIRE JAVA

    include LogArtifactState

    log_attr :source, :base, :manifest

    def initialize(*args)
        @sources = []
        super
        @ignore_dirs = true

        @base        ||= 'classes'
        @manifest    ||=  nil

        raise "Invalid base directory '#{@base}'" unless File.directory?(@base)

        if @manifest
            @manifest = fullpath(@manifest)
            raise "Manifest file '#{@manifest}' cannot be found" unless File.exists?(@manifest)
            raise "Manifest file '#{@manifest}' is a directory"  if     File.directory?(@manifest)
        end
    end

    def build()
        tmpdir  = Dir.mktmpdir

        puts ">>> #{tmpdir}"
        begin
            list = []

            list_items { | path, m |
                list << path
                basedir = File.dirname(path)
                fp      = fullpath(path)
                FileUtils.mkdir_p(File.join(tmpdir, basedir))
                FileUtils.cp(fp, File.join(tmpdir, basedir, File.basename(path)))
            }

            Dir.chdir(tmpdir)
            dest = fullpath()
            if @manifest
                r = Artifact.exec(@java.jar, 'cfm', "\"#{dest}\"", "\"#{@manifest}\"", "-C \"#{tmpdir}\"", list)
            else
                r = Artifact.exec(@java.jar, 'cf', "\"#{dest}\"",  "-C \"#{tmpdir}\"", list)
            end
            raise "JAR '#{dest}' creation error" if r != 0

        ensure
            #FileUtils.remove_entry tmpdir
        end
    end

    def list_items_to_array(rel = nil)
        res = []
        @sources.each { | source |
            res << source.list_items_to_array.map { | path | fullpath(path) }
        }
        return res
    end

    def list_items(rel = nil)
        @sources.each { | source |
            source.list_items { | path, m |
                yield path, m
            }
        }
    end

    def CONTENT(path, base = nil)
        fm = FileMask.new(path)
        @sources << fm
        REQUIRE fm
    end

    def what_it_does()
        return "Create JAR '#{@destination}' by '#{name}' relatively to '#{@base}'"
    end
end



