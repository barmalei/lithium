require 'fileutils'

require 'lithium/core'

class CLEAN < Artifact
    def build
        # firstly let's create tree that resolves static dependencies (for instance set environment variables)
        tree = ArtifactTree.new(owner.artifact(@name))
        tree.art.clean
    end

    def what_it_does
        "Cleanup '#{@name}', #{owner.artifact(@name).class}"
    end
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
    include OptionsSupport

    def initialize(name, &block)
        super
        OPT($lithium_options['meta.opt'])
    end

    def build
        p  = Project.current
        unless p.nil?
            if OPT?('current')
                stack = [ p ]
                traverse(stack, stack.length - 1)
            elsif OPT?('owner')
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
            raise 'Current actual project cannot be detected'
        end
    end

    def traverse(stack, index, shift = '')
        if index >= 0
            prj = stack[index]
            artname = ArtifactName.relative_to(@name, prj.homedir)
            puts "#{shift}[+] PROJECT:'#{prj}' {\n"
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
                pmeta, ow = prj.owner.match_meta(m)
                ps = " (#{prj.owner.name}:#{pmeta.to_s})" unless pmeta.nil?
                #ps = " (#{prj.owner} #{pmeta.class})" unless pmeta.nil?
            end
            pp = m.match(artname) ? " : [ '#{artname}' ]" : ''
            if OPT?('path') == false || pp.length > 0
                printf("#{shift}    %-20s => '%s'#{ps}#{pp}\n", m.clazz, m)
                puts_prj_metas(prj._artifact_by_meta(m, m), artname, shift + '    ') if m.clazz <= FileMaskContainer
                count += 1
            end
        }

        puts "#{shift}    <no meta is available>" if count == 0
    end

    def what_it_does
        "List meta tree"
    end
end

class REQUIRE < Artifact
    def build
        puts "Artifact '#{@name}:' dependencies list {"
        art = Project.artifact(@name)
        art.each_required { | art |
            aname = art.kind_of?(Artifact) ? ArtifactName.new(art.name, art.class) : name
            printf("    %-20s : '%s'\n", aname, art)
        }
        puts '}'
    end

    def what_it_does() "List '#{@name}' artifact dependencies" end
end

class TREE < Artifact
    def initialize(name)
        @show_id, @show_owner, @show_mtime = true, true, true
        super
    end

    def build
        #show_tree(ArtifactTree.new(@name))
        show_tree(ArtifactTree.new(Project.current.artifact(@name)))
    end

    def show_tree(root) puts tree2string(nil, root) end

    def tree2string(parent, root, shift=0)
        pshift, name = shift, File.basename(root.art.name)

        e = (root.expired ? '*' : '') +
            (@show_id ? " ##{root.art.object_id}" : '') +
            (root.expired_by_kid ? "*[#{root.expired_by_kid}]" : '') +
            (@show_mtime ? " #{root.art.mtime}ms" : '') +
            (@show_owner ? ":<#{root.art.owner.class}:#{root.art.owner}>" : '')

        s = "#{' '*shift}" + (parent ? '+-' : '') + "#{name} (#{root.art.class})"  + e
        b = parent && root != parent.children.last
        if b
            s, k = "#{s}\n#{' '*shift}|", name.length/2 + 1
            s = "#{s}#{' '*k}|" if root.children.length > 0
        else
            k = shift + name.length / 2 + 2
            s = "#{s}\n#{' '*k}|" if root.children.length > 0
        end

        shift = shift + name.length / 2 + 2
        root.children.each { | node |
            rs, s = tree2string(root, node, shift), s + "\n"
            if b
                rs.each_line { | line |
                    line[pshift] = '|'
                    s = s + line
                }
            else
                s = s + rs
            end
        }
        return s
    end

    def what_it_does() "Show '#{@name}' dependencies tree" end
end

# list expired items or/and attributes for the given artifact
class EXPIRED < Artifact
    def build
        a = Project.artifact(@name)

        name = "Artifact '#{a.class}:#{a.name}'"
        if a.kind_of?(LogArtifactState)
            if a.original_expired?
                puts "#{name} is expired: 'expire?' => true"
                return
            else
                ei = 0
                a.list_expired_items { | path, tm |
                    puts "#{name} is expired: '#{path}' => #{tm} : #{File.mtime(path).to_i}"
                    ei += 1
                }

                a.list_expired_attrs { |n, ov|
                    puts "#{name} is expired: '#{n}' => #{ov}"
                    ei += 1
                }

                return if ei > 0
            end
        elsif a.expired?
            puts "#{name} is expired: 'expire?' => true"
            return
        end
        puts "#{name} is not expired"
    end

    def what_it_does() "Explain expiration state of '#{@name}' artifact" end
end

class INFO < Artifact
    def self.info(art)
        art  = Project.artifact(art) unless art.kind_of?(Artifact)

        variables = art.instance_variables

        is_tracked_art_sign = 'untracked'
        tracked_attrs       = []
        if art.kind_of?(LogArtifactState)
            is_tracked_art_sign =  'tracked'
            art.class.each_log_attrs { | attr_name |
                attr_name = attr_name[1, attr_name.length - 1]
                tracked_attrs << attr_name
            }
        end

        puts "Artifact (#{is_tracked_art_sign}) #{art.class}:'#{art}' {"
        puts "    (M) project() = '#{art.project}'"
        puts "    (M) homedir() = '#{art.homedir}'"
        puts "    (M) expired?  = #{art.expired?}"
        variables.each { | var_name |
            is_tracked_sign = tracked_attrs.include?(var_name[2, var_name.length - 2]) ? 'T' : ' '
            puts "    (#{is_tracked_sign}) #{var_name} = #{INFO.format_val(art.instance_variable_get(var_name))}" if var_name != '@name'
        }
        puts '}'
    end

    def initialize(name = '.') super end

    def build
        INFO.info(@name)
    end

    def what_it_does() "Inspect artifact '#{@name}'" end

    protected

    def self.format_val(val)
        return 'nil' if val.nil?
        val = val.kind_of?(Array) || val.kind_of?(Hash) || val.kind_of?(String) ? val.inspect : val.to_s
        val = val[0 .. 128] + " [more ..] " if val.length > 128
        return val
    end
end

class INIT < ExistentFile
    def build
        path = fullpath()

        raise "File '#{path}' is not a directory or doesn't exist" unless File.directory?(path)
        lp = File.expand_path(File.join(path, ".lithium"))

        if File.exists?(lp)
            raise "'.lithium' as a file already exits in '#{lp}'" if File.file?(lp)
            puts_warning "Project '#{lp}' already has lithium stuff initialized"
        else
            Dir.mkdir(lp)
        end

        prj_file = File.join(lp, 'project.rb')
        unless File.exists?(prj_file)
            puts "Creating project config file -> '#{prj_file}'"
            File.open(prj_file, 'w') { | f |
                f.puts("-> {\n}")
            }
        else
            puts_warning "Project configuration '#{prj_file}' already exists"
        end
    end

    def what_it_does
        "Generate lithium stuff for '#{@name}'" 
    end
end

class INSTALL < Artifact
    def initialize(name = 'INSTALL')
        super
        @script_name ||= 'lithium'

        if File::PATH_SEPARATOR == ':'
            @os = :unix
        elsif File::PATH_SEPARATOR == ';'
            @os = :win
        else
            @os = nil
        end

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
@ruby %LITHIUM_HOME%/lib/lithium.rb %
"
        if @os == :unix
            @script_path = "/usr/local/bin/#{@script_name}"
            @script = @nix_script
        elsif @os == :win
            win = ENV['WINDIR'].dup
            win["\\"] = '/'
            @script_path = "#{win}/#{@script_name}.bat"
            @script = @win_script
        else
            raise 'Unsupported platform, nix or windows are expected'
        end
    end

    def build
        if File.exists?(@script_path)
            puts_warning "File '#{@script_path}' already exists"
            File.open(@script_path, 'r') { | f |
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
            f.chmod(0777) if @os != :win
        }
    end

    def what_it_does() "Install Lithium '#{@script_path}' script" end
end