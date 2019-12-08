require "pathname"

require 'lithium/core'

require 'rexml/document'

class JavaClasspath < Artifact
    include AssignableDependency
    include LogArtifactState

    log_attr :paths

    # join class paths and normalize it
    def JavaClasspath.join(*parts)
        cl = parts.select { | part | !part.nil? && parts.length > 0 }.join(File::PATH_SEPARATOR)
        res = JavaClasspath::norm_classpath(cl)
        return res
    end

    # split classpath and remove duplicated libs
    def JavaClasspath.norm_classpath(cp)
        res   = []
        names = {}
        cp.split(File::PATH_SEPARATOR).each { | part |
            ext = File.extname(part)
            if ext == '.jar' || ext == '.zip'
                name = File.basename(part)
                if names[name].nil?
                    names[name] = part
                else
                    puts_error "Duplicated '#{name}' library has been detected in class path:"
                    puts_error "   ? '#{names[name]}'"
                    puts_error "   ? '#{part}'"
                end
            end

            res.push(part) unless res.include?(part)
        }
        return res.join(File::PATH_SEPARATOR)
    end

    # expand directory to a classpath that contains all JARs filed found in the directory
    def JavaClasspath.expand_classpath_dir(path) ### Array
        if File.directory?(path)
            classpath_items = []
            Dir[File.join(path, '*.jar')].each { | item |
                classpath_items.push(item)
            }

            return classpath_items
        else
            raise "Invalid classpath directory '#{path}'"
        end
    end

    def initialize(*args, &block)
        @paths = []
        super
    end

    # add JARs to classpath
    def JARS(*args)
        args.each { | path |
            @paths.push({
                :path   => path,
                :type   => :jar,
                :expand => false
            })
        }
    end

    # add path to classpath
    def PATH(path, expand_path = false)
        @paths.push({
            :path   => path,
            :type   => :path,
            :expand => expand_path
        })
    end

    # clear classpath
    def CLEAR()
        @paths = []
    end

    def assign_me_to()
        'classpaths'
    end

    # keep it to track the artifact logged expiration state
    def expired?
        false
    end

    def build()
    end

    def classpath()
        hd        = project.homedir
        classpath = []
        @paths.each { | entry |
            path = entry[:path]
            path = File.join(hd, path) unless (Pathname.new path).absolute?
            classpath.concat(JavaClasspath.expand_classpath_dir(path)) if entry[:expand] == true
            classpath.push(path)
        }

        return classpath.join(File::PATH_SEPARATOR)
    end

    def what_it_does()
        "Build '#{name}' class path "
    end
end

class DefaultClasspath < JavaClasspath
    def initialize(*args, &block)
        super

        # if a user defines its own customization block ignore classpath auto-detection
        if block.nil?
            hd = project.homedir
            PATH('classes')   if File.exists?(File.join(hd, 'classes'))
            PATH('lib', true) if File.exists?(File.join(hd, 'lib'))
        end
    end
end

class WarClasspath < JavaClasspath
    def initialize(*args, &block)
        super

        hd = project.homedir
        base_lib = File.join(hd, 'WEB-INF')
        PATH(File.join('WEB-INF', 'classes'))   if File.exists?(File.join(base_lib, 'classes'))
        PATH(File.join('WEB-INF', 'lib'), true) if File.exists?(File.join(base_lib, 'lib'))
    end
end

class WildflyWarClasspath < WarClasspath
    attr_reader :modules_path

    def initialize(*args, &block)
        @modules_path = FileArtifact.look_directory_up(project.homedir, 'modules')
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
                        JARS(jar)
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
        JARS(*_MODULE(_system_module_root, path))
    end

    def ADDON_MODULES(*paths)
        paths.each { | path |
            ADDON_MODULE(path)
        }
    end

    def ADDON_MODULE(path)
        JARS(*_MODULE(_addon_module_root, path))
    end

    def _MODULE(root, path)
        raise 'Empty WildFly module path'                   if     path.nil? || path.length == 0
        raise "Absolute WildFly module '#{path}' detected"  if     Pathname.new(path).absolute?
        raise "Modules root path '#{root}' is invalid"      unless Pathname.new(root).directory?

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

    def initialize(name, &block)
        name = '.classpath' if name.nil?
        super
        @read_as_lines ||= false
    end

    def assign_me_to()
        'classpaths'
    end

    def build()
        super
        fp = fullpath
        raise "Classpath file/directory '#{fp}' doesn't exist" unless File.exists?(fp)
    end

    def list_items()
        fp = fullpath
        if File.directory?(fp)
            FileArtifact.dir(File.join(fp, '/*')) { | path |
                yield path, File.mtime(path).to_i
            }
        else
            super
        end
    end

    def classpath()
        fp = fullpath
        return nil unless File.exists?(fp)

        cp = nil
        if File.directory?(fp)
            cp = []
            FileArtifact.dir(File.join(fp, '/*')) { | path |
                cp.push(read_classpath_file(path))
            }
            cp = cp.join(File::PATH_SEPARATOR)
        else
            cp = read_classpath_file(fp)
        end

        return cp if cp.nil?
        return JavaClasspath.norm_classpath(cp)
    end

    def read_classpath_file(path)
        return File.read(path).strip unless @read_as_lines

        cp = []
        File.readlines(path).each { | line |
            line = line.strip
            next if line.length == 0 || line[0] == '#'
            cp.push(line)
        }
        return cp.join(File::PATH_SEPARATOR)
    end
end

class JVM < EnvArtifact
    include LogArtifactState

    def initialize(*args, &block)
        @classpaths = []
        super
    end

    def classpath()
        classpath = @classpaths.map { | art | art.classpath }.select { | cp | !cp.nil? && cp.length > 0 }.join(File::PATH_SEPARATOR)
        return classpath.nil? || classpath.length == 0 ? nil : JavaClasspath.norm_classpath(classpath)
    end

    def list_classpaths()
        return 'None' if @classpaths.length == 0
        @classpaths.map { | clz |
            clz.name
        }.join(',')
    end

    def what_it_does()
        "Init #{self.class.name} environment '#{@name}', CP = [ #{list_classpaths} ]"
    end
end

class JAVA < JVM
    include AutoRegisteredArtifact

    log_attr :java_home, :jdk_home, :java_version, :java_version_low, :java_version_high

    def initialize(*args)
        REQUIRE(DefaultClasspath)

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
            raise "JDK '#{@jdk_home}' directory is invalid" if !File.exists?(@jdk_home) || !File.directory?(@jdk_home)
        end

        @java_version_version = '?'
        @java_version_low     = '?'
        @java_version_high    = '?'

        IO.popen([java(), '-version',  :err=>[:child, :out]]) { | stdout |
            begin
                stdout.each { |line|
                    m = /java\s+version\s+\"([0-9]+)\.([0-9]+)\.([^\"]*)\"/.match(line.chomp)
                    if m
                        @java_version_high = m[1]
                        @java_version_low  = m[2]
                        @java_version      = "#{@java_version_high}.#{@java_version_low}.#{m[3]}"
                        stdout.close
                        break
                    end
                }
            rescue Errno::EIO
                puts_warning 'Java version cannot be detected'
            end
        }

        raise "Java version cannot be identified for #{@java_home}" if @java_version.nil?
        puts "Java version '#{@java_version}', home '#{@java_home}'"
    end

    def expired?() false end

    def javac()   jtool('javac')   end
    def javadoc() jtool('javadoc') end
    def java()    jtool('java')    end
    def jar()     jtool('jar')     end

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

    def initialize(*args)
        super

        unless @groovy_home
            groovy_path = FileArtifact.which('groovy')
            @groovy_home = File.dirname(File.dirname(groovy_path)) if groovy_path
        end
        raise "Cannot find groovy home '#{@groovy_home}'" unless File.exists?(@groovy_home)

        puts "Groovy home: '#{groovy_home}'"
    end

    def groovyc() File.join(@groovy_home, 'bin', 'groovyc') end
    def groovy()  File.join(@groovy_home, 'bin', 'groovy')  end
end


class KotlinClasspath < JavaClasspath
    def initialize(*args, &block)
        super
        raise 'Kotlin home is not defined' if @kotlin_home.nil?
        raise "Kotlin home '#{@kotlin_home}' is invalid" unless File.directory?(@kotlin_home)

        lib = File.join(@kotlin_home, 'lib')
        JARS(File.join(lib, 'kotlin-stdlib.jar' ),
             File.join(lib, 'kotlin-reflect.jar'))
    end
end

# Kotlin environment
class KOTLIN < JVM
    include AutoRegisteredArtifact

    log_attr :kotlin_home

    def initialize(*args)
        super
        kotlinc_path = @kotlin_home
        unless @kotlin_home
            kotlinc_path = FileArtifact.which('kotlinc')
            kotlinc_path = File.dirname(File.dirname(kotlinc_path)) if kotlinc_path
            @kotlin_home = kotlinc_path
        end
        raise "Kotlin home '#{@kotlin_home}' cannot be found" if @kotlin_home.nil? || !File.exist?(@kotlin_home)

        lib = File.join(@kotlin_home, 'lib')
        REQUIRE(KotlinClasspath) {
            @kotlin_home = kotlinc_path
        }
    end

    def kotlinc() File.join(@kotlin_home, 'bin', 'kotlinc') end
end

# Scala environment
class SCALA < JVM
    include AutoRegisteredArtifact

    log_attr :scala_home

    def initialize(*args)
        super

        unless @scala_home
            scala_path = FileArtifact.which('scalac')
            @scala_home = File.dirname(File.dirname(scala_path)) if scala_path
        end

        raise "Scala home '#{@scala_home}' cannot be found" if @scala_home.nil? || !File.exist?(@scala_home)
        puts "Scala home: '#{@scala_home}'"
    end

    def scalac() File.join(@scala_home, 'bin', 'scalac') end

    def scala() File.join(@scala_home, 'bin', 'scala') end
end


