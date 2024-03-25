require 'pathname'
require 'open3'
require 'tempfile'

module Files
    def self.look_directory_up(path, fname, top_path = nil)
        self.look_path_up(path, fname, top_path) { | nm | File.directory?(nm) }
    end

    def self.look_file_up(path, fname, top_path = nil)
        self.look_path_up(path, fname, top_path) { | nm | File.file?(nm) }
    end

    def self.look_path_up(path, fname, top_path = nil, &block)
        path      = File.expand_path(path)
        top_path  = File.expand_path(top_path) unless top_path.nil?
        prev_path = nil

        #raise "Path '#{path}' doesn't exist" unless File.exist?(path)
        #raise "Path '#{path}' has to be a directory" unless File.directory?(path)

        while path && prev_path != path && (top_path.nil? || prev_path != top_path)
            marker = File.join(path, fname)
            return marker if File.exist?(marker) && (block.nil? || block.call(marker))
            prev_path = path
            path      = File.dirname(path)
            break if path == '.'  # dirname can return "." if there is no available top directory
        end

        return nil
    end

    def self.tmpfile(data = nil, &block)
        raise 'Unknown passed block' if block.nil?

        tmp_file = Tempfile.new('tmp_file')
        begin
            unless data.nil?
                if data.kind_of?(String)
                    tmp_file.puts(data)
                elsif data.kind_of?(Array)
                    data.each { | line |
                        tmp_file.puts(line)
                    }
                else
                    tmp_file.puts(data.to_s)
                end
                tmp_file.close()
            end

            block.call(tmp_file)
        ensure
            tmp_file.close()
            tmp_file.unlink()
        end
    end

    def self.fmask?(path)
        not path.index(/[\[\]\?\*\{\}]/).nil?
    end

    def self.cut_fmask(path)
        mi = path.index(/[^\[\]\?\*\{\}\/]*[\[\]\?\*\{\}]/) # test if the path contains mask
        mask = nil
        unless mi.nil?
            path = path.dup
            mask = path[mi, path.length]
            path = path[0, mi]
            path = nil if path.length == 0
        end

        path = path[..-2] if !path.nil? && path[-1] == '/'
        return path, mask
    end

    def self.relative_to(path, to)
        raise 'Nil path' if path.nil?

        path, = self.cut_fmask(path)
        path = Pathname.new(path).cleanpath
        to   = Pathname.new(to).cleanpath

        if path.absolute? == to.absolute? && Files.path_start_with?(path.to_s, to.to_s)
            return path.relative_path_from(to).to_s
        else
            return nil
        end
    end

    #
    # Test if the "path" starts from the specified "from" path
    # @param path - string path to be evaluated
    # @param from - string path from that the given path is evaluated
    # @return true or false
    #
    def self.path_start_with?(path, from)
        from = from[0..-2] if from[-1]   == '/'
        path = path[0..-2] if path[-1] == '/'

        return true  if from == path
        return false if from.length == path.length
        i = path.index(from)
        return false if i.nil? || i != 0
        return path[from.length] == '/'
    end

    def self.which(cmd, realpath = false)
        exts = ENV['PATHEXT'] ? ENV['PATHEXT'].split(';') : ['']
        ENV['PATH'].split(File::PATH_SEPARATOR).each do | path |
            path = path.gsub('\\', '/') if File::PATH_SEPARATOR == ';'
            exts.each { | ext |
                exe = File.join(path, "#{cmd}#{ext}")

                if File.executable?(exe) && File.file?(exe)
                    if realpath
                        pp = File.realdirpath(exe)
                    else
                        pp = exe
                    end
                    return pp
                end
            }
        end
        return nil
    end

    # *args - command arguments
    # block - call back to catch output
    def self.exec(*args, &block)
        # clone arguments
        args = args.dup

        # use quotas to surround process if necessary
        args[0] = "\"#{args[0]}\"" if !args[0].index(' ').nil? && args[0][0] != "\""

        # merged stderr and stdout
        Open3.popen2e(args.join(' ')) { | stdin, stdout, thread |
            stdout.set_encoding(Encoding::UTF_8)
            if  block.nil?
                # close stdin
                stdin.close

                while line = stdout.gets do
                    $stdout.puts line
                end
            else
                block.call(stdin, stdout, thread)
            end
            return thread.value
        }
    end

    def self.grep_exec(*args, pattern:nil, find_first:true, &block)
        acc = []
        self.exec(*args) { | stdin, stdout, thread |
            while line = stdout.gets do
                m = pattern.match(line.chomp)
                if m
                    if m.length > 1
                        r = m[1..]
                    elsif m.length == 1
                        r = m[1]
                    else
                        r = m[0]
                    end

                    if find_first == true
                        stdout.close
                        return r
                    else
                        acc.append(r)
                    end
                end
            end
        }

        if find_first == true || acc.length == 0
            return nil
        else
            return acc
        end
    end

    def self.execInTerm(hd, cmd)
        pl = Gem::Platform.local.os
        if  pl == 'darwin'
            `osascript -e 'tell app "Terminal"
                activate
                do script "#{cmd}"
            end tell'`
        else
            raise "Terminal execution is not supported for '#{pl}' platform"
        end
    end

    def self.dir(path, ignore_dirs = true, &block)
        raise 'Path cannot be nil' if path.nil?

        pp, mask = self.cut_fmask(path)
        raise "Path '#{path}' points to file" if File.file?(path)
        raise "Path '#{path}' doesn't exist"  if !File.exist?(path) && mask.nil?

        list = []
        Dir[path].each { | item |
            next if ignore_dirs && File.directory?(item)
            if block.nil?
                list.push(item)
            else
                block.call(item)
            end
        }

        return block.nil? ? list : nil
    end

    def self.exists?(path, ignore_dirs = true)
        pp, mask = self.cut_fmask(path)
        raise "File '#{path}' cannot be found" if !File.exist?(path) && mask.nil?

        if File.directory?(path) || mask
            self.dir(path, ignore_dirs) { | item |
                return true
            }
        else
            return File.exist?(path)
        end
    end

    def self.cpfile(src, dest)
        self.testdir(dest)
        raise "Source '#{src}' file is a directory or doesn't exist" unless File.file?(src)
        raise "Destination '#{dest}' cannot be file" if File.file?(dest)
        FileUtils.mkdir_p(dest) unless File.exist?(dest)
        FileUtils.cp(src, dest)
    end

    def self.cpdir(src, dest, em = nil)
        self.testdir(src) && self.testdir(dest)

        Dir.foreach(src) { |path|
            next if path == '.' || path == '..' || (em && (path =~ em) != nil)
            dpath, spath = dest/path, src/path

            if File.directory?(spath)
                Dir.mkdir(dpath)
                cpdir(spath, dpath, em)
            else
                File.cp(spath, dpath)
            end
        }
    end

    def self.assert_dir(*args)
        path = File.join(*args)
        raise "Expected directory '#{path}' points to a file" if File.file?(path)
        raise "Expected directory '#{path}' doesn't exist" unless File.directory?(path)
        return path
    end

    def self.assert_file(*args)
        path = File.join(*args)
        raise "Expected file '#{path}' points to a directory" if File.directory?(path)
        raise "Expected file '#{path}' doesn't exist or points to a directory" unless File.file?(path)
        return path
    end

    def self.testdir(dir)
        raise 'Directory cannot be nil' if dir.nil?
    end
end


module Block
    def self.combine_blocks(block1, block2)
        return block2 if block1.nil?
        return block1 if block2.nil?
        return Proc.new {
            self.instance_exec(&block1)
            self.instance_exec(&block2)
        }
    end
end

# an artifact has to include the module to be assigned to an attribute of an artifact
# that requires the AssignableDependency artifact
module AssignableDependency
    def self.included(o)
        raise "Class '#{o.name}' already includes '#{self.name}' module"  if o.class == Class && o.superclass < AssignableDependency
        o.include(IncludePart)
        o.extend(ExtendPart)
        o.set_assign_me_as([nil, false])
    end

    # use the method to parametrize module inclusion with an attribute name and is_array parameters
    #    include  AssignableDependency[:name, true]
    def self.[](nm = nil, is_array = false)
        Module.new {
            @assign_me_as = [ nm, is_array ]
            def self.included(o)
                o.include(AssignableDependency) unless o < AssignableDependency
                name, is_array = @assign_me_as
                unless name.nil?
                    raise "Invalid attribute name argument type '#{name.class}'"           unless name.kind_of?(String) || name.kind_of?(Symbol)
                    raise "Invalid attribute array flag argument type '#{is_array.class}'" unless is_array == true || is_array == false
                end
                o.set_assign_me_as(@assign_me_as)
            end
        }
    end

    module ExtendPart
        def set_assign_me_as(assign_me_as)
            @assign_me_as = assign_me_as.dup
        end

        def get_assign_me_as
            return self.superclass.get_assign_me_as unless defined?(@assign_me_as) || self.superclass.nil? || !self.superclass.respond_to?('get_assign_me_as')
            return @assign_me_as
        end

        def assign_with_name
            nm = get_assign_me_as
            nm.nil? || nm[0].nil? ? self.name.downcase : nm[0]
        end

        def assign_as_array?
            nm = get_assign_me_as
            nm.nil? ? false : nm[1]
        end
    end

    module IncludePart
        def assign_me_to(target)
            clazz = self.class
            raise "Target is nil and cannot be assigned with a value provided by #{self.class}:#{self.name}" if target.nil?
            raise "Nil assignable property name for #{self.class}:#{self.name}"                              if clazz.assign_with_name.nil?

            attr_name, is_array = self.class.assign_with_name, self.class.assign_as_array?

            new_value = self
            attr_name = "@#{attr_name}"
            cur_value = target.instance_variable_get(attr_name)
            if is_array
                cur_value = [] if cur_value.nil?
                target.instance_variable_set(attr_name, cur_value.push(new_value)) if cur_value.index(new_value).nil?
            else
                raise "Other '#{cur_value.name}' artifact has been already assigned to '#{attr_name}' attribute of #{target.class}:#{target.name} artifact" unless cur_value.nil? || cur_value == new_value
                target.instance_variable_set(attr_name, new_value)
            end
        end
    end
end

# The base class to support classpath / path like artifact
module PATHS
    class CombinedPath
        include PATHS

        def initialize(hd = nil)
            @homedir = hd
        end

        def homedir
            @homedir
        end
    end

    def self.new(dir = nil)
        CombinedPath.new(dir)
    end

    def path_valid?
        @is_path_valid ||= false
        return @is_path_valid
    end

    def INCLUDE?(path)
        matched_path(path) >= 0
    end

    def FILTER(fpath)
        @paths ||= []
        if @paths.length > 0
            @paths = @paths.filter { | path |
                match_two_paths(fpath, path) == false
            }
        end
    end

    def matched_path(path)
        paths().each_index { | index |
            path_item = paths[index]
            return index if match_two_paths(path, path_item)
        }

        return -1
    end

    def match_two_paths(path, path_item)
        is_file  = false
        bd       = homedir
        has_mask = Files.fmask?(path)

        unless has_mask
            path = File.join(bd, path) unless bd.nil? || File.absolute_path?(path)
            if path[-1] == '/'
                path = path[0..-2]
            elsif File.file?(path)
                is_file = true
                path = File.basename(path)
            end
        end

        if has_mask
            return true if File.fnmatch?(path, path_item)
        else
            path_item = File.basename(path_item) if is_file && File.file?(path_item)
            return true if path_item == path
        end

        return false
    end

    # add path item
    # @param parts - array, string or PATHS
    def JOIN(*parts)
        @paths ||= []

        return JOIN(*(parts[0])) if parts.length == 1 && parts[0].kind_of?(Array)

        parts.each { | path |
            if path.kind_of?(PATHS)
                @paths.concat(path.paths())
            elsif path.kind_of?(String)
                hd = homedir
                path.split(File::PATH_SEPARATOR).each { | path_item |
                    path_item = File.join(hd, path_item) unless hd.nil? || File.absolute_path?(path_item)

                    pp, mask = Files.cut_fmask(path_item)
                    unless mask.nil?
                        @paths.concat(Files.dir(path_item))
                        @paths.push(pp)
                    else
                        @paths.push(path_item)
                    end
                }
            else
                raise "Unknown path type '#{path.class}' cannot be joined"
            end
        }
        @is_path_valid = false if parts.length > 0
        return self
    end

    # clear path
    def CLEAR
        @paths = []
        @is_path_valid = true
        return self
    end

    def paths
        @paths ||= []
        unless path_valid?
            res   = []
            files = {}
            @paths ||= []

            @paths.each { | path |
                puts_warning "File '#{path}' doesn't exists (#{@paths.length})" unless File.exist?(path)

                path = path[0..-2] if path[-1] == '/'
                key = path
                key = File.basename(path) if File.file?(path) # check if the path is file

                if files[key].nil?
                    files[key] = path
                    res.push(path)
                else
                    path_x = files[key]
                    if path_x == path
                        puts_warning "Duplicated '#{path}' path is detected"
                    else
                        puts_warning "Duplicated file is detected:"
                        puts_warning "   ? '#{path_x}'"
                        puts_warning "   ? '#{path}'"
                    end
                end
            }

            @paths = res
            @is_path_valid = true
        end
        return @paths
    end

    def EMPTY?
        paths().length == 0
    end

    def list_items
        @paths ||= []
        @paths.each {  | p |
            yield p, 1
        }
    end

    # TODO: copy paste from  FileArtifact
    def list_items_as_array
        list = []
        list_items { | path, m |
            list << path
        }
        return list
    end

    def to_s(*args)
        if EMPTY?
            return nil if args.length == 0
            return args.join(File::PATH_SEPARATOR)
        else
            pp = paths()
            return pp.join(File::PATH_SEPARATOR) if args.length == 0
            return [].concat(pp).concat(args).join(File::PATH_SEPARATOR)
        end
    end
end


# Option support
module OptionsSupport
    @@NAMED_OPT = /^(\-{0,2})([^=]+)=?([^=]*)?/
    #@@NAMED_OPT = /^(\-{0,2})([^ ]+)\s?([^- ]*)?/

    def OPTS!(*args)
        if args.length > 0
            @_options = _options()
            @_options.push(*(args.map {  | o | _convert_if_map(o) } ).flatten())
            return _options().dup
        else
            return super
        end
    end

    def OPTS(*args)
        if args.length > 0
            @_options = []
            @_options.push(*(args.map {  | o | _convert_if_map(o) } ).flatten())
        else
            @_options = _options()
        end
        _options().dup
    end

    def OPT(opt)
        _options().push(opt)
    end

    def OPT?(op)
        _options().include?(op) || !self[op].nil?
    end

    def OPTS?
        _options().length > 0
    end

    def []=(n, v = nil)
        raise 'Option name cannot be nil or empty' if n.nil? || n.strip() == ''
        opt   = n.strip()
        opt  += "=#{v.strip}" unless v.nil?
        opts  = _options()

        i = opts.index { | o |
            m = @@NAMED_OPT.match(o)
            !m.nil? && (n == m[2] || n == '-' + m[2] || n == '--' + m[2])
        }

        if i.nil?
            opts.push(opt)
        else
            if opt[0] != '-'
                m = /^(\-{0,2})/.match(opts[i])
                opt = m[1] + opt unless m.nil?
            end
            opts[i] = opt
        end
    end

    def [](n)
        _options().each { | o |
            m = @@NAMED_OPT.match(o)
            return m[3] if !m.nil? && (m[2] == n || '-' + m[2] == n || '--' + m[2] == n)
        }
        return nil
    end

    # return valid not nil attribute value in a case of making it loggable.
    # Otherwise 'option' attribute can equal [] after building (since OPTS)
    # method has been called, but be nil before an artifact building
    def _options
        @_options ||= []
        return @_options
    end

    def _convert_if_map(o)
        if o.kind_of?(Hash)
            return o.to_a.map { | e | "-#{e[0]}=#{e[1]}" }
        else
            return o
        end
    end
end


#
#   <WITH>  <COMMANDS> <OPTS>  <TARGETS>  <ARGS>
#     |         |        |        |          |
#     |         |        |        |          +--- test
#     |         |        |        |   +--- [ file_list ]
#     |         |        |        +---|
#     |         |        |            +--- path_to_tmp_file (contains files to be processed)
#     |         |        |
#     |         |        s+--- e.g -cp classes:lib
#     |         |
#     |         +--- install
#     |
#     +--- e.g java
#
module ToolExecuter
    include OptionsSupport

    # ec - Process::Status
    def error_exit_code?(ec)
        ec.exitstatus != 0
    end

    # can be overridden to transform paths,
    # e.g. convert path to JAVA file to a class name
    def transform_target_path(path)
        "\"#{path}\""
    end

    def WITH_COMMANDS
        []
    end

    def WITH
        raise "Tool name is not defined in '#{self.class.name}' class"
    end

    # @return Array
    def WITH_OPTS
        OPTS()
    end

    def ARGS(*args)
        @arguments = [] + args
    end

    def WITH_ARGS
        @arguments ||= []
        @arguments = $lithium_args.dup if @arguments.length == 0 && $lithium_args && $lithium_args.length > 0
        @arguments
    end

    def WITH_TARGETS
        []
    end

    def CMD(run_with, cmds, opts, targets, args)
        [ run_with ] + cmds + opts + targets + args
    end

    def EXEC(&block)
        targets = WITH_TARGETS().map { | path | "#{transform_target_path(path)}" }
        cmd = CMD(WITH(), WITH_COMMANDS(), WITH_OPTS(), targets, WITH_ARGS())
        _exec(*cmd, &block)
    end

    def FAILED(*args, err_code:1)
        raise "'#{self.class}' has failed cmd = '#{args}'"
    end

    # private method
    def _exec(*args, &block)
        #puts args.join(" ")

        ec = block.nil? ? Files.exec(*args) : Files.exec(*args, &block)
        if error_exit_code?(ec)
            FAILED(*args, err_code:ec.exitstatus)
        else
            puts "'#{self.class}' was successfully executed"
        end
    end
end

#transform_targets
#from_file

module FromFileToolExecuter
    include ToolExecuter

    def transform_target_file(path)
        "@#{path}"
    end

    def EXEC(&block)
        targets, tmp = WITH_TARGETS(), Tempfile.open('lithium')
        begin
            targets.each { | path |
                tmp.puts(transform_target_path(path))
            }
        ensure
           tmp.close
        end
        targets = [ transform_target_file(tmp.path) ]

        cmd = CMD(WITH(), WITH_COMMANDS(), WITH_OPTS(), targets, WITH_ARGS())
        begin
            _exec(*cmd)
        ensure
            tmp.unlink unless tmp.nil?
        end
    end
end


class Properties
    def self.parse(str)
        str = str.gsub!(/(^\s*[!\#].*$)|(^\s+)|(\s+$)|(\\\s*$[\n\r]+)|(^\s*[\n\r]\s*$)/, '')
        unless str.nil?
            str.each_line { | line |
                m = /([^=]+)=(.*)/.match(line)
                yield m[1].strip, m[2].strip unless m.nil?
            }
        end
    end

    def self.fromStr(str)
        props = {}
        parse(str) { | n, v |
            props[n] = v
        }
        return props
    end

    def self.fromFile(path)
        raise "File '#{path}' doesn't exist" unless File.exist?(path)
        raise "Path '#{path}' points to a directory" if File.directory?(path)
        return fromStr(IO.read(path))
    end

    def self.fromMask(mask, find_first = false)
        res = Files.dir(mask)
        raise "There is no any file that can be identified with '#{mask}'" if res.length == 0
        raise "Few files ('#{res}') have been identified by #{mask}" if res.length > 1 && find_first == false
        return self.fromFile(res[0])
    end

    def self.property(mask, name, find_first = false)
        self.fromMask(mask, find_first)[name]
    end
end
