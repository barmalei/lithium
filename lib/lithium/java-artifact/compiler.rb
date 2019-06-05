require 'fileutils'

require 'lithium/java-artifact/base'

#
#  Java compiler
#
class JavaCompiler < FileMask
    include LogArtifactState

    REQUIRE JAVA

    log_attr :destination, :options, :create_destination

    def initialize(*args)
        @create_destination = false
        @description        = 'JAVA compiler'
        @options            = ''
        @list_expired       = false
        @_cleanup_files     = []

        super

        if !@destination
            @destination = fullpath('classes')
            @destination = fullpath(File.join('WEB-INF', 'classes')) unless File.exists?(@destination)
            @destination = fullpath('lib')                           unless File.exists?(@destination)
            puts_warning "Class destination is not specified. Stick to '#{@destination}' as default one"
        else
            @destination = fullpath(@destination) unless Pathname.new(@destination).absolute?
            if !File.exists?(@destination) && @create_destination
                puts_warning "Create destination '#{@destination}' folder"
                FileUtils.mkdir_p(@destination)
            end
        end

        assert_destination()
    end

    def assert_destination()
        raise "Destination folder '#{@destination}' doesn't exist"      if !File.exists?(@destination)
        raise "Destination folder '#{@destination}' is not a directory" if !File.directory?(@destination)
    end

    def expired?() false end

    def build_compiler()
        @java.javac
    end

    def build_classpath()
        @java.classpath
    end

    def build_target_list()
        list = []
        if @list_expired
            list_expired() { |n, t|  list << "#{n}" }
        else
            list_items() { |n, t|  list << "#{n}" }
        end
        list
    end

    def build_target(list)
        path = File.expand_path('to_be_compiled.lst')
        @_cleanup_files = [ path ]
        File.open(path, 'w') { |f| f.print(list.join("\n")) }
        return "\"@#{path}\""
    end

    def build_cmd(list, target, dest)
        cp       = build_classpath()
        compiler = build_compiler()
        if cp
            [ compiler, '-classpath', "\"#{cp}\"", @options, '-d', dest, target ]
        else
            [ compiler, @options, '-d', dest, target ]
        end
    end

    def build()
        super

        list = build_target_list()
        if list.nil? || list.length == 0
            puts_warning "Nothing to be compiled"
        else
            begin
                target = build_target(list)
                cmd    = build_cmd(list, target, @destination)
                go_to_homedir()
                raise 'Compilation has failed' if Artifact.exec(*cmd) != 0
                puts "#{list.length} source files have been compiled"
            ensure
                @_cleanup_files.each { | path | File.delete(path) }
            end
        end
    end

    def what_it_does() "Compile (#{@description})\n    from: '#{@name}'\n    to:   '#{@destination}'" end
end

#
# Groovy compiler
#
class GroovyCompiler < JavaCompiler
    REQUIRE GROOVY, JAVA

    def initialize(*args)
        super
        @description = 'Groovy compiler'
    end

    def build_compiler()
        @groovy.groovyc
    end

    def build_classpath()
        CLASSPATH::join(@groovy.classpath, @java.classpath)
    end

    def what_it_does()
        "Compile groovy '#{@name}' code"
    end
end

#
# Kotlin compiler
#
class CompileKotlin < JavaCompiler
    REQUIRE KOTLIN, JAVA

    def initialize(*args)
        super
        @description = 'Kotlin compiler'
    end

    def build_compiler()
        @kotlin.kotlinc
    end

    def build_classpath()
        CLASSPATH::join(@kotlin.classpath, @java.classpath)
    end

    def build_destination()
        dest = fullpath(@destination)
        return dest if File.extname(File.basename(dest)) == '.jar'
        return super
    end

    def what_it_does()
        "Compile Kotlin '#{@name}' code"
    end
end

#
# Scala compiler
#
class CompileScala < JavaCompiler
    REQUIRE SCALA, JAVA

    def initialize(*args)
        super
        @description = 'Scala compiler'
    end

    def build_compiler()
        @scala.scalac
    end

    def build_classpath()
        CLASSPATH::join(@scala.classpath, @java.classpath)
    end

    def what_it_does()
        "Compile Scala '#{@name}' code"
    end
end
