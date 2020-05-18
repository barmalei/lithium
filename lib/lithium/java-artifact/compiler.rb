require 'fileutils'
require 'tempfile'

require 'lithium/java-artifact/base'

#  Java compile_with
class JavaCompiler < FileMask
    include LogArtifactState
    include OptionsSupport

    log_attr :destination,  :create_destination, :options

    def initialize(*args)
        REQUIRE JAVA

        @create_destination = false
        @description        = 'JAVA'
        @destination        = nil
        @list_expired       = false
        @source_as_file     = false  # store target files into tmp file

        super
    end

    def expired?() false end

    def destination()
        unless @destination.nil?
            @destination = File.join(homedir, @destination) unless Pathname.new(@destination).absolute?
            if !File.exists?(@destination) && @create_destination
                puts_warning "Create destination '#{@destination}' folder"
                FileUtils.mkdir_p(@destination)
            end

            return @destination
        else
            puts_warning 'Destination has not been specified, it will be auto-detected'
            pp = project
            while not pp.nil?
                hd = pp.homedir
                [ File.join(hd, 'classes'), File.join(hd, 'WEB-INF', 'classes') ].each { | path |
                    if File.exists?(path)
                        return path
                    else
                        puts_warning("Evaluated destination '#{path}' doesn't exist")
                    end
                }
                pp = pp.project
            end
            return nil
        end
    end

    def compile_with()
        @java.javac
    end

    def classpath()
        @java.classpath
    end

    def list_source_paths()
        if @list_expired
            list_expired_items { | n, t |  yield n }
        else
            list_items   { | n, t |  yield n }
        end
    end

    def list_dest_paths()
        dest = destination()
        unless dest.nil?
            list_source_paths { | path |
                pkg = JVM.grep_package(path)

                cn  = File.basename(path)
                cn[/\.java$/] = '' if cn.end_with?('.java')
                raise 'Class name cannot be identified' if cn.nil?

                fp = File.join(dest, pkg.gsub('.', '/'), "#{cn}.class")
                yield fp, pkg if File.exists?(fp)
                FileArtifact.dir(File.join(dest, pkg.gsub('.', '/'), "#{cn}$*.class")) { | item |
                    yield item, pkg
                }
            }
        end
    end

    def source()
        if @source_as_file
            f = Tempfile.open('lithium')
            c = 0
            begin
                list_source_paths { | path |
                    f.puts("\"#{path}\"")
                    c = c + 1
                }
            ensure
               f.close
            end

            if f.length == 0
                f.unlink
                return nil
            else
                return f, c
            end
        else
            list = []
            list_source_paths { | path |
                list.push("\"#{path}\"")
            }
            return list.length == 0 ? nil : list, list.length
        end
    end

    def cmd(src)
        cp  = classpath()
        src = src.kind_of?(Tempfile) || src.kind_of?(File) ? "@\"#{src.path}\"" : src
        dst = destination()
        raise "Destination '#{dst}' cannot be detected" if dst.nil? || !File.exists?(dst)

        cp = JavaClasspath.join(cp, dst) unless JavaClasspath.has?(cp, dst)
        if cp
            [ compile_with, '-classpath', "\"#{cp}\"", OPTS(), '-d', dst, src ]
        else
            [ compile_with, OPTS(), '-d', dst, src ]
        end
    end

    def build()
        super

        src, length = source()
        if src.nil? || length == 0
            puts_warning "Nothing to be compiled"
        else
            begin
                go_to_homedir
                raise 'Compilation has failed' if Artifact.exec(*cmd(src)) != 0
                puts "#{length} source files have been compiled"
            ensure
                src.unlink if src.kind_of?(Tempfile)
            end
        end
    end

    def clean()
        list_dest_paths { | path |
            File.delete(path)
        }
    end

    def what_it_does() "Compile (#{@description})\n    from: '#{@name}'\n    to:   '#{destination()}'" end

    def self.abbr() 'JVC' end
end

class JDTCompiler < JavaCompiler
    def initialize(*args)
        REQUIRE JAVA

        super
        @description = 'JDT'
        @jdt_jar_path = File.join($lithium_code, 'tools', 'java', 'jdt', 'ecj-4.15.jar') unless @jdt_jar_path

        raise "JDT libray '#{@jdt_jar_path}' cannot be found" unless File.file?(@jdt_jar_path)

        OPTS('-jar', @jdt_jar_path, '-1.8')
    end

    def compile_with()
        @java.java
    end

    def what_it_does()
        "Compile JAVA '#{@name}' code with JDT\n        to:  '#{destination()}'"
    end

    def self.abbr() 'JDT' end
end

#
# Groovy compile_with
#
class GroovyCompiler < JavaCompiler
    def initialize(*args)
        REQUIRE GROOVY

        super
        @description = 'Groovy'
    end

    def compile_with()
        @groovy.groovyc
    end

    def classpath()
        JavaClasspath::join(@groovy.classpath, @java.classpath)
    end

    def what_it_does()
        "Compile groovy '#{@name}' code"
    end

    def self.abbr() 'GTC' end
end

#
# Kotlin compile_with
class KotlinCompiler < JavaCompiler
    def initialize(*args)
        REQUIRE KOTLIN
        super
        @description = 'Kotlin'
    end

    def compile_with()
        @kotlin.kotlinc
    end

    def classpath()
        JavaClasspath::join(@kotlin.classpath, @java.classpath)
    end

    # TODO: not clear what it is
    # def build_destination()
    #     dest = fullpath(destination())
    #     return dest if File.extname(File.basename(dest)) == '.jar'
    #     return super
    # end

    def what_it_does()
        "Compile Kotlin '#{@name}' code\n            to '#{destination()}'"
    end

    def self.abbr() 'KTC' end
end

#
# Scala compile_with
#
class ScalaCompiler < JavaCompiler
    def initialize(*args)
        REQUIRE SCALA
        super
        @description = 'Scala'
    end

    def compile_with()
        @scala.scalac
    end

    def classpath()
        JavaClasspath::join(@scala.classpath, @java.classpath)
    end

    def what_it_does()
        "Compile Scala '#{@name}' code"
    end

    def self.abbr() 'STC' end
end
