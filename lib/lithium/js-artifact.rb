require 'fileutils'
require 'tmpdir'

require 'lithium/core'
require 'lithium/file-artifact/command'
require 'lithium/java-artifact/runner'
require 'lithium/file-artifact/acquired'

$NODEJS_MODULES_DIR = 'node_modules'

# node js  environment
class JS < EnvArtifact
    include AutoRegisteredArtifact
    include LogArtifactState

    log_attr :nodejs, :npm

    def initialize(name, &block)
        super

        @nodejs ||= FileArtifact.which('node')
        raise 'Node JS cannot be detected' if @nodejs.nil?

        @npm ||= FileArtifact.which('npm')
        raise 'Node JS npm cannot be detected' if @npm.nil?
    end

    def nodejs
        @nodejs
    end

    def npm
        @npm
    end

    def module_home(name)
        raise 'Name of module cannot be empty' if name.nil? || name.length == 0
        module_home = File.join(homedir, $NODEJS_MODULES_DIR, name)
        module_home = File.join(owner.homedir, $NODEJS_MODULES_DIR, name) unless File.exists?(module_home) || owner.nil?
        module_home = File.join($lithium_code, $NODEJS_MODULES_DIR, name) unless File.exists?(module_home)
        return module_home
    end

    def what_it_does
        "Initialize Node JS environment '#{@name}'"
    end
end

class NodeJsPackageFile < ExistentFile
    include LogArtifactState

    @abbr = 'NPF'

    def initialize(name = nil, &block)
        REQUIRE JS
        name         = homedir if name.nil?
        fp           = fullpath(name)
        packageFile  = FileArtifact.look_file_up(fp, 'package.json', homedir)
        raise "Package file cannot be detected by '#{fp}' path" if packageFile.nil?
        super(packageFile, &block)
    end
end

class InstallNodeJsPackage < NodeJsPackageFile
    include OptionsSupport

    @abbr = 'RNP'

    def initialize(name, &block)
        super
        @targets ||= [ 'install' ]
    end

    def TARGETS(*args)
        @targets = []
        @targets.concat(args)
    end

    def expired?
        true
    end

    def build
        path = fullpath
        raise "Target package JSON artifact cannot be found '#{path}'" unless File.exists?(path)
        target_dir = File.dirname(path)
        chdir(target_dir) {
            if Artifact.exec(*command()).exitstatus != 0
                raise "Pub [#{@targets.join(',')}] running failed"
            end
        }
    end

    def command
        [ @js.npm, OPTS(), @targets.join(' ') ]
    end

    def what_it_does
        "Run NPM '#{@name}'\n    Targets = [ #{@targets.join(', ')} ]\n    OPTS    = '#{OPTS()}'"
    end
end

# nodejs module
class NodejsModule < FileArtifact
    def initialize(name ,&block)
        REQUIRE JS

        unless File.absolute_path?(name)
            bn = File.basename(File.dirname(name))
            name = File.join($NODEJS_MODULES_DIR, name) if bn != $NODEJS_MODULES_DIR
        end

        super

        bn = File.basename(File.dirname(fullpath))
        if bn != $NODEJS_MODULES_DIR
            raise "Invalid module '#{fullpath}' path. '[<homedir>/]node_modules/<module-name>' path is expected"
        end
    end

    def build
        project.go_to_homedir
        puts "Install module in #{Dir.pwd} hd = #{project.go_to_homedir}"
        raise "Install of '#{@name}' nodejs module" if Artifact.exec(@js.npm, 'install', File.basename(fullpath)) != 0
    end

    def clean
        if File.exists?(fullpath)
            project.go_to_homedir
            raise "Install of '#{@name}' nodejs module" if Artifact.exec(@js.npm, 'uninstall', File.basename(fullpath)) != 0
        end
    end

    def expired?
        !File.exists?(fullpath)
    end

    def what_it_does
        "Install '#{File.basename(fullpath)}' nodejs module"
    end
end


# Run JS with nodejs
class RunNodejs < ExistentFile
    include OptionsSupport

    @abbr = 'RJS'

    def initialize(name, &block)
        REQUIRE JS
        super
    end

    def build
        raise "Running of '#{@name}' JS script failed" if Artifact.exec(@js.nodejs, OPTS(), q_fullpath) != 0
    end

    def what_it_does
        "Run JS '#{@name}' script with nodejs"
    end
end

# nodejs uglyfier
# @name : name of the uglified file
class UglifiedJSFile < GeneratedFile
    def initialize(name, &block)
        REQUIRE {
            JS()
            NodejsModule('uglify-js')
        }
        super
    end

    def build
        list = []
        list_sources_items { | source, from, from_m, dest |
            raise "Source from file '#{from}' doesn't exists or points to directory" unless File.file?(from)
            list.push(from)
        }

        raise 'Source list is empty' if list.length == 0
        validate_extension()
        project.go_to_homedir
        raise 'Uglifier has failed' if Artifact.exec(
            File.join(@js.module_home('uglify-js'), 'bin', 'uglifyjs'), 
            OPTS(), 
            list.map { | s |  "\"#{s}\"" }.join(' '), 
            '-o',
            q_fullpath
        ) != 0
    end

    def clean
        validate_extension
        super
    end

    def what_it_does
        "Uglifyjs (nodejs) #{@name}' JS script"
    end

    # to avoid name clash with JS source code
    def validate_extension
        fp = fullpath()
        raise "Minified file name '#{fp}' points to JS code" unless File.basename(fp).end_with?('.min.js')
    end
end


class CombinedJSFile < GeneratedFile
    def build
        list = []
        list_sources_items { | source, from, from_m, dest |
            raise "Source from file '#{from}' doesn't exist or points to directory" unless File.file?(from)
            list.push(from)
        }

        f = File.new(fullpath(), 'w')
        f.write("(function() {\n\n")

        list.each { | path |
            puts " combine with '#{path}'"
            f.write(File.readlines(path).join())
            f.write("\n\n")
        }

        f.write("\n\n})();")
        f.close()
    end

    def clean
       File.delete(fullpath()) if File.exists?(fullpath())
    end

    def what_it_does() "Combine JavaScript files into '#{@name}'" end
end

class JavaScriptDoc < FileArtifact
    def initialize(name, &block)
        REQUIRE {
            JS()
            NodejsModule('yuidocjs')
        }
        super
        @config   ||= nil
        @template ||= nil
        @input    ||= '.'
        raise 'Name has to be directory' unless File.directory?(fullpath)
    end

    def expired?
       !File.exists?(fullpath)
    end

    def clean
        FileUtils.rmtree(fullpath()) if File.directory?(fullpath())
    end

    def build
        p = fullpath()
        raise "Invalid artifact path '#{p}'" unless File.directory?(p)

        args = [ File.join(@js.module_home('yuidoc'), 'bin', 'yuidoc') , '-o ', p, '-n', '-C' ]

        unless @template.nil?
            t = fullpath(@template)
            raise "Invalid template path '#{t}'" unless File.directory?(t)
            args << '-t ' << t
        end

        unless @config.nil?
            c = fullpath(@config)
            raise "Invalid template path '#{c}'" unless File.file?(c)
            args << '-c ' << c
        end

        istmp = false
        i = fullpath(@input)
        raise "Invalid input path '#{i}'" unless File.exists?(i)
        unless File.directory?(i)
            tmp = Dir.mktmpdir()
            FileUtils.cp(i, tmp.to_s)
            i = tmp
            istmp = true
        end

        args << i

        Artifact.exec(*args)

        FileUtils.rmtree(i) if istmp
    end

    def what_it_does
        "Generate '#{@name}' JavaScript doc by '#{@input}'"
    end
end

class TypeScriptCompiler < FileMask
    include OptionsSupport

    def initialize(name, &block)
        REQUIRE JS
        super
    end

    def build
        go_to_homedir
        raise "Compilation of '#{@name}' has failed" if Artifact.exec('tsc', OPTS(), q_fullpath) != 0
    end

    def what_it_does
        "Compile typescript'#{@name}'"
    end
end


class JavaScriptHint < FileMask
    def initialize(name, &block)
        REQUIRE JS
        super
    end

    def build
        raise "Linting of '#{@name}' failed" if Artifact.exec('jshint', fullpath) != 0
    end

    def what_it_does
        "JavaScript lint '#{@name}'"
    end
end
