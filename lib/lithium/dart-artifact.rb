require 'lithium/core'
require 'lithium/file-artifact/command'

# DART
class DART < SdkEnvironmen
    @tool_name = 'dart'

    def initialize(name, &block)
        super
        @version = Artifact.grep_exec(dart, "--version", pattern:/version:\s+([0-9]+)\.([0-9]+)\.([0-9]+)/)
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

class ValidateDartCode < FileMask
    include OptionsSupport

    @abbr = 'VDC'

    def initialize(name, &block)
        REQUIRE DART
        super
    end

    def build_item(path, mt)
        puts "Validate '#{path}'"
        raise "Validation DART script '#{path}' failed" if Artifact.exec(@dart.dart, 'compile', 'jit-snapshot', OPTS(), q_fullpath(path)) != 0
    end

    def what_it_does() "Validate '#{@name}' DART code" end
end


#  Run dart
class RunDartCode < ExistentFile
    include OptionsSupport

    @abbr = 'RDS'

    def initialize(name, &block)
        REQUIRE DART
        super
    end

    def build
        super
        raise "Run #{self.class.name} failed" if Artifact.exec(@dart.dart, OPTS(), q_fullpath) != 0
    end

    def what_it_does() "Run '#{@name}' dart script" end
end

class PubspecFile < ExistentFile
    include LogArtifactState
    #include StdFormater
    include AssignableDependency

    @abbr = 'PSP'

    def initialize(name = nil, &block)
        REQUIRE DART
        name = homedir if name.nil?
        fp   = fullpath(name)
        pubspec  = FileArtifact.look_file_up(fp, 'pubspec.yaml', homedir)
        raise "Pubspec cannot be detected by '#{fp}' path" if pubspec.nil?
        super(pubspec, &block)
    end

    def assign_me_as
        [ :pubspec, false ]
    end
end

class RunDartPub < PubspecFile
    include OptionsSupport

    @abbr = 'RPS'

    def initialize(name, &block)
        super
        @targets ||= [ 'get' ]
    end

    def TARGETS(*args)
        @targets = []
        @targets.concat(args)
    end

    def expired?
        true
    end

    def build
        super
        path = fullpath
        chdir(File.dirname(path)) {
            if Artifact.exec(*command()).exitstatus != 0
                raise "Pub [#{@targets.join(',')}] running failed"
            end
        }
    end

    def command
        if @dart.version[0].to_i == 1
            return [ @dart.pub, OPTS(), @targets.join(' ') ]
        else
            return [ @dart.dart, 'pub', OPTS(), @targets.join(' ') ]
        end
    end

    def what_it_does
        "Run pub: '#{@name}'\n    Targets = [ #{@targets.join(', ')} ]\n    OPTS    = '#{OPTS()}'"
    end
end

class RunDartPubBuild < RunDartPub
    def initialize(name, &block)
        super
        TARGETS('build')
    end

    def command
        if @dart.version[0].to_i == 1
            return super
        else
            # TODO: option should be set in initialize, but @dart is resolved only on build stage
            OPT("--output web:build") if @dart.version[0].to_i > 1
            return [ 'webdev', @targets.join(' '), OPTS() ]
        end
    end
end

class RunDartPubGet < RunDartPub
    def initialize(name, &block)
        super
        TARGETS('get')
    end
end
