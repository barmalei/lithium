require 'fileutils'
require 'pathname'

require 'lithium/core'
require 'lithium/file-artifact/acquired'

module ZipTool
    def detect_zip
        @zip_path ||= nil
        @zip_path = FileArtifact.which('zip') if @zip_path.nil?
        return @zip_path
    end

    def detect_unzip
        @unzip_path ||= nil
        @unzip_path = FileArtifact.which('unzip') if @unzip_path.nil?
        return @unzip_path
    end

    def detect_zipinfo
        @zipinfo_path ||= nil
        @zipinfo_path = FileArtifact.which('zipinfo') if @zipinfo_path.nil?
        return @zipinfo_path
    end

    def zip(archive_path, *files)
        raise "There is no any files to be archived in '#{archive_path}' have been specified" if files.length == 0
        args = [ detect_zip, '-9q', "\"#{archive_path}\"" ]
        args = args.concat(files.map { | p | "\"#{p}\"" })
        raise "ZIP '#{archive_path}' file cannot be created" if Artifact.exec(*args).exitstatus != 0
    end

    def unzip(archive_path, dest_dir = nil)
        archive_path = assert_zip_archive(archive_path)
        args = [ detect_unzip, archive_path ]
        unless dest_dir.nil?
            raise "Invalid '#{dest_dir}' destination zip directory" unless File.directory?(dest_dir)
            args.push('-d', dest_dir)
        end
        raise "Unzip '#{archive_path}' file failed" if Artifact.exec(*args).exitstatus != 0
    end

    def lszip(archive_path, *patterns)
        archive_path = assert_zip_archive(archive_path)
        args = [ detect_zipinfo, '-1', archive_path ]
        args = args.concat(patterns.map { | p | "\"#{p}\"" }) if patterns.length > 0

        err = Artifact.exec(*args) { | stdin, stdout, th |
            stdout.each { | line |
                yield line.chomp if patterns.length == 0 || !line.start_with?('caution:')
            }
        }

        raise "List zip '#{archive_path}' file failed" if err.exitstatus != 11 && err.exitstatus != 0
    end

    def assert_zip_archive(archive_path)
        raise "Zip archive '#{archive_path}' doesn't exist" unless File.file?(archive_path)
        return "\"#{archive_path}\""
    end
end

#
#  Find an item in archive file or files by the @pattern (can be passed as command line argument)
#
class FindInZip < FileMask
    include ZipTool

    attr_accessor :patterns

    def initialize(name, &block)
        super
        @patterns ||= $lithium_args.dup
    end

    def build
        raise 'No any archive pattern has been defined' if @patterns.nil? || @patterns.length == 0
        counter = 0
        find(*(@patterns)) { | rel_path, zip_item_path |
            puts "    [#{rel_path} => #{zip_item_path}]"
            counter += 1
        }

        puts_warning "No a zip item matches by '#{@patterns}' patterns" if counter == 0
    end

    def find(*patterns)
        hd  = homedir
        list_items { | archive_path, m |
            fp       = fullpath(archive_path)
            rel_path = Pathname.new(fp).relative_path_from(Pathname.new(hd))
            lszip(fp, *(patterns)) { | zip_item_path |
                yield rel_path, zip_item_path
            }
        }
    end

    def what_it_does
        "Search '#{@patterns}' in '#{@name}' archive"
    end
end

#
#  Abstract archive file that should be generated by a specified SOURCE
#
class ArchiveFile < GeneratedFile
    include OptionsSupport
    include LogArtifactState

    def build
        fp  = fullpath
        raise "File '#{fp}' points to directory" if File.directory?(fp)

        tmp = nil
        begin
            tmp = GeneratedTmpDirectory.new(File.basename(fp), owner:self.owner) {
                @full_copy = true
            }
            tmp.sources(*@sources)
            ArtifactTree.new(tmp).build

            list = tmp.list_items_as_array()

            # save current directory to restore it later before temporary directory will be removed
            chdir(tmp.fullpath) {
                generate(list)
            }
        rescue
            raise
        ensure
            # restore directory otherwise we will stay in not exited temporary
            # directory what can bring to unexpected error (e.g. java process
            # cannot be run)
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
        "Create '#{@name}' archive file"
    end
end

#
# Zip implementation of ArchiveFile
#
class ZipFile < ArchiveFile
    include ZipTool

    @abbr = 'ZIP'

    def generate(src_list)
        zip(fullpath, *src_list)
    end
end

#
# Helps to get access to archive file items that are unpacked in a virtual folder
#
class ArchiveFileContent < FileArtifact
    include ZipTool
    include FileSourcesSupport::FileSource

    @abbr = 'AFC'

    def initialize(name, &block)
        super
        @vs_directory = File.join(homedir, vs_home())
        @base = vs_home()
    end

    def BASE(base)
        @base = base
        @base = base[0 .. base.length - 1] unless base.nil? || base[-1] != '/'
        @base = File.join(vs_home, base)
        return self
    end

    def expired?
        !File.directory?(@vs_directory) || File.mtime(@vs_directory) < File.mtime(fullpath())
    end

    def build
        fp = fullpath
        raise "Archive file '#{fp}' doesn't exist" unless File.file?(fp)

        clean # clean previously generated content
        begin
            FileUtils.mkdir_p(@vs_directory)
            chdir(@vs_directory) {
                unzip(fp)
            }
        rescue Exception => e
            clean
            raise e
        end
    end

    def clean
        FileUtils.rm_r(@vs_directory) if File.exist?(@vs_directory)
    end

    def list_items
        return unless File.exist?(fullpath)

        base  = vs_home()
        mtime = File.mtime(fullpath).to_i
        if !File.directory?(@vs_directory) || File.mtime(@vs_directory) < File.mtime(fullpath())
            lszip(fullpath()) { | path |
                yield File.join(base, path), mtime
            }
        else
            Dir.glob(File.join(base, '**', "*"), File::FNM_DOTMATCH | File::FNM_PATHNAME).each { | path |
                yield path, mtime if !path.end_with?('.') && !path.end_with?('..')
            }

        end
    end

    def vs_home
        File.join('.lithium', 'vs', @name + '.dir')
    end

    def what_it_does
        "Represent '#{fullpath}' archive file content"
    end
end
