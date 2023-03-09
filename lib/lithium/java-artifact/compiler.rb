require 'fileutils'

require 'lithium/java-artifact/base'


class JvmDestinationDir < ExistentDirectory
    include AssignableDependency[:destination]

    def build
        unless exists?
            puts_warning "Create destination '#{fullpath}' folder"
            FileUtils.mkdir_p(fullpath)
        end
        super
    end
end

#  Java 
class JvmCompiler < RunJvmTool
    def initialize(name, &block)
        DESTINATION('classes')
        super
    end

    def expired?
        false
    end

    def classpath
        #dst = destination()
        dst = @destination.fullpath
        raise 'Destination cannot be detected' if dst.nil?
        cp  = super
        cp.JOIN(dst) unless cp.INCLUDE?(dst)
        return cp
    end

    def list_dest_paths
        #dest = destination()
        dst = @destination.fullpath
        unless dest.nil?
            list_items { | path, t |
                cn = JVM.grep_classname(path)
                fn = "#{cn.gsub('.', '/')}.class"
                fp = File.join(dest, fn)
                yield fp, cn if File.exist?(fp)
                FileArtifact.dir(File.join(dest, "#{cn.gsub('.', '/')}$*.class")) { | item |
                    yield item, cn
                }
            }
        end
    end

    def WITH_OPTS
        #dst  = destination()
        dst = @destination.fullpath
        raise "Destination '#{dst}' cannot be detected" if dst.nil? || !File.exist?(dst)
        super.push('-d', "\"#{dst}\"")
    end

    def clean
        list_dest_paths { | path |
            File.delete(path)
        }
    end

    def DESTINATION(path)
        REQUIRE(path, JvmDestinationDir)
    end

    def what_it_does
        "Compile (#{self.class})\n    from: '#{@name}'\n    to:   '#{@destination.fullpath}'"
    end
end

class JavaCompiler < JvmCompiler
    @abbr = 'JVC'

    def initialize(name, &block)
        REQUIRE JAVA
        super
    end

    def WITH
        @java.javac
    end
end

class JDTCompiler < JavaCompiler
    @abbr = 'JDT'

    def initialize(name, &block)
        super
        @jdt_home    ||= File.join($lithium_code, 'ext', 'java', 'jdt')
        raise "JDT home '#{@jdt_home}' cannot be found" unless File.file?(@jdt_home)
        @target_version ||= '1.8'
    end

    def WITH
        @java.java
    end

    def WITH_OPTS
        super.push('-jar', File.join(@jdt_home, '*.jar'), @target_version)
    end
end


# Groovy 
class GroovyCompiler < JvmCompiler
    @abbr = 'GTC'

    def initialize(name, &block)
        REQUIRE GROOVY
        super
    end

    def WITH
        @groovy.groovyc
    end
end

#
# Kotlin 
class KotlinCompiler < JvmCompiler
    @abbr = 'KTC'

    def initialize(name, &block)
        REQUIRE KOTLIN
        super
    end

    def WITH
        @kotlin.kotlinc
    end
end

# Scala 
class ScalaCompiler < JvmCompiler
    include StdFormater

    @abbr = 'STC'

    def initialize(name, &block)
        REQUIRE SCALA
        super
        OPT "-no-colors"
    end

    def WITH
        @scala.scalac
    end

    def format(msg, level, parent)
        parent.format(msg.gsub(/\x1b\s*\[[0-9]+m/, ""), level, $STDOUT)
    end
end


def a!
end
