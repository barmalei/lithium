require 'fileutils'

require 'lithium/core'
require 'lithium/platform'
require 'lithium/utils'


class CLEANUP < Artifact
    def build() Project.artifact(@name).cleanup end
    def what_it_does() "Cleanup '#{@name}', #{Project.artifact(@name).class}" end
end

# Display registered meats
#   -- Show the full list of meta registered for the whole projects hierarchy
#   -- Mark meta references to the same parent metas
#   -- Mark meta that matches target artifact name
#
# Options:
#    meta.opts
#      -- owner   - show only owner metas
#      -- current - show only current project metas
#      -- path    - show only metas (from the whole hierarchy) that matches target
#
# Example:
# -------
#      META:*                    # target artifact doesn't matter
#      META:compile:**/*.java    # mark 'compile:**/*.java' as target artifact in meta tree
#
class META < Artifact
    def initialize(*args, &block)
        super
        @options ||= $lithium_options['meta.opt']
        @options = [] if @options.nil?
        @options = @options.split(',') if @options.kind_of?(String)
    end

    def build()
        p  = Project.current
        unless p.nil?
            if @options.include?('current')
                stack = [ p ]
                traverse(stack, stack.length - 1)
            elsif @options.include?('owner')
                if p.owner.nil?
                    raise "Project '#{p}' doesn't have an owner project"
                else
                    stack = [ p.owner ]
                    traverse(stack, stack.length - 1)
                end
            else
                stack = []
                while !p.nil? do
                    stack << p
                    p = p.owner
                end
                traverse(stack, stack.length - 1)
            end
        else
            raise "Current actual project cannot be detected"
        end
    end

    def traverse(stack, index, shift = '')
        if index >= 0
            prj = stack[index]
            artname = prj.relative_art(@name)
            puts "#{shift}[+] Meta data for '#{prj}' project {\n"
            puts_prj_metas(prj, artname, shift)
            traverse(stack, index - 1, shift + '    ')
            puts "#{shift}}"
        end
    end

    def puts_prj_metas(prj, artname, shift)
        count = 0
        prj._meta.each { | m |
            ps = ''
            unless prj.owner.nil?
                pmeta = prj.owner.find_meta(m[1].artname)
                ps = " (#{prj.owner}:#{pmeta.artname})" unless pmeta.nil?
            end
            pp = m[0].match(artname) ? " : [ '#{artname}' ]" : ''
            if !@options.include?('path') || pp.length > 0
                printf("#{shift}    %-20s => '%s'#{ps}#{pp}\n", m[1][:clazz], m[1].artname)
                puts_prj_metas(prj._artifact_by_meta(m[1].artname, m[1]), artname, shift + '    ') if m[1][:clazz] <= FileMaskContainer
                count += 1
            end
        }

        puts "#{shift}    <no meta is available>" if count == 0
    end

    def what_it_does()
        "List meta tree"
    end
end

class REQUIRE < Artifact
    def build()
        res = Project.artifact(@name).requires()

        puts "Artifact '#{@shortname}' dependencies list {"
        res.each { | e |
            printf("    %-20s => '%s'\n", e.class, e)
        }

        puts '    < dependencies list is empty! >' if res.length == 0
        puts '}'
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

        unless a.expired?
            ei = 0
            puts "Detected expired items for '#{@name}':"
            a.list_expired_items { | path, tm |
                puts "   '#{path}': #{tm}"
                ei += 1
            }
            puts '    <No expired items have been detected !' if ei == 0

            ei = 0
            puts "\nDetected expired properties for '#{@name}':"
            a.list_expired_attrs { |n, ov|
                puts "    '#{n}' = #{ov}"
                ei += 1
            }
            puts '    <No an expired property has been detected !' if ei == 0
            puts ''
        else
            puts "Artifact '#{@name}' is not expired"
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

