require 'lithium/java-artifact/base'
require 'lithium/file-artifact/archive'
require 'lithium/utils'

class GenerateJavaDoc < RunJvmTool
    include FromFileToolExecuter

    @abbr = 'JDC'

    default_name('src/main/java/**/*.java')

    def initialize(name = nil, &block)
        DESTINATION('apidoc')
        super
    end

    def WITH
        @java.javadoc
    end

    def WITH_OPTS
        super + [ '-d', @destination.q_fullpath ]
    end

    def DESTINATION(path)
        REQUIRE(path, DestinationDirectory)
    end

    def clean
        dest = @destination.fullpath
        FileUtils.rm_r(dest) unless File.directory?(dest)
    end
end

class LiJavaToolClasspath < DefaultClasspath
    default_name('.env/li/classpath')

    def initialize(name = nil, &block)
        super
        base = Files.assert_dir($lithium_code, 'ext', 'java', 'lithium')
        JOIN(File.join(base, 'classes'))
        JOIN(File.join(base, 'lib/*.jar'))
    end
end

class LiJavaToolRunner < RunJvmTool
    def initialize(name, &block)
        super
        REQUIRE LiJavaToolClasspath
        if @command.nil?
            p = ArtifactPath.prefix(name)
            @command = p[0 ..-2] unless p.nil?
        end
    end

    def WITH
        @java.java
    end

    # available commands:
    #   'methods', 'classInfo', 'module', 'field', 'class'
    def COMMAND(cmd)
        @command = cmd
        return self
    end

    def WITH_TARGETS
        [ 'lithium.JavaTools', "#{@command}:#{File.basename(@name)}" ] + super
    end
end

# TODO: revise !!!
class FindInClasspath < Artifact
    include ClassPathHolder

    def initialize(name, &block)
        super
        REQUIRE(name)
        @pattern      ||= $lithium_args[0]
        @findJvmClasses = true if @findJvmClasses.nil?
        @cacheEnabled   = true if @cacheEnabled.nil?
        raise 'Pattern has not been defined' if @pattern.nil?
        @cache = _load_cache() if @cacheEnabled == true
    end

    def build
        res = []
        cp  = classpath()
        if @cacheEnabled == true && !@cache.empty? && @cache.has_key?(@pattern)
            @cache[@pattern].each_pair { | path, items |
                if path != 'JVM'
                    b = !File.exist?(path) ||
                        (File.directory?(path) && !items.detect { | item | !File.exist?(File.join(path, item)) }.nil?) ||
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
                    r_path = Files.relative_to(path, homedir)
                    path   = r_path unless r_path.nil?
                    res.push([path, item])
                }
            else
                puts_warning 'Classpath is empty'
            end

            if @findJvmClasses
                ArtifactTree.new(LiJavaToolRunner.new(@pattern, owner:self.owner).COMMAND('class')).build { | stdin, stdout, th |
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
        File.delete(fn) if File.exist?(fn) && !File.directory?(fn)
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
                go_to_homedir {
                    Dir[path].each { | lib_path |
                        if File.file?(lib_path)
                            ZipTool.lszip(lib_path, "**/#{pattern}") { | item |
                                yield lib_path, item
                            }
                        end
                    }
                }
            else
                puts_warning "File '#{path}' doesn't exist" unless File.exist?(path)
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
        File.join(homedir, '.lithium', '.logs', "#{self.class.name}_cache.liser")
    end

    def _load_cache
        if File.exist?(_cache_path)
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

    def what_it_does
        "Looking for '#{@pattern}' in classpath"
    end
end
