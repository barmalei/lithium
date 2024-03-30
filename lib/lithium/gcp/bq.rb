require 'lithium/core-file-artifact'

class GCE < SdkEnvironmen
    @tool_name = 'gcloud'

    def gcloud
        tool_path(tool_name())
    end
end

class BqRunner < ExistentFile
    include ToolExecuter

    def initialize(name, &block)
        super
        OPT('--use_legacy_sql=false')

        if self['project_id'].nil?
            m = FileArtifact.grep_file(fullpath(), /`([a-zA-Z0-9_\-]+)\.[a-zA-Z0-9_\-]+\.[a-zA-Z0-9_\-*]+`/)
            unless m.nil?
                prj = m[0][:matched_part]
                puts "BQ project was auto detected by SQL as '{prj}'"
                PROJECT_ID(prj)
            end
        end
    end

    def WITH
        'bq'
    end

    def WITH_COMMANDS
        [ 'query' ]
    end

    def transform_target_path(path)
        path
    end

    def WITH_TARGETS
        content = File.readlines(fullpath(), :encoding => 'UTF-8').join("\n")
        [ "< #{fullpath}" ]
    end

    def PROJECT_ID(project_id)
        OPT("--project_id=#{project_id}")
    end

    def build
        super()
        # for some reason in some cases line and an column numbers are located on the next line
        # the block below fixes the problem
        EXEC { | stdin, stdout, thread |
            buf = nil
            stdin.close()
            stdout.each { | line |
                if buf.nil?
                    buf = line
                else
                    if /^\[[0-9]+:[0-9]\]\n$/ =~ line
                        puts "#{buf.chomp} #{line}"
                    else
                        puts "#{buf}#{line}"
                    end
                    buf = nil
                end
            }
            puts buf unless buf.nil?
        }
    end
end

class ValidateBqSql < BqRunner
    @abbr = 'VBQ'

    def initialize(name, &block)
        super
        OPT('--dry_run')
    end
end

class RunBqSql < BqRunner
    @abbr = 'RBQ'

    def initialize(name, &block)
        super
        OPT('--format=sparse')
        OPT('--maximum_bytes_billed=100')
    end
end

