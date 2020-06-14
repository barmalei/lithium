require 'fileutils'

require 'lithium/java-artifact/base'

#  Java 
class JavaCompiler < RunJavaTool
    log_attr :destination, :create_destination

    def initialize(*args)
        @create_destination = false
        @description        = 'JAVA'
        @destination        = nil
        super
    end

    def expired?
        false
    end

    def classpath
        dst = destination()
        cp  = super
        cp.JOIN(dst) unless cp.INCLUDE?(dst)
        return cp
    end

    def destination
        unless @destination.nil?
            @destination = File.join(homedir, @destination) unless File.absolute_path?(@destination)
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

    def run_with
        @java.javac
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

    def run_with_options(opts)
        opts = super(opts)
        dst  = destination()
        raise "Destination '#{dst}' cannot be detected" if dst.nil? || !File.exists?(dst)
        opts.push('-d', dst)
        return opts
    end

    def clean
        list_dest_paths { | path |
            File.delete(path)
        }
    end

    def what_it_does() "Compile (#{@description})\n    from: '#{@name}'\n    to:   '#{destination()}'" end

    def self.abbr() 'JVC' end
end

class JDTCompiler < JavaCompiler
    def initialize(*args)
        super
        @description   = 'JDT'
        @jdt_home    ||= File.join($lithium_code, 'tools', 'java', 'jdt')
        raise "JDT home '#{@jdt_home}' cannot be found" unless File.file?(@jdt_home)
        @target_version ||= '1.8'
    end

    def run_with
        @java.java
    end

    def run_with_options(opts)
        opts.push('-jar', File.join(@jdt_home, '*.jar'), @target_version)
        return opts
    end

    def what_it_does
        "Compile JAVA '#{@name}' code with JDT\n        to:  '#{destination()}'"
    end

    def self.abbr() 'JDT' end
end


# Groovy 
class GroovyCompiler < JavaCompiler
    def initialize(*args)
        REQUIRE GROOVY
        super
        @description = 'Groovy'
    end

    def classpath
        super.JOIN(@groovy.classpaths)
    end

    def run_with
        @groovy.groovyc
    end

    def what_it_does
        "Compile groovy '#{@name}' code"
    end

    def self.abbr() 'GTC' end
end

#
# Kotlin 
class KotlinCompiler < JavaCompiler
    def initialize(*args)
        REQUIRE KOTLIN
        super
        @description = 'Kotlin'
    end

    def classpath
        super.JOIN(@kotlin.classpaths)
    end

    def run_with
        @kotlin.kotlinc
    end

    # TODO: not clear what it is
    # def build_destination()
    #     dest = fullpath(destination())
    #     return dest if File.extname(File.basename(dest)) == '.jar'
    #     return super
    # end

    def what_it_does
        "Compile Kotlin '#{@name}' code\n            to '#{destination()}'"
    end

    def self.abbr() 'KTC' end
end

# Scala 
class ScalaCompiler < JavaCompiler
    def initialize(*args)
        REQUIRE SCALA
        super
        @description = 'Scala'
    end

    def run_with
        @scala.scalac
    end

    def classpath
        super.JOIN(@scala.classpaths)
    end

    def what_it_does
        "Compile Scala '#{@name}' code"
    end

    def self.abbr() 'STC' end
end
