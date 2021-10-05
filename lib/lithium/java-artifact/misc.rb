require 'lithium/core'
require 'lithium/java-artifact/base'

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

class FindInClasspath < FileCommand
    def initialize(*args)
        REQUIRE JAVA
        super
        @target ||= $lithium_args[0]
        @use_zipinfo = false
        @use_zipinfo = true unless FileArtifact.which('zipinfo').nil?
    end

    def build()
        unless @java.classpath.EMPTY?
            count = 0
            FindInClasspath.find(@use_zipinfo, @java.classpath, @target) { | path, item, is_jar |
                item_found(path, item, is_jar)
                count = count + 1
            }

            puts_warning "No item for '#{@target}' has been found" if count == 0
        else
            puts_warning 'Classpath is not defined'
        end
    end

    def item_found(path, item, is_jar)
        puts "    [#{path} => #{item}]"
        #puts "  {\n    \"item\": \"#{item}\",\n    \"path\": \"#{path}\"\n  }"
    end

    def FindInClasspath.find(use_zipinfo, classpath, target)
        classpath.paths.each { | path |
            if File.directory?(path)
                Dir.glob(File.join(path, '**', target)).each  { | item |
                    yield path, item, false
                }
            elsif path.end_with?('.jar') || path.end_with?('.zip')
                if use_zipinfo
                    FindInZip.find_with_zipinfo('zipinfo', path, "/" + target) { | item |
                        yield path, item, true
                    }
                else
                    FindInZip.find_with_jar('jar', path, "/" + target) { | item |
                        yield path, item, true
                    }
                end
            else
                puts_warning "File '#{path}' doesn't exist" unless File.exists?(path)
            end
        }
    end

    def what_it_does() "Looking for '#{@target}' in classpath" end
end

# TODO: the name is almost similar to prev class name, a bit confusion.
class FindClassInClasspath < FindInClasspath
    def initialize(*args)
        super
        raise 'Target class is not known' if @target.nil?
        @target = @target + '.class' unless @target.end_with?('.class')
    end

    def build
        li_java_ext = File.join($lithium_code, 'ext', 'java', 'lithium')
        Artifact.exec(
            @java.java, 
            '-classpath',
            "\"#{File.join(li_java_ext, 'classes')}\"#{File::PATH_SEPARATOR}\"#{File.join(li_java_ext, 'lib/*')}\"",
            'lithium.JavaTools',
            "class:#{@target}") 
        super
    end

    def item_found(path, item, is_jar)
        unless is_jar
            path = path + '/' if path[-1] != '/'
            item[path] = ''
        end
        super
    end

    def self.abbr() 'FCC' end
end
