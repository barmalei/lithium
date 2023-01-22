require 'lithium/std-core' # help to run it as a code, since puts_warning is expected
require 'lithium/core'

require 'rexml/document'
require 'tempfile'

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
                JOIN('classes')   if File.exists?(File.join(hd, 'classes'))
                JOIN('lib/*.jar') if File.exists?(File.join(hd, 'lib'))
            end
        end
    end
end

class WarClasspath < JavaClasspath
    def initialize(name, &block)
        super
        hd = File.join(homedir, 'WEB-INF')
        JOIN(File.join('WEB-INF', 'classes'))   if File.exists?(File.join(hd, 'classes'))
        JOIN(File.join('WEB-INF', 'lib/*.jar')) if File.exists?(File.join(hd, 'lib'))
    end
end

class WildflyWarClasspath < WarClasspath
    attr_reader :modules_path

    def initialize(name, &block)
        @modules_path = FileArtifact.look_directory_up(homedir, 'modules')
        raise 'Invalid nil WildFly module path' if modules_path.nil?
        raise "Invalid WildFly module path '#{@modules_path}'" unless File.directory?(@modules_path)

        super

        SYSTEM_MODULES('javax/servlet', 'javax/security', 'javax/ws')
    end

    # TODO: not completed method to lookup WF modules
    def DEPLOYMENT()
        dep_xml = File.join(homedir, 'WEB-INF', 'jboss-deployment-structure.xml')
        jars    = []
        if File.exists?(dep_xml)
            xmldoc = REXML::Document.new(File.new(dep_xml))
            xmldoc.elements.each('jboss-deployment-structure/deployment/dependencies/module') { | el |
                if el.attributes['export'] == 'true'
                    name = el.attributes['name']
                    name = name.gsub('.', '/')
                    root = File.join(_addon_module_root, '**', name, 'main', '*.jar')
                    FileArtifact.dir(root) { | jar |
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
        raise "WildFly module path '#{path}' is invalid" unless File.exists?(path)
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

class InFileClasspath < ExistentFile
    include AssignableDependency[ :classpaths, true ]
    include LogArtifactState
    include PATHS

    default_name(".lithium/classpath")

    log_attr :exclude

    def initialize(name, &block)
        super
        fp = fullpath
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

class JVM < SdkEnvironmen
    attr_reader :classpaths # array of PATHS instances

    def list_classpaths
        return 'None' if @classpaths.length == 0
        @classpaths.map { | clz |
            clz.name
        }.join(',')
    end

    def classpath
        @classpaths ||= []
        PATHS.new(homedir).JOIN(@classpaths)
    end

    # def what_it_does
    #     "Init #{self.class.name} environment '#{@name}', CP = [ #{list_classpaths} ]"
    # end

    # TODO: strange implementation
    def SDKMAN(version, candidate = 'java')
        raise "Invalid '#{candidate}' candidate"                 if candidate.nil? || candidate.length < 3
        raise "Invalid '#{version}' #{candidate} SDKMAN version" if version.nil?   || version.length   < 2

        sdk_home = File.expand_path("~/.sdkman/candidates/#{candidate}")
        raise "Invalid '#{sdk_home}' SDKMAN #{candidate} candidates folder" unless File.directory?(sdk_home)

        candidates = Dir.glob(File.join(sdk_home, "*#{version}*")).filter { | path | File.directory?(path) }
        raise "SDKMAN '#{version}' #{candidate} version cannot be detected" if candidates.length == 0

        return File.join(candidates[0])
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
    include SelfRegisteredArtifact

    @tool_name = 'java'

    log_attr :java_version

    def initialize(name, &block)
        unless @sdk_home || !ENV['JAVA_HOME']
            @sdk_home = ENV['JAVA_HOME']
            @sdk_home.gsub('\\','/') # windows !
            puts_warning 'Java home has not been defined by project. Use Java home specified by env. variable'
        end

        super
    end

    def javac()   tool_path('javac')     end
    def javadoc() tool_path('javadoc')   end
    def java()    tool_path(tool_name()) end
    def jar()     tool_path('jar')       end

    def SDKMAN(version, candidate = 'java')
        @sdk_home = super
    end

    def tool_path(pp)
        path = super
        return path if File.exists?(path) || (File::PATH_SEPARATOR == ';' && File.exists?(path + '.exe'))
        puts_warning "'#{path}' not found. Use '#{tool}' as is"
        return tool
    end

    def tool_version(version = '-version')
        super
    end
end

class GROOVY < JVM
    include SelfRegisteredArtifact

    @tool_name = 'groovy'

    def SDKMAN(version, candidate = 'groovy')
        @sdk_home = super
    end

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
    include SelfRegisteredArtifact

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

    def SDKMAN(version, candidate = 'kotlin')
        @sdk_home = super
    end

    def kotlinc() tool_path('kotlinc') end

    def kotlin() tool_path(tool_name()) end
end

# Scala environment
class SCALA < JVM
    include SelfRegisteredArtifact

    @tool_name = 'scala'

    def SDKMAN(version, candidate = 'scala')
        @sdk_home = super
    end

    def scalac() tool_path('scalac') end

    def scala() tool_path(tool_name()) end
end

class RunJvmTool < RunTool
    attr_reader :classpaths

    def assign_req_as(art)
        @jvm_classpath = art.classpath if art.is_a?(JVM)
        return nil
    end

    def classpath
        cp = []
        cp = cp.append(@jvm_classpath) if @jvm_classpath
        cp = cp.append(@classpaths)    if @classpaths
        PATHS.new(homedir).JOIN(cp)
    end

    def error_exit_code?(ec)
        ec != 0
    end

    def WITH_OPTS
        op = super
        cp = classpath
        op.push('-classpath', "\"#{cp}\"") unless cp.EMPTY?
        return op
    end
end

class RunJavaTool < RunJvmTool
    def initialize(name, &block)
        REQUIRE JAVA
        super
    end
end

