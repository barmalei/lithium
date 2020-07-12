require 'fileutils'
require 'pathname'

require 'lithium/core'

module SOURCE
    include AssignableDependency

    def assign_me_to
        :add_source
    end

    def get_base
        @base ||= nil
        return @base
    end

    def BASE(base)
        @base = base
        @base = base[0 .. base.length - 1] unless base.nil? || base[-1] != '/'
        return self
    end
end

# file that contains artifacts paths of a composite target artifact
class MetaSourceFile < FileArtifact
    include LogArtifactState
    include SOURCE

    attr_accessor :validate_items
    log_attr :base

    def initialize(*args, &block)
        BASE(args[1]) if args.length > 1
        super(args[0], &block)
    end

    def list_items(rel = nil)
        fp = fullpath
        unless File.exists?(fp)
            puts "Meta file '#{fp}'' doesn't exist"
        else
            raise "Meta file '#{fp}' is directory" if File.directory?(fp)

            go_to_homedir
            # read meta file line by line
            File.readlines(fp).each { | item |
                item = item.strip
                next if item.length == 0 || item[0,1]=='#'  # skip comment and empty strings

                files = FileMask.new(item)
                files.list_items(rel) { | path, m |
                    yield path, m
                }
            }
        end
    end

    def expired?
        log_path = items_log_path()
        !File.exists?(log_path) || File.mtime(fullpath).to_i > File.mtime(log_path).to_i
    end

    def build
        fp = fullpath
        raise "Meta file '#{fp}' points to directory or doesn't exist" unless File.file?(fp)
    end

    def what_it_does
        "Validate META file '#{@name}'"
    end
end

class FileMaskSource < FileMask
    include LogArtifactState
    include SOURCE

    log_attr :base

    def initialize(*args, &block)
        BASE(args[1]) if args.length > 1
        @ignore_dirs ||= true
        super(args[0], &block)
    end

    def expired?
        false
    end
end

# acquired file artifact
class GeneratedFile < FileArtifact
    include OptionsSupport

    # called every time a new source has been registered
    def add_source(source)
        @sources ||= []
        if source.is_a?(Enumerable)
            @sources.concat(source)
        else
            @sources.push(source)
        end
    end

    def sources
        @sources ||= []
        return @sources
    end

    # yield files from all registered sources:
    #   (from, as, from_mtime)
    # @from  an absolute path to file that has to be used as a part of generation
    # @as a path under which the given source is expected to handle
    # @from_mtime modified time of source file
    def list_sources_items
        sources.each { | source |
            base = source.get_base
            source.list_items { | path, m |
                from = fullpath(path)
                raise "File '#{from}' cannot be found" unless File.exists?(from)

                is_path_dir = File.directory?(from)
                from_dir    = is_path_dir ? path : File.dirname(path)
                unless base.nil?
                    as = Pathname.new(from_dir).relative_path_from(Pathname.new(base)).to_s
                    if as == '.' # relative path completely eats directory from path
                        raise "Invalid relative path detected for '#{path}' by '#{base}' base" if is_path_dir
                        as = File.basename(path)
                    elsif as == '/'
                        raise "Invalid relative detected for '#{path}' by '#{base}' points to root!"
                    elsif as.start_with?('..') # relative path could not be resolved
                        raise "Invalid base path '#{base}'"
                    else
                        as = is_path_dir ? as : File.join(as, File.basename(path))
                    end
                else
                    as = path
                end

                raise "Absolute path '#{as}' cannot be used as a relative destination" if File.absolute_path?(as)
                yield from, as, m
            }
        }
    end

    def clean
        fp = fullpath
        raise "Path to generated file '#{fp}' points to directory" if File.directory?(fp)
        File.delete(fp) if File.file?(fp)
    end

    def expired?
        !File.exists?(fullpath)
    end
end

# Generate directory
class GeneratedDirectory < GeneratedFile
    def initialize(*args, &block)
        @full_copy = false
        super
    end

    # the generated directory is exact copy of sources (that means
    # it contains the same files the sources produce)
    def EXACT_COPY
        @full_copy = true
    end

    def clean
        fp = fullpath
        if @full_copy == true
            if File.directory?(fp)
                puts "Remove directory: '#{fp}'"
                FileUtils.rm_r(fp)
            end
        else
            dirs = { }
            list_sources_items { | from, as |
                dest = File.join(fp, as)
                if File.directory?(from)
                    raise "Invalid destination directory: '#{dest}'" if File.file?(dest)
                    if File.exists?(dest)
                        puts "Remove directory(s): '#{dest}'"
                        FileUtils.rm_r(dest)
                    end
                else
                    raise "Invalid destination file '#{dest}'" if File.directory?(dest)

                    if File.exists?(dest)
                        puts "Remove file:         '#{dest}'"
                        FileUtils.rm(dest)
                    end

                    dn  = File.dirname(as)
                    key = File.dirname(dest)
                    unless dirs.has_key?(key)
                        while dn != '.'
                            dirs[key] = true
                            dn  = File.dirname(dn)
                            key = File.join(fp, dn)
                        end
                    end
                end
            }

            # remove empty directory only to avoid unexpected removal
            dirs = dirs.sort_by { | k, v | -k.length }.to_h # reverse order, longest path is first
            dirs.each_key { | dn |
                if Dir.exists?(dn) && Dir.empty?(dn)
                    puts "Remove directory:    '#{dn}'"
                    Dir.rmdir(dn)
                end
            }
        end
    end

    def build
        super
        fp = fullpath

        clean() if @full_copy == true

        raise "Directory path '#{fp}' point to existing file" if File.file?(fp)
        unless File.exists?(fp)
            puts "Create target directory '#{fp}'"
            FileUtils.mkdir_p(fp)
        end

        list_sources_items { | from, as, from_m |
            dest = File.join(fp, as)
            if File.directory?(from)
                raise "Invalid destination directory '#{dest}'" if File.file?(dest)
                unless File.exists?(dest)
                    puts "Create directory: '#{dest}'"
                    FileUtils.mkdir_p(dest)
                end
            else
                unless File.directory?(File.dirname(dest))
                    dest_up = File.dirname(dest)
                    puts "Create directory '#{dest_up}'"
                    FileUtils.mkdir_p(dest_up)
                end

                unless File.exists?(dest) && File.mtime(dest).to_i > from_m
                    if File.exists?(dest)
                        puts "Update file from: '#{from}'\n            to:   '#{dest}'"
                    else
                        puts "Copy file from:   '#{from}'\n            to:   '#{dest}'"
                    end
                    FileUtils.cp(from, dest)
                end
            end
        }

        FileUtils.touch(fp)
    end

    def list_items(rel = nil)
        fp = fullpath
        list_sources_items { | from, as, from_m |
            as_fp = File.join(fp, as) unless File.absolute_path?(as)
            yield as, File.exists?(as_fp) ? File.mtime(as_fp).to_i : -1
        }
    end

    def list_items_to_array
        list = []
        list_items { | path, m |
            list << path
        }
        return list
    end

    def expired?
        return true if super
        fp = fullpath

        list_sources_items { | from, as, from_m |
            path = File.join(fp, as)
            return true unless File.exists?(path)
            return true if from_m > 0 && from_m > File.mtime(path).to_i
        }
        return false
    end

    def what_it_does
        "Generate folder '#{@name}' and its content"
    end
end

# Generated temporary directory
class GeneratedTmpDirectory < GeneratedDirectory
    def initialize(name, &block)
        raise "Absolute path '#{name}' cannot be used" if File.absolute_path?(name)
        dir = Dir.mktmpdir(name)
        super(dir, &block)
    end

    def clean
        fp = fullpath
        FileUtils.rm_r(fp) if File.directory?(fp)
    end
end

module ZipTool
    def detect_zip
        @zip_path ||= nil
        @zip_path = FileArtifact.which('zip') if @zip_path.nil?
        return @zip_path
    end

    def detect_zipinfo
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

# @sources - FileMask artifacts list that point to files that has to be grabbed for archiving
class ArchiveFile < GeneratedFile
    include LogArtifactState

    def build
        fp  = fullpath
        raise "File '#{fp}' points to directory" if File.directory?(fp)

        tmp = nil
        begin
            tmp = GeneratedTmpDirectory.new(File.basename(fp)) {
                @full_copy = true
            }
            tmp.add_source(sources)
            ArtifactTree.new(tmp).build

            list = tmp.list_items_to_array()
            Dir.chdir(tmp.fullpath)
            raise "Archiving of '#{fp}' has failed" if generate(list) != 0
        rescue
            raise
        ensure
            tmp.clean() unless tmp.nil?
        end
    end

    # called to generate an archive by the given sources files
    # the current directory is set to temporary folder where
    # all content to be archived is copied.
    def generate(src_list)
        raise 'Not implemented method'
    end

    def what_it_does
        "Create '#{@name}' archive"
    end
end

class ZipFile < ArchiveFile
    include ZipTool

    def initialize(*args)
        OPT '-9q'
        super
    end

    def generate(src_list)
        run_zip(OPTS(), "\"#{fullpath}\"", src_list.join(' '))
    end
end
