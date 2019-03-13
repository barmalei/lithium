require 'lithium/file-artifact/command'


class RunPhpScript < FileCommand
    def build() raise 'Run PHP failed' if exec4("php", "-f", "'#{fullpath}'", $arguments.join(' ')) != 0 end
    def what_it_does() "Run PHP '#{@name}' script" end
end

#
#  Validate PHP script
#
class ValidatePhpScript < FileMask
    def build_item(path, mt)
        raise "Invalid PHP '#{path}' script" if exec4("php", "-l", "-f", "'#{fullpath(path)}'") != 0
    end

    def what_it_does() "Validate PHP '#{@name}' script" end
end

