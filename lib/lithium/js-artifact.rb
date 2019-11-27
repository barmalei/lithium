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

    attr_reader :nodejs, :npm

    def initialize(*args)
        super

        @nodejs ||= FileArtifact.which('node')
        raise 'Node JS cannot be detected' if @nodejs.nil?

        @npm ||= FileArtifact.which('npm')
        raise 'Node JS npm cannot be detected' if @npm.nil?
    end

    def nodejs()
        return @nodejs
    end

    def npm()
        return @npm
    end

    def module_home(name)
        raise 'Name of module cannot be empty' if name.nil? || name.length == 0
        module_home = File.join(homedir, $NODEJS_MODULES_DIR, name)
        module_home = File.join(owner.homedir, $NODEJS_MODULES_DIR, name) if     !File.exists?(module_home) && !owner.nil?
        module_home = File.join($lithium_code, $NODEJS_MODULES_DIR, name) unless File.exists?(module_home)
        return module_home
    end

    def what_it_does() "Initialize Node JS environment '#{@name}'" end

    def expired?
        return false
    end
end

# nodejs module
class NodejsModule < FileArtifact
    REQUIRE JS

    def initialize(name, &block)
        puts "1)    ------ #{name}"
        puts "2)    ------ #{project.homedir}"

        unless Pathname.new(name).absolute?

            bn = File.basename(File.dirname(name))
            name = File.join($NODEJS_MODULES_DIR, name) if bn != $NODEJS_MODULES_DIR
        end
        super(name, &block)

#        puts "3)    ------ #{fullpath}"

        bn = File.basename(File.dirname(fullpath))
        if bn != $NODEJS_MODULES_DIR
            raise "Invalid module '#{fullpath}' path. '[<homedir>/]node_modules/<module-name>' path is expected"
        end
    end

    def build()
        project.go_to_homedir
        puts "Install module in #{Dir.pwd} hd = #{project.go_to_homedir}"
        raise "Install of '#{@name}' nodejs module" if Artifact.exec(@js.npm, 'install', File.basename(fullpath)) != 0
    end

    def expired?
        puts "---------- #{fullpath}"
        return !File.exists?(fullpath)
    end

    def clean()
        if File.exists?(fullpath)
            project.go_to_homedir
            raise "Install of '#{@name}' nodejs module" if Artifact.exec(@js.npm, 'uninstall', File.basename(fullpath)) != 0
        end
    end

    def what_it_does()
        return "Install '#{File.basename(fullpath)}' nodejs module"
    end
end

module NPM
    def NPM(name)
        return REQUIRE("NodejsModule:#{name}")
    end
end

# Run JS with nodejs
class RunNodejs < FileCommand
    REQUIRE JS

    def build()
        raise "Running of '#{@name}' JS script failed" if Artifact.exec(@js.nodejs, "\"#{fullpath}\"") != 0
    end

    def what_it_does()
        "Run JS '#{@name}' script with nodejs"
    end
end

# nodejs uglyfier
class UglifiedJSFile < ArchiveFile
    extend NPM

    REQUIRE(JS)

    NPM('uglify-js').OWN.TO('uglify')

    include OptionsSupport

    def generate(path, dest_dir, list)
        validate_extension()
        project.go_to_homedir
        return Artifact.exec(File.join(@uglify.fullpath, 'bin', 'uglifyjs'), OPTS(), list.join(' '), '-o', fullpath)
    end

    def expired?()
       return !File.exists?(fullpath)
    end

    def clean()
        validate_extension()
        File.delete(fullpath()) if File.exists?(fullpath())
    end

    def list_items(rel = nil)
        if @sources.length == 0
            fp     = fullpath()
            bn     = File.basename(fp)
            suffix = '.min.js'
            i      = bn.rindex(suffix)

            raise "JS minified file '#{bn}' cannot be used to detect input JS file" if i.nil? || i != (bn.length - suffix.length)
            bn = bn[0, i + 1] + 'js'
            fp = File.join(File.dirname(fp), bn);
            raise "Auto-detected input JS file '#{fp}' doesn't exists or points to directory" if !File.exists?(fp) || File.directory?(fp)
            yield fp, File.mtime(fp).to_i, nil
        else
            super(rel)
        end
    end

    def what_it_does()
        "Uglifyjs (nodejs) #{@name}' JS script"
    end

    # to avoid name clash with JS source code
    def validate_extension()
        bn  = File.basename(fullpath)
        ext = File.extname(bn)
        return if ext.downcase != '.js'
        bn = bn[0..(bn.length - ext.length + 1)]
        ext = File.extname(bn)
        raise "Minified file name '#{fullpath}' points to JS code" if ext.nil? || ext.length == 0
    end
end


class CombinedJSFile < ArchiveFile
    def generate(path, dest_dir, list)
        f = File.new(fullpath(), 'w')
        f.write("(function() {\n\n")

        list.each { | path |
            puts " combine with '#{path}'"
            f.write(File.readlines(path).join())
            f.write("\n\n")
        }

        f.write("\n\n})();")
        f.close()

        return 0;
    end

    def expired?()
       return !File.exists?(fullpath)
    end

    def clean()
       File.delete(fullpath()) if File.exists?(fullpath())
    end

    def what_it_does() "Combine JavaScript files into '#{@name}'" end
end

class JavaScriptDoc < FileArtifact
    REQUIRE JS

    def initialize(name)
        super
        @config   ||= nil
        @template ||= nil
        @input    ||= '.'
        raise 'Name has to be directory' if File.exists?(fullpath) && !File.directory?(fullpath)

        REQUIRE('npm:yuidocjs')
    end

    def expired?()
       return !File.exists?(fullpath)
    end

    def clean()
        FileUtils.rmtree(fullpath()) if File.exists?(fullpath()) && File.directory?(fullpath())
    end

    def build
        p = fullpath()
        raise "Invalid artifact path '#{p}'" if File.exists?(p) && !File.directory?(p)

        args = [ File.join(@js.module_home('yuidoc'), 'bin', 'yuidoc') , '-o ', p, '-n', '-C' ]

        unless @template.nil?
            t = fullpath(@template)
            raise "Invalid template path '#{t}'" if !File.exists?(t) || !File.directory?(t)
            args << '-t ' << t
        end

        unless @config.nil?
            c = fullpath(@config)
            raise "Invalid template path '#{c}'" if !File.exists?(c) || File.directory?(c)
            args << '-c ' << c
        end

        istmp = false
        i = fullpath(@input)
        raise "Invalid input path '#{i}'" if !File.exists?(i)
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

    def what_it_does()
        "Generate '#{@name}' JavaScript doc by '#{@input}'"
    end
end

class CompileTypeScript < FileMask
end


class JavaScriptHint < FileMask
    REQUIRE JS

    def build()
        raise "Linting of '#{@name}' failed" if Artifact.exec('jshint', fullpath) != 0
    end

    def what_it_does()
        return "JavaScript lint '#{@name}'"
    end
end
