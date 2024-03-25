require 'lithium/core-file-artifact'

#
#   Tree top grammar compiler
#
# TODO: should be revised
class CompileTTGrammar < RunTool
    @abbr = 'CTT'

    def initialize(name, &block)
        REQUIRE RUBY
        super
        # TODO: can be replaced with destination dir
        @output_dir ||= File.dirname(@name)
        @output_dir = fullpath(@output_dir)

        @tt_path ||= Files.which("tt")
        raise 'Cannot detect tree top grammar compiler' if !@tt_path || File.is_directory?(@tt_path)
        @tt_path = path
        raise "Undefined output directory '#{@output_dir}'" unless File.directory?(@output_dir)
    end

    def WITH
        @ruby.ruby
    end

    def WITH_OPTS
        rubypath() + [ @tt ] + super
    end

    def WITH_ARGS
        [ '-o' ] + super + [ "\"#{output_path()}\"" ]
    end

    def build
        opath = output_path()
        File.delete(opath) if File.exist?(opath)
        super
    end

    def output_path
        oname      = File.basename(path)
        ext        = File.extname(oname)
        oname[ext] = '.rb' if ext
        return File.join(@output_dir, oname)
    end

    def what_it_does
        "Compile '#{@name}' tree top grammar to '#{@output_dir}'"
    end
end
