require 'lithium/file-artifact/command'
require 'lithium/misc-artifact'

require 'pathname'

# Ruby environment
class RUBY < EnvArtifact
    include LogArtifactState
    include AutoRegisteredArtifact

    log_attr :libs, :ruby_home

    def initialize(name)
        super
        @libs      ||= [ 'lib' ]
        @ruby_home ||= nil
        if @ruby_home.nil?
            @ruby_home = FileArtifact.which('ruby')
            raise 'Ruby cannot be found' if @ruby_home.nil?
            @ruby_home = File.dirname(File.dirname(@ruby_home))
        end

        puts "Ruby home   : '#{@ruby_home}'\n     library: '#{rpath}'"
    end

    def rpath()
        rpath = []
        @libs.each { | path |
            path = File.join(homedir, path) unless Pathname.new(path).absolute?
            if File.directory?(path)
                rpath.push("-I#{path}")
            else
                puts_warning "Ruby library path '#{path}' cannot be found"
            end
        }

        path  = File.join(homedir, '.lithium', 'lib')
        rpath.push("-I#{path}")  if File.directory?(path)
        return rpath.join(' ')
    end

    def ruby() File.join(@ruby_home, 'bin', 'ruby') end

    def what_it_does() "Initialize Ruby environment '#{@name}'\n    '#{rpath}'" end
end

# Run ruby script
class RunRubyScript < FileCommand
    REQUIRE RUBY

    include OptionsSupport

    def build()
        raise "Running RUBY '#{@name}' script failed" if Artifact.exec(@ruby.ruby, OPTS(), @ruby.rpath, "\"#{fullpath}\"") != 0
    end

    def what_it_does() "Run '#{@name}' script" end
end

class RunRubyString < StringRunner
    REQUIRE RUBY

    def cmd() @ruby.ruby end
end

# Validate RUBY script
class ValidateRubyScript < FileMask
    REQUIRE RUBY

    include OptionsSupport

    def initialize(*args)
        OPT '-c'
        super
    end

    def build_item(path, mt)
        puts "Validate '#{path}'"
        raise "Validation RUBY script '#{path}' failed" if Artifact.exec(@ruby.ruby, OPTS(), "\"#{fullpath(path)}\"") != 0
    end

    def what_it_does() "Validate '#{@name}' script" end
end
