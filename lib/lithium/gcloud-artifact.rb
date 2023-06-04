require 'lithium/core-file-artifact'

class GCE < SdkEnvironmen
    @tool_name = 'gcloud'

    def gcloud
        tool_path(tool_name())
    end
end

class GoogleAppFile < ExistentFile
    @abbr = 'GAF'

    def initialize(name = nil, &block)
        app_file_path = [ 'appengine-web.xml', 'app.yaml' ].map { | app_file_name |
            if !name.nil? && app_file_name == File.basename(name)
                break fullpath(name)
            else
                target = "target/**/#{app_file_name}"
                paths  = Files.dir(target)
                paths  = paths.filter { | path | path.index('generated-sources').nil? } if paths.length > 0
                raise "Few '#{fp}' application XMLs were found by '#{target}' path" if paths.length > 1
                break paths[0] if paths.length == 1
            end
        }

        raise 'Application file cannot be detected' if app_file_path.nil? || app_file_path.length == 0
        super(app_file_path, &block)
        puts "Detected Google application file: '#{fullpath}'"
    end
end

class DeployGoogleApp < GoogleAppFile
    include OptionsSupport

    @abbr = 'DGA'

    def initialize(name, &block)
        REQUIRE GCE
        super
        OPT "--no-promote"
        OPTS($lithium_args) if $lithium_args.length > 0
    end

    def build
        super
        Files.execInTerm(homedir, command())
    end

    def command
        [ @gce.gcloud, 'app', 'deploy', fullpath, @gce.OPTS(), OPTS() ].join(' ')
    end

    def what_it_does
        "Deploy google app '#{name}'"
    end
end


# TODO: it is not completed
class DeployGoogleQueue < RunTool
    @abbr = 'DGQ'

    def initialize(name, &block)
        REQUIRE GCE
        super
    end

    def WITH
        @gce.gcloud
    end

    def WITH_OPTS(opts)
        opts.push('deploy')
    end

    def what_it_does
        "Deploy google queue '#{name}'"
    end
end
