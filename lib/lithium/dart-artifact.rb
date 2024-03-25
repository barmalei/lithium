require 'lithium/core-file-artifact'

# DART
class DART < SdkEnvironmen
    @tool_name = 'dart'

    def initialize(name, &block)
        super
        @version = Files.grep_exec(dart, '--version', pattern:/version:\s+([0-9]+)\.([0-9]+)\.([0-9]+)/)
        puts "DART version = #{@version.join('.')}"
    end

    def dart
        tool_path(tool_name())
    end

    def version
        @version.dup
    end

    def pub
        tool_path('pub')
    end
end

class ValidateDartCode < RunTool
    @abbr = 'VDC'

    def initialize(name, &block)
        REQUIRE DART
        super
        OPTS('compile', 'jit-snapshot')
    end

    def WITH
        @dart.dart
    end

    def what_it_does
        "Validate '#{@name}' DART code"
    end
end

#  Run dart
class RunDartCode < RunTool
    @abbr = 'RDS'

    def initialize(name, &block)
        REQUIRE DART
        super
    end

    def WITH
        @dart.dart
    end

    def what_it_does
        "Run '#{@name}' dart script"
    end
end

class PubspecFile < ExistentFile
    include LogArtifactState
    #include StdFormater
    include AssignableDependency[:pubspec]

    @abbr = 'PSP'

    def initialize(name = nil, &block)
        name = File.join(homedir, 'pubspec.yaml') if name.nil?
        super(name, &block)
    end
end

class RunDartPub < Artifact
    include ToolExecuter

    default_name(".env/dart/pub")

    @abbr = 'RPS'

    def initialize(name, &block)
        REQUIRE PubspecFile
        REQUIRE DART
        super
        @targets ||= [ 'get' ]
    end

    def TARGETS(*args)
        @targets = []
        @targets.concat(args)
    end

    def WITH
        if @dart.version[0].to_i == 1
            @dart.pub
        else
            @dart.dart
        end
    end

    def WITH_OPTS
        if @dart.version[0].to_i == 1
            super
        else
            [ 'pub' ] + super
        end
    end

    def WITH_TARGETS
        @targets
    end

    def expired?
        true
    end

    def build
        super
        go_to_homedir
        EXEC()
    end

    def what_it_does
        "Run pub: '#{@name}'\n    Targets = [ #{@targets.join(', ')} ]\n    OPTS    = '#{OPTS()}'"
    end
end

class RunDartPubBuild < RunDartPub
    default_name('.env/dart/pub.build')

    def initialize(name, &block)
        super
        TARGETS('build')
    end

    def WITH_OPTS
        if @dart.version[0].to_i == 1
            super
        else
            [ '--output web:build' ] + super
        end
    end

    def WITH
        if @dart.version[0].to_i == 1
            super
        else
            'webdev'
        end
    end
end

class RunDartPubGet < RunDartPub
    default_name('.env/dart/pub.get')

    def initialize(name = nil, &block)
        super
        TARGETS('get')
    end
end
