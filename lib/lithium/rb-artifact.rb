require 'lithium/core-file-artifact'

class DefaultRubypath < EnvironmentPath
    def initialize(name, &block)
        super
        JOIN('lib') if block.nil? && File.exist?(File.join(homedir, 'lib'))
    end
end

# Ruby environment
class RUBY < SdkEnvironmen
    @tool_name = 'ruby'

    self.default_name(".env/RBV")

    def initialize(name, &block)
        REQUIRE DefaultRubypath
        super
    end

    def rubypath
        @paths.nil? || @paths.length == 0 ? nil : PATHS.new(homedir).JOIN(@paths)
    end

    def ruby
        tool_path(tool_name)
    end
end

# Run ruby script
class RunRubyScript < RunTool
    @abbr = 'RRS'

    def initialize(name, &block)
        REQUIRE RUBY
        super
    end

    def WITH
        @ruby.ruby
    end

    def WITH_OPTS
        super + rubypath()
    end

    #
    # Returns list of ruby paths
    # @return <array> list of ruby paths
    #
    def rubypath
        rpath = []
        @ruby.rubypath.paths.each { | path |
            if File.directory?(path)
                rpath.push("-I\"#{path}\"")
            else
                puts_warning "Ruby library path '#{path}' cannot be found"
            end
        }

        path = File.join(homedir, '.lithium', 'lib')
        rpath.push("-I\"#{path}\"") if File.directory?(path)
        return rpath
        #return rpath.join(' ')
    end

     def what_it_does() "Run '#{@name}' RUBY script" end
end

# Validate RUBY script
class ValidateRubyScript < RunTool
    @abbr = 'VRS'

    def initialize(name, &block)
        REQUIRE RUBY
        OPT '-wc'
        super
    end

    def WITH
        @ruby.ruby
    end

    def what_it_does
        "Validate '#{@name}' RUBY script"
    end
end
