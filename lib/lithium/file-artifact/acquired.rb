require 'lithium/core'
require 'lithium/utils'

# acquired file artifact
class GeneratedFile < FileArtifact
    def initialize(*args)
        super
        fp = fullpath()
        raise "File '#{fp}' points to directory" if File.directory?(fp)
    end

    def cleanup() File.delete(fullpath) if File.exists?(fullpath) end
    def expired?() !File.exists?(fullpath) end
    def build() raise NotImplementedError, '' end
end

# file that contains artifacts paths of a composite target artifact
class MetaFile < FileArtifact
    include LogArtifactState

    def list_items(check_existance = false)
        fp = fullpath
        return unless File.exists?(fp)

        if File.directory?(fp)
            puts_error "Template file points to '#{fp}' directory, file is required"
            return
        end

        go_to_homedir
        # read meta file line by line
        File.readlines(fp).each { | i |
            i = i.strip
            next if i.length == 0 || i[0,1]=='#'  # skip comment and empty strings

            if i[0,1] == ':'  # try to handle it as an artifact specific command
                raise "Unknown empty command '#{i}'" if !@command_listener
                @command_listener.handle_command(i)
                next
            end

            if i.index(/[\[\]\?\*\{\}]/) != nil  # check if file mask is in
                cc = 0
                Dir[i].each { | j |
                    yield j, File.mtime(fullpath(j)).to_i
                    cc += 1
                }
                raise "Mask '#{@name}>#{i}' doesn't match any file" if cc == 0 && check_existance
            else
                p = fullpath(i)
                raise "File '#{@name}>#{i}' cannot be found" if check_existance && !File.exists?(p)
                yield i, File.exists?(i) ? File.mtime(p).to_i : -1
            end
        }
    end

    def build() end
    def what_it_does() '' end

    def command_listener(l)
        raise "Object '#{l}' does not declare 'handle_command(cmd)' method" if l && !l.respond_to?(:handle_command)
        @command_listener = l
    end
end

class MetaGeneratedFile < GeneratedFile
    def initialize(*args)
        super
        @meta = META()
        REQUIRE @meta
    end

    def META()
        MetaFile.new(File.join('.lithium', 'meta', @name))
        MetaFile.owner = owner
    end

    def what_it_does() "Create file by '#{@meta.name}'" end
end

class ZipFile < MetaGeneratedFile
    def initialize(*args)
        super
        fp = fullpath
        raise "Zip file name points to directory #{fp}" if File.exists?(fp) && File.directory?(fp)
        @options ||= '-9q'
        @base    ||= nil
    end

    def pre_build() cleanup() end

    def build()
        go_to_homedir

        list = []
        @meta.list_items(true) { |n,t| list << "#{n}" }

        if list.length > 0
            bb = @base.nil? ? homedir() : @base
            list.each_index { |i| list[i] = list[i].gsub("#{bb}/", '') }
            Dir.chdir(bb)

            list.each { |f| raise "'#{f}' file cannot be found" unless File.exists?(f) }
            list = list.collect { |f| "'#{f}'" }

            zip_path = FileUtils.which('zip')
            raise 'command line zip tool cannot be found' unless zip_path.nil?
            raise 'Archive building failed' if exec4(zip_path, @options, fullpath, list.join(' ')) != 0
        else
            puts_warning 'No file to be packed'
        end
    end

    def build_failed() cleanup() end
    def what_it_does() "Create ZIP file by '#{@meta.name}'" end
end

# Copy file format:
#   1. pattern: src/test.java                  - copy "test.java" file to "."
#   2. pattern: src/test.java && preserve_path - copy "test.java" file to "./src"
#   3. pattern: src/lib                        - copy "lib" directorty to "./lib"
#   4. pattern: src/lib && preserve_path       - copy "lib" directorty as "./src/lib"
class MetaGeneratedDirectory < MetaGeneratedFile
    CONTENT_FN = 'list_of_files'

    def cleanup()
        @preserve_path = false
        fp = fullpath()
        @meta.list_items { |n, t|
            p =  @preserve_path ? File.join(fp, n): File.join(fp, File.basename(n))

            next unless File.exists?(p)
            if File.directory?(p)
                if @preserve_path
                    FileUtils.rm_r(File.join(fp, n.split('/')[0]))
                else
                    FileUtils.rm_r(p)
                end
            else
                FileUtils.rm(p)
            end
        }
    end

    def expired?()
        return true if super

        @preserve_path = false
        fp = fullpath
        @meta.list_items() { |n, t|
            p =  @preserve_path ? File.join(fp, n) : File.join(fp, File.basename(n))
            return true unless File.exists?(p)
        }
        false
    end

    def pre_build() cleanup() end

    def build()
        @preserve_path = false
        fp = fullpath
        FileUtils.mkdir_p(fp) unless File.exists?(fp)

        go_to_homedir
        @meta.list_items(true) { |n, t|
            s = fullpath(n)
            raise "File '#{s}' cannot be found" unless File.exists?(s)

            d = fp
            if @preserve_path  # keep source path
                d = File.join(d, File.dirname(n))  # preserve source directories in destination
                FileUtils.mkdir_p(d) unless File.exists?(d) # create directory or directories in destination
                d = File.join(d, File.basename(n)) # add file to be copied to destination
            end

            if File.directory?(s)
                if @preserve_path
                    FileUtils.cp_r(s, File.join(fp, n))
                else
                    FileUtils.cp_r(s, File.join(fp, File.basename(n)))
                end
            else
                FileUtils.cp(s, d)
            end
        }
    end

    def handle_command(c)
        raise "Unknown command '#{c}'" unless c.start_with?(':preserve_path')
        @preserve_path = true
    end

    def META()
        meta = MetaFile.new(File.join('.lithium', 'meta', name, CONTENT_FN))
        meta.command_listener(self)
        meta
    end

    def what_it_does() "Create folder '#{@name}' and its content" end
end

