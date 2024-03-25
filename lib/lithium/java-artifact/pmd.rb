require 'fileutils'

require 'lithium/java-artifact/runner'
require 'lithium/utils'

class PMD < SdkEnvironmen
    @tool_name = 'pmd'

    self.default_name(".env/PMD")

    def force_sdkhome_detection
        Files.assert_dir($lithium_code, 'ext', 'java', 'pmd')
    end

    def pmd
        tool_path(tool_name())
    end
end

class PmdCheckRunner < RunJvmTool
    def initialize(name, &block)
        REQUIRE PMD
        WITH_FORMAT('text')
        WITH_DEFAULT_RULE_SETS()
        super
    end

    def WITH
        @pmd.pmd
    end

    def WITH_FORMAT(frm)
        self['-f'] = frm
    end

    def WITH_DEFAULT_RULE_SETS
        WITH_RULE_SETS(File.join('rulesets', 'java', 'quickstart.xml'))
    end

    def WITH_RULE_SETS(rule)
        self['-R'] = rule
    end

    def WITH_COMMANDS
        [ 'check' ]
    end

    def classpath_opts
        cp = classpath()
        cp.EMPTY? ? [] : [ '--aux-classpath', cp ]
    end

    def error_exit_code?(ec)
        ec.exitstatus != 0 && ec.exitstatus != 4
    end
end

#  PMD code analyzer
class PmdCheckFiles < PmdCheckRunner
    include FromFileToolExecuter

    def transform_target_file(targets)
        targets
    end

    def transform_target_path(path)
        path
    end

    def WITH_OPTS
        super + [ '--file-list' ]
    end
end

class PmdCheckDir < PmdCheckRunner
    def WITH_OPTS
        super + [ '-d' ]
    end
end

class PmdCopyPasteDup < RunTool
    def initialize(name, &block)
        REQUIRE PMD
        WITH_LANGUAGE('java')
        WITH_MIN_TOKENS(100)
        super
    end

    def WITH_MIN_TOKENS(tokens)
        self['--minimum-tokens'] = tokens.to_s
    end

    def WITH_LANGUAGE(lang)
        self['--language'] = lang
    end

    def WITH
        @pmd.pmd
    end

    def WITH_COMMANDS
        [ 'cpd' ]
    end

    def WITH_OPTS
        super + [ '--dir' ]
    end

    def error_exit_code?(ec)
        ec.exitstatus != 0 && ec.exitstatus != 4
    end
end
