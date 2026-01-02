require 'lithium/py'


# Python home
class UV < SdkEnvironmen
    @tool_name = 'uv'

    log_attr :pyname

    def initialize(name, &block)
        REQUIRE DefaultPythonPath
        super
    end

    def pypath
        @paths.nil? || @paths.length == 0 ? nil : PATHS.new(homedir).JOIN(@paths)
    end

    def uv
        tool_path(tool_name())
    end
end

module UvExecutor
    include ToolExecuter

    def WITH
        @uv.uv
    end

    def build
        go_to_homedir
        EXEC()
        super
    end
end

class UvLockFile < LoggedFileArtifact
    @abbr = 'UVL'

    include LogArtifactState
    include AssignableDependency[:lock]
    include UvExecutor

    default_name('uv.lock')

    def initialize(name, &block)
        REQUIRE UV
        REQUIRE '**/*/pyproject.toml', LoggedFileMask
        REQUIRE 'pyproject.toml', LoggedFileArtifact
        super
    end

    def WITH_COMMANDS
        [ 'sync' ]
    end
end


class UvRun < RunTool
    @abbr = 'RUV'

    def initialize(name, &block)
        REQUIRE UV
        super
    end

    def WITH
        @uv.uv
    end

    def WITH_COMMANDS
        [ 'run' ]
    end

    def what_it_does
        "Run '#{@name}' script with UV"
    end
end


class UvRunTest < UvRun
    def WITH_COMMANDS
        [ 'run', 'pytest' ]
    end

    def what_it_does
        "Run '#{@name}' pytest with UV"
    end
end

class UvRunBlackTool < UvRun
    def WITH_COMMANDS
        [ 'tool', 'run', 'black' ]
    end
end

