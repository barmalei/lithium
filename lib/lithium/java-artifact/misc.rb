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

# TODO: most likely it should be removed
class SuggestClassname < JavaFileRunner
    REQUIRE JAVA

    def initialize(*args)
        super
        @arguments = [ $lithium_args[0] ]
    end

    def build_classpath()
        File.join($lithium_code, 'classes') + File::PATH_SEPARATOR + @java.classpath
    end

    def build_target()
        'test.ClassMethods'
    end
end

class FindInClasspath < FileCommand
    REQUIRE JAVA

    def initialize(*args)
        super
        @target ||= $lithium_args[0]
        @use_zipinfo = false
        @use_zipinfo = true unless FileArtifact.which('zipinfo').nil?
    end

    def build()
        unless @java.classpath.nil?
            count = 0
            FindInClasspath.find(@use_zipinfo, @java.classpath, @target) { | path, item |
                item_found(path, item)
                count = count + 1
            }

            puts_warning "No item for '#{@target}' has been found" if count == 0
        else
            puts_warning 'Classpath is not defined'
        end
    end

    def item_found(path, item)
        puts "    [#{path} => #{item}]"
    end

    def FindInClasspath.find(use_zipinfo, classpath, target)
        classpath.split(File::PATH_SEPARATOR).each { | path |
            if File.directory?(path)
                Dir.glob(File.join(path, '**', target)).each  { | item |
                    yield path, item
                }
            elsif path.end_with?('.jar') || path.end_with?('.zip')
                if use_zipinfo
                    FindInZip.find_with_zipinfo('zipinfo', path, "/" + target) { | item |
                        yield path, item
                    }
                else
                    FindInZip.find_with_jar('jar', path, "/" + target) { | item |
                        yield path, item
                    }
                end
            else
                wmsg "File '#{path}' doesn't exist" unless File.exists?(path)
            end
        }
    end

    def what_it_does() "Looking for '#{@target}' in classpath" end
end

class FindClassInClasspath < FindInClasspath
    REQUIRE JAVA

    def initialize(*args)
        super
        @target = @target + '.class' unless @target.end_with?('.class')
    end

    def build()
        Artifact.exec(@java.java, '-classpath',
                      "\"#{File.join($lithium_code, 'classes')}\"",
                      'lithium.DiscoverSystemClass',
                      @target ) { | stdin, stdout, thread |
            # if thread.value != 0
            #     puts_warning "System class detection has failed"
            # else
                Artifact.read_exec_output(stdin, stdout, thread) { | line |
                    puts line
                }
           # end
        }

        super
    end
end
