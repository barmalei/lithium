require 'lithium/core-file-artifact'
require 'lithium/std-core'

class TerraformRunner < RunTool
    include StdFormater

    def WITH
        'terraform'
    end

    def WITH_TARGETS
        [ ]
    end

    def build
        go_to_homedir()
        super()
    end

    def format(msg, level, parent)
        parent.format(msg.gsub(/\x1b\s*\[[0-9]+m/, ""), level, $STDOUT)
    end
end

class ValidateTf < TerraformRunner
    @abbr = 'VTF'

    def WITH_COMMANDS
        [ 'validate' ]
    end

    def what_it_does() "Validate terraform" end
end


class RunTf < TerraformRunner
    @abbr = 'RTF'

    def WITH_COMMANDS
        [ 'plan' ]
    end

    def what_it_does() "Plan terraform" end
end

