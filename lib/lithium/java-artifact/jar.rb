require 'lithium/core'
require 'lithium/file-artifact/archive'
require 'lithium/java-artifact/base'

module JarTool
    include ZipTool

    def detect_zip
        @java.jar
    end

    def detect_unzip
        @java.jar
    end

    def detect_zipinfo
        @java.jar
    end

    def unzip(archive_path, dest_dir = nil)
        archive_path = assert_zip_archive(archive_path)
        args = [ detect_unzip, 'xf', archive_path ]
        unless dest_dir.nil?
            raise "Invalid '#{dest_dir}' destination JAR directory" unless File.directory?(dest_dir)
            args.push('-C', dest_dir)
        end
        raise "UnJar '#{archive_path}' file failed" if Artifact.exec(*args).exitstatus != 0
    end

    def lszip(archive_path, *patterns)
        archive_path = assert_zip_archive(archive_path)
        raise 'JAR tool does not support pattern to filter listed archive items' if patterns.length > 0
        err = Artifact.exec(detect_zipinfo, '-tf', archive_path) { | stdin, stdout, th |
            stdin.close()
            stdout.read.split("\n").each { | path |
                yield File.join(base, path) unless path.end_with?('/..') ||  path.end_with?('/.')
            }
        }

        raise "List JAR '#{archive_path}' file failed" if err.exitstatus != 11 && err.exitstatus != 0
    end

    def zip(archive_path, *files)
        raise "There is no any files to be archived in '#{archive_path}' have been specified" if files.length == 0

        # detect manifest file
        manifest_file = files.find { | path |
            File.basename(path) == 'MANIFEST.MF'
        }

        args = [ detect_zip ]
        if manifest_file.nil?
            args.push('vcf', "\"#{archive_path}\"")
        else
            args.push('vcfm', "\"#{archive_path}\"", "\"#{manifest_file}\"")
            files = files.filter { | path |
                File.basename(path) != 'MANIFEST.MF'
            }
        end
        args.push("-C \"#{Dir.pwd}\"")
        args = args.concat(files.map { | p | "\"#{p}\"" })
        raise "JAR '#{archive_path}' file cannot be created" if Artifact.exec(*args).exitstatus != 0
    end
end


# visualize a JAR file content making it available for copying via a
# virtual directory
class JarFileContent < ArchiveFileContent
    include JarTool

    @abbr = 'JRC'

    def initialize(name, &block)
        REQUIRE JAVA
        super
    end

    def what_it_does
        "Represent '#{fullpath}' JAR file content"
    end
end

# generate JAR file
class JarFile < ArchiveFile
    include JarTool

    @abbr = 'JAR'

    def initialize(name, &block)
        REQUIRE JAVA
        super
    end

    def generate(list)
        zip(fullpath, *list)
    end
end
