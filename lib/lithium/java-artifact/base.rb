require "pathname"

require 'lithium/core'

class JavaClasspath < Artifact
    include AssignableDependecy
    include LogArtifactState

    log_attr :libs, :classpath

    def self.classpath_path(name)
        raise 'Class path file name cannot be nil or empty' if name.nil? || name.length == 0
        File.join('.env', 'classpath', name)
    end

    def self.join(*parts)
        cl = parts.select { | part | !part.nil? && parts.length > 0 }.join(File::PATH_SEPARATOR)
        return JavaClasspath::norm_classpath(cl)
    end

    def self.norm_classpath(cp)
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

            res << part unless res.include?(part)
        }
        return res.join(File::PATH_SEPARATOR)
    end

    def self.build_classpath(root, *libs)
        classpath = nil
        libs.each { | lib_path |
            lib_path = File.join(root, lib_path) unless (Pathname.new lib_path).absolute?
            classpath = classpath ? classpath + File::PATH_SEPARATOR + lib_path : lib_path
            if File.directory?(lib_path)
                Dir[File.join(lib_path, '*.jar')].each { | item |
                    classpath = classpath + File::PATH_SEPARATOR + item
                }
            end
        }
        return classpath ? JavaClasspath::norm_classpath(classpath) : nil
    end

    default_name classpath_path('java_classpath')

    def initialize(*args, &block)
        super
        @libs ||= []
        @classpath = resolve_classpath()
    end

    def assign_me_to()
        'classpaths'
    end

    # keep it to logging to track the artifact expiration state
    def expired?
        false
    end

    def detect_libs()
        base = project().homedir
        libs = []
        libs << 'classes' if File.exists?(File.join(base, 'classes'))
        libs << 'lib'     if File.exists?(File.join(base, 'lib'))
        return libs
    end

    def build()
    end

    def resolve_classpath()
        libs = @libs.length > 0 ? @libs.dup() : detect_libs()

        return JavaClasspath::build_classpath(homedir, *libs)
    end
end

class WarClasspath < JavaClasspath
    default_name JavaClasspath::classpath_path('war_classpath')

    def detect_libs()
        base = project().homedir
        libs = []
        libs << File.join('WEB-INF', 'classes') if File.exists?(File.join(base, 'WEB-INF', 'classes'))
        libs << File.join('WEB-INF', 'lib')     if File.exists?(File.join(base, 'WEB-INF', 'lib'))
        return libs
    end
end

class JavaClasspathFile < FileArtifact
    include AssignableDependecy
    include LogArtifactState

    def assign_me_to()
        'classpaths'
    end

    def expired?()
        !File.exists?(fullpath)
    end

    def build()
        super
        raise "Classpath file points to existing directory '#{fullpath()}'" if File.directory?(fullpath())
    end

    def classpath()
        return File.exists?(fullpath) ? File.read(fullpath) : nil
    end
end


class WildflyWarClasspath < JavaClasspath
    default_name JavaClasspath::classpath_path('wildfly_war_classpath')

    def detect_libs()
        libs = []
        modules_path = FileArtifact.look_directory_up(homedir, 'modules')
        raise "Invalid Wildfly module path '#{modules_path}'" if !File.exists?(modules_path) || !File.directory?(modules_path)
        javax_modules(modules_path, 'servlet', libs)
        javax_modules(modules_path, 'security', libs)
        return libs
    end

    def javax_modules(modules_path, path, libs)
        path = File.join(modules_path, 'system', 'layers', 'base', 'javax', path, '**', '*.jar')
        Dir[path].each { | jar_path |
            libs << jar_path
        }
    end
end


class JavaClasspathDirectory < FileArtifact
    include AssignableDependecy
    include LogArtifactState

    default_name JavaClasspath::classpath_path('.classpath')

    def assign_me_to()
        'classpaths'
    end

    def expired?()
        false
    end

    def build()
    end

    def list_items(rel = nil)
        FileMask.new(File.join(fullpath, '*')).list_items(rel) { | it, m |
            yield it, m
        }
    end

    def classpath()
        cp_path = fullpath

        list = []
        list_items { | it, m |
            list << it
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

        REQUIRE(JavaClasspath)
    end

    def classpath()
        classpath = @classpaths.map { | art | art.classpath }.select { | cp | !cp.nil? && cp.length > 0 }.join(File::PATH_SEPARATOR)
        return classpath.nil? || classpath.length == 0 ? nil : classpath
    end
end

class JAVA < JVM
    include AutoRegisteredArtifact

    log_attr :java_home, :java_version, :java_version_low, :java_version_high

    def initialize(*args)
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
        path = File.join(@java_home, 'bin', tool)
        return path if File.exists?(path) || (File::PATH_SEPARATOR && File.exists?(path + '.exe'))
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
    def groovy() File.join(@groovy_home, 'bin', 'groovy') end
end

#
# Kotlin environment
#
class KOTLIN < JVM
    include AutoRegisteredArtifact

    log_attr :kotlin_home, :runtime_libs

    def initialize(*args)
        super

        unless @kotlin_home
            kotlinc_path = FileArtifact.which('kotlinc')
            @kotlin_home = File.dirname(File.dirname(kotlinc_path)) if kotlinc_path
        end
        raise "Kotlin home '#{@kotlin_home}' cannot be found" if @kotlin_home.nil? || !File.exist?(@kotlin_home)
        puts "Kotlin home: '#{@kotlin_home}'"

        unless @runtime_libs
            @runtime_libs = [ File.join(@kotlin_home, 'lib', 'kotlin-stdlib.jar'),
                              File.join(@kotlin_home, 'lib', 'kotlin-reflect.jar') ]
        end
    end

    def classpath()
        if @runtime_libs.length > 0
            cp = @runtime_libs.dup
            cp << super
            return JavaClasspath::join(*cp)
        else
            return super
        end
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

        raise "Scala home '#{@kotlin_home}' cannot be found" if scala_home.nil? || !File.exist?(@scala_home)
        puts "Scala home: '#{scala_home}'"
    end

    def what_it_does() "Initialize Scala environment '#{@name}'" end

    def scalac() File.join(@scala_home, 'bin', 'scalac') end

    def scala() File.join(@scala_home, 'bin', 'scala') end
end
