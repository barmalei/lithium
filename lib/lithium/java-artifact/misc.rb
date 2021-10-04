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

class RC < Artifact
    def initialize(*args)
        super
        @target = args[0].is_a?(Artifact) ? args[0] : owner.artifact(args[0])
        REQUIRE @target
    end

    def expired?
        true
    end
end

class ListJavaClasspath < RC
    def build
        unless @target.classpath.EMPTY?
            count = 0
            list_items { | path |
                count += 1
                puts "#{count}: #{path}"
            }
        else
            puts_warning 'Class path is empty'
        end
    end

    def list_items
        @target.classpath.paths.each { | path |
            if File.directory?(path)
                Dir.glob(File.join(path, '**')).each  { | item |
                    yield path
                }
            else
                yield path
            end
        }
    end
end

class FindInClasspath < RC
    def initialize(*args)
        super
        @patterns ||= $lithium_args.dup
    end

    def build()
        unless @target.classpath.EMPTY?
            count = 0
            find(@target.classpath, *(@patterns)) { | path, item, is_jar |
                item_found(path, item, is_jar)
                count = count + 1
            }

            puts_warning "No item for '#{@target}' has been found" if count == 0
        else
            puts_warning 'Classpath is empty'
        end
    end

    def item_found(path, item, is_jar)
        puts "    [#{path} => #{item}]"
        #puts "  {\n    \"item\": \"#{item}\",\n    \"path\": \"#{path}\"\n  }"
    end

    def find(classpath, *patterns)
        classpath.paths.each { | path |
            if File.directory?(path)
                Dir.glob(File.join(path, '**', patterns[0])).each  { | item |
                    yield path, item, false
                }
            elsif path.end_with?('.jar') || path.end_with?('.zip')
                FindInZip.new(path, self.owner).find(*patterns) { | item |
                    yield path, item, true
                }
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

READY {
    # Project.PROJECT {
    #     JAVA {
    #         .
    #         DefaultClasspath {
    #             JOIN('.lithium_code/ext/java/junit/junit-4.11.jar')
    #         }

    #     }

    # }


    JV = Project.artifact('.env/JAVA')
    JV.() {
        DefaultClasspath {
            puts "?????????????"
            JOIN('.lithium_code/ext/java/junit/junit-4.11.jar')
        }
    }


    puts "???? #{JV.classpaths.length}"

    puts "???? #{Project.artifact('.env/JAVA').classpaths.length}"

    # Project.artifact('.env/JAVA').REQUIRE


    #puts ">> #{ArtifactTree.build('.env/JAVA').owner}"
    a = ListJavaClasspath.new('.env/JAVA', Project.current)
    l = ArtifactTree.build(a)

    # Project.artifact('.env/JAVA')
    # puts ">>>> #{Project.artifact('.env/JAVA').classpaths}"
}