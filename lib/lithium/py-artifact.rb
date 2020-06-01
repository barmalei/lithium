require 'lithium/core'
require 'lithium/file-artifact/command'
require 'lithium/misc-artifact'

class PYPATH < Artifact
    include AssignableDependency
    include LogArtifactState
    include PATHS

    log_attr :paths

    def assign_me_to
       :add_pypath
    end

    def expired?
        false
    end

    def build
    end
end

class DefaultPypath < PYPATH
    def initialize(*args, &block)
        super
        JOIN('lib') if block.nil? && File.exists?(File.join(path_base_dir, 'lib'))
    end
end

# Python home
class PYTHON < EnvArtifact
    include LogArtifactState
    include AutoRegisteredArtifact

    log_attr :python_home, :pyname

    def initialize(*args)
        @pypaths = []
        REQUIRE(DefaultPypath)
        super

        if !@python_home
            if @pyname
                python_path = FileArtifact.which(@pyname)
            else
                python_path = FileArtifact.which('python')
                if python_path
                    @pyname = 'python'
                else
                    python_path = FileArtifact.which('python3')
                    @pyname= 'python3' if python_path
                end
            end
            @python_home = File.dirname(File.dirname(python_path)) if python_path
        else
            @pyname ||= 'python'
        end

        raise "Python home ('#{@python_home}') cannot be detected" if !@python_home || !File.exists?(@python_home) || !File.directory?(@python_home)
        raise "Python ('#{python()}') cannot be found"             if !File.exists?(python()) || File.directory?(python())

        puts "Python home '#{@python_home}', pyname = #{@pyname}"
    end

    def add_pypath(pp)
        @pypaths.push(pp)  if @pypaths.index(pp).nil?
    end

    def pypath
        @pypaths.length == 0 ? nil : PATHS.new(project.homedir).JOIN(@pypaths)
    end

    def python()
        File.join(@python_home, 'bin', @pyname)
    end

    def what_it_does() "Initialize python environment '#{@name}'" end
end

#  Run python
class RunPythonScript < FileCommand
    include OptionsSupport

    def initialize(*args)
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
        raise "Run #{self.class.name} failed" if Artifact.exec(@python.python, OPTS(), "\"#{fullpath}\"") != 0
    end

    def what_it_does() "Run '#{@name}' script" end

    def self.abbr() 'RPS' end
end

class ValidatePythonCode < FileMask
    include OptionsSupport

    def initialize(*args)
        REQUIRE PYTHON
        super
    end

    def build_item(path, mt)
        raise 'Pyflake python code validation failed' if Artifact.exec('pyflake', OPTS(), "\"#{fullpath(path)}\"") != 0
    end
end

class ValidatePythonScript < FileCommand
    def initialize(*args)
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
