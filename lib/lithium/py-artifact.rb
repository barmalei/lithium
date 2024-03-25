require 'lithium/core-file-artifact'

class DefaultPythonPath < EnvironmentPath
    def initialize(name, &block)
        super
        JOIN('lib') if block.nil? && File.exist?(File.join(homedir, 'lib'))
    end
end

# Python home
class PYTHON < SdkEnvironmen
    @tool_name = detect_tool_name('python3', 'python3.10', 'python', 'py')

    log_attr :pyname

    def initialize(name, &block)
        REQUIRE DefaultPythonPath
        super

        res = Files.grep_exec(pip(), 'list -v', pattern:/^([a-zA-Z_\-.0-9]+)\s+([^ ]+)\s+(.*)\s+pip$/, find_first:false)

        #
        # { <mod_name> => {  path: '', version: ''}}
        #
        @modules = {}
        unless res.nil?
          res.each { | e |
            @modules[e[0]] = {
                'path'    => e[2].gsub('\\', '/'),
                'version' => e[1]
            }
          }
        end
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

    def modules(nm = nil)
        nm.nil? ? @modules : @modules[nm]
    end

    def user_base
        @user_base
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

    def required_was_created(req)
        if req.kind_of?(PYTHON)
            @module_name = File.basename(@name)
            m = @python.modules(@module_name)
            unless m.nil?
                @module_ver  = m['version']
                @module_path = File.join(m['path'], @module_name)
            else
                @module_ver  = nil
                @module_path = nil
            end
        end
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
        #raise "#{p} file exists" if File.file?(p)
        # name of package can be different to the name it really stored in file system
        # p = File.join(@python.user_site_base, n.gsub(/-/, '_')) unless File.exist?(p)
        # raise "#{p} file exists" if File.file?(p)

        @module_name.nil? || !File.directory?(@module_path)

        #ver = Files.grep_exec(@python.pip, 'show', File.basename(@name), pattern:/Version:\s*(.*)/)
        #return ver.nil?
        #return false
    end

    def what_it_does
        "Install '#{@name}' python package"
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
        m = @python.modules('pyflakes')
        p = m['path']
        if File::PATH_SEPARATOR == ';'
            File.join(File.dirname(p), 'Scripts', 'pyflakes')
        else
            File.join(File.expand_path("../../..", p), 'bin', 'pyflakes')
        end
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
