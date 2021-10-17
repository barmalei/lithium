require 'lithium/core'
require 'lithium/java-artifact/base'
require 'lithium/file-artifact/archive'

class GenerateJavaDoc < RunJavaTool
    def initialize(name, &block)
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

class DetectJvmClassByName < LithiumJavaToolRunner
    @java_tool_command_name = 'class'
end

class FindInClasspath < ArtifactAction
    def initialize(name, &block)
        super
        REQUIRE @target
        @patterns ||= $lithium_args.dup
        @findJvmClasses ||= true
    end

    def build()
        raise 'Patterns have not been defined' if @patterns.nil? || @patterns.length == 0

        classpath = @target.classpath if @target.kind_of?(JVM)
        classpath = @target           if @target.kind_of?(JavaClasspath)
        res       = []

        unless @target.classpath.EMPTY?
            find(@target.classpath, *(@patterns)) { | path, item |
                path   = File.absolute_path(path)
                r_path = FileArtifact.relative_to(path, @target.homedir)
                path   = r_path unless r_path.nil?
                res.push([path, item])
            }
        else
            puts_warning 'Classpath is empty'
        end

        if @findJvmClasses
            @patterns.each { | pattern |
                ArtifactTree.build(DetectJvmClassByName.new(pattern, owner:self.owner)) { |stdin, stdout, th|
                    prefix = 'detected:'
                    stdout.each { | line |
                        res.push(['JVM', line.chomp[prefix.length..]]) if line.start_with?(prefix)
                    }
                }
            }
        end

        res.each { | path, item |
            puts "    [#{path} => #{item}]"
        }

        puts_warning "No item for '#{@patterns}' has been found" if res.length == 0
    end

    def find(classpath, *patterns)
        classpath.paths.each { | path |
            if File.directory?(path)
                patterns.each { | pattern |
                    Dir.glob(File.join(path, '**', pattern)).each  { | item |
                        item = Pathname.new(item)
                        item = item.relative_path_from(path).to_s if item.absolute?
                        yield path, item.to_s
                    }
                }
            elsif path.end_with?('.jar') || path.end_with?('.zip')
                # TODO: probably "find" should be static method
                FindInZip.new(path, owner:self.owner).find(*patterns) { | jar_path, item |
                    yield jar_path, item
                }
            else
                puts_warning "File '#{path}' doesn't exist" unless File.exists?(path)
            end
        }
    end

    def what_it_does() "Looking for '#{@patterns}' in classpath" end
end
