require 'lithium/core'
require 'lithium/file-artifact/acquired'
require 'lithium/file-artifact/command'

require 'rexml/parsers/pullparser'

class RunShell < FileCommand
    def build()
        raise "Script '#{@name}' running failed" if Artifact.exec('sh', fullpath) != 0
    end
end

# Validate XML
class ValidateXML < FileMask
    def build_item(path, mt)
        fp = fullpath(path)
        parser = REXML::Parsers::PullParser.new(File.new(fp, 'r'))
        raise "test ex"
        begin
            parser.each() { |res| }
        rescue Exception => ee
            puts_error("#{fp}:#{ee.line}: #{ee.to_s}")
        end
    end

    def what_it_does() "Validate '#{@name}' XML file(s)" end
end

class StringRunner < Artifact
    def initialize(*args, &block)
        @script = nil
        super
    end

    def build()
        raise 'Script string has not been defined' unless @script
        r = Artifact.exec(*cmd()) { | stdin, stdout, stderr, thread |
            stdin << @script
            stdin.close
        }
        raise 'Run string has failed' if r != 0
    end

    def what_it_does()
        formated, line = [], 1
        @script.each_line() { |l|
            formated << "  #{line}: #{l.strip}"
            line += 1
        }
        "Run string by #{self.class}: {\n#{formated.join("\n")}\n}\n\n"
    end

    def cmd() raise "Not implemented" end
end

