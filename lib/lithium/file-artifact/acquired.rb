require 'fileutils'
require 'pathname'

require 'lithium/core'

# acquired file artifact
class GeneratedFile < FileArtifact
    include OptionsSupport

    def build()
        super

        tmpdir, remove = detstination_dir()
        begin
            list = []
            list_items { | path, m, base |
                fp = fullpath(path)
                raise "File '#{fp}' cannot be found" unless File.exists?(fp)

                is_path_dir = File.directory?(fp)
                dir         = is_path_dir ? path : File.dirname(path)
                unless base.nil?
                    dir = Pathname.new(dir).relative_path_from(Pathname.new(base)).to_s
                    if dir == '.' # relative path completely eats directory from path
                        raise "Invalid relative path detected for '#{path}' by '#{base}' base" if is_path_dir
                        list << File.basename(path)
                    elsif dir.start_with?('..') # relative path could not be resolved
                        raise "Invalid base path '#{base}'"
                    else
                        list << is_path_dir ? File.join(dir) : File.join(dir, File.basename(path))
                    end
                else
                    list << path
                end

                dest_dir = File.join(tmpdir, dir)
                if File.exists?(dest_dir)
                    raise "Destination directory '#{dest_dir}' already exists as a file" if File.file?(dest_dir)
                else
                    FileUtils.mkdir_p(dest_dir)
                end

                FileUtils.cp(fp, File.join(dest_dir, File.basename(path))) unless is_path_dir
            }

            raise "Cannot detect generated file items" if list.length == 0
            list.each { | item |
                puts "    '#{item}'"
            }

            dest = fullpath()
            Dir.chdir(tmpdir)
            raise "File '#{dest}' generation error" if generate(dest, tmpdir, list) != 0
        ensure
            FileUtils.remove_entry(tmpdir) if remove
        end
    end

    def detstination_dir()
       return Dir.mktmpdir, true
    end

    # yield (path, mtime, base = nil)
    def list_items(rel = nil)
        raise NotImplementedError, ''
    end

    def clean() File.delete(fullpath) if File.exists?(fullpath) end
    def expired?() !File.exists?(fullpath) end
    def generate(dest, dest_dir, list) raise NotImplementedError, '' end
end

module ZipTool
    def detect_zip()
        @zip_path ||= nil
        @zip_path = FileArtifact.which('zip') if @zip_path.nil?
        return @zip_path
    end

    def detect_zipinfo()
        @zipinfo_path ||= nil
        @zipinfo_path = FileArtifact.which('zipinfo') if @zipinfo_path.nil?
        return @zipinfo_path
    end

    def run_zip(*args)
        z = detect_zip
        raise 'zip command line tool cannot be found' if z.nil?
        return Artifact.exec(*([ z ] << args))
    end

    def run_zipinfo(*args)
        zi = detect_zipinfo
        raise 'zip command line tool cannot be found' if zi.nil?
        return Artifact.exec(*([ zi ] << args))
    end
end

class ArchiveFile < GeneratedFile
    include LogArtifactState

    def initialize(*args)
        @sources = []
        @bases   = []
        super

        fp = fullpath()
        raise "File '#{fp}' points to directory" if File.directory?(fp)
    end

    def list_items(rel = nil)
        @sources.each_index { | i |
            @sources[i].list_items { | path, m |
                yield path, m, @bases[i]
            }
        }
    end

    def SOURCE(path, base = nil)
        fm = FileMask.new(path)
        @sources << fm
        unless base.nil?
            base = base[0 .. base.length - 1] if base[-1] != '/'
            raise "Invalid base '#{base}' directory for '#{path}' path" unless path.start_with?(base)
        end

        @bases << base
    end

    def what_it_does()
        return "Create'#{@name}' by '#{@sources.map { | item | item.name }}'"
    end
end

class ZipFile < ArchiveFile
    include ZipTool

    def initialize(*args)
        OPT '-9q'
        super
    end

    def generate(path, dest_dir, list)
        return run_zip(OPTS(), "\"#{path}\"",  list.join(' '))
    end
end

# file that contains artifacts paths of a composite target artifact
class MetaFile < FileArtifact
    include LogArtifactState

    attr_accessor :validate_items

    def initialize(*args)
        @validate_items = true
        super
    end

    def list_items(rel = nil)
        fp = fullpath
        return unless File.exists?(fp)

        go_to_homedir
        # read meta file line by line
        File.readlines(fp).each { | item |
            item = item.strip
            next if item.length == 0 || item[0,1]=='#'  # skip comment and empty strings

            files = FileMask.new(item)
            files.list_items { | path, m |
                if @validate_items
                    fp = fullpath(path)
                    raise "File '#{fp}' cannot be found" unless File.exists?(fp)
                end

                yield path, m, nil
            }
        }
    end

    def build()
        raise "Meta file '#{fp}' points to directory or doesn't exist" unless File.file?(fp)
    end

    def what_it_does() nil end
end

class MetaGeneratedFile < GeneratedFile
    def initialize(*args)
        super
        @meta = META()
        REQUIRE @meta
    end

    def META()
        meta = MetaFile.new(File.join('.lithium', 'meta', relative_path))
        fp = meta.fullpath
        raise "Invalid meta file path '#{fp}'" unless File.file?(fp)
        return meta
    end

    def list_items(rel = nil)
        @meta.list_items { | p, m |
            yield p, m, nil
        }
    end

    def what_it_does() "Generate file by '#{@meta.name}'" end
end

class MetaGeneratedZipFile < MetaGeneratedFile
    include ZipTool

    def initialize(*args)
        OPT '-9q'
        super
        @base ||= nil
        fp = fullpath
        raise "Zip file '#{fp}' points to directory or doesn't exist" unless File.file?(fp)
    end

    def list_items(rel = nil)
        list_items { | p, m |
            yield p, m, @base
        }
    end

    def generate(path, source, list)
        return run_zip(OPTS(), "\"#{path}\"",  list.join(' '))
    end

    def build_failed() clean() end
    def what_it_does() "Generate ZIP file by '#{@meta.name}'" end
end

# Copy file format:
#   1. pattern: src/test.java                  - copy "test.java" file to "."
#   2. pattern: src/test.java && preserve_path - copy "test.java" file to "./src"
#   3. pattern: src/lib                        - copy "lib" directorty to "./lib"
#   4. pattern: src/lib && preserve_path       - copy "lib" directorty as "./src/lib"
class MetaGeneratedDirectory < MetaGeneratedFile
    CONTENT_FN = '.dir_content'

    def clean()
        fp = fullpath
        list_items { |n, t|
            p =  File.join(fp, n)

            next unless File.exists?(p)
            if File.directory?(p)
                FileUtils.rm_r(File.join(fp, n.split('/')[0]))
            else
                FileUtils.rm(p)
            end
        }
    end

    def expired?()
        return true if super

        fp = fullpath
        list_items { |n, t|
            p =  File.join(fp, n)
            return true unless File.exists?(p)
        }
        false
    end

    def pre_build()
        clean()
    end

    def generate(dir, tmpdir, list) return 0 end

    def detstination_dir()
       fp = fullpath
       FileUtils.mkdir_p(fp) unless File.exists?(fp)
       return fp, false
    end

    def META()
        meta = MetaFile.new(File.join('.lithium', 'meta', relative_path, CONTENT_FN))
        raise "Meta file cannot be found #{meta.fullpath}" if !File.exists?(meta.fullpath)
        meta
    end

    def build_failed() clean() end

    def what_it_does() "Generate folder '#{@name}' and its content" end
end

