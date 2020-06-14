require 'lithium/java-artifact/runner'


class BuildVaadinSass < JavaFileRunner
    def initialize(*args)
        super

        @inputFile  = fullpath()
        @outputFile = @inputFile.dup
        @outputFile[/[.]scss$/] = '' if @outputFile.end_with?('scss')
        @outputFile = @outputFile + '.css'

        @arguments.push("'#{@inputFile}'", "'#{@outputFile}'")

        OPT('com.vaadin.sass.SassCompiler')
    end

    def what_it_does
        "Generate CSS:\n    from '#{@outputFile}'\n    to   '#{@inputFile}'"
    end
end

