require 'lithium/core'
require 'lithium/file-artifact/command'

# DART
class DART < EnvArtifact
    include LogArtifactState
    include AutoRegisteredArtifact

    log_attr :dart_home

    def initialize(name, &block)
        super
        @dart_home = File.dirname(File.dirname(FileArtifact.which('dart'))) unless @dart_home
        raise "DART home ('#{@dart_home}') cannot be detected" if !@dart_home || !File.directory?(@dart_home)
        puts "DART home '#{@dart_home}'"
    end

    def dart
        File.join(@dart_home, 'bin', 'dart')
    end

    def pub
        File.join(@dart_home, 'bin', 'pub')
    end

    def what_it_does() "Initialize DART environment '#{@name}'" end
end

#  Run dart
class RunDartCode < FileCommand
    include OptionsSupport

    def initialize(name, &block)
        REQUIRE DART
        super
    end

    def build()
        raise "File '#{fullpath()}' cannot be found" unless File.exists?(fullpath())
        raise "Run #{self.class.name} failed" if Artifact.exec(@dart.dart, OPTS(), "\"#{fullpath}\"") != 0
    end

    def what_it_does() "Run '#{@name}' dart script" end

    def self.abbr() 'RDS' end
end


class PubspecFile < ExistentFile
    include LogArtifactState
    include StdFormater
    include AssignableDependency

    def initialize(name = nil, &block)
        REQUIRE DART
        name = homedir if name.nil?
        fp   = fullpath(name)
        pubspec  = FileArtifact.look_file_up(fp, 'pubspec.yaml', homedir)
        raise "Pubspec cannot be detected by '#{fp}' path" if pubspec.nil?
        super(pubspec, &block)
    end

    def assign_me_to
        'pubspec'
    end

    def self.abbr() 'PSP' end
end

class RunDartPub < PubspecFile
    include OptionsSupport

    def initialize(name, &block)
        super
        @targets ||= [ 'get' ]
    end

    def expired?
        true
    end

    def TARGETS(*args)
        @targets = []
        @targets.concat(args)
    end

    def build
        path = fullpath
        raise "Target pub artifact cannot be found '#{path}'" unless File.exists?(path)
        chdir(File.dirname(path)) {
            if Artifact.exec(@dart.pub, OPTS(), @targets.join(' ')).exitstatus != 0
                raise "Pub [#{@targets.join(',')}] running failed"
            end
        }
    end

    def what_it_does
        "Run pub: '#{@name}'\n    Targets = [ #{@targets.join(', ')} ]\n    OPTS    = '#{OPTS()}''"
    end

    def self.abbr() 'RPS' end
end

class RunDartPubBuild < RunDartPub
    def initialize(name, &block)
        super
        TARGETS('build')
    end
end
