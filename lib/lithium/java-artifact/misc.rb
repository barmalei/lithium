require 'lithium/core'
require 'lithium/java-artifact/base'
require 'lithium/utils'

class GenerateJavaDoc < FileArtifact
    include LogArtifactState
    required JAVA

    def initialize(*args)
        super
        @sources ||= 'src/java'
        raise "Source dir '#{@sources}' cannot be found" if !File.directory?(fullpath(@sources))

        if !@pkgs
            puts_warning 'Package list has not been specified. Build it automatically.'
            @pkgs = []

            Dir.chdir(fullpath(@sources))
            Dir["**/*"].each { | n |
                next if n =~ /CVS$/ || n =~ /[.].*/
                @pkgs << n if File.directory?(n)

            }
        end

        raise "Packages have not been identified" if @pkgs.length == 0

        @pkgs.each() { |p|
            p = fullpath(File.join(@sources, p.tr('.', '/')))
            raise "Package '#{p}' cannot be found" if !File.exists?(p)
        }
    end

    def list_items()
        go_to_homedir()
        Dir["#{@sources}/**/*.java"].each { | n |
            yield n, File.mtime(n).to_i
        }
    end

    def pre_build() cleanup() end

    def build()
        p = @pkgs.collect() { |e| e.tr('/', '.') }
        puts ['Packages:'] << p

        j = java()
        system "#{j.javadoc()} -classpath '#{j.classpath}' -d '#{fullpath()}' -sourcepath '#{fullpath(@sources)}' #{p.join(' ')}"
        raise 'Java doc generation error.' if $? != 0
    end

    def cleanup() FileUtils.rm_r(fullpath()) if  File.exists?(fullpath()) end
    def expired?() !File.exists?(fullpath()) end
    def what_it_does() "Generate javadoc into '#{@name}'" end
end


class FindClassAction < Artifact
    def build_()
        result = []
        path = @target.name.gsub('.', '/') + '.class'
        msg "Looking for '#{path}' class."

    java().classpath.split(File::PATH_SEPARATOR).each { |i|
      if File.directory?(i)
        Dir["#{i}/#{path}"].each { |file|
          next if File.directory?(file)
          result << file
        }
        result = result + JAR.find(i, @target.name)
      else
        wmsg "File '#{i}' doesn't exist." if !File.exists?(i)
      end
    }
    wmsg "Class #{@target.name} not found." if result.length == 0
    result
  end
end
