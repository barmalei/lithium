require 'lithium/core'
require 'lithium/java-artifact/base'
require 'lithium/file-artifact/archive'

class GenerateJavaDoc < RunJavaTool
    def initialize(*args)
        super
        @source_as_file = true
        @destination ||= 'apidoc'
    end

    def destination
        dest = fullpath(@destination)
        return dest if File.directory?(dest)
        raise "Invalid destination directory '#{dest}'" if File.exists?(dest)
        return dest
    end

    def run_with
        @java.javadoc
    end

    def run_with_options(opts)
        opts.push('-d', destination())
        return opts
    end

    def clean
        dest = destination()
        FileUtils.rm_r(dest) unless File.directory?(dest)
    end

    def what_it_does
        "Generate javadoc to '#{destination()}' folder"
    end

    def self.abbr() 'JDC' end
end

class LithiumJavaToolRunner < RunJavaTool
    @java_tool_command_name = 'Unknown java tool command'

    def self.java_tool_command_name
        @java_tool_command_name
    end

    def classpath
        base = File.join($lithium_code, 'ext', 'java', 'lithium')
        super.JOIN(File.join(base, 'classes'))
             .JOIN(File.join(base, 'lib/*.jar'))
    end

    def run_with
        @java.java
    end

    def run_with_target(src)
        t = [ 'lithium.JavaTools', "#{self.class.java_tool_command_name}:#{@shortname}" ]
        t.concat(super(src))
        return t
    end

end

class ShowClassMethods < LithiumJavaToolRunner
    @java_tool_command_name = 'methods'
end

class ShowClassInfo < LithiumJavaToolRunner
    @java_tool_command_name = 'classInfo'
end

class ShowClassModule < LithiumJavaToolRunner
    @java_tool_command_name = 'module'
end

class ShowClassField < LithiumJavaToolRunner
    @java_tool_command_name = 'field'
end

# TODO: the class has to be re-worked since it add JAVA as
# dependency whose classpath is used as the target. It is
# better to pass the classpath somehow to the artifact.
# The artifact name is used to detect proper home, so it
# can be any file or directory
class FindInClasspath < FileCommand
    def initialize(*args)
        REQUIRE JAVA

        super
        @patterns ||= $lithium_args.dup
        raise 'Target class is not known' if @patterns.nil? || @patterns.length == 0
    end

    def build()
        unless @java.classpath.EMPTY?
            count = 0
            find(@java.classpath, *(@patterns)) { | path, item |
                item_found(path, item)
                count = count + 1
            }

            puts_warning "No item for '#{@patterns}' has been found" if count == 0
        else
            puts_warning 'Classpath is empty'
        end
    end

    def item_found(path, item)
        puts "    [#{path} => #{item}]"
        #puts "  {\n    \"item\": \"#{item}\",\n    \"path\": \"#{path}\"\n  }"
    end

    def find(classpath, *patterns)
        classpath.paths.each { | path |
            if File.directory?(path)
                patterns.each { | pattern |
                    Dir.glob(File.join(path, '**', pattern)).each  { | item |
                        yield path, item
                    }
                }
            elsif path.end_with?('.jar') || path.end_with?('.zip')
                # TODO: probably "find" should be static method
                FindInZip.new(path, self.owner).find(*patterns) { | jar_path, item |
                    yield jar_path, item
                }
            else
                puts_warning "File '#{path}' doesn't exist" unless File.exists?(path)
            end
        }
    end

    def what_it_does() "Looking for '#{@patterns}' in classpath" end
end

# TODO: the name is almost similar to prev class name, a bit confusion.
# the only purpose of the class is fulfilling class lookup with detection
# of Java standard classes by calling JavaTool code
class FindClassInClasspath < FindInClasspath
    def build
        li_java_ext = File.join($lithium_code, 'ext', 'java', 'lithium')

        # TODO: ugly implementation when we need to call external code that also has to follow
        # defined format in its output
        @patterns.each { | pattern |
            pattern = File.basename(pattern)
            Artifact.exec(
                @java.java,
                '-classpath',
                "\"#{File.join(li_java_ext, 'classes')}\"#{File::PATH_SEPARATOR}\"#{File.join(li_java_ext, 'lib/*')}\"",
                'lithium.JavaTools',
                "class:#{pattern}")
        }

        super
    end

    def self.abbr() 'FCC' end
end
