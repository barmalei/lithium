require 'lithium/core'
require 'lithium/file-artifact/command'

class PYPATH < EnvArtifact
    include LogArtifactState
    include PATHS

    log_attr :paths

    def assign_me_as
        [ :pypaths, true ]
    end
end

class DefaultPypath < PYPATH
    def initialize(name, &block)
        super
        JOIN('lib') if block.nil? && File.exists?(File.join(homedir, 'lib'))
    end
end

# Python home
class PYTHON < SdkEnvironmen
    @tool_name = 'python3'

    log_attr :pyname

    def initialize(name, &block)
        REQUIRE(DefaultPypath)
        super
    end

    def pypath
        @pypaths.nil? || @pypaths.length == 0 ? nil : PATHS.new(homedir).JOIN(@pypaths)
    end

    def python
        tool_path(tool_name())
    end

    def tool_name
        @pyname.nil? ? super : @pyname
    end
end

#  Run python
class RunPythonScript < ExistentFile
    include OptionsSupport

    @abbr = 'RPS'

    def initialize(name, &block)
        REQUIRE PYTHON
        OPT '-u'
        super
    end

    def pypath
        @python.pypath
    end

    def build
        raise "File '#{fullpath()}' cannot be found" unless File.exists?(fullpath())
        pp = pypath()
        ENV['PYTHONPATH'] = pp.to_s unless pp.EMPTY?
        raise "Run #{self.class.name} failed" if Artifact.exec(@python.python, @python.OPTS(), OPTS(), q_fullpath) != 0
    end

    def what_it_does() "Run '#{@name}' script" end
end

class ValidatePythonCode < FileMask
    include OptionsSupport

    def initialize(name, &block)
        REQUIRE PYTHON
        super
    end

    def build_item(path, mt)
        raise 'Pyflake python code validation failed' if Artifact.exec('pyflake', OPTS(), q_fullpath(path)) != 0
    end
end

class ValidatePythonScript < ExistentFile
    def initialize(name, &block)
        REQUIRE PYTHON
        super
    end

    def build()
script = "
import py_compile, sys\n

try:\n
    py_compile.compile('#{fullpath}', doraise=True)\n
except py_compile.PyCompileError:\n
    print sys.exc_info()[1]\n
    exit(1)
"
        raise 'Validation failed' unless exec(@python.python, '-c', "\"#{script}\"")
    end

    def what_it_does() "Validate '#{@name}' script" end
end
