require 'fileutils'

require 'lithium/file-artifact/command'
require 'lithium/rb-artifact'

#
#   Tree top grammar compiler
#
class CompileTTGrammar < FileCommand
    required RUBY

    def initialize(*args)
        super
        @output_dir ||= File.dirname(@name)
        @output_dir = fullpath(@output_dir)

        path = FileArtifact.which("tt")
        raise 'Cannot detect tree top grammar compiler' if !path || File.is_directory?(path)
        @tt = path
        raise "Undefined output directory '#{@output_dir}'" if !File.directory?(@output_dir)
    end

    def build_item(path, mt)
        # kill extension
        oname      = File.basename(path)
        ext        = File.extname(oname)
        oname[ext] = '.rb' if ext

        opath = File.join(@output_dir, oname)
        File.delete(opath) if File.exists?(opath)

        raise "Grammar '#{path}' compilation failed" if Artifact.exec(ruby().ruby, ruby().rpath, @tt, "\"#{fullpath(path)}\"", '-o', "\"#{opath}\"") != 0
    end

    def what_it_does() "Compile '#{@name}' tree top grammar to '#{@output_dir}'" end
end



