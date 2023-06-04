require 'lithium/core-file-artifact'

class DefaultPythonPath < EnvironmentPath
    def initialize(name, &block)
        super
        JOIN('lib') if block.nil? && File.exist?(File.join(homedir, 'lib'))
    end
end

# Python home
class PYTHON < SdkEnvironmen
    @tool_name = detect_tool_name('python3', 'python')

    log_attr :pyname

    def initialize(name, &block)
        REQUIRE DefaultPythonPath
        super
        fp_re = /([^$^%|$:;,<>]+)/
        @user_base      = Files.grep_exec(python(), ' -m site --user-base', pattern:fp_re)
        @user_site_base = Files.grep_exec(python(), ' -m site --user-site', pattern:fp_re)
    end

    def pypath
        @paths.nil? || @paths.length == 0 ? nil : PATHS.new(homedir).JOIN(@paths)
    end

    def python
        tool_path(tool_name())
    end

    def pip
        tool_name.end_with?('3') ? tool_path('pip3') : tool_path('pip3')
    end

    def user_base
        @user_base
    end

    def user_site_base
        @user_site_base
    end

    def tool_name
        @pyname.nil? ? super : @pyname
    end
end

class PipPackage < EnvArtifact
    def initialize(name, &block)
        REQUIRE PYTHON
        super
    end

    def build
        raise "Fail to install #{@name} python package" if Files.exec(@python.pip, 'install --upgrade', File.basename(@name)).exitstatus != 0
    end

    def expired?
        n = File.basename(@name)
        p = File.join(@python.user_site_base, n)
        raise "#{p} file exists" if File.file?(p)

        # name of package can be different to the name it really stored in file system
        p = File.join(@python.user_site_base, n.sub(/-/, '_')) unless File.exist?(p)
        raise "#{p} file exists" if File.file?(p)

        !File.directory?(p)
    end

    def what_it_does
        "Deploy '#{@name}' python package"
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
        super
        pp = pypath()
        ENV['PYTHONPATH'] = pp.to_s unless pp.EMPTY?
        raise "Run #{self.class.name} failed" if Files.exec(@python.python, @python.OPTS(), OPTS(), q_fullpath) != 0
    end

    def what_it_does() "Run '#{@name}' script" end
end

class RunPyFlake < FileMask
    include OptionsSupport

    def initialize(name, &block)
        REQUIRE PYTHON
        REQUIRE '.env/pyflakes', PipPackage
        super
    end

    def build_item(path, mt)
        pyf  = File.join(@python.user_base(), 'bin', 'pyflakes')
        code = Files.exec(pyf, OPTS(), q_fullpath(path)).exitstatus
        raise 'Pyflake python code validation could not be started' if code != 0 && code != 1
    end
end

class ValidatePythonScript < ExistentFile
    def initialize(name, &block)
        REQUIRE PYTHON
        super
    end

    def build
        super
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


