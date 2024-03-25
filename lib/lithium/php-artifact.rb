require 'lithium/core-file-artifact'

class RunPhpScript < RunTool
    @abbr = 'RPH'

    def initialize(name, &block)
        OPTS('-f')
        super
    end

    def WITH
        'php'
    end

    def what_it_does() "Run '#{@name}' PHP  script" end
end

#
#  Validate PHP script
#
class ValidatePhpScript < RunTool
    @abbr = 'VPH'

    def initialize(name, &block)
        OPTS('-l', '-f')
        super
    end

    def WITH
        'php'
    end

    def what_it_does() "Validate '#{@name}' PHP script" end
end
