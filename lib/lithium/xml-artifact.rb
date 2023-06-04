require 'lithium/core-file-artifact'
require 'rexml/parsers/pullparser'

# Validate XML
class ValidateXML < FileMask
    def build_item(path, mt)
        fp = fullpath(path)
        parser = REXML::Parsers::PullParser.new(File.new(fp, 'r'))
        begin
            parser.each { |res| }
        rescue Exception => ee
            puts_error("#{fp}:#{ee.line}: #{ee.to_s}")
        end
    end

    def what_it_does() "Validate '#{@name}' XML file(s)" end
end

