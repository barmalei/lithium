require 'lithium/file-artifact/command'
require 'lithium/utils'
require 'lithium/misc-artifact'

require 'pathname'

# Ruby environment
class RUBY < EnvArtifact
    include LogArtifactState
    include AutoRegisteredArtifact

    log_attr :libs

    def initialize(name)
        super

        @libs      ||= [ 'lib' ]
        @ruby_path ||= ''
        @libs.each { | path |
            path = File.join(homedir, path) if !Pathname.new(path).absolute?
            if File.directory?(path)
                @ruby_path = "#{@ruby_path} -I#{path}"
            else
                puts "Ruby library path '#{path}' cannot be found"
            end
        }

        path = File.join(homedir, '.lithium', 'lib')
        @ruby_path = "#{@ruby_path} -I#{path}" if File.directory?(path)
    end

    def ruby() "ruby #{@ruby_path}" end
    def build() end
    def what_it_does() "Initialize Ruby environment '#{@name}'\n    '#{@ruby_path}'" end
end

# Run ruby script
class RunRubyScript < FileCommand
    required RUBY

    def build()
        raise 'Run RUBY failed' if exec4(ruby().ruby, "'#{fullpath()}'", $lithium_args.join(' ')) != 0
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
        raise "Validation RUBY script '#{path}' failed" if exec4("ruby -c", "'#{fullpath(path)}'") != 0
    end

    def what_it_does() "Validate '#{@name}' script" end
end
