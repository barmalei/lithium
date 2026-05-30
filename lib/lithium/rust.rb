require 'lithium/core-file-artifact'


class CargoFile < ExistentFile
    include LogArtifactState
    include AssignableDependency[:cargo]

    default_name('Cargo.toml')

    def expired?
        false
    end
end


module CargoExecutor
    include ToolExecuter

    def WITH
        'cargo'
    end

    def build
        go_to_homedir
        EXEC()
        super
    end
end


# Run ruby script
class RunCargo < Artifact
    include CargoExecutor

    @abbr = 'RCR'
    @commands = [ 'run' ]

    def initialize(name, &block)
        super
        REQUIRE CargoFile
    end

    def expired?
        false
    end


    # def prepare
    #     path = Files.look_file_up(File.dirname(fullpath), 'Cargo.toml')
    #     chdir(File.dirname(path))
    # end

    def what_it_does() "Run '#{@name}' rust" end
end


class RunRust < RunTool
    def WITH
        puts fullpath
        path = File.basename(fullpath)
        path['.rs'] = ''
        return "./#{path}"
    end
end

class CompileRust < RunTool
    @abbr = 'RSC'
    @with = 'rustc'

    def initialize(name, &block)
        super
        REQUIRE CargoFile
    end

    def what_it_does() "Compile '#{@name}' rust" end
end
