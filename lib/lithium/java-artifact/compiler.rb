require 'fileutils'
require 'tempfile'

require 'lithium/java-artifact/base'

#  Java compiler
class JavaCompiler < FileMask
    include LogArtifactState
    include OptionsSupport

    REQUIRE JAVA

    log_attr :destination, :options, :create_destination

    def initialize(*args)
        @create_destination = false
        @description        = 'JAVA compiler'
        @list_expired       = false

        super

        unless @destination.nil?
            @destination = File.join(homedir, @destination) unless Pathname.new(@destination).absolute?
            if !File.exists?(@destination) && @create_destination
                puts_warning "Create destination '#{@destination}' folder"
                FileUtils.mkdir_p(@destination)
            end
        else
            puts_warning 'Destination has not been specified, it will be auto-detected'
        end
    end

    def expired?() false end

    def detect_destination()
        hd = homedir
        pp = project.project

        destinations = [
            File.join(hd, 'classes'),
            File.join(hd, 'WEB-INF', 'classes')
        ]

        destinations.push(File.join(pp.homedir, 'classes')) unless pp.nil?

        destinations.each { | path |
            return path if File.exists?(path)
        }

        str = destinations.map { | path |  "    '" + path + "'\n" }
        str = str.join('') + "\n"
        raise "Destination folder detection has failed\n#{str}"
    end

    def destination()
        return detect_destination() if @destination.nil?
        return @destination
    end

    def build_compiler()
        @java.javac
    end

    def build_classpath()
        @java.classpath
    end

    def build_target_list()
        list = []
        if @list_expired
            list_expired() { | n, t |  list << "#{n}" }
        else
            list_items()   { | n, t |  list << "#{n}" }
        end
        list
    end

    def build_target(list)
        return Tempfile.open('lithium') { | f | f << list.join("\n") }
    end

    def build_cmd(list, target, dest)
        cp       = build_classpath()
        compiler = build_compiler()
        if cp
            [ compiler, '-classpath', "\"#{cp}\"", OPTS(), '-d', dest, target ]
        else
            [ compiler, OPTS(), '-d', dest, target ]
        end
    end

    def build()
        super

        list = build_target_list()
        if list.nil? || list.length == 0
            puts_warning "Nothing to be compiled"
        else
            target = nil
            begin
                target = build_target(list)
                cmd    = build_cmd(list, target.kind_of?(File) ? "@#{target.path}" : target, destination())
                go_to_homedir()
                raise 'Compilation has failed' if Artifact.exec(*cmd) != 0
                puts "#{list.length} source files have been compiled"
            ensure
                File.delete(target.path) if target.kind_of?(File)
            end
        end
    end

    def what_it_does() "Compile (#{@description})\n    from: '#{@name}'\n    to:   '#{destination()}'" end
end

#
# Groovy compiler
#
class GroovyCompiler < JavaCompiler
    REQUIRE JAVA
    REQUIRE GROOVY

    def initialize(*args)
        super
        @description = 'Groovy compiler'
    end

    def build_compiler()
        @groovy.groovyc
    end

    def build_classpath()
        JavaClasspath::join(@groovy.classpath, @java.classpath)
    end

    def what_it_does()
        "Compile groovy '#{@name}' code"
    end
end

#
# Kotlin compiler
#
class KotlinCompiler < JavaCompiler
    REQUIRE JAVA
    REQUIRE KOTLIN

    def initialize(*args)
        super
        @description = 'Kotlin compiler'
    end

    def build_compiler()
        @kotlin.kotlinc
    end

    def build_classpath()
        #return @kotlin.classpath
        JavaClasspath::join(@kotlin.classpath, @java.classpath)
    end

    # TODO: not clear what it is
    # def build_destination()
    #     dest = fullpath(destination())
    #     return dest if File.extname(File.basename(dest)) == '.jar'
    #     return super
    # end

    def what_it_does()
        "Compile Kotlin '#{@name}' code"
    end
end

#
# Scala compiler
#
class ScalaCompiler < JavaCompiler
    REQUIRE JAVA
    REQUIRE SCALA

    def initialize(*args)
        super
        @description = 'Scala compiler'
    end

    def build_compiler()
        @scala.scalac
    end

    def build_classpath()
        JavaClasspath::join(@scala.classpath, @java.classpath)
    end

    def what_it_does()
        "Compile Scala '#{@name}' code"
    end
end
