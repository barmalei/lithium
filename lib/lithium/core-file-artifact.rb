require 'pathname'

require 'lithium/core-artifact'

#  Base file artifact
class FileArtifact < Artifact
    @abbr = 'FAR'

    attr_reader :is_absolute

    def initialize(name, &block)
        path = Pathname.new(name).cleanpath
        @is_absolute = path.absolute?
        super(path.to_s, &block)
    end

    def absolute?
        @is_absolute
    end

    def exists?
        File.exist?(fullpath)
    end

    def homedir
        if @is_absolute
            unless owner.nil?
                home = owner.homedir
                if File.absolute_path?(home)
                    home = home[0, home.length - 1] if home.length > 1 && home[home.length - 1] == '/'
                    return home #if Files.path_start_with?(@name, home)
                end
            end

            return File.dirname(@name)
        else
            return super
        end
    end

    # return path that is relative to the artifact homedir
    def relative_to_home
        Files.relative_to(@name, homedir).path
    end

    def q_fullpath(path = @name)
        p = fullpath(path)
        return "\"#{p}\"" unless p.nil?
        return p
    end

    def fullpath(path = @name)
        return path if path.start_with?('.env/')

        if path == '.' || path == './'
            return Pathname.new(File.join(Dir.pwd, path)).cleanpath.to_s
        elsif path == @name
            return path if @is_absolute
            return res = Pathname.new(File.join(homedir, path)).cleanpath.to_s
        else
            path = Pathname.new(path).cleanpath
            home = homedir

            if path.absolute?
                path = path.to_s
                home = home[0, home.length - 1] if home.length > 1 && home[home.length - 1] == '/'
                raise "Path '#{path}' is not relative to '#{home}' home" unless Files.path_start_with?(path, home)
                return path
            else
                return File.join(home, path.to_s)
            end
        end
    end

    # test if the given path is in a context of the given file artifact
    def match(path)
        raise 'Invalid empty or nil path' if path.nil? || path.length == 0

        pp = path.dup
        path, mask = Files.cut_fmask(path)
        raise "Path '#{pp}' includes mask only" if path.nil?

        path  = Pathname.new(path).cleanpath
        home  = Pathname.new(homedir)
        raise "Home '#{home}' is not an absolute path" if path.absolute? && !home.absolute?

        # any relative path is considered as a not matched path
        return false if !path.absolute? && home.absolute?
        return Files.path_start_with?(path.to_s, home.to_s)
    end

    # !!!!
    # since the method can be caught with logger it should not be called anywhere
    # the method should just provide mtime value that is it
    # !!!!
    def mtime
        exists? ? File.mtime(fullpath).to_i : -1
    end

    def puts_items
        list_items { | p, t |
            puts "logged item = '#{p}' : #{t}"
        }
    end

    def list_items
        fp = fullpath
        yield fp, exists? ? File.mtime(fp).to_i : -1
    end

    def list_items_as_array
        list = []
        list_items { | path, m |
            list << path
        }
        return list
    end

    def search(path)
        FileArtifact.search(path, self)
    end

    # track not found items
    @search_cache = {}

    # search the given path
    def self.search(path, art = $current_artifact, &block)
        if File.exist?(path)
            return [ File.expand_path(path) ] if block.nil?
            return block.call(path)
        end

        art = Project.current if art.nil? || !art.kind_of?(FileArtifact)
        if art.nil?
            return [] if block.nil?
            return
        end

        # test if current artifact points to path we are searching
        fp = art.fullpath
        if fp.end_with?(path)
            return  [ fp ] if block.nil?
            return block.call(fp)
        else
            hd  = $current_artifact.homedir
            hfp = File.join(hd, path)
            if File.exist?(hfp)
                return  [ hfp ] if block.nil?
                return block.call(hfp)
            end
        end

        fp = File.dirname(fp) unless File.directory?(fp)
        if File.exist?(fp)
            path = Pathname.new(path).cleanpath.to_s
            if @search_cache[fp] && @search_cache[fp][path]
                return [] if block.nil?
                return
            end

            res = Dir.glob(File.join(fp, '**', path))
            if res.length > 0
                return res if block.nil?
                res.each { | found_item |
                    block.call(found_item)
                }
            end

            @search_cache[fp] = {} unless @search_cache[fp]
            @search_cache[fp][path] = true
        end

        return art.kind_of?(Project) ? [] : FileArtifact.search(path, art.project, &block)
    end

    # TODO: grep and grep_file a bit weird names
    def self.grep_file(path, pattern, match_all = false, &block)
        raise 'Pattern cannot be nil' if pattern.nil?
        pattern = Regexp.new(pattern) if pattern.kind_of?(String)

        raise "File '#{path}' is a directory or doesn't exist" unless File.file?(path)

        list = []
        line_num = 0

        File.readlines(path, :encoding => 'UTF-8').each { | line |
            line_num += 1
            line = line.chomp.strip
            next if line.length == 0
            mt = pattern.match(line)
            unless mt.nil?
                matched_part = mt[0]
                if mt.length > 1
                    matched_part = ''
                    for i in (1 .. mt.length - 1)
                        matched_part = matched_part + mt[i]
                    end
                end

                if block.nil?
                    list.push({
                        :path         => path,
                        :line_num     => line_num,
                        :line         => line,
                        :matched_part => matched_part
                    })
                else
                    block.call(path, line_num, line, matched_part)
                end

                break unless match_all
            end
        }

        return block.nil? ? list : nil
    end

    def self.grep(path, pattern, match_all = false, &block)
        raise 'Pattern cannot be nil' if pattern.nil?
        pattern = Regexp.new(pattern) if pattern.kind_of?(String)

        pp, mask = Files.cut_fmask(path)
        raise "File '#{path}' cannot be found" if !File.exist?(path) && mask.nil?

        list = []
        if File.directory?(path) || mask
            Files.dir(path, true) { | item |
                res = FileArtifact.grep_file(item, pattern, match_all, &block)
                list.concat(res) unless res.nil?
            }
        else
            list = FileArtifact.grep_file(path, pattern, match_all, &block)
        end

        return block.nil? ? list : nil
    end
end

# Permanent file shortcut
class ExistentFile < FileArtifact
    def exists?
        File.file?(fullpath)
    end

    def build
        Files.assert_file(fullpath)
        super
    end
end

# Directory artifact
class Directory < FileArtifact
    def expired?
        !exists?
    end

    def exists?
        File.directory?(fullpath)
    end

    def build
        fp = fullpath
        raise "File '#{fp}' is not a directory" if File.file?(fp)
        super
    end

    def mkdir
        FileUtils.mkdir_p(fullpath) unless exists?
    end
end

class ExistentDirectory < Directory
    def build
        Files.assert_dir(fullpath)
        super
    end
end

class DestinationDirectory < ExistentDirectory
    include AssignableDependency[:destination]

    def build
        unless exists?
            puts_warning "Create destination '#{fullpath}' folder"
            FileUtils.mkdir_p(fullpath)
        end
        super
    end
end

# File mask artifact that can identify set of file artifacts
class FileMask < FileArtifact
    @abbr = 'FMS'

    def initialize(name, &block)
        super
        @regexp_filter ||= nil
        @ignore_dirs   ||= false
        @ignore_files  ||= false
        raise 'Files and directories are ignored at the same time' if @ignore_files && @ignore_dirs
    end

    def build
        list_items { | p, mt |
            build_item(p, mt)
        }
    end

    def ignore_hidden
        @regexp_filter = /^[\.].*/
    end

    # called for every detected item as a part of build process
    def build_item(path, m) end

    # List items basing on the mask returns items relatively to the
    # passed path
    def list_items
        go_to_homedir {
            Dir[@name].each { | path |
                next if @regexp_filter && !(path =~ @regexp_filter)

                if @ignore_files || @ignore_dirs
                    b = File.directory?(path)
                    next if (@ignore_files && !b) || (@ignore_dirs && b)
                end

                yield path, File.mtime(path).to_i
            }
        }
    end
end

#
#   <WITH>  <OPTS>  <TARGETS>  <ARGS>
#     |       |        |          |
#     |       |        |          +--- test
#     |       |        |   +--- [ file_list ]
#     |       |        +---|
#     |       |            +--- path_to_tmp_file (contains files to be processed)
#     |       |
#     |       +--- e.g -cp classes:lib
#     |
#     +--- e.g java
#
class RunTool < FileMask
    include LogArtifactState
    include OptionsSupport

    log_attr :_options, :arguments

    def initialize(name)
        super

        @arguments ||= []
        @arguments = $lithium_args.dup if @arguments.length == 0 && $lithium_args && $lithium_args.length > 0
    end

    # ec - Process::Status
    def error_exit_code?(ec)
        ec.exitstatus != 0
    end

    # can be overridden to transform paths,
    # e.g. convert path to JAVA file to a class name
    def transform_target_path(path)
        path
    end

    def WITH
        raise 'Run tool name is not defined'
    end

    # @return Array
    def WITH_OPTS
        OPTS()
    end

    # @param src - array of [ path1, path2, ... pathN ] or path to file
    # @return array
    def WITH_TARGETS(src)
        return [] if src.nil?
        return src.is_a?(String) ? [ "\"#{src}\"" ] : src
    end

    def run_with_output_handler
        @output_handler
    end

    def build(&block)
        super

        begin
            tmp, src, len = nil, [], 0
            if @targets_from_file
                tmp = Tempfile.open('lithium')
                begin
                    list_items { | path, t |
                        tmp.puts(transform_target_path(path))
                        len = len + 1
                    }
                ensure
                   tmp.close
                end
                src = tmp.path
            else
                list_items{ | path, t |
                    src.push("\"#{transform_target_path(path)}\"")
                }
                len = src.length
            end

            puts_warning "Source files cannot be detected by '#{@name}'" if src.nil?

            cmd = [ WITH() ] + WITH_OPTS() + WITH_TARGETS(src) + @arguments

            go_to_homedir()
            ec = block.nil? ? Files.exec(*cmd) : Files.exec(*cmd, &block)

            if error_exit_code?(ec)
                # TODO: simplify detailed level fetching
                level = !$lithium_options.nil? && $lithium_options.key?('v') ? $lithium_options['v'].to_i : 0
                raise "'#{self.class}' has failed cmd = '#{cmd}'" if level == 2
                raise "'#{self.class}' has failed"
            end
            puts "#{len} source files have been processed with '#{self.class}'"
        ensure
            tmp.unlink unless tmp.nil?
        end
    end
end

class RunShell < RunTool
    def WITH
        'bash'
    end
end

# mask container
class FileMaskContainer < FileMask
    include ArtifactContainer

    def initialize(name, &block)
        super

        # sort artifacts that have been created with passed block
        _meta.sort!
    end

    def delegate_to_owner_if_meta_cannot_be_found?
        true
    end
end

# project artifact
class Project < ExistentDirectory
    include ArtifactContainer
    include OptionsSupport

    @@curent_project = nil

    def initialize(name, &block)
        super
        OPTS($lithium_options)
        LOAD('project.rb')
    end

    def self.new(name, owner:nil, &block)
        @@curent_project = super
        return @@curent_project
    end

    def self.current=(prj)
        @@curent_project = prj
    end

    def self.current
        @@curent_project
    end

    def self.artifact(name, clazz = nil, &block)
        self.current.artifact(name, clazz, &block)
    end

    def self.PROJECT(&block)
        raise "Current project is not known" if self.current.nil?
        self.current.instance_exec(&block)
    end

    def artifact(name, clazz = nil, &block)
        art_name = ArtifactPath.new(name, clazz)
        # detect if the path point to project itself
        return self if (art_name.clazz.nil? || art_name.clazz == self.class) && art_name.to_s == @name
        super
    end

    def PROFILE(name, *args)
        OPTS!(args)
        LOAD(File.join($lithium_code, 'profiles', name + '.rb'))
    end

    def LOAD(path)
        path = File.join(homedir, '.lithium', path) unless File.absolute_path?(path)
        unless File.file?(path)
            puts_warning "Project configuration '#{path}' doesn't exist for '#{self}' artifact"
        else
            self.instance_eval(File.read(path)).call
        end
    end

    def SILENT(level = 0)
       $lithium_options['v'] = level
    end

    def VERBOSE(level = 3)
       $lithium_options['v'] = level
    end

    def MATCH(file_mask, &block)
        raise "Block is expected for MATCH '#{file_mask}'" if block.nil?
        DEFINE(file_mask, FileMaskContainer, &block)
    end

    def OTHERWISE(&block)
        DEFINE('**/*', FileMask, &block)
    end

    def homedir
        @is_absolute ? @name : super
    end

    def what_it_does
        nil
    end

    def expired?
        true
    end
end

