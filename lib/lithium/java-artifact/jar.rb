require 'lithium/file-artifact/archive'
require 'lithium/java-artifact/base'

# visualize a JAR file content making it available for copying via a
# virtual directory
class JarFileContent < ArchiveFileContent
    @abbr = 'JRC'

    def initialize(name, &block)
        REQUIRE JAVA
        super
    end

    def unzip(archive_path, dest_dir)
        chdir(dest_dir) {
            archive_path = Files.assert_file(archive_path)
            args = [ @java.jar, 'xf', archive_path ]
            raise "UnJar '#{archive_path}' file failed" if Files.exec(*args).exitstatus != 0
        }
    end

    def lszip(archive_path)
        archive_path = Files.assert_file(archive_path)
        err = Files.exec(@java.jar, '-tf', archive_path) { | stdin, stdout, th |
            stdin.close()
            stdout.read.split("\n").each { | path |
                yield File.join(base, path) unless path.end_with?('/..') ||  path.end_with?('/.')
            }
        }

        raise "List JAR '#{archive_path}' file failed" if err.exitstatus != 11 && err.exitstatus != 0
    end

    def what_it_does
        "Represent '#{fullpath}' JAR file content"
    end
end

# generate JAR file
#  TODO: re-work with ToolExecuter
class JarFile < ArchiveFile
    include ToolExecuter

    @abbr = 'JAR'

    def initialize(name, &block)
        REQUIRE JAVA
        super
    end

    def generate(list)
        zip(fullpath, *list)
    end

    def zip(archive_path, *files)
        raise "There is no any files to be archived in '#{archive_path}' have been specified" if files.length == 0

        # detect manifest file
        manifest_file = files.find { | path |
            File.basename(path) == 'MANIFEST.MF'
        }

        args = [ @java.jar ]
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
        raise "JAR '#{archive_path}' file cannot be created" if Files.exec(*args).exitstatus != 0
    end
end
