require 'fileutils'

require 'lithium/core'

class CLEAN < Artifact
    def build()
        # firstly let's create tree that resolves static dependencies (for instance set environment variables)
        name = @name
        tree = Project.current.new_artifact {
            ArtifactTree.new(name)
        }

        tree.build()
        tree.root_node.art.clean
    end

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
    include OptionsSupport

    def initialize(*args, &block)
        super
        OPT($lithium_options['meta.opt'])
    end

    def build()
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
                pmeta = prj.owner.find_meta(m)
                ps = " (#{prj.owner}:#{pmeta})" unless pmeta.nil?
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

    def what_it_does()
        "List meta tree"
    end
end

class REQUIRE < Artifact
    def build()

        puts "Artifact '#{@shortname}' dependencies list {"
        Project.artifact(@name).requires { | dep, assignTo, is_own, block |
            printf("    %-20s : '%s' (assignTo = %s)\n", dep.name, ArtifactName.new(dep, &block), (assignTo.nil? ? '<none>' : assignTo))
        }
        puts '}'
    end

    def what_it_does() "List '#{@name}' artifact dependencies" end
end

class TREE < Artifact
    def build()
        tree = ArtifactTree.new(@name)
        tree.build()

        #TODO: makes sense to support the flag on the level of ArtifactTree class
        #tree.norm_tree() #if @normalize_tree
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

    def build()
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

class INIT < FileCommand
    def initialize(*args)
        super(args.length == 0 || args[0].nil? ? '.' : args[0])
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
            lh = File.join($lithium_code, 'templates',  @template, '.lithium')
            begin
                l = File.join(lp, 'project.rb')
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

        if RUBY_PLATFORM =~ /darwin/i || RUBY_PLATFORM =~ /linux/i || RUBY_PLATFORM =~ /freebsd/i || RUBY_PLATFORM =~ /freebsd/i || RUBY_PLATFORM =~ /netbsd/i || RUBY_PLATFORM =~ /cygwin/i
            os = :unix
        elsif RUBY_PLATFORM =~ /mswin/i || RUBY_PLATFORM =~ /mingw/i || RUBY_PLATFORM =~ /bccwin/i
            os = :win
        else
            os = nil;
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
@ruby %LITHIUM_HOME%/lib/lithium.rb %*
"
        if os == :unix
            @script_path = "/usr/local/bin/#{@script_name}"
            @script = @nix_script
        elsif os == :win
            win = ENV['WINDIR'].dup
            win["\\"] = '/'
            @script_path = "#{win}/#{@script_name}.bat"
            @script = @win_script
        else
            raise 'Unsupported platform, nix or windows are expected'
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
            f.chmod(0777) if os != :win
        }
    end

    def what_it_does() "Install Lithium '#{@script_path}' script" end
end