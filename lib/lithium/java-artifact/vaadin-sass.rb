require 'lithium/java-artifact/runner'


class BuildVaadinSass < JavaFileRunner
    @abbr = 'BVS'

    def initialize(name, &block)
        super

        @inputFile  = fullpath()
        @outputFile = @inputFile.dup
        @outputFile[/[.]scss$/] = '' if @outputFile.end_with?('scss')
        @outputFile = @outputFile + '.css'

        @arguments.push("'#{@inputFile}'", "'#{@outputFile}'")

        OPT('com.vaadin.sass.SassCompiler')
    end
end

