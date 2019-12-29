require 'fileutils'

require 'lithium/file-artifact/command'
require 'lithium/rb-artifact'

#
#   Tree top grammar compiler
#
class CompileTTGrammar < FileCommand
    def initialize(*args)
        REQUIRE RUBY
        super
        @output_dir ||= File.dirname(@name)
        @output_dir = fullpath(@output_dir)

        @tt_path ||= FileArtifact.which("tt")
        raise 'Cannot detect tree top grammar compiler' if !@tt_path || File.is_directory?(@tt_path)
        @tt_path = path
        raise "Undefined output directory '#{@output_dir}'" unless File.directory?(@output_dir)
    end

    def build_item(path, mt)
        # kill extension
        oname      = File.basename(path)
        ext        = File.extname(oname)
        oname[ext] = '.rb' if ext

        opath = File.join(@output_dir, oname)
        File.delete(opath) if File.exists?(opath)

        raise "Grammar '#{path}' compilation failed" if Artifact.exec(@ruby.ruby, @ruby.rpath, @tt, "\"#{fullpath(path)}\"", '-o', "\"#{opath}\"") != 0
    end

    def what_it_does() "Compile '#{@name}' tree top grammar to '#{@output_dir}'" end
end



