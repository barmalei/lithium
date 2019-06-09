require 'fileutils'
require 'pathname'

require 'lithium/core'
require 'lithium/file-artifact/command'
require 'lithium/file-artifact/acquired'
require 'lithium/java-artifact/base'

class ExtractJar < FileCommand
    REQUIRE JAVA

    def initialize(*args)
        super
        @destination ||= 'tmp'
    end

    def build()
        FileUtils.mkdir_p(@destination) unless File.exists?(@destination)
        Dir.chdir(@destination)
        `#{@java.jar} -xfv '#{fullpath()}'`.each_line { |i|
            puts " :: #{i.chomp}"
        }
    end

    def what_it_does() "Extract files from '#{@name}' to '#{@destination}'" end
end

class FindInZip < FileMask
    REQUIRE JAVA

    attr_accessor  :pattern

    def initialize(*args)
        super
        @pattern ||= $lithium_args[0]
        @zipinfo   = FileArtifact.which('zipinfo')
    end

    def build()
        raise 'Class name cannot be detected' if @pattern.nil?

        c  = 0
        hd = homedir
        mt = @pattern

        # detect if class name is regexp
        mt = Regexp.new(@pattern) unless @pattern.index(/[\*\?\[\]\{\}\^]/).nil?

        list_items { | path, m |
            fp = fullpath(path)
            if @zipinfo
                find_with_zipinfo(fp, mt) { | found |
                    puts "    #{Pathname.new(fp).relative_path_from(Pathname.new(hd))} : #{found}"
                    c += 1
                }
            else
                find_with_jar(fp, mt) { | found |
                    puts "    #{Pathname.new(fp).relative_path_from(Pathname.new(hd))} : #{found}"
                    c += 1
                }
            end
        }
        puts_warning "No a class whose name matches '#{@pattern}' was found" if c == 0
    end

    def find_width_jar(jar, match)
        `#{@java.jar} -ft '#{jar}'`.each_line { |item|
            yield item.chomp unless item.chomp.index(match).nil?
        }
    end

    def find_with_zipinfo(jar, match)
        IO.popen(['zipinfo', '-1',  jar, :err=>[:child, :out]]) { | stdout |
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


class JarFile < FileArtifact
    REQUIRE JAVA

    include LogArtifactState

    log_attr :source, :base, :manifest

    def initialize(*args)
        @sources = []
        @bases   = []

        super
        @manifest ||=  nil

        if @manifest
            @manifest = fullpath(@manifest)
            raise "Manifest file '#{@manifest}' cannot be found" unless File.exists?(@manifest)
            raise "Manifest file '#{@manifest}' is a directory"  if     File.directory?(@manifest)
        end
    end

    def build()
        tmpdir = Dir.mktmpdir
        begin
            list = []
            list_items { | path, m, base |
                dir = File.dirname(path)
                if base
                    dir = Pathname.new(dir).relative_path_from(Pathname.new(base)).to_s
                    if dir == '.'
                        list << File.basename(path)
                    elsif dir.start_with?('..')
                        raise "Invalid base path '#{base}'"
                    else
                        list << File.join(dir, File.basename(path))
                    end
                else
                    list << path
                end

                FileUtils.mkdir_p(File.join(tmpdir, dir))
                FileUtils.cp(fullpath(path), File.join(tmpdir, dir, File.basename(path)))
            }

            raise "Cannot detect files to archive by '#{@sources}' sources" if list.length == 0
            list.each { | item |
                puts "    '#{item}'"
            }

            dest = fullpath()
            Dir.chdir(tmpdir)
            raise "JAR '#{dest}' creation error" if arhive_with_zip(dest, tmpdir, list) != 0
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
        @sources.each_index { | i |
            source = @sources[i]
            base   = @bases[i]
            source.list_items { | path, m |
                yield path, m, base
            }
        }
    end

    def arhive_with_jar(jar, source, list)
        return Artifact.exec(@java.jar, 'cfm', "\"#{jar}\"", "\"#{@manifest}\"", "-C \"#{source}\"", list) if @manifest
        return Artifact.exec(@java.jar, 'cf', "\"#{jar}\"",  "-C \"#{source}\"", list)
    end

    def arhive_with_zip(jar, source, list)
        return Artifact.exec('zip', "\"#{jar}\"",  list.join(' '))
    end

    def SOURCE(path, base = nil)
        @sources ||= []
        @bases   ||= []
        fm = FileMask.new(path)
        @sources << fm
        unless base.nil?
            base = base[0 .. base.length - 1] if base[-1] != '/'
            raise "Invalid base '#{base}' directory for '#{path}' path" unless path.start_with?(base)
        end

        @bases << base
        REQUIRE fm
    end

    def what_it_does()
        return "Create'#{@name}' by '#{@sources.map { | item | item.name }}'"
    end
end
