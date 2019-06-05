require 'pathname'

require 'lithium/core'
require 'lithium/file-artifact/command'
require 'lithium/misc-artifact'

#
# Python home
#
class PYTHON < EnvArtifact
    include LogArtifactState
    include AutoRegisteredArtifact

    log_attr :libs, :pypath, :python_home, :pyname

    def initialize(*args)
        super
        @libs   ||= []
        @pypath ||= ENV['PYTHONPATH']

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

        # setup pypath
        @libs.each { | lib |
            lib = File.join(homedir, lib)       unless Pathname.new(lib).absolute?()
            raise "Invalid lib path - '#{lib}'" unless File.directory?(lib)
            @pypath = @pypath ? lib + File::PATH_SEPARATOR + @pypath : lib
        }
        ENV['PYTHONPATH'] = @pypath
    end

    def python
        File.join(@python_home, 'bin', @pyname)
    end

    def what_it_does() "Initialize python environment '#{@name}'" end
end

#
#  Run python
#
class RunPythonScript < FileCommand
    REQUIRE PYTHON

    def build()
        raise "File '#{fullpath()}' cannot be found" unless File.exists?(fullpath())
        raise "Run #{self.class.name} failed" if Artifact.exec(@python.python, '-u', "\"#{fullpath}\"") != 0
    end

    def what_it_does() "Run '#{@name}' script" end
end

class RunPythonString < StringRunner
    REQUIRE PYTHON

    def cmd() [ @python.python,  '-' ] end
end


class ValidatePythonCode < FileMask
    def build_item(path, mt)
        raise 'Pyflake python code validation failed' if Artifact.exec('pyflake', "\"#{fullpath(path)}\"") != 0
    end
end

class ValidatePythonScript < FileCommand
    def build() raise 'Validation failed' unless ValidatePythonScript.validate(fullpath) end
    def what_it_does() "Validate '#{@name}' script" end

    def self.validate(path)
script = "
import py_compile, sys\n

try:\n
    py_compile.compile('#{path}', doraise=True)\n
except py_compile.PyCompileError:\n
    print sys.exc_info()[1]\n
    exit(1)
"
        exec "python", "-c", "\"#{script}\""
    end
end
