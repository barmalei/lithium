require 'lithium/std-core' # help to run it as a code, since puts_warning is expected
require 'lithium/core'

require 'rexml/document'
require 'tempfile'

class JavaClasspath < EnvArtifact
    include LogArtifactState
    include PATHS

    log_attr :paths

    def assign_me_to
        :add_classpath
    end

    def build
    end

    def what_it_does
        "Build '#{name}' class path "
    end
end

class DefaultClasspath < JavaClasspath
    def initialize(name, &block)
        super
        # if a user defines its own customization block ignore classpath auto-detection
        if block.nil?
            hd = path_base_dir
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
        base_lib = File.join(path_base_dir, 'WEB-INF')
        JOIN(File.join('WEB-INF', 'classes'))   if File.exists?(File.join(base_lib, 'classes'))
        JOIN(File.join('WEB-INF', 'lib/*.jar')) if File.exists?(File.join(base_lib, 'lib'))
    end
end

class WildflyWarClasspath < WarClasspath
    attr_reader :modules_path

    def initialize(name, &block)
        @modules_path = FileArtifact.look_directory_up(project.homedir, 'modules')
        raise 'Invalid NIL WildFly module path' if modules_path.nil?
        raise "Invalid WildFly module path '#{@modules_path}'" unless File.directory?(@modules_path)

        super

        SYSTEM_MODULES('javax/servlet', 'javax/security', 'javax/ws')
    end

    # TODO: not completed method to lookup WF modules
    def DEPLOYMENT()
        dep_xml = File.join(project.homedir, 'WEB-INF', 'jboss-deployment-structure.xml')
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

class InFileClasspath < FileArtifact
    include AssignableDependency
    include LogArtifactState
    include PATHS

    default_name(".li_classpath")

    log_attr :exclude

    def initialize(name, &block)
        super
        fp = fullpath
        @exclude ||= []
        load_paths() if File.exists?(fp)
    end

    def assign_me_to
        :add_classpath
    end

    def build()
        super
        fp = fullpath
        raise "Classpath file/directory '#{fp}' doesn't exist" unless File.exists?(fp)
        load_paths()
    end

    def load_paths
        CLEAR().JOIN(read_classpath_file(fullpath))
        if @exclude.length > 0
            @exclude.each { | exc_path |
                FILTER(exc_path )
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

    def expired?
        false
    end

    def EXCLUDE(*path)
        @exclude ||= []
        @exclude.push(*path)
    end
end

class JVM < EnvArtifact
    include LogArtifactState

    attr_reader :classpaths # array of PATHS instances

    def initialize(name, &block)
        @classpaths = []
        super
    end

    def add_classpath(cp)
        raise "Invalid class path type: '#{cp.class}'" unless cp.kind_of?(PATHS)
        # the method can call multiple time for the same instance of the artifact
        # if there are more than 1 artifact that depends on the artifact
        @classpaths.push(cp) if @classpaths.index(cp).nil?
    end

    def list_classpaths
        return 'None' if @classpaths.length == 0
        @classpaths.map { | clz |
            clz.name
        }.join(',')
    end

    def classpath
        PATHS.new(project.homedir).JOIN(@classpaths)
    end

    def what_it_does
        "Init #{self.class.name} environment '#{@name}', CP = [ #{list_classpaths} ]"
    end

    def SDKMAN(version, candidate = 'java')
        raise "Invalid '#{candidate}' candidate"         if candidate.nil? || candidate.length < 3
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
    include AutoRegisteredArtifact

    log_attr :java_home, :jdk_home, :java_version

    def initialize(name, &block)
        super

        # identify Java Home
        unless @java_home
            if ENV['JAVA_HOME']
                @java_home = ENV['JAVA_HOME']
                puts_warning 'Java home has not been defined by project. Use Java home specified by env. variable'
            else
                @java_home = FileArtifact.which('java')
                @java_home = File.dirname(File.dirname(@java_home)) if @java_home
            end
        end

        raise 'Java home cannot be identified' if @java_home.nil?
        @java_home = @java_home.gsub('\\','/')

        unless @jdk_home
            @jdk_home = @java_home
        else
            raise "JDK '#{@jdk_home}' directory is invalid" unless File.directory?(@jdk_home)
        end

        @java_version = Artifact.grep_exec(File.join(@java_home, 'bin', 'java'), "-version", pattern:/version\s+\"([^\"]+)\"/)
        raise "Java version cannot be identified for #{@java_home}" if @java_version.nil?
        puts "Java version '#{@java_version}', home '#{@java_home}'"
    end

    def javac()   jtool('javac')   end
    def javadoc() jtool('javadoc') end
    def java()    jtool('java')    end
    def jar()     jtool('jar')     end

    def SDKMAN(version, candidate = 'java')
        @java_home = super
    end

    protected

    def jtool(tool)
        path = File.join(@jdk_home, 'bin', tool)
        return path if File.exists?(path) || (File::PATH_SEPARATOR == ';' && File.exists?(path + '.exe'))
        puts_warning "'#{path}' not found. Use '#{tool}' as is"
        return tool
    end
end

class GROOVY < JVM
    include AutoRegisteredArtifact

    log_attr :groovy_home

    def initialize(name, &block)
        super

        unless @groovy_home
            groovy_path = FileArtifact.which('groovy')
            @groovy_home = File.dirname(File.dirname(groovy_path)) if groovy_path
        end
        raise "Cannot find groovy home '#{@groovy_home}'" unless File.exists?(@groovy_home)

        puts "Groovy home: '#{groovy_home}'"
    end

    def SDKMAN(version, candidate = 'groovy')
        @groovy_home = super
    end

    def groovyc() File.join(@groovy_home, 'bin', 'groovyc') end
    def groovy()  File.join(@groovy_home, 'bin', 'groovy')  end
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
    include AutoRegisteredArtifact

    log_attr :kotlin_home

    def initialize(name, &block)
        super
        kotlinc_path = @kotlin_home
        unless @kotlin_home
            kotlinc_path = FileArtifact.which('kotlinc')
            kotlinc_path = File.dirname(File.dirname(kotlinc_path)) if kotlinc_path
            @kotlin_home = kotlinc_path
        end
        raise "Kotlin home '#{@kotlin_home}' cannot be found" if @kotlin_home.nil? || !File.exist?(@kotlin_home)

        KotlinClasspath {
            @kotlin_home = kotlinc_path
        }
    end

    def SDKMAN(version, candidate = 'kotlin')
        @kotlin_home = super
    end

    def kotlinc() File.join(@kotlin_home, 'bin', 'kotlinc') end

    def kotlin() File.join(@kotlin_home, 'bin', 'kotlin') end
end

# Scala environment
class SCALA < JVM
    include AutoRegisteredArtifact

    log_attr :scala_home

    def initialize(name, &block)
        super

        unless @scala_home
            scala_path = FileArtifact.which('scalac')
            @scala_home = File.dirname(File.dirname(scala_path)) if scala_path
        end

        raise "Scala home '#{@scala_home}' cannot be found" if @scala_home.nil? || !File.exist?(@scala_home)
        puts "Scala home: '#{@scala_home}'"
    end

    def SDKMAN(version, candidate = 'scala')
        @scala_home = super
    end

    def scalac() File.join(@scala_home, 'bin', 'scalac') end

    def scala() File.join(@scala_home, 'bin', 'scala') end
end

class RunJvmTool < RunTool
    attr_reader :classpaths

    # the method is called when required classpath is specified
    # (classpath classes are auto assignable artifact that has
    # to be assigned by add_classpath method)
    def add_classpath(cp)
        @classpaths ||= []
        @classpaths.push(cp)
    end

    def classpath
        cp = tool_classpath()
        cp.JOIN(@classpaths) if @classpaths
        return cp
    end

    def error_exit_code?(ec)
        ec != 0
    end

    def tool_classpath
        raise "#{self.class}.tool_classpath() is not implemented"
    end

    def run_with_options(opts)
        cp = classpath
        opts.push('-classpath', "\"#{cp}\"") unless cp.EMPTY?
        return opts
    end
end

class RunJavaTool < RunJvmTool
    def initialize(name, &block)
        REQUIRE JAVA
        super
    end

    def tool_classpath
        @java.classpath
    end
end
