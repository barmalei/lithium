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

        puts("!!! Constructor PYTHON() #{self.object_id} #{self.owner}")

        fp_re           = /([^$^%|:;,<>]+)/
        @user_base      = Files.grep_exec(python(), ' -m site --user-base', pattern:fp_re)
        @user_site_base = Files.grep_exec(python(), ' -m site --user-site', pattern:fp_re)
    end

    def pypath
        @paths.nil? || @paths.length == 0 ? nil : PATHS.new(homedir).JOIN(@paths)
    end

    def python
        tool_path(tool_name())
    end

    # TODO: improve
    def pip
        if @pip_name.nil?
            m = /[a-zA-Z_]+([0-9.]+$)?/.match(tool_name())
            suffix = m[1]
            if suffix.nil?
                return tool_path('pip')
            else
                return tool_path("pip#{suffix}")
            end
        else
            return tool_path(@pip_name)
        end
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
    include ToolExecuter

    def initialize(name, &block)
        REQUIRE PYTHON
        super
        OPT('--upgrade')
    end

    def WITH
        @python.pip
    end

    def WITH_COMMANDS
        [ 'install' ]
    end

    def WITH_TARGETS
        [ File.basename(@name) ]
    end

    def build
        super()
        EXEC()
    end

    def expired?
        #ver = Files.grep_exec(@python.pip, 'show', File.basename(@name), pattern:/Version:\s*(.*)/)
        #return ver.nil?
        return false
    end

    def what_it_does
        "Deploy '#{@name}' python package"
    end
end

#  Run python
class RunPythonScript < RunTool
    @abbr = 'RPS'

    def initialize(name, &block)
        REQUIRE PYTHON
        OPT '-u'
        super
    end

    def WITH_TARGETS
        return [ @module_name ] unless @module_name.nil?
        return super()
    end

    def WITH
        @python.python
    end

    def pypath
        @python.pypath
    end

    def build
        pp = pypath()
        ENV['PYTHONPATH'] = pp.to_s unless pp.EMPTY?
        super
    end

    def what_it_does
        "Run '#{@name}' script"
    end
end

class RunPyFlake < RunTool
    include OptionsSupport

    def initialize(name, &block)
        REQUIRE PYTHON
        REQUIRE '.env/pyflakes', PipPackage
        super
    end

    def WITH
        File.join(@python.user_base(), 'bin', 'pyflakes')
    end
end

class RunPySetup < RunTool
    include OptionsSupport

    def initialize(name, &block)
        REQUIRE PYTHON
        OPT('install')
        super
    end

    def WITH_TARGETS
        [ File.dirname(fullpath) ]
    end

    def WITH
        @python.pip
    end
end

