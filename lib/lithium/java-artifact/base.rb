require 'tmpdir'
require "pathname"
require "pty"

require 'lithium/core'
require 'lithium/utils'

module CLASSPATH
    def build_classpath(*libs)
        classpath = nil

        libs.each { | lib |
            expand_class_path(lib).each { | path |
                classpath = classpath ? classpath + File::PATH_SEPARATOR + path : path
            }
        }

        return classpath ? CLASSPATH::norm_classpath(classpath) : nil
    end

    def detect_libs()
        base = homedir()
        libs = []
        libs << 'classes'         if File.exists?(File.join(base, 'classes'))
        libs << 'lib'             if File.exists?(File.join(base, 'lib'))
        libs << 'WEB-INF/classes' if File.exists?(File.join(base, 'WEB-INF', 'classes'))
        libs << 'WEB-INF/lib'     if File.exists?(File.join(base, 'WEB-INF', 'lib'))
        return libs
    end

    def expand_class_path(path)
        root = homedir
        path = File.join(root, path) if !(Pathname.new path).absolute?
        list = [ path ]
        Dir["#{path}/*.jar"].each { |i|  list << i } if File.directory?(path)
        list
    end

    def self.join(*parts)
        cl = nil
        parts.each { |part|
            cl = cl ? cl + File::PATH_SEPARATOR + part : part if part
        }
        return CLASSPATH::norm_classpath(cl)
    end

    def self.norm_classpath(cp)
        res = []
        cp.split(File::PATH_SEPARATOR).each { | part |
            if res.include?(part)
            else
                res << part
            end
        }
        return res.join(File::PATH_SEPARATOR)
    end
end

class JVM < EnvArtifact
    include CLASSPATH
    include LogArtifactState
end

class JAVA < JVM
    include AutoRegisteredArtifact

    attr_reader :classpath

    log_attr :java_home, :java_version, :libs, :java_version_low, :java_version_high

    def initialize(*args)
        super

        @libs = detect_libs() if !@libs

        # identify Java Home
        if !@java_home
            if ENV['JAVA_HOME']
                @java_home = ENV['JAVA_HOME']
                puts_warning "Java home has not been defined by project. Use Java home specified by env. variable"
            else
                @java_home = FileUtil.which('java')
                @java_home = File.dirname(File.dirname(@java_home)) if @java_home
            end
        end
        raise 'Java home cannot be identified' if !@java_home
        @java_home = @java_home.gsub('\\','/')

        @java_version_version = '?'
        @java_version_low     = '?'
        @java_version_high    = '?'
        PTY.spawn("#{java()} -version") do |stdout, stdin, pid|
            begin
                stdout.each { |line|
                    m = /java\s+version\s+\"([0-9]+)\.([0-9]+)\.([^\"]*)\"/.match(line.chomp)
                    if m
                        @java_version_high = m[1]
                        @java_version_low  = m[2]
                        @java_version      = "#{@java_version_high}.#{@java_version_low}.#{m[3]}"
                        break
                    end
                }
            rescue Errno::EIO
                puts_warning "Java version cannot be detected"
            end
        end

        raise "Java version cannot be identified for #{@java_home}" if !@java_version
        puts "Java version #{@java_version}, home '#{@java_home}'"

        @classpath = build_classpath(*@libs)
    end

    def build() end

    def expired?() false end

    def javac()   jtool('javac')   end
    def javadoc() jtool('javadoc') end
    def java()    jtool('java')    end
    def jar()     jtool('jar')     end

    def what_it_does() "Initialize Java environment #{@java_version} '#{@name}' " end

    protected

    def jtool(tool)
        path = "#{@java_home}/bin/#{tool}"
        return path if File.exists?(path) || (File::PATH_SEPARATOR && File.exists?(path + '.exe'))
        puts_warning "'#{path}' not found. Use '#{tool}' as is"
        tool
    end
end

class GROOVY < JVM
    include AutoRegisteredArtifact

    log_attr :groovy_home, :runtime, :libs

    attr_reader :classpath

    def initialize(*args)
        super

        if !@groovy_home
            groovy_path = FileUtil.which('groovy')
            @groovy_home = File.dirname(File.dirname(groovy_path)) if groovy_path
        end
        raise "Cannot find groovy home '#{@groovy_home}'" if !File.exists?(@groovy_home)

        puts "Groovy '#{groovy_home}'"

        @libs      = detect_libs()  if !@libs
        @runtime   = runtime_libs() if !@runtime
        @classpath = build_classpath(*(@runtime + @libs));
    end

    def build() end

    def runtime_libs()
        return []
    end

    def groovyc() File.join(@groovy_home, 'bin', 'groovyc') end
    def groovy() File.join(@groovy_home, 'bin', 'groovy') end
end

#
# Kotlin environment
#
class KOTLIN < JVM
    include AutoRegisteredArtifact

    log_attr :kotlin_home, :runtime, :libs

    attr_reader :classpath

    def initialize(*args)
        super

        if !@kotlin_home
            kotlinc_path = FileUtil.which("kotlinc")
            @kotlin_home = File.dirname(File.dirname(kotlinc_path)) if kotlinc_path
        end
        raise "Kotlin home '#{@kotlin_home}' cannot be found" if @kotlin_home.nil? || !File.exist?(@kotlin_home)

        puts "Kotlin home: '#{@kotlin_home}'"

        @libs      = detect_libs()  if !@libs
        @runtime   = runtime_libs() if !@runtime
        @classpath = build_classpath(*(@runtime + @libs));
    end

    def build() end

    def runtime_libs()
        return "#{@kotlin_home}/lib/kotlin-stdlib.jar",
               "#{@kotlin_home}/lib/kotlin-reflect.jar"
    end

    def what_it_does() "Initialize Kotlin environment '#{@name}' " end

    def kotlinc() File.join(@kotlin_home, 'bin', 'kotlinc') end
end


# Scala environment
class SCALA < JVM
    include AutoRegisteredArtifact

    log_attr :scala_home

    attr_reader :classpath

    def initialize(*args)
        super

        if !@scala_home
            scala_path = FileUtil.which("scalac")
            @scala_home = File.dirname(File.dirname(scala_path)) if scala_path
        end

        raise "Scala home '#{@kotlin_home}' cannot be found" if scala_home.nil? || !File.exist?(@scala_home)

        puts "Scala '#{scala_home}'"

        @libs      = detect_libs()  if !@libs
        @classpath = build_classpath(*@libs);
    end

    def build() end

    def what_it_does() "Initialize Scala environment '#{@name}' " end

    def scalac() File.join(@scala_home, 'bin', 'scalac') end

    def scala() File.join(@scala_home, 'bin', 'scala') end
end

