require 'lithium/java-artifact/base'

class JavaFileRunner < RunJvmTool
    def WITH
        @java.java
    end

    def what_it_does
        "Run '#{@name}' with '#{self.class}'"
    end
end

class RunJavaClass < JavaFileRunner
    @abbr = 'RJC'

    def transform_target_path(path)
        n = path.dup
        n[/[.]class$/] = '' if n.end_with?('.class')
        n
    end
end

class RunJavaCode < JavaFileRunner
    @abbr = 'JRF'

    def initialize(name, &block)
        super
        # TODO: hard-coded artifact prefix
        REQUIRE "compile:#{name}"
    end

    def transform_target_path(path)
        JVM.grep_classname(path)
    end
end

class RunJAR < JavaFileRunner
    def WITH_OPTS
        super + [ '-jar' ]
    end
end

class RunGroovyScript < RunJvmTool
    @abbr = 'RGS'

    def initialize(name, &block)
        REQUIRE GROOVY
        super
    end

    def WITH
        @groovy.groovy
    end
end

class RunKotlinCode < RunJvmTool
    @abbr = 'RKC'

    def initialize(name, &block)
        REQUIRE KOTLIN
        super
        REQUIRE "compile:#{name}"
    end

    def WITH
        @kotlin.kotlin
    end

    def transform_target_path(path)
        pkg  = JVM.grep_package(path)
        ext  = File.extname(path)
        name = File.basename(path, ext)

        clname = name[0].upcase() + name[1..name.length - 1]
        clname = clname + ext[1].upcase() + ext[2..ext.length - 1] unless ext.nil?
        return pkg.nil? ? clname : "#{pkg}.#{clname}"
    end
end

class RunScalaCode < RunJvmTool
    @abbr = 'RSC'

    def initialize(name, &block)
        REQUIRE SCALA
        super
        REQUIRE "compile:#{name}"
    end

    def transform_target_path(path)
        pkg = JVM.grep_package(path)
        cln = nil
        res = FileArtifact.grep_file(path, /^object[ \t]+([a-zA-Z0-9_.]+)[ \t]*/)

        if res.length > 1
            raise "Ambiguous class name detection '#{res}'"
        elsif res.length == 1
            cln = res[0][:matched_part]
        else
            raise 'Class name cannot be detected'
        end

        return pkg.nil? ? cln : "#{pkg}.#{cln}"
    end

    def WITH
        @scala.scala
    end
end

