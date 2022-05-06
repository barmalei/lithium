require 'lithium/file-artifact/command'

class RUBYPATH < EnvArtifact
    include AssignableDependency
    include LogArtifactState
    include PATHS

    log_attr :paths

    def assign_me_to
       :add_rubypath
    end

    def expired?
        false
    end

    def build
    end
end

class DefaultRubypath < RUBYPATH
    def initialize(name, &block)
        super
        JOIN('lib') if block.nil? && File.exists?(File.join(path_base_dir, 'lib'))
    end
end

# Ruby environment
class RUBY < EnvArtifact
    include LogArtifactState
    include AutoRegisteredArtifact

    log_attr :ruby_home

    def initialize(name, &block)
        @ruby_paths = []
        REQUIRE DefaultRubypath
        super

        @ruby_home ||= nil
        if @ruby_home.nil?
            @ruby_home = FileArtifact.which('ruby')
            raise 'Ruby cannot be found' if @ruby_home.nil?
            @ruby_home = File.dirname(File.dirname(@ruby_home))
        end

        puts "Ruby home   : '#{@ruby_home}'\n     library: '#{rubypath}'"
    end

    def add_rubypath(rp)
        @ruby_paths.push(rp) if @ruby_paths.index(rp).nil?
    end

    def rubypath
        PATHS.new(project.homedir).JOIN(@ruby_paths)
    end

    def ruby() File.join(@ruby_home, 'bin', 'ruby') end

    def what_it_does() "Initialize Ruby environment '#{@name}'\n    '#{rubypath}'" end

    def self.abbr() 'RUB' end
end

# Run ruby script
class RunRubyScript < FileCommand
    include OptionsSupport

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
        raise "Running RUBY '#{@name}' script failed" if Artifact.exec(@ruby.ruby, OPTS(), cmd_rubypath, "\"#{fullpath}\"") != 0
    end

    def what_it_does() "Run '#{@name}' script" end

    def self.abbr() 'RRS' end
end

# Validate RUBY script
class ValidateRubyScript < FileMask
    include OptionsSupport

    def initialize(name, &block)
        REQUIRE RUBY
        OPT '-wc'
        super
    end

    def build_item(path, mt)
        puts "Validate '#{path}'"
        raise "Validation RUBY script '#{path}' failed" if Artifact.exec(@ruby.ruby, OPTS(), "\"#{fullpath(path)}\"") != 0
    end

    def what_it_does() "Validate '#{@name}' script" end

    def self.abbr() 'VRS' end
end
