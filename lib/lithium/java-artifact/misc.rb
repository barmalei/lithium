require 'lithium/core'
require 'lithium/java-artifact/base'
require 'lithium/file-artifact/archive'

class GenerateJavaDoc < RunJavaTool
    @abbr = 'JDC'

    def initialize(name, &block)
        super
        @targets_from_file = true
        @destination ||= 'apidoc'
    end

    def destination
        dest = fullpath(@destination)
        return dest if File.directory?(dest)
        raise "Invalid destination directory '#{dest}'" if File.exists?(dest)
        return dest
    end

    def WITH
        @java.javadoc
    end

    def WITH_TARGETS(src)
        super("@#{src}")
    end

    def WITH_OPTS
        super.push('-d', destination())
    end

    def clean
        dest = destination()
        FileUtils.rm_r(dest) unless File.directory?(dest)
    end
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

    def WITH
        @java.java
    end

    def WITH_TARGETS(src)
        t = [ 'lithium.JavaTools', "#{self.class.java_tool_command_name}:#{File.basename(@name)}" ]
        t.concat(super(src))
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

# TODO: revise !!!
class FindInClasspath < Artifact
    def initialize(name, &block)
        super
        REQUIRE (name)
        @pattern      ||= $lithium_args[0]
        @findJvmClasses = true if @findJvmClasses.nil?
        @cacheEnabled   = true if @cacheEnabled.nil?
        raise 'Pattern has not been defined' if @pattern.nil?
        @cache = _load_cache() if @cacheEnabled == true
    end

    # [name, is_array]
    def assign_req_as(art)
        return [ :classpaths, true ] if art.is_a?(JVM) || art.is_a?(JavaClasspath)
        return art.assign_me_to.push
    end

    def classpath
        @classpaths ||= []
        PATHS.new(homedir).JOIN(@classpaths.map { | art |  art.is_a?(JVM) ? art.classpath : art } ) if @classpaths.length > 0
    end

    def build
        res = []
        cp  = classpath()
        if @cacheEnabled == true && !@cache.empty? && @cache.has_key?(@pattern)
            @cache[@pattern].each_pair { | path, items |
                if path != 'JVM'
                    b = !File.exists?(path) ||
                        (File.directory?(path) && !items.detect { | item | !File.exists?(File.join(path, item)) }.nil?) ||
                        (File.file?(path) && !cp.INCLUDE?(path))

                    if b
                        @cache[@pattern].delete(path)
                        res = []
                        break
                    end
                end
                items.each { | item | res.push([path, item]) }
            }
        end

        if res.length == 0
            unless cp.EMPTY?
                find(cp, @pattern) { | path, item |
                    path   = File.absolute_path(path)
                    r_path = FileArtifact.relative_to(path, homedir)
                    path   = r_path unless r_path.nil?
                    res.push([path, item])
                }
            else
                puts_warning 'Classpath is empty'
            end

            if @findJvmClasses
                ArtifactTree.new(DetectJvmClassByName.new(*[ @pattern ], owner:self.owner)).build { | stdin, stdout, th |
                    prefix = 'detected:'
                    stdout.each { | line |
                        res.push(['JVM', line.chomp[prefix.length..]]) if line.start_with?(prefix)
                    }
                }
            end
        end

        res.each { | path, item |
            puts "    [#{path} => #{item}]"
            if @cacheEnabled == true
                @cache[@pattern]       = {} if @cache[@pattern].nil?
                @cache[@pattern][path] = [] if @cache[@pattern][path].nil?
                @cache[@pattern][path].push(item) if @cache[@pattern][path].index(item).nil?
            end
        }

        _save_cache(@cache) if @cacheEnabled == true
        puts_warning "No item for '#{@pattern}' has been found" if res.length == 0
    end

    def clean
        fn = _cache_path
        File.delete(fn) if File.exists?(fn) && !File.directory?(fn)
    end

    def find(classpath, pattern)
        classpath.paths.each { | path |
            if File.directory?(path)
                Dir.glob(File.join(path, '**', pattern)).each  { | item |
                    item = Pathname.new(item)
                    item = item.relative_path_from(path).to_s if item.absolute?
                    yield path, item.to_s
                }
            elsif path.end_with?('.jar') || path.end_with?('.zip')
                # TODO: probably "find" should be static method
                FindInZip.new(path, owner:self.owner).find(*[ "**/#{pattern}" ]) { | jar_path, item |
                    yield jar_path, item
                }
            else
                puts_warning "File '#{path}' doesn't exist" unless File.exists?(path)
            end
        }
    end

    #  Cache structure:
    #    {  "<class_name1>.class" : {
    #           "<path>" : [  "<full_class_name1>", "<full_class_name2>", ... ]
    #       },
    #       "<class_name2>.class" :  { ... }
    #       ...
    #    }
    def _cache_path
        # TODO: more unique name is required, should depend on classpath
        File.join(homedir, '.lithium', '.logs', "#{self.class.name}_cache.ser")
    end

    def _load_cache
        if File.exists?(_cache_path)
            File.open(_cache_path, 'r') { | f |
                begin
                    return Marshal.load(f)
                rescue
                    File.delete(path)
                    raise
                end
            }
        else
            return {}
        end
    end

    def _save_cache(cache)
        File.open(_cache_path, 'w') {
            | f | Marshal.dump(cache, f)
        }
    end

    def what_it_does() "Looking for '#{@pattern}' in classpath" end
end
