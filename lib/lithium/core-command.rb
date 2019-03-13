require 'fileutils'

require 'lithium/core'
require 'lithium/platform'
require 'lithium/utils'


class CLEANUP < Artifact
    def build() Project.artifact(@name).cleanup end
    def what_it_does() "Cleanup '#{@name}', #{Project.artifact(@name).class}" end
end

class REQUIRE < Artifact
    def build()
        cc = 0
        puts "Artifact '#{@name}' dependencies list:"
        Project.artifact(@name).requires().collect {| e |
            puts "   [class = #{e.class}]: '#{e}'"
            cc += 1
        }
        puts "Dependencies list is empty" if cc == 0
        puts ""
    end

    def what_it_does() "List '#{@name}' artifact dependencies" end
end

class TREE < Artifact
    def build()
        tree = ArtifactTree.new(@name)
        tree.build()
        tree.norm_tree() if @normalize_tree
        tree.show_tree()
    end

    def what_it_does() "Show '#{@name}' dependencies tree" end
end

# list expired items or/and attributes for the given artifact
class EXPIRED < Artifact
    def build()
        a = Project.artifact(@name)
        raise "Artifact '#{@name}' doesn't track its state" unless a.kind_of?(LogArtifactState)

        if !a.expired?
            puts "Artifact '#{@name}' is not expired"
        else
            ei = 0
            puts "Detected expired items for '#{@name}':"
            a.list_expired_items { | path, tm |
                puts "   '#{path}': #{tm}"
                ei += 1
            }
            puts "    <No expired items have been detected !" if ei == 0

            ei = 0
            puts "\nDetected expired properties for '#{@name}':"
            a.list_expired_attrs { |n, ov|
                puts "    '#{n}' = #{ov}"
                ei += 1
            }
            puts "    <No an expired property has been detected !" if ei == 0
            puts ""
        end
    end

    def what_it_does() "List of expired items of '#{@name}' artifact" end
end

class INSPECT < Artifact
    def initialize(name = '.') super end

    def build()
        art       = Project.artifact(@name)
        variables = art.instance_variables

        is_tracked_art_sign = "untracked"
        tracked_attrs       = []
        if art.kind_of?(LogArtifactState)
            is_tracked_art_sign =  "tracked"
            art.class.each_log_attrs { | attr_name |
                attr_name = attr_name[1, attr_name.length - 1]
                tracked_attrs << attr_name
            }
        end

        puts "Artifact (#{is_tracked_art_sign}):'#{art.name}' (class = #{art.class}) {"
        variables.each { | var_name |
            is_tracked_sign = tracked_attrs.include?(var_name[2, var_name.length - 2]) ? 'T' : ' '
            puts "    (#{is_tracked_sign}) #{var_name}= #{format_val(art.instance_variable_get(var_name))}" if var_name != '@name'
        }
        puts '}'
    end

    def what_it_does() "Inspect artifact '#{@name}'" end

    protected

    def format_val(val)
        return 'nil' if val.nil?
        return val.inspect if val.kind_of?(Array) || val.kind_of?(Hash) || val.kind_of?(String)
        return val.to_s
    end
end

class INIT < FileCommand
    def initialize(*args)
        super
        @template ||= 'generic'
    end

    def build()
        path = fullpath()
        raise "File '#{path}' doesn't exist"      unless File.exists?(path)
        raise "File '#{path}' is not a directory" unless File.directory?(path)
        lp = File.expand_path(File.join(path, ".lithium"))

        if File.exists?(lp)
            raise "'.lithium' as a file already exits in '#{lp}'" unless File.directory?(lp)
            puts_warning "Project '#{lp}' already has lithium stuff initialized"
        else
            lh = File.join($lithium_code, "templates",  @template, ".lithium")
            begin
                l = File.join(lp, "project.rb")
                FileUtils.cp_r(lh, path)
            rescue
                FileUtils.rm_r lp if File.exists?(lp)
                raise
            end
        end
    end

    def what_it_does() "Generate lithium stuff for '#{@name}'" end
end

# list all configured artifacts
class LIST < Artifact
    def build()
        ls_artifacts()

        #TODO: analyze and remove
        # if @name == 'artifacts'
        #     ls_artifacts()
        # elsif @name == 'all'
        #     puts "Artifacts list"
        #     puts "#{'='*60}"
        #     puts
        # else
        #     raise "'#{@name}' is unknown artifacts list type"
        # end
    end

    def ls_artifacts()


        Project.target._artifacts.each_value { |e|
            if e.kind_of?(Artifact)
                n, clazz = e.name, e.class.to_s
            else
                n, clazz = e[0][0], e[0][-1].to_s
            end
            puts sprintf "  %-20s('%s')\n", clazz, n
        }
    end

    def what_it_does() "List project '#{@name}' artifacts" end
end


class INSTALL < Artifact
    def initialize(name = 'INSTALL')
        super
        @script_name ||= 'lithium'

@nix_script = "#!/bin/bash

LITHIUM_HOME=#{$lithium_code}

vc=\"ruby \\\"$LITHIUM_HOME/lib/lithium.rb\\\" \"
for ((i=1; i<=$\#; i++))
do
  vn=\"$\"$i
  va=$(eval echo $vn)
  vc=\"$vc \\\"$va\\\"\"
done;

eval \"$vc\"
"
@win_script="
@set LITHIUM_HOME=#{$lithium_code}
@ruby %LITHIUM_HOME%/lib/lithium.rb %*
"
        if Platform::OS == :unix
            @script_path = "/usr/local/bin/#{@script_name}"
            @script = @nix_script
        elsif Platform::OS == :win32
            win = ENV['WINDIR'].dup
            win["\\"] = '/'
            win = FileUtil.correct_win_path(win)
            @script_path = "#{win}/#{@script_name}.bat"
            @script = @win_script
        else
            raise "Unsupported platform #{Platform::OS}"
        end
    end

    def build()
        if File.exists?(@script_path)
            puts_warning "File '#{@script_path}' already exists"
            File.open(@script_path, 'r') { |f|
                l = f.readlines()
                l = l.join(' ')
                if l.index('LITHIUM_HOME').nil?
                    raise "File '#{@script_path}' cannot be overwritten, it is not lithium script\nTry to use another name for deployed script"
                end
            }
            puts "Install '#{@script_path}' anyway"
        end

        File.open(@script_path, 'w') { |f|
            f.print @script
            f.chmod(0777) if Platform::OS != :win32
        }
    end

    def what_it_does() "Install Lithium '#{@script_path}' script" end
end

