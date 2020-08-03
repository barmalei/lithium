require 'lithium/core'
require 'lithium/file-artifact/command'

# DART
class DART < EnvArtifact
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

        raise "Python home ('#{@python_home}') cannot be detected" if !@python_home || !File.directory?(@python_home)
        raise "Python ('#{python()}') cannot be found"             unless File.file?(python()) 

        puts "Python home '#{@python_home}', pyname = #{@pyname}"

        # setup pypath
        @libs.each { | lib |
            lib = File.join(homedir, lib)       unless File.absolute_path?(lib)
            raise "Invalid lib path - '#{lib}'" unless File.directory?(lib)
            @pypath = @pypath ? lib + File::PATH_SEPARATOR + @pypath : lib
        }
        ENV['PYTHONPATH'] = @python_path
    end

    def python
        File.join(@python_home, 'bin', @pyname)
    end

    def what_it_does() "Initialize python environment '#{@name}'" end
end

#  Run dart
class RunDartCode < FileCommand
    include OptionsSupport

    def initialize(*args)
        REQUIRE DART
        OPT '-u'
        super
    end

    def build()
        raise "File '#{fullpath()}' cannot be found" unless File.exists?(fullpath())
        raise "Run #{self.class.name} failed" if Artifact.exec(@python.python, OPTS(), "\"#{fullpath}\"") != 0
    end

    def what_it_does() "Run '#{@name}' script" end

    def self.abbr() 'RPS' end
end


class LintDartCode < FileMask
    include OptionsSupport

    def build_item(path, mt)
        raise 'Pyflake python code validation failed' if Artifact.exec('pyflake', OPTS(), "\"#{fullpath(path)}\"") != 0
    end
end

