require 'lithium/core'
require 'lithium/java-artifact/base'

class JavaDoc < FileCommand
    #include LogArtifactState
    REQUIRE JAVA

    def initialize(*args)
        @sources = []
        super
        @sources = $lithium_args.dup if @sources.length == 0 && $lithium_args.length > 0
    end

    def build()
        pkgs  = []
        files = []

        fp = fullpath()
        raise "Javadoc destination cannot point to a directory '#{fp}'" if File.exists?(fp) || File.file?(fp)

        @sources.each  { | source |
            fp = fullpath(source)
            raise "Source path '#{fp}' doesn't exists"   unless File.exists?(fp)
            raise "Source path '#{fp}' points to a file" unless File.directory?(fp)

            FileArtifact.grep(File.join(source, '**', '*.java'), /^package\s+([a-zA-Z._0-9]+)\s*;/, true) { | path, line_num, line, matched_part |
                pkgs.push(matched_part) unless pkgs.include?(matched_part)
                files.push(path)
            }
        }

        if files.length > 0
            puts "Detected packages: #{pkgs.join(', ')}"

            FileArtifact.tmpfile(files) { | tmp_file |
                r = Artifact.exec(@java.javadoc,
                                  "-classpath '#{@java.classpath}'",
                                  "-d '#{fullpath()}'",
                                  "@#{tmp_file.path}" )
                raise 'Javadoc generation has failed' if r != 0
            }
        else
            puts_warning 'No a source file has been found'
        end
    end

    def clean() FileUtils.rm_r(fullpath()) if  File.exists?(fullpath()) end
    #def expired?() !File.exists?(fullpath()) end
    def what_it_does() "Generate javadoc to '#{@name}' folder" end
end


class Introspect < Artifact
    REQUIRE JAVA

    def build()
        Artifact.exec()
    end
end

class FindJavaClass < FileCommand
    REQUIRE JAVA

    def build()
        result = []
        clname   = @name.gsub('.', '/')
        clname   = clname + '.class' unless clname.end_with?('.class')

        #puts "CLNAME = #{clname}"

        @java.classpath.split(File::PATH_SEPARATOR).each { | path |
            if File.directory?(path)
                FileArtifact.dir(File.join(path, clname)) { | item |
                    result << file unless File.directory?(file)
                }
            elsif path.end_with?('.jar')
                zip = FindInZip.new(path)
                zip.find_width_jar(path, clname)
            else
                wmsg "File '#{path}' doesn't exist" unless File.exists?(path)
            end
        }

        puts_warning "Class #{@target.name} not found" if result.length == 0
        return result
    end
end
