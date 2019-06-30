require "pathname"

require 'lithium/core'

module CLASSPATH
    def self.join(*parts)
        cl = nil
        parts.each { | part |
            cl = cl.nil? || cl.length == 0 ? part : cl + File::PATH_SEPARATOR + part  if part && parts.length > 0
        }
        return CLASSPATH::norm_classpath(cl)
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
end


class JVM < EnvArtifact
    include CLASSPATH
    include LogArtifactState

    attr_reader :classpath

    def initialize(*args, &block)
        super
        @libs               ||= []
        @libs_autodetection ||= true

        libs = @libs.length == 0 && @libs_autodetection ? autodetected_libs() : @libs.dup()
        @classpath = build_classpath(*libs)
    end

    def build_classpath(*libs)
        classpath = nil
        root      = homedir

        libs.each { | lib_path |
            path = File.join(root, lib_path) unless (Pathname.new lib_path).absolute?
            classpath = classpath ? classpath + File::PATH_SEPARATOR + path : path
            if File.directory?(path)
                Dir[File.join(path, '*.jar')].each { | item |
                    classpath = classpath + File::PATH_SEPARATOR + item
                }
            end
        }

        cp_path = File.join(root, '.lithium', '.classpath')
        if File.exists?(cp_path) && File.directory?(cp_path)
            Dir[File.join(cp_path, '*')].each { | item |
                if File.size(item) > 0
                    content = File.read(item)
                    content = content.strip
                    classpath = classpath ? classpath + File::PATH_SEPARATOR + content : content if content.length > 0
                end
            }
        end

        return classpath ? CLASSPATH::norm_classpath(classpath) : nil
    end

    def autodetected_libs()
        pp = project
        while pp do
            base = pp.homedir
            libs = []
            libs << 'classes'                       if File.exists?(File.join(base, 'classes'))
            libs << 'lib'                           if File.exists?(File.join(base, 'lib'))
            libs << File.join('WEB-INF', 'classes') if File.exists?(File.join(base, 'WEB-INF', 'classes'))
            libs << File.join('WEB-INF', 'lib')     if File.exists?(File.join(base, 'WEB-INF', 'lib'))
            pp = pp.project
        end
        return libs
    end
end

class JAVA < JVM
    include AutoRegisteredArtifact

    log_attr :java_home, :java_version, :libs, :java_version_low, :java_version_high

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

    log_attr :groovy_home, :runtime, :libs

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

    log_attr :kotlin_home, :runtime_libs, :libs

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

        @classpath = CLASSPATH::join(@classpath, *@runtime_libs)
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


