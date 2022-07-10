require 'lithium/file-artifact/command'

class RUBYPATH < EnvArtifact
    include LogArtifactState
    include PATHS

    log_attr :paths

    def assign_me_as
       :add_rubypath
    end
end

class DefaultRubypath < RUBYPATH
    def initialize(name, &block)
        super
        JOIN('lib') if block.nil? && File.exists?(File.join(homedir, 'lib'))
    end
end

# Ruby environment
class RUBY < SdkEnvironmen
    @tool_name = 'ruby'
    @abbr      = 'RUB'

    def initialize(name, &block)
        REQUIRE DefaultRubypath
        super
    end

    def add_rubypath(rp)
        @ruby_paths ||= []
        @ruby_paths.push(rp) if @ruby_paths.index(rp).nil?
    end

    def rubypath
        @ruby_paths.nil? || @ruby_paths.length == 0 ? nil : PATHS.new(homedir).JOIN(@ruby_paths)
    end

    def ruby
        tool_path(tool_name())
    end
end

# Run ruby script
class RunRubyScript < ExistentFile
    include OptionsSupport

    @abbr = 'RRS'

    def initialize(name, &block)
        REQUIRE RUBY
        super
    end

    def rubypath
        @ruby.rubypath
    end

    def cmd_rubypath
        rpath = []
        rubypath.paths.each { | path |
            if File.directory?(path)
                rpath.push("-I\"#{path}\"")
            else
                puts_warning "Ruby library path '#{path}' cannot be found"
            end
        }

        path = File.join(homedir, '.lithium', 'lib')
        rpath.push("-I\"#{path}\"") if File.directory?(path)
        return rpath.join(' ')
    end

    def build
        raise "Running RUBY '#{@name}' script failed" if Artifact.exec(@ruby.ruby, OPTS(), cmd_rubypath, q_fullpath) != 0
    end

    def what_it_does() "Run '#{@name}' script" end
end

# Validate RUBY script
class ValidateRubyScript < FileMask
    include OptionsSupport

    @abbr = 'VRS'

    def initialize(name, &block)
        REQUIRE RUBY
        OPT '-wc'
        super
    end

    def build_item(path, mt)
        puts "Validate '#{path}'"
        raise "Validation RUBY script '#{path}' failed" if Artifact.exec(@ruby.ruby, OPTS(), q_fullpath(path)) != 0
    end

    def what_it_does() "Validate '#{@name}' script" end
end
