
require 'lithium/std-core' # help to run it as a code, since puts_warning is expected
require 'lithium/core-file-artifact'

require 'rexml/document'
require 'tempfile'


#
#  Methods to detect SDKMAN packages by candidate name and optionally version
#  If version was not passed current one will be used. If tool name was not defined
#  it tries to fetch it via "tool_name" method (SdkEnvironmen classes define it)
#
module SdkmanTool
    def force_sdkhome_detection
        SDKMAN()
    end

    def SDKMAN(version = nil)
        sdkman_pkg_home(respond_to?(:tool_name) ? tool_name : nil, version)
    end

    # detect home version
    # @param  candidate
    # @param  version
    def sdkman_pkg_home(candidate, version = nil)
        raise "Invalid '#{candidate}' candidate"  if candidate.nil? || candidate.length < 3

        sdk_home = File.expand_path("~/.sdkman/candidates/#{candidate}")
        raise "Invalid '#{sdk_home}' SDKMAN #{candidate} candidates folder" unless File.directory?(sdk_home)

        if version.nil?
            path = File.join(sdk_home, 'current')
            if File.directory?(path)
                sdk_home = File.expand_path(path)
            else
                candidates = Dir.glob(File.join(sdk_home, '*')).filter { | path |
                    File.directory?(path)
                }

                if candidates.length > 0
                    sdk_home = File.join(candidates[0])
                else
                    raise "SDKMAN '#{candidate}' version cannot be detected"
                end
            end
        else
            candidates = Dir.glob(File.join(sdk_home, "#{version}*")).filter { | path | File.directory?(path) }
            if candidates.length == 0
                raise "SDKMAN '#{version}' #{candidate} version cannot be detected"
            else
                sdk_home = File.join(candidates[0])
            end
        end

        sdk_home = File.realdirpath(sdk_home) if !sdk_home.nil? && File.symlink?(sdk_home)
        return sdk_home
    end
end


class SDKMAN < SdkEnvironmen
    include SdkmanTool

    @@sdkman_base = '.env/sdkman/'

    def initialize(name, &block)
        raise "Invalid '#{self.class}' artifact '#{name}' name " unless name.start_with?(@@sdkman_base)
        super
    end

    def force_sdkhome_detection
        path = Files.relative_to(@name, @@sdkman_base)
        raise "'#{@name}' doesn't contain candidate" if path.nil?
        parts = path.split('/')
        rasie "'#{@name}' path is invalid" if parts.length > 2
        candidate = parts[0]
        version   = parts.length > 1 ? parts[1] : nil
        sdkman_pkg_home(candidate, version)
    end
end

class JavaClasspath < EnvArtifact
    include LogArtifactState
    include PATHS
    include AssignableDependency[:classpaths, true]

    log_attr :paths

    def what_it_does
        "Build '#{name}' class path "
    end
end

class DefaultClasspath < JavaClasspath
    def initialize(name, &block)
        super
        # if a user defines its own customization block ignore classpath auto-detection
        if block.nil?
            hd = homedir
            unless hd.nil?
                JOIN('classes')   if File.exist?(File.join(hd, 'classes'))
                JOIN('lib/*.jar') if File.exist?(File.join(hd, 'lib'))
            end
        end
    end
end

class WarClasspath < JavaClasspath
    def initialize(name, &block)
        super
        hd = File.join(homedir, 'WEB-INF')
        JOIN(File.join('WEB-INF', 'classes'))   if File.exist?(File.join(hd, 'classes'))
        JOIN(File.join('WEB-INF', 'lib/*.jar')) if File.exist?(File.join(hd, 'lib'))
    end
end

class WildflyWarClasspath < WarClasspath
    attr_reader :modules_path

    def initialize(name, &block)
        @modules_path = Files.look_directory_up(homedir, 'modules')
        raise 'Invalid nil WildFly module path' if modules_path.nil?
        raise "Invalid WildFly module path '#{@modules_path}'" unless File.directory?(@modules_path)

        super

        SYSTEM_MODULES('javax/servlet', 'javax/security', 'javax/ws')
    end

    # TODO: not completed method to lookup WF modules
    def DEPLOYMENT()
        dep_xml = File.join(homedir, 'WEB-INF', 'jboss-deployment-structure.xml')
        jars    = []
        if File.exist?(dep_xml)
            xmldoc = REXML::Document.new(File.new(dep_xml))
            xmldoc.elements.each('jboss-deployment-structure/deployment/dependencies/module') { | el |
                if el.attributes['export'] == 'true'
                    name = el.attributes['name']
                    name = name.gsub('.', '/')
                    root = File.join(_addon_module_root, '**', name, 'main', '*.jar')
                    Files.dir(root) { | jar |
                        JOIN(jar)
                    }
                end
            }
        end

        return jars
    end

    def SYSTEM_MODULES(*paths)
        paths.each { | path |
            SYSTEM_MODULE(path)
        }
    end

    def SYSTEM_MODULE(path)
        JOIN(*_MODULE(_system_module_root, path))
    end

    def ADDON_MODULES(*paths)
        paths.each { | path |
            ADDON_MODULE(path)
        }
    end

    def ADDON_MODULE(path)
        JOIN(*_MODULE(_addon_module_root, path))
    end

    def _MODULE(root, path)
        raise 'Empty WildFly module path'                   if     path.nil? || path.length == 0
        raise "Absolute WildFly module '#{path}' detected"  if     File.absolute_path?(path)
        raise "Modules root path '#{root}' is invalid"      unless File.directory?(root)

        path = File.join(root, path)
        raise "WildFly module path '#{path}' is invalid" unless File.exist?(path)
        path = File.join(path, '**', '*.jar')

        libs = []
        Dir[path].each { | jar_path |
            libs.push(jar_path)
        }

        return libs
    end

    def _system_module_root()
        File.join(@modules_path, 'system', 'layers', 'base')
    end

    def _addon_module_root()
        File.join(@modules_path, 'system', 'add-ons')
    end
end

class InFileClasspath < FileArtifact
    include AssignableDependency[ :classpaths, true ]
    include LogArtifactState
    include PATHS

    log_attr :exclude

    def initialize(name, &block)
        super
        @exclude ||= []
        load_paths() if exists?
    end

    def build
        super
        load_paths()
    end

    def expired?
        !File.file?(fullpath)
    end

    def load_paths
        CLEAR().JOIN(read_classpath_file(fullpath))
        if @exclude.length > 0
            @exclude.each { | exc_path |
                FILTER(exc_path)
            }
        end
    end

    def read_classpath_file(path)
        lines = []
        File.readlines(path).each { | line |
            line = line.strip
            next if line.length == 0 || line[0] == '#'
            lines.push(line)
        }
        return lines
    end

    def EXCLUDE(*path)
        @exclude ||= []
        @exclude.push(*path)
    end
end

#
# Module implements aggregated classpath
#
module ClassPathHolder
    attr_reader :classpaths # array of PATHS instances

    def classpath
        cp = instance_variables
            .map    { | n | instance_variable_get(n) }
            .map    { | v | v.is_a?(JVM) ? v.classpath : v.is_a?(JavaClasspath) ? v : nil }
            .select { | e | !e.nil? }

        @classpaths ||= []
        cp.concat(@classpaths)
        PATHS.new(homedir).JOIN(cp)
    end
end

class JVM < SdkEnvironmen
    include ClassPathHolder
    include SdkmanTool

    def list_classpaths
        return 'None' if @classpaths.length == 0
        @classpaths.map { | clz |
            clz.name
        }.join(',')
    end

    def self.grep_package(path, pattern = /^package[ \t]+([a-zA-Z0-9_.]+)[ \t]*/)
        res = FileArtifact.grep_file(path, pattern)

        if res.length == 0
            puts_warning 'Package name is empty'
            return nil
        elsif res.length > 1
            raise "Ambiguous package detection '#{res}'"
        else
            return res[0][:matched_part]
        end
    end

    def self.grep_classname(path)
        pkgname = self.grep_package(path)
        clname  = File.basename(path.dup())
        clname[/\.java$/] = '' if clname.end_with?('.java')
        raise "Class name cannot be identified by '#{path}'" if clname.nil?
        return pkgname.nil? ? clname : "#{pkgname}.#{clname}"
    end

    def self.relpath_to_class(src_path)
        pkg = self.grep_package(src_path)

        cn  = File.basename(src_path)
        cn[/\.java$/] = '' if cn.end_with?('.java')
        raise "Class name cannot be identified by #{src_path}" if cn.nil?

        File.join(pkg.gsub('.', '/'), cn + '.class')
    end
end

class JAVA < JVM
    @tool_name = 'java'

    log_attr :java_version

    def initialize(name, &block)
        super
        # Java home variable has to be initialized
        # JAVA_HOME can be required by other JVM based langs like kotlin, groovy etc
        ENV['JAVA_HOME'] = @sdk_home
    end

    def force_sdkhome_detection
        var_name = 'JAVA_HOME'
        unless !ENV[var_name]
            puts_warning "Java home '#{var_name}' variable is detected. Use it as java home"
            java_home = ENV[var_name].gsub('\\','/') # windows !
            return java_home
        end
        super
    end

    def javac()   tool_path('javac')     end
    def javadoc() tool_path('javadoc')   end
    def java()    tool_path(tool_name()) end
    def jar()     tool_path('jar')       end

    def SDKMAN(*args)
        @sdk_home = super
    end

    def tool_version(version = '-version')
        super
    end
end

class GROOVY < JVM
    @tool_name = 'groovy'

    def groovyc() tool_path('groovyc')  end
    def groovy()  tool_path(tool_name())  end
end


class KotlinClasspath < JavaClasspath
    def initialize(name, &block)
        super
        raise 'Kotlin home is not defined' if @kotlin_home.nil?
        raise "Kotlin home '#{@kotlin_home}' is invalid" unless File.directory?(@kotlin_home)

        lib = File.join(@kotlin_home, 'lib')
        JOIN(File.join(lib, 'kotlin-stdlib.jar' ),
             File.join(lib, 'kotlin-reflect.jar'))
    end
end

# Kotlin environment
class KOTLIN < JVM
    @tool_name = 'kotlin'

    def initialize(name, &block)
        super

        # TODO: redesign, may be replace KotlinClasspath with DefaultClasspath ?
        hm = @sdk_home
        REQUIRE {
            KotlinClasspath {
                @kotlin_home = hm
            }
        }
    end

    def kotlinc() tool_path('kotlinc') end

    def kotlin() tool_path(tool_name()) end
end

# Scala environment
class SCALA < JVM
    @tool_name = 'scala'

    def scalac() tool_path('scalac') end

    def scala() tool_path(tool_name()) end
end

class RunJvmTool < RunTool
    include ClassPathHolder

    # Internal field to customize JAVA, should be used only by self.JAVA method
    @JAVA = nil

    def initialize(name, &block)
        require_java()
        super
    end

    def require_java
        name, block = self.class.JAVA
        REQUIRE name, JAVA, &block
    end

    def WITH_OPTS
        super + classpath_opts
    end

    def classpath_opts
        cp = classpath
        cp.EMPTY? ? [] : [ '-classpath', "\"#{cp}\"" ]
    end

    #
    # Method to customize JAVA on the level of tool class:
    #   ToolName.JAVA {
    #       SDKMAN("21")
    #   }
    #
    def self.JAVA(name = nil, &block)
        if name.nil? && block.nil?
            return @JAVA.nil? ? [ JAVA.default_name(), block ] : @JAVA
        else
            @JAVA = [ name.nil? ? ".env/#{self.name}/JAVA" : name, block ]
        end
    end
end
