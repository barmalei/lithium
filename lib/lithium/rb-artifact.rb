require 'lithium/file-artifact/command'
require 'lithium/utils'
require 'lithium/misc-artifact'

require 'pathname'

# Ruby environment
class RUBY < Artifact
    include LogArtifactState
    include AutoRegisteredArtifact

    log_attr :libs

    def initialize(name)
        super

        # TODO: File.dirname($lithium_code) is ugly
        @libs ||=  (owner.nil? || owner.name != File.dirname($lithium_code) ? [ 'lib' ] : [ '.lithium/lib' ])
        @ruby_path = ''
        @libs.each { | path |
            path = "#{homedir()}/#{path}" if !Pathname.new(path).absolute?()
            raise "Invalid Ruby lib path - '#{path}'" if !File.directory?(path)
            @ruby_path = "#{@ruby_path} -I#{path}"
        }

    end

    def ruby() "ruby #{@ruby_path}" end
    def build() end
    def what_it_does() "Initialize Ruby environment '#{@name}'" end
end

# Run ruby script
class RunRubyScript < FileCommand
    required RUBY

    def build()
        raise 'Run RUBY failed' if exec4(ruby().ruby, "'#{fullpath()}'", $arguments.join(' ')) != 0
    end

    def what_it_does() "Run '#{@name}' script" end
end

class RunRubyString < StringRunner
    required RUBY
    def cmd() ruby().ruby end
end

# Validate RUBY script
class ValidateRubyScript < FileMask
    required RUBY

    def build_item(path, mt)
        puts "Validate '#{path}'"
        raise "Validation RUBY script '#{path}' failed" if exec4("ruby -c", "'#{fullpath(path)}'") {} != 0
    end

    def what_it_does() "Validate '#{@name}' script" end
end
