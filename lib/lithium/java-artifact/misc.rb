require 'lithium/core'
require 'lithium/java-artifact/base'

class GenerateJavaDoc < RunJavaTool
    def initialize(*args)
        super
        @source_as_file = true
        @destination ||= 'apidoc'
    end

    def destination
        dest = fullpath(@destination)
        return dest if File.directory?(dest)
        raise "Invalid destination directory '#{dest}'" if File.exists?(dest)
        return dest
    end

    def run_with
        @java.javadoc
    end

    def run_with_options(opts)
        opts.push('-d', destination())
        return opts
    end

    def clean
        dest = destination()
        FileUtils.rm_r(dest) unless File.directory?(dest)
    end

    def what_it_does
        "Generate javadoc to '#{destination()}' folder"
    end

    def self.abbr() 'JDC' end
end

class ShowClassMethods < JavaFileRunner
    def classpath
        super.JOIN(File.join($lithium_code, 'classes'))
    end

    def run_with_target(src)
        t = [ 'lithium.JavaTools', "methods:#{@shortname}" ]
        t.concat(super(src))
        return t
    end
end

class ShowClassModule < JavaFileRunner
    def classpath
        super.JOIN(File.join($lithium_code, 'classes'))
    end

    def run_with_target(src)
        t = [ 'lithium.JavaTools', "module:#{@shortname}" ]
        t.concat(super(src))
        return t
    end
end

class ShowClassField < JavaFileRunner
    def classpath
        super.JOIN(File.join($lithium_code, 'classes'))
    end

    def run_with_target(src)
        t = [ 'lithium.JavaTools', "field:#{@shortname}" ]
        t.concat(super(src))
        return t
    end
end

class FindInClasspath < FileCommand
    def initialize(*args)
        REQUIRE JAVA
        super
        @target ||= $lithium_args[0]
        @use_zipinfo = false
        @use_zipinfo = true unless FileArtifact.which('zipinfo').nil?
    end

    def build()
        unless @java.classpath.EMPTY?
            count = 0
            FindInClasspath.find(@use_zipinfo, @java.classpath, @target) { | path, item, is_jar |
                item_found(path, item, is_jar)
                count = count + 1
            }

            puts_warning "No item for '#{@target}' has been found" if count == 0
        else
            puts_warning 'Classpath is not defined'
        end
    end

    def item_found(path, item, is_jar)
        puts "    [#{path} => #{item}]"
        #puts "  {\n    \"item\": \"#{item}\",\n    \"path\": \"#{path}\"\n  }"
    end

    def FindInClasspath.find(use_zipinfo, classpath, target)
        classpath.paths.each { | path |
            if File.directory?(path)
                Dir.glob(File.join(path, '**', target)).each  { | item |
                    yield path, item, false
                }
            elsif path.end_with?('.jar') || path.end_with?('.zip')
                if use_zipinfo
                    FindInZip.find_with_zipinfo('zipinfo', path, "/" + target) { | item |
                        yield path, item, true
                    }
                else
                    FindInZip.find_with_jar('jar', path, "/" + target) { | item |
                        yield path, item, true
                    }
                end
            else
                puts_warning "File '#{path}' doesn't exist" unless File.exists?(path)
            end
        }
    end

    def what_it_does() "Looking for '#{@target}' in classpath" end
end

class FindClassInClasspath < FindInClasspath
    def initialize(*args)
        super
        raise 'Target class is not known' if @target.nil?
        @target = @target + '.class' unless @target.end_with?('.class')
    end

    def build
        Artifact.exec(
            @java.java, 
            '-classpath',
            "\"#{File.join($lithium_code, 'classes')}\"",
            'lithium.JavaTools',
            "class:#{@target}") 
        super
    end

    def item_found(path, item, is_jar)
        unless is_jar
            path = path + '/' if path[-1] != '/'
            item[path] = ''
        end
        super
    end

    def self.abbr() 'FCC' end
end

def SyncWarClasses(art, war_path)
    war_dir  = File.dirname(war_path)
    war_path = File.join($lithium_options['app_server_root'], war_path) if war_dir.nil? || war_dir == '.'

    raise "Invalid WAR path '#{war_path}'" unless File.directory?(war_path)
    dest = File.join(war_path, 'WEB-INF', 'classes')
    raise "Invalid WAR classpath path '#{dest}'" unless File.directory?(dest)

    art.list_dest_paths { | path, pkg |
        puts "Copy '#{path}' to '#{dest}'"

        FileArtifact.cpfile(path,
            File.join(dest, pkg.gsub('.', '/'))
        )
    }

    Touch.touch(File.join(war_path, 'WEB-INF', 'web.xml'))
    Touch.touch(File.join(war_path, '..', "#{File.basename(war_path)}.deployed"))
end