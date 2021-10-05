require 'fileutils'
require 'pathname'

require 'lithium/core'

module FileSourcesSupport
    module FileSource
    include AssignableDependency

    def assign_me_to
        :sources
    end

    def relative_from
        @base ||= nil
        return @base
    end

    def BASE(base)
        @base = base
        @base = base[0 .. base.length - 1] unless base.nil? || base[-1] != '/'
        return self
    end
end

    def BASE(path)
        @sources ||= []
        @sources.each { | src |  src.BASE(path) unless src.relative_from.nil? }
    end

    def sources(*src)
        @sources ||= []

        # validate
        src.each { | s |
            raise 'Source cannot be nil' if s.nil?
        }

        @sources = @sources.concat(src) if src.length > 0
        return self
    end

    # yield files from all registered sources:
    #   (source, source_path, mtime, dest)
    # @from  an absolute path to file that has to be used as a part of generation
    # @as a path under which the given source is expected to handle
    # @from_mtime modified time of source file
    def list_sources_items
        @sources.each { | source |
            source.list_items { | path, mtime |
                from = fullpath(path)
                raise "File '#{from}' cannot be found" unless File.exists?(from)

                dest = destination(source, path, mtime)
                raise "Absolute path '#{dest}' cannot be used as a relative destination" if File.absolute_path?(dest)

                yield source, from, mtime, dest
            }
        }
    end

    def destination(source, path, mtime)
        from        = fullpath(path)
        base        = source.relative_from
        is_path_dir = File.directory?(from)
        unless base.nil?
            dest = Pathname.new(is_path_dir ? path : File.dirname(path)).relative_path_from(Pathname.new(base)).to_s
            if dest == '.' # relative path completely eats directory from path
                raise "Invalid relative path detected for '#{path}' by '#{base}' base" if is_path_dir
                dest = File.basename(path)
            elsif dest == '/'
                raise "Invalid relative detected for '#{path}' by '#{base}' points to root!"
            elsif dest.start_with?('..') # relative path could not be resolved
                raise "Invalid base path '#{base}'"
            else
                dest = is_path_dir ? dest : File.join(dest, File.basename(path))
            end
            return dest
        else
            return path
        end
    end

    def SOURCES(&block)
        begin
            @add_as_sources = true
            self.instance_eval &block
        ensure
            @add_as_sources = false
        end
    end

    def REQUIRE(art)
        if @add_as_sources == true
            raise "Source artifact '#{art.class}:#{art.name}' doesn't implement 'list_items' method" unless art.respond_to?(:list_items)

            unless art.is_a?(FileSource)
                class << art
                    include FileSource
                end
            end
        end

        super(art)
    end
end

class FileMaskSource < FileMask
    include FileSourcesSupport::FileSource
end

# file that contains artifacts paths of a composite target artifact
class MetaFile < ExistentFile
    include LogArtifactState

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

                files = FileMask.new(item, self.owner)
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

# acquired file artifact
class GeneratedFile < FileArtifact
    include FileSourcesSupport

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
class GeneratedDirectory < Directory
    include FileSourcesSupport

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
                puts "Remove '#{fp}' destination directory"
                FileUtils.rm_r(fp)
            end
        else
            dirs = { }
            list_sources_items { | source, from, mtime, as |
                dest = File.join(fp, as)
                if File.directory?(from)
                    raise "Invalid '#{dest}' destination directory" if File.file?(dest)
                    if File.exists?(dest)
                        puts "Remove '#{dest}' destination directory(s)"
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

        list_sources_items { | source, from, mtime, as |
            dest = File.join(fp, as)
            if File.directory?(from)
                raise "Invalid destination directory '#{dest}'" if File.file?(dest)
                unless File.exists?(dest)
                    puts "Creating '#{dest}' destination directory"
                    FileUtils.mkdir_p(dest)
                end
            else
                unless File.directory?(File.dirname(dest))
                    dest_up = File.dirname(dest)
                    puts "Creating '#{dest_up}' destination directory"
                    FileUtils.mkdir_p(dest_up)
                end

                unless File.exists?(dest) && File.mtime(dest).to_i > mtime
                    if File.exists?(dest)
                        puts "Updating '#{from}'\n    with '#{dest}'"
                    else
                        puts "Copying '#{from}'\n     to '#{dest}'"
                    end
                    FileUtils.cp(from, dest)
                end
            end
        }

        FileUtils.touch(fp)
    end

    def list_items(rel = nil)
        fp = fullpath
        list_sources_items { | source, from, mtime, as |
            as_fp = File.join(fp, as) unless File.absolute_path?(as)
            yield as, File.exists?(as_fp) ? File.mtime(as_fp).to_i : -1
        }
    end

    def expired?
        return true if super
        fp = fullpath

        list_sources_items { | source, from, mtime, as |
            path = File.join(fp, as)
            return true unless File.exists?(path)
            return true if mtime > 0 && mtime > File.mtime(path).to_i
        }
        return false
    end

    def what_it_does
        "Generate folder '#{fullpath}' and its content"
    end

    def self.abbr
        'DIR'
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
    
    def what_it_does
        "Generate temporary folder '#{fullpath}' and its content"
    end
end

