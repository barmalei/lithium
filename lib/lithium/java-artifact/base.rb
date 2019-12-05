require "pathname"

require 'lithium/core'

require 'rexml/document'

class JavaClasspath < Artifact
    include AssignableDependency
    include LogArtifactState

    log_attr :paths
    attr_reader :classpath

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
        @classpath = build_classpath()
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
    # def expired?
    #     false
    # end

    def build()
        puts ">>>>>>>>>>>>>>>>>> !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    end

    def build_classpath()
        return nil if @paths.length == 0

        hd        = project.homedir
        classpath = []
        @paths.each { | entry |
            path = entry[:path]

            puts " --- #{path}"

            path = File.join(hd, path) unless (Pathname.new path).absolute?
            classpath.concat(JavaClasspath.expand_classpath_dir(path)) if entry[:expand] == true
            classpath.push(path)
        }

        return classpath.join(File::PATH_SEPARATOR)
    end
end

class JavaDefaultClasspath < JavaClasspath
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
    def initialize(name, &block)
        super(name) {
            hd = project.homedir
            base_lib = File.join(hd, 'WEB-INF')
            PATH(File.join('WEB-INF', 'classes'))   if File.exists?(File.join(base_lib, 'classes'))
            PATH(File.join('WEB-INF', 'lib'), true) if File.exists?(File.join(base_lib, 'lib'))
        }
        self.instance_eval &block unless block.nil?
    end
end

class InFileClasspath < FileArtifact
    include AssignableDependency
    include LogArtifactState

    def Initialize(name, &block)
        name = '.classpath' if name.nil?
        super
    end

    def assign_me_to()
        'classpaths'
    end

    def expired?()
        !File.exists?(fullpath)
    end

    def build()
        super
        fp = fullpath
        raise "Classpath file '#{fp}' doesn't exist"       unless File.exists?(fp)
        raise "Classpath file points to directory '#{fp}'" if File.directory?(fp)
    end

    def classpath()
        return File.exists?(fullpath) ? JavaClasspath.norm_classpath(File.read(fullpath))
                                      : nil
    end
end

class WildflyWarClasspath < WarClasspath
    attr_reader :modules_path

    def initialize(name, &block)
        @modules_path = FileArtifact.look_directory_up(project.homedir, 'modules')
        raise "Invalid Wildfly module path '#{@modules_path}'" unless File.directory?(@modules_path)
        super(name) {
            libs = javax_modules('servlet')
            libs.concat(javax_modules('security'))
            JARS(*libs)
            JARS(*detect_deployment_modules())
        }

        self.instance_eval &block unless block.nil?
    end

    # TODO: not completed methof to lookup WF modules
    def detect_deployment_modules()
        dep_xml = File.join(project.homedir, 'WEB-INF', 'jboss-deployment-structure.xml')
        jars    = []
        if File.exists?(dep_xml)
            xmldoc = REXML::Document.new(File.new(dep_xml))
            xmldoc.elements.each('jboss-deployment-structure/deployment/dependencies/module') { | el |
                if el.attributes['export'] == 'true'
                    name = el.attributes['name']
                    FileArtifact.grep(File.join(@modules_path, "**", "*.xml"), "\"#{name}\"") { | found_xml |
                        found_xml_doc = REXML::Document.new(File.new(found_xml))

                        if found_xml_doc.root.attributes['name'] == name
                            Dir[File.join(File.dirname(found_xml), '*.jar')].each { | jar_path |
                                jars.push(jar_path)
                            }
                            break
                        end
                    }
                end
            }
        end

        return jars
    end

    def javax_modules(path)
        libs = []
        path = File.join(@modules_path, 'system', 'layers', 'base', 'javax', path, '**', '*.jar')
        Dir[path].each { | jar_path |
            libs.push(jar_path)
        }
        return libs
    end
end


class InDirectoryClasspath < FileMask
    include AssignableDependency
    include LogArtifactState

    def assign_me_to()
        'classpaths'
    end

    def expired?()
        false
    end

    def classpath()
        cp_path = fullpath

        list = []
        list_items { | it, m |
            list.push(it)
        }

        cp = list.map { | item |
            File.size(item) > 0 ? File.read(item).strip : nil
        }.select { | item | !item.nil? && item.length > 0 }.join(File::PATH_SEPARATOR)

        return cp.nil? || cp.strip.length == 0 ? nil : cp
    end
end


class JVM < EnvArtifact
    include LogArtifactState

    def initialize(*args, &block)
        super
        @classpaths = []
    end

    def REMOVE_CLASSPATH(clazz)
    end

    def classpath()
        classpath = @classpaths.map { | art | art.classpath }.select { | cp | !cp.nil? && cp.length > 0 }.join(File::PATH_SEPARATOR)
        return classpath.nil? || classpath.length == 0 ? nil : JavaClasspath.norm_classpath(classpath)
    end
end

class JAVA < JVM
    include AutoRegisteredArtifact

    log_attr :java_home, :jdk_home, :java_version, :java_version_low, :java_version_high

    def initialize(*args)
        super

        REQUIRE(JavaDefaultClasspath)

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

    def what_it_does() "Initialize Java environment #{@java_version} '#{@name}' " end

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

end

# Kotlin environment
class KOTLIN < JVM
    include AutoRegisteredArtifact

    log_attr :kotlin_home

    def initialize(*args)
        super

        unless @kotlin_home
            kotlinc_path = FileArtifact.which('kotlinc')
            @kotlin_home = File.dirname(File.dirname(kotlinc_path)) if kotlinc_path
        end
        raise "Kotlin home '#{@kotlin_home}' cannot be found" if @kotlin_home.nil? || !File.exist?(@kotlin_home)

        lib = File.join(@kotlin_home, 'lib')
        REQUIRE(KotlinClasspath) {
            JARS(File.join(lib, 'kotlin-stdlib.jar' ),
                 File.join(lib, 'kotlin-reflect.jar'))
        }
    end

    def classpath()
        puts "Korlin.CLASSPATHS = #{@classpaths.map { | a | a.class }}"

        cl = super
        return cl
    end

    def what_it_does() "Initialize Kotlin environment '#{@name}' " end

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

    def what_it_does() "Initialize Scala environment '#{@name}'" end

    def scalac() File.join(@scala_home, 'bin', 'scalac') end

    def scala() File.join(@scala_home, 'bin', 'scala') end
end


