require 'fileutils'
require 'pathname'

require 'lithium/core'

#
#  Touch file - change the file updated time stamp
#
class Touch < FileCommand
    def build()
        super
        go_to_homedir()
        path = fullpath()

        if File.exists?(path)
            File.utime(File.atime(path), Time.now(), path)
        else
            puts_warning "File '#{path}' cannot be found to be touched"
        end
    end
end

#
#  Copy file or directory to the given destination
#
class CopyFile < FileCommand
    attr_reader :destination

    def initialize(name, dest = nil, &block)
        super(name, &block)
        @ignore_hidden_files ||= true

        unless @destination
            if dest
                @destination = dest
            elsif $lithium_args.length > 0
                self.destination = $lithium_args[0]
            end
        end

        self.destination = @destination
    end

    def destination=(v)
        raise 'Destination path is not defined' if !v

        if Pathname.new(v).absolute?
            puts "Destination path is absolute path '#{v}'"
        else
            v = fullpath(v)
        end

        fp = fullpath()
        v = File.join(v, File.basename(fp)) if !File.directory?(fp) && File.directory?(v)

        @destination = File.expand_path(v)
    end

    def expired?
        return !File.exists?(@destination) || !File.exists?(fullpath()) || File.mtime(fullpath()).to_i > File.mtime(@destination).to_i
    end

    def cleanup()
    end

    def build()
        super

        source = fullpath()

        raise 'Destination path is not defined' unless @destination
        raise "Source file '#{source}' cannot be found" unless File.exists?(source)

        if File.directory?(source)
            filter = @ignore_hidden_files ? /^[\.].*/ : nil
            FileArtifact.cpdir(source, @destination, filter)
        else
            FileUtils.cp(source, @destination)
        end
    end

    def what_it_does() "Copy file from: '#{fullpath()}'\n     to  : '#{@destination}'" end
end

#
#  Remove a file
#
class RmFile < FileCommand
    def initialize(*args)
        super
        @recursive ||= false;
    end

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
        !File.exists?(fullpath())
    end
end


class GREP < FileMask
    def initialize(*args)
        super
        @auto_detect_comment ||= true
        if !@auto_detect_comment
            @singleline_comment ||= nil
            @multilines_comment ||= nil
        else
            raise "Comment expression cannot be set. It is auto-detected." if @singleline_comment || @multilines_comment
        end
        @grep ||= 'TODO'
        @ignore_dirs = true
    end

    def build_item(n, t)
        bcomment_started, line_num = false, 0
        @singleline_comment, @multilines_comment = GREP.detect_commet(n) if @auto_detect_comment

        File.readlines(n).each() { | line |
            line_num += 1
            line = line.chomp.strip()
            next if line.length == 0

            lcomment_started = false
            bcomment_started = line.index(@multilines_comment[0]) if @multilines_comment && !bcomment_started
            lcomment_started = line.index(@singleline_comment)    if @singleline_comment && !bcomment_started
            if !bcomment_started && !lcomment_started
                $~ = nil
                if line.index(@grep)
                    if $~
                        puts "#{n}:#{line_num}:#{line}"
                    else
                        puts "#{n}:#{line_num}:#{line}"
                    end
                end
            end
            bcomment_started = false if bcomment_started && line.index(@multilines_comment[1])
        }
    end

    def what_it_does() "Looking for '#{@grep}' in '#{@name}'" end

    protected

    def self.detect_commet(n)
        e = File.extname(n)
        e = e && e.length > 1 ? e[1, e.length-1] : nil
        return [nil, nil] if !e
        @comments[e]
    end

    @comment_set1 = [  /[ ]*\/\//,  [ /[ ]*\/\*/, '*/' ] ]
    @comment_set2 = [  /[ ]*#/,  nil ]
    @comment_set3 = [  /[ ]*\/\//,  [ /[ ]*\{/, '}' ] ]

    @comments = { 'java' => @comment_set1,
                  'cpp'  => @comment_set1,
                  'c'    => @comment_set1,
                  'php'  => @comment_set1,
                  'rb'   => @comment_set2,
                  'py'   => @comment_set2,
                  'sh'   => @comment_set2,
                  'pas'  => @comment_set3  }
end


class BackupFile < PermanentFile
    def build()
        super

        if @destination_dir.nil?
            wmsg 'Destination directory is not defined. Use default one'
            @destination_dir = fullpath('backup') if @destination_dir.nil?
        end

        template_name = (@name == '.') ? 'project-root' : @name
        template_path = File.join($project_def, "#{template_name}.backup")

        if @backup_descriptor && !File.exists?(template_path)
            template_path= File.join($project_def, @backup_descriptor)
            raise "Backup descriptor cannot be found '#{template_path}'" if !File.exists?(template_path)
        end

        template_path = nil if !File.exists?(template_path)

        go_to_homedir()
        msg "Backup '#{@name}' to '#{@destination_dir}'"
        if template_path
            File.readlines(template_path).each { |l|
                l = l.chomp
                next if l.length == 0
                msg "Backup by '#{l}' mask"
                cpbymask(l, @name, @destination_dir)
            }
        else
            wmsg 'No backup descriptor file was found'
            wmsg 'All available files will be copied'
            cpbymask('**/*', @name, @destination_dir)
        end
    end

    private

    def cpbymask(mask, src_dir, dest_dir)
        Dir[src_dir/mask].each { |f|
            if File.directory?(f)
                FileUtils.mkdir_p(f) if !File.exists?(f)
            else
                cf = f.gsub('../', '')
                dir = File.expand_path(File.join(dest_dir, File.dirname(cf)))
                FileUtils.mkdir_p(dir) unless File.exists?(dir)
                dest_file = File.join(dest_dir, cf)
                raise "File '#{dest_file}' already exists" if File.exists?(dest_file)
                File.cp(f, dest_file)
            end
        }
    end
end

