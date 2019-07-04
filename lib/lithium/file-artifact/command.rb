require 'fileutils'
require 'pathname'

require 'lithium/core'

#  Touch file - change the file updated time stamp
class Touch < FileCommand
    def build()
        super

        path = fullpath()
        if File.exists?(path)
            File.utime(File.atime(path), Time.now(), path)
        else
            puts_warning "File '#{path}' cannot be found to be touched"
        end
    end
end

#  Copy of a file artifact
class CopyOfFile < FileCommand
    attr_reader :source

    def expired?
        src = validate_source()
        return !File.exists?(fullpath) || File.mtime(fullpath).to_i < File.mtime(src).to_i
    end

    def cleanup()
        File.delete(fullpath) if File.exists?(fullpath)
    end

    def build()
        super
        src  = validate_source()
        dest = fullpath()
        fetch()
    end

    def fetch()
        FileUtils.cp(src, dest)
    end

    def validate_source()
        raise 'Source path is not defined' if @source.nil?
        src = Pathname.new(@source).absolute? ? @source : fullpath(@source)
        raise "Source '#{src}' doesn't exist or points to a directory"  if !File.exists?(src) || File.directory?(src)
        return src
    end


    def what_it_does() "    '#{@source}' => '#{fullpath()}'" end
end

#  Remove a file or directory
class RmFile < FileCommand
    def build()
        super

        path = fullpath()
        if File.directory?(path)
            FileUtils.remove_dir(path)
        else
            File.delete(path)
        end
    end

    def expired?()
        File.exists?(fullpath)
    end
end


class GREP < FileMask
    def initialize(*args)
        super
        @grep ||= $lithium_args.length > 0 ? $lithium_args[0] : 'TODO'

        pref = 'regexp:'
        @grep = Regexp.new(@grep[pref.length, @grep.length - pref.length]) if @grep.start_with?(pref)
    end

    def build_item(n, t)
        line_num = 0
        File.readlines(n).each { | line |
            line_num += 1
            line = line.chomp.strip()
            next if line.length == 0

            $~ = nil
            if line.index(@grep)
                if $~
                    puts "    #{n}:#{line_num}:#{line}"
                else
                    puts "    #{n}:#{line_num}:#{line}"
                end
            end
        }
    end

    def what_it_does() "Looking for '#{@grep}' in '#{@name}'" end
end
