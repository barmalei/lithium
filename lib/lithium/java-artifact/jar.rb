require 'fileutils'
require 'pathname'

require 'lithium/core'
require 'lithium/file-artifact/command'
require 'lithium/file-artifact/acquired'
require 'lithium/java-artifact/base'

class JarFileContent < Directory
    REQUIRE JAVA

    def build()
        raise 'Invalid source file' if @source.nil?
        raise "Source file '#{@source.fullpath}' doesn't exist or points to directory" if !File.exists?(@source.fullpath) || File.directory?(@source.fullpath)

        fp = fullpath
        FileUtils.mkdir_p(fp) unless File.exists?(fp)
        Dir.chdir(fp)
        `#{@java.jar} -xfv '#{@source.fullpath}'`.each_line { |i|
            puts " :: #{i.chomp}"
        }
    end

    def what_it_does() "Extract files from '#{@name}' to '#{@destination}'" end
end

class FindInZip < FileMask
    include ZipTool

    REQUIRE JAVA

    attr_accessor  :pattern

    def initialize(*args)
        super
        @pattern ||= $lithium_args[0]
    end

    def build()
        raise 'Class name cannot be detected' if @pattern.nil?

        c  = 0
        hd = homedir
        mt = @pattern

        # detect if class name is regexp
        mt = Regexp.new(@pattern) unless @pattern.index(/[\*\?\[\]\{\}\^]/).nil?

        zi = detect_zipinfo
        list_items { | path, m |
            fp = fullpath(path)
            unless zi.nil?
                FindInZip.find_with_zipinfo(zi, fp, mt) { | found |
                    puts "    #{Pathname.new(fp).relative_path_from(Pathname.new(hd))} : #{found}"
                    c += 1
                }
            else
                FindInZip.find_with_jar(@java.jar, fp, mt) { | found |
                    puts "    #{Pathname.new(fp).relative_path_from(Pathname.new(hd))} : #{found}"
                    c += 1
                }
            end
        }
        puts_warning "No a class whose name matches '#{@pattern}' was found" if c == 0
    end

    def FindInZip.find_width_jar(jar, jar_path, match)
        `#{jar} -ft '#{jar_path}'`.each_line { |item|
            yield item.chomp unless item.chomp.index(match).nil?
        }
    end

    def FindInZip.find_with_zipinfo(zi, jar_path, match)
        IO.popen([zi, '-1',  jar_path, :err=>[:child, :out]]) { | stdout |
            begin
                stdout.each { |line|
                    yield line.chomp unless line.chomp.index(match).nil?
                }
            rescue Errno::EIO
                puts_warning 'Java version cannot be detected'
            end
        }
    end

    def what_it_does() "Try to find #{@pattern} class in '#{@name}'" end
end


class JarFile < ArchiveFile
    REQUIRE JAVA

    log_attr :manifest

    def initialize(*args)
        super
        @manifest ||= nil

        if @manifest
            @manifest = fullpath(@manifest)
            raise "Manifest file '#{@manifest}' cannot be found" unless File.exists?(@manifest)
            raise "Manifest file '#{@manifest}' is a directory"  if     File.directory?(@manifest)
        end
    end

    def genarate(jar, destdir, list)
        return Artifact.exec(@java.jar, 'cfm', "\"#{jar}\"", "\"#{@manifest}\"", "-C \"#{destdir}\"", list) unless @manifest.nil?
        return Artifact.exec(@java.jar, 'cf', "\"#{jar}\"",  "-C \"#{destdir}\"", list)
    end
end
