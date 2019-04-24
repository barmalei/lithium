require 'pathname'

require 'lithium/core'
require 'lithium/file-artifact/command'
require 'lithium/utils'
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
                python_path = FileUtil.which(@pyname)
            else
                python_path = FileUtil.which("python")
                if python_path
                    @pyname = "python"
                else
                    python_path = FileUtil.which("python3")
                    @pyname= "python3" if python_path
                end
            end
            @python_home = File.dirname(File.dirname(python_path)) if python_path
        else
            @pyname ||= "python"
        end

        raise "Python home ('#{@python_home}') cannot be detected" if !@python_home || !File.exists?(@python_home) || !File.directory?(@python_home)
        raise "Python ('#{python()}') cannot be found"             if !File.exists?(python()) || File.directory?(python())

        puts "Python home '#{@python_home}', pyname = #{@pyname}"

        # setup pypath
        @libs.each { | lib |
            lib = "#{homedir()}/#{lib}" if !Pathname.new(lib).absolute?()
            raise "Invalid lib path - '#{lib}'" if !File.directory?(lib)
            @pypath = @pypath ? lib + File::PATH_SEPARATOR + @pypath : lib
        }
        ENV['PYTHONPATH'] = @pypath
    end

    def python
        File.join(@python_home, 'bin', @pyname)
    end

    def build() end
    def what_it_does() "Initialize python environment '#{@name}'" end
end

#
#  Run python
#
class RunPythonScript < FileCommand
    required PYTHON

    def build()
        raise "File '#{fullpath()}' cannot be found" if !File.exists?(fullpath())
        raise "Run #{self.class.name} failed" if exec4("#{python().python} -u", "'#{fullpath()}'", $lithium_args.join(' '))  != 0
    end

    def what_it_does() "Run '#{@name}' script" end
end

class RunPythonString < StringRunner
    required PYTHON

    def cmd() "#{python.python} -" end
end


class ValidatePythonCode < FileMask
    def build_item(path, mt)
        raise 'Pyflake python code validation failed' if exec4("pyflake", "'#{fullpath(path)}'") != 0
    end
end

class ValidatePythonScript < FileCommand
    def build() raise "Validation failed" unless ValidatePythonScript.validate(fullpath()) end
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
        exec4 "python", "-c", "\"#{script}\""
    end
end
