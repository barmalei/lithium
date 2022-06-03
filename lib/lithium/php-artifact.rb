require 'lithium/file-artifact/command'


class RunPhpScript < ExistentFile
    include OptionsSupport

    @abbr = 'RPH'

    def initialize(name, &block)
        OPTS('-f')
        super
    end

    def build
        raise 'Run PHP failed' if Artifact.exec('php', OPTS(), q_fullpath) != 0
    end

    def what_it_does() "Run PHP '#{@name}' script" end
end

#
#  Validate PHP script
#
class ValidatePhpScript < FileMask
    include OptionsSupport

    @abbr = 'VPH'

    def initialize(name, &block)
        OPTS('-l', '-f')
        super
    end

    def build_item(path, mt)
        raise "Invalid PHP '#{path}' script" if Artifact.exec('php', OPTS(), q_fullpath(path)) != 0
    end

    def what_it_does() "Validate PHP '#{@name}' script" end
end
