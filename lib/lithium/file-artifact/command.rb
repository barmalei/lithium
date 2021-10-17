require 'fileutils'

require 'lithium/core'

#  Touch file - change the file updated time stamp
class Touch < FileArtifact
    def build()
        super

        path = fullpath()
        if File.exists?(path)
            File.utime(File.atime(path), Time.now(), path)
        else
            puts_warning "File '#{path}' cannot be found to be touched"
        end
    end

    def expired?() true end

    def self.touch(path)
        Touch.new(path).build
    end

    def what_id_does()
        "Touch '#{fullpath}'"
    end
end

#  Copy of a file artifact
class CopyOfFile < FileArtifact
    attr_reader :source

    def initialize(name, &block)
        super
        @source ||= $lithium_args[0]
    end

    def expired?
        src = validate_source()
        return !File.exists?(fullpath) || File.mtime(fullpath).to_i < File.mtime(src).to_i
    end

    def clean
        if File.exists?(fullpath)
            File.delete(fullpath)
        else
            puts_warning "File '#{fullpath}' doesn't exist"
        end
    end

    def build
        super
        fetch(validate_source, fullpath)
    end

    def fetch(src, dest)
        FileUtils.cp(src, dest)
    end

    def validate_source()
        raise 'Source path is not defined' if @source.nil?
        src = File.absolute_path?(@source) ? @source : fullpath(@source)
        raise "Source '#{src}' doesn't exist or points to a directory" unless File.file?(src)
        return src
    end

    def what_it_does() "    '#{@source}' => '#{fullpath}'" end
end

#  Remove a file or directory
class RmFile < FileCommand
    def build()
        super

        path = fullpath
        if File.directory?(path)
            FileUtils.remove_dir(path)
        elsif File.exists?(path)
            File.delete(path)
        else
            puts_warning "File '#{path}' doesn't exist"
        end
    end

    def expired?()
        File.exists?(fullpath)
    end
end


class GREP < FileMask
    attr_reader :grep, :matched

    def initialize(name, &block)
        super
        @grep ||= $lithium_args.length > 0 ? $lithium_args[0] : 'TODO'
        @match_all = true if @match_all.nil?
    end

    def MATCHED(&block)
        @matched = block
    end

    def build_item(fp, t)
        line_num = 0
        File.readlines(fp, :encoding => 'UTF-8').each { | line |
            line_num += 1
            line = line.chomp.strip
            next if line.length == 0
            value = match_line(line_num, line)
            unless value.nil?
                puts_matched_line(fp, line_num, line, value)
                @matched.call(fp, line_num, line, value) unless @matched.nil?
                break unless @match_all
            end
        }
    end

    def puts_matched_line(fp, line_num, line, value)
        puts "    #{fp}:#{line_num}:#{value}"
    end

    def match_line(line_num, line)
        i = line.index(@grep)
        if i.nil?
            return nil
        else
            return line[i, @grep.length]
        end
    end

    def what_it_does() "Match '#{@grep}'\n   in '#{@name}'" end
end

class REGREP < GREP
    def initialize(name, &block)
        super
        @grep = Regexp.new(@grep) unless @grep.kind_of?(Regexp)
    end

    def match_line(line_num, line)
        m = @grep.match(line)
        if m.nil?
            return nil
        elsif m.length > 1
            res = ''
            for i in (1 .. m.length - 1)
                res = res + m[i]
            end
            return res
        else
            return m[0]
        end
    end
end

