require 'pathname'
require 'json'

class StdPattern
    FILENAME_PATTERN = '[^\:\,\!\?\;\~\`\&\^\*\(\)\=\+\{\}\|\>\<\%]+'

    class StdMatch
        def initialize(msg, groups)
            @msg, @groups, @variables = msg, [], {}
            groups.each_index { | i |
                group       = groups[i]
                name, value = group[:name], group[:value]
                @groups[i] = group.dup()
                @variables[name] = value if name[0] != '_' && !@variables.has_key?(name)
            }
        end

        def wrap(name, start_with, end_with)
            convert(name)  { | value |
                "#{start_with}#{value}#{end_with}"
            }
        end

        def wrap?(name, start_with, end_with)
            convert?(name)  { | value |
                "#{start_with}#{value}#{end_with}"
            }
        end

        def cut(name)
            convert(name) { '' }
            return self
        end

        def cut?(name)
            convert?(name) { '' }
            return self
        end

        def replace(name, value)
            convert(name) { value }
            return self
        end

        def replace?(name, value)
            convert?(name) { value }
            return self
        end

        def convert?(name, &block)
            _convert(name, false, &block)
        end

        def convert(name, &block)
            _convert(name, &block)
        end

        def _convert(name, group_should_exist = true,  &block)
            return self if @groups.length == 0 && group_should_exist == false
            raise 'Conversion block is expected' if block.nil?

            group = @groups.detect { | g | g[:name] == name }
            raise "Group '#{name}' has not been detected" if group.nil? && group_should_exist

            unless group.nil?
                value, start_pos, name = group[:value], group[:start], group[:name]
                new_value = instance_exec(value, &block)

                begin
                    new_value = new_value % @variables
                rescue KeyError => e
                    puts_warning("Placeholder cannot be detected: '#{e}'")
                end

                if !new_value.nil? && new_value != value
                    @msg[start_pos, value.length] = new_value

                    dt = new_value.length - value.length
                    group[:value] = @variables[name] = new_value

                    for i in (group[:index] + 1 .. @groups.length - 1)
                        group = @groups[i]
                        group[:start] = group[:start] + dt
                    end
                end
            end

            self
        end

        def group(name)
            gr = @groups.detect { | gr | gr[:name] == name }
            return gr.dup unless gr.nil?
            nil
        end

        def has_groups?
            @groups.length > 0
        end

        def has_group?(name)
            @groups.detect { | gr | gr[:name] == name } != nil
        end

        def groups_names()
            @groups.map { | gr |
                gr[:name]
            }
        end

        def to_s()
            @msg
        end
    end

    def initialize(level = 0, &block)
        @level = level
        flush()
        instance_eval(&block) unless block.nil?
    end

    def _add_group(name, &block)
        @groups.push({
            :name  => name.kind_of?(Symbol) ? name : name.to_sym,
            :block => block,
            :start => -1,
            :value => '',
            :index => @groups.length,
            :exists => true
        })
    end

    def _append(pattern, name = nil, &block)
        raise 'Pattern cannot be nil'     if  pattern.nil?
        raise 'Group name is not defined' if !block.nil? && name.nil?

        unless name.nil?
            pattern = "(?<#{name}>#{pattern})"
            _add_group(name, &block)
        end
        @re_parts.push(pattern)
        return self
    end

    def identifier(name = nil, &block)
        _append('[a-zA-Z_$][0-9a-zA-Z_$]*', name, &block)
    end

    def identifier?(name = nil, &block)
        identifier(name, &block)
        @re_parts.push('?')
        return self
    end

    def num(name = nil, &block)
        _append('[0-9]+', name, &block)
    end

    def line(&block)
        num(:line, &block)
    end

    def line?(&block)
        line(&block)
        @re_parts.push('?')
        return self
    end

    def column(&block)
        num(:column, &block)
    end

    def column?(&block)
        column(&block)
        @re_parts.push('?')
        return self
    end

    def dot()
        any('\.')
    end

    def spaces()
        any('\s+')
    end

    def spaces?()
        any('\s*')
    end

    def colon()
        any(':')
    end

    def colon?()
        any(':{0,1}')
    end

    def any(*args)
        @re_parts.push(args.join()) if args.length > 0
        @re_parts.push('.*')        if args.length == 0
        return self
    end

    def group?(name, pattern = nil, &block)
        group(name, pattern = nil, &block)
        @re_parts.push('?')
        return self
    end

    def group(name, pattern = nil, &block)
        raise 'Group name cannot be nil' if name.nil?
        raise 'Block has to be defined'  if pattern.nil? && block.nil?

        if pattern.nil?
            _add_group(name)
            @re_parts.push("(?<#{name}>")
            instance_eval(&block)
            @re_parts.push(')')
        else
            @re_parts.push("(?<#{name}>#{pattern})")
            _add_group(name, &block)
        end
        return self
    end

    def replace(value, pattern = nil, &block)
        raise 'Replace value is nil' if value.nil?
        index = @groups.length
        group('_replace', pattern, &block)
        @groups[index][:value] = value
        return self
    end

    def cut(pattern = nil, &block)
        replace('', pattern, &block)
    end

    def file?(*args, &block)
        file(*args, &block)
        @re_parts.puts('?')
        return self
    end

    # file([ext1, ext2, ...])
    def file(*args, &block)
        ext = args
        ext = [ '[a-zA-Z]+' ] if args.length == 0
        ext = "(?<extension>#{ext.join('|')})"
        @re_parts.push("(?<file>#{FILENAME_PATTERN}\.#{ext})")
        _add_group('file', &block)
        _add_group('extension')
        return self
    end

    def wrap(start_with, end_with, &block)
        replace("#{start_with}%{current}#{end_with}", &block)
    end

    def rbrackets(&block)
        _append('\(')
        instance_eval(&block)
        _append('\)')
    end

    def brackets(&block)
        _append('\[')
        instance_eval(&block)
        _append('\]')
    end

    def quotes(&block)
        _append('\'')
        instance_eval(&block)
        _append('\'')
    end

    def dquotes(&block)
        _append('\"')
        instance_eval(&block)
        _append('\"')
    end

    def location(*args, &block)
        group(:location) {
            file(*args, &block); colon; line; colon?; column?
        }
    end

    def location?(*args, &block)
        location(*args, &block)
        @re_parts.push('?')
        return self
    end

    def level()
        @level
    end

    def flush()
        @re_parts, @groups, @re = [], [], nil
    end

    def match(msg)
        @re = Regexp.new(@re_parts.join()) if @re.nil?

        m = @re.match(msg)
        if !m.nil? && m.length > 1 && @groups.length > 0
            dt, variables = 0, {}

            # collect all groups values
            m.names.each { | name |
                variables[name.to_sym] = m[name]
            }

            @groups.each_index { | i |
                # fetch group
                group = @groups[i]

                # collect group properties
                name, value, block = group[:name], group[:value], group[:block]

                # get group match text location
                start_pos, end_pos = m.offset(i + 1)

                # switch to the next the next group if the group cannot be found
                if m[i + 1].nil? || m[i + 1].length == 0
                    group[:exists] = false
                    if i > 0
                        group[:start] = @groups[i - 1][:start] + @groups[i - 1][:value].length
                    else
                        group[:start] = 0
                    end
                else
                    group[:start] = start_pos + dt
                    if name == :_replace
                        if value.length > 0
                            variables[:current] = m[i + 1]
                            begin
                                value = value % variables
                            rescue KeyError => e
                                puts_warning("Placeholder cannot be detected: '#{e}'")
                            end
                        end

                        # replace
                        msg[start_pos + dt .. end_pos + dt - 1] = value
                        group[:start] = start_pos + dt
                        dt = dt + start_pos - end_pos + value.length
                    else
                        # fetch group text
                        value = m[i + 1]

                        # if block is defined call it to transform group text
                        unless block.nil?
                            new_value = instance_exec(value, &block)
                            if !new_value.nil? && new_value != value
                                msg[start_pos + dt .. end_pos + dt - 1] = new_value
                                dt = dt + new_value.length - value.length

                                # modify group placeholder with new transformed value
                                group[:value] = variables[name.to_sym] = new_value
                            else
                                group[:value] = value
                            end
                        else
                            group[:value] = value
                        end
                    end
                end
            }
            return StdMatch.new(msg, @groups)
        else
            return nil
        end
    end
end

module ExpandFileLocation
    def file(*args, &block)
        raise 'File block cannot be consumed' unless block.nil?
        super(*args) { | path |
            expand_path(path)
        }
    end

    def expand_path(path)
        if File.exists?(path)
            return File.expand_path(path)
        elsif !Pathname.new(path).absolute? && !Artifact.last_caller.nil? && !Artifact.last_caller.owner.nil?
            home  = Artifact.last_caller.owner.homedir
            npath = File.join(home, path)
            if File.exists?(npath)
                return npath
            else
                npath = File.join(home, 'src', path)
                return npath if File.exists?(npath)

                # TODO: can consume time if src exists and contains tons of sources
                found = Dir.glob(File.join(home, 'src', '**', path))
                return found[0] if found && found.length > 0
            end
        end
    end
end

class FileLocPattern < StdPattern
    def initialize(*args)
        @expand_path = false # expand_path
        super(level) {
            location(*(args))
        }
    end
end

class JavaPattern < StdPattern
    def class_name
        _append('[a-zA-Z$_][a-zA-Z0-9$_]*(\.[a-zA-Z$_][a-zA-Z0-9$_]*)*', :class)
    end
end

class JavaExceptionLocPattern < JavaPattern
    include ExpandFileLocation

    def initialize()
        super(3) {
            any('^\s+at\s*'); class_name; dot; identifier(:method)
            rbrackets {
                location('java', 'scala', 'kt', 'groovy')
            }
        }
    end

    def method_ref
        class_name; dot; identifier(:method)
    end
end

class JavaCompileErrorPattern < JavaPattern
    def initialize()
        super(2) {
            location('java'); any('\s+error:\s+'); group(:message, '.*$')
        }
    end
end



# msg = "/Users/brigadir/projects/wildfly/standalone/deployments/cfs.war/src/core/CFS.java:49: error: <identifier> expected"
# pattern = JavaCompileErrorPattern.new()
# tr = pattern.match(msg)

# puts tr

# tr.convert?(:dsd) { | location |
#     "[[%{file}:%{line}:%{:column}]]"
# }


# STDOUT.puts "MSG = #{tr}"

