require 'lithium/java-artifact/base'

#
# ANT Environment
#
class ANT < SdkEnvironmen
    @tool_name = 'ant'

    def ant
        tool_path(tool_name())
    end
end

class AntFile < ExistentFile
    include LogArtifactState
    include AssignableDependency[:antfile]

    default_name('build.xml')

    @abbr = 'ANF'

    def expired?
        false
    end
end


# Simple ant runner
class RunANT < Artifact
    include ToolExecuter

    @abbr = 'RAN'

    default_name('.env/ant/build')

    def initialize(name = nil, &block)
        REQUIRE ANT
        REQUIRE AntFile
        super(name, &block)
    end

    def WITH
        @ant.ant
    end

    def WITH_TARGETS
        [ '-buildfile', @antfile.q_fullpath ] + super
    end

    def what_it_does
        "Run ANT '#{fullpath}'"
    end
end

