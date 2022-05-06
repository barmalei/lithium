require 'lithium/core'
require 'lithium/properties'
require 'lithium/file-artifact/command'

class GCE < EnvArtifact
    include LogArtifactState
    include AutoRegisteredArtifact
    include OptionsSupport

    def initialize(name, &block)
        super
        @gce_home = File.dirname(File.dirname(FileArtifact.which('gcloud'))) unless @gce_home
        raise "GCE home ('#{@gce_home}') cannot be detected" if !@gce_home || !File.directory?(@gce_home)
        puts "GCE home '#{@gce_home}'"
    end

    def gcloud
        File.join(@gce_home, 'bin', 'gcloud')
    end

    def what_it_does() "Initialize GCE environment '#{@name}'" end
end

class GoogleAppFile < ExistentFile
    def initialize(name = nil, &block)
        app_file_path = [ 'appengine-web.xml' ].map { | app_file_name |
            if !name.nil? && app_file_name == File.basename(name)
                break fullpath(name)
            else
                target = "target/**/#{app_file_name}"
                paths  = FileArtifact.dir(target)
                paths  = paths.filter { | path | path.index('generated-sources').nil? } if paths.length > 0
                raise "Few '#{fp}' application XMLs were found by '#{target}' path" if paths.length > 1
                break paths[0] if paths.length == 1
            end
            break nil
        }

        raise 'Application file cannot be detected' if app_file_path.nil?
        super(app_file_path, &block)
        puts "Detected Google application file: '#{fullpath}'"
    end

    def self.abbr() 'GAF' end
end

class DeployGoogleApp < GoogleAppFile
    include OptionsSupport

    def initialize(name, &block)
        REQUIRE GCE
        super
        OPT "--no-promote"
        OPTS($lithium_args) if $lithium_args.length > 0
    end

    def build
        Artifact.execInTerm(homedir, command())
    end

    def command
        [ @gce.gcloud, 'app', 'deploy', fullpath, @gce.OPTS(), OPTS() ].join(' ')
    end

    def what_it_does
        "Deploy google app '#{name}'"
    end

    def self.abbr() 'DGA' end
end
