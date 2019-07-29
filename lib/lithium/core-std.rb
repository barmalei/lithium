require 'pathname'
require 'json'

# !!! debug field
# Can be useful to debug lithium stdout. Using original
# stdout stored in $M variable allows developers printing
# debug messages with $M.puts(,,,)
# !!!
$M = $stdout

$RECOGNIZERS      = {}
$FILENAME_PATTERN = "[^\:\,\!\?\;\ \~\`\&\^\*\(\)\=\+\{\}\|\>\<\%]+"

def STD_RECOGNIZERS(args)
    # normalize keys and values
    args.each_pair { | k, v |
        # normalize values
        v.each_index { | i |
            v[i] = Std::RegexpRecognizer.new(v[i]) if v[i].kind_of?(Regexp) || v[i].kind_of?(String)
        }

        # normalize keys
        kk = []
        if k.kind_of?(Array)
            kk = kk.concat(k)
        else
            kk.push(k)
        end
        kk.each { | key |
            if key.kind_of?(Class)
                key = key.name
            elsif !key.kind_of?(String)
                raise "Invalid object type '#{key.class.name}'"
            end

            $RECOGNIZERS[key] = [] unless $RECOGNIZERS.has_key?(key)
            $RECOGNIZERS[key].push(*v)
        }
    }
end

def puts_error(*args)
    if Std.std
        Std.std.puts_error(*args)
    else
        puts args
    end
end

def puts_warning(*args)
    if Std.std
        Std.std.puts_warning(*args)
    else
        puts args
    end
end

class Std
    @@std                    = nil  # singleton object static variable
    @@backtrace_deepness     = -1
    @@ruby_exception_pattern = /\s*from\ .*\:[0-9]+(\:in\s+\`.*\')?/

    @@signs_map = { 0 => [ 'INF', 'Z'], 1 => [ 'WAR', '!'], 2 => [ 'ERR', '?'], 3 => [ 'EXC', '?'] }

    # Make std singleton object
    def Std.new(*args, &block)
        @@std.endup() if @@std
        @@std = super(*args, &block)
        @@std.started() if @@std.respond_to?(:started)
        @@std
    end

    def Std.std()         @@std                    end
    def Std.restore_std() @@std.endup() if @@std   end
    def Std.backtrace(d)  @@backtrace_deepness = d end

    class Std
        def initialize(&block) @block = block end
        def write(msg) @block.call(msg)  end

        def puts(*args)
            args.each { | a |
                a = a.to_s
                write((a.length == 0 || a[-1, 1] != "\n") ? "#{a}\n" : a)
            }
        end

        def print(*args) args.each { | a | write(a.to_s) } end
        def <<(*args) print(*args) end

        def flush() end
    end

    #
    #  Output string recognized entity
    #
    class Entity < String
        #  type, and the given entity location
        attr_accessor :type, :start_at, :end_at

        def initialize(text, type, offsets = [-1, -1])
            super text
            @type, @start_at, @end_at = type, offsets[0], offsets[1]
        end

        def ==(o) super(o) && @start_at == o.start_at && @type == o.type && @end_at == o.end_at end

        def empty()
            return clone('')
        end

        def to_hash()
            { :type => @type, :start => @start_at, :end => @end_at, :text => to_s}
        end

        def clone(text)
            return Entity.new(text, @type, [@start_at, @end_at])
        end
    end

    class RegexpRecognizer
        attr_reader   :regexp
        attr_accessor :classifier

        def initialize(regexp = '.*')
            @regexp = Regexp.new(regexp)
        end

        def classifier(value)
            @classifier = value
            return self
        end

        # yield number of entities object { type => entity }
        def recognize(msg)
            m = @regexp.match(msg.chop)
            if m && m.length > 0
                entities = {}

                m.names.each { | name |
                    # optional regexp group can come as nil
                    entities[name] = Entity.new(m[name], name, m.offset(name)) if name && name.length > 0 && m[name]
                }

                normalize(entities) { | entity |
                    entities[entity.type] = entity
                }

                entities['classifier'] = Entity.new(@classifier, 'classifier') unless @classifier.nil?

                entities.each_value { | v |
                    yield v
                }
            end
        end

        def normalize(entities)
        end
    end

    #
    #  File name and line location recognizer
    #
    class FileLocRecognizer < RegexpRecognizer
        def initialize(regexp = nil, ext: nil)
            if regexp.nil?
                regexp = '\:\s*(?<line>[0-9]+)\s*(\:)?(?<column>[0-9]+)?'
                if ext.nil?
                    regexp = '\s*(?<file>${file_pattern}\.[a-z0-9A-Z_]+)' + regexp
                else
                    regexp = '\s*(?<file>${file_pattern}\.${file_extension})' + regexp
                end
            end

            if regexp.kind_of?(String)
                regexp = regexp.gsub("${file_pattern}", $FILENAME_PATTERN)
                regexp = regexp.gsub("${file_extension}", ext) unless ext.nil?
            elsif ext
                raise 'File extension cannot be specified for none-string regexp'
            end

            super regexp
        end

        def normalize(entities)
            if entities.has_key?('file')
                path = entities['file']

                if File.exists?(path)
                    yield path.clone(File.expand_path(path.to_s))
                elsif !Pathname.new(path.to_s).absolute? && !Artifact.last_caller.nil? && !Artifact.last_caller.owner.nil?
                    home  = Artifact.last_caller.owner.homedir
                    npath = File.join(home, path.to_s)
                    if File.exists?(npath)
                        yield path.clone(npath)
                    else
                        npath = File.join(home, 'src', path.to_s)
                        if File.exists?(npath)
                            yield path.clone(npath)
                        else
                            # TODO: can consume time if src exists and contains tons of sources
                            found = Dir.glob(File.join(home, 'src', '**', path.to_s))
                            yield path.clone(found[0]) if found && found.length > 0
                        end
                    end
                end
            end
        end
    end

    def initialize(format = nil)
        @stdout, @stderr, @ebuffer, @buffer = $stdout, $stderr, [], []
        $stdout, $stderr, @format = Std.new() { | m | self.write(m, 0) }, Std.new() { |m| self.write(m, 2) }, format

    end

    def <<(msg) @stdout << msg end

    def puts_warning(*args)
        args.each { |a|
            a = a.to_s
            write((a.length == 0 || a[-1, 1] != "\n") ? "#{a}\n" : a, 1)
        }
    end

    def puts_error(*args)
        args.each { | a |
            a = a.to_s
            write((a.length == 0 || a[-1, 1] != "\n") ? "#{a}\n" : a, 2)
        }
    end

    def write(msg, level)
        msg = msg.to_s
        return if msg.length == 0
        begin
            # disable uncontrolled output for a thrown exception and
            # do it with special Std method "_exception_"

            if $! && level == 2 && msg =~ @@ruby_exception_pattern
                if @exception != $!
                    @exception = $!
                    _exception_($!)
                end
            else
                msg.each_line { | line |
                    if line[-1, 1] != "\n"
                        @buffer << line
                    else
                        if @buffer.length > 0
                            line = "#{@buffer.join('')}#{line}"
                            @buffer.clear()
                        end
                        expose(line, level)
                    end
                }
            end
        rescue Exception => e
            begin
                _fatal_(e)
            rescue
            end
        end

    end

    def _fatal_(e)
        # fatal error has happened in Std implementation
        $M.puts 'Fatal error has occurred:'
        $M.puts " #{$!.message}:"
        e.backtrace().each { | line | $M.puts "     #{line}" }
    end

    # show exception stack trace according to configured "@@backtrace_deepness"
    def _exception_(e)
        expose("#{e.message}\n", 3)
        bt  = e.backtrace()
        max = @@backtrace_deepness < 0 ? bt.length : @@backtrace_deepness
        for i in 0..max - 1
            expose("   #{bt[i]}\n", 3)
        end
    end

    #
    #  This method is called every time a new message is written into std.
    #  It triggers calling format method for incoming message that does entity
    #  recognition and normalization
    #
    def expose(msg, level)
        entities = {}  # set of recognized entities

        # collect default recognized entities
        if $RECOGNIZERS['default']
            $RECOGNIZERS['default'].each { | r |
                r.recognize(msg) { | e |
                    entities[e.type] = e unless entities.has_key?(e.type)
                }
            }
        end

        # collect artifact related recognized entities
        cur_art = $current_artifact ? $current_artifact : nil # current artifact
        if cur_art
            parent_class = cur_art.class
            while parent_class do
                recognizer = $RECOGNIZERS[parent_class.name]

                if recognizer && recognizer.length > 0
                    recognizer.each { | r |
                        r.recognize(msg) { | e |
                            entities[e.type] = e unless entities.has_key?(e.type)
                        }
                    }
                    break
                end
                parent_class = parent_class.superclass
            end
        end

        if entities.length > 0
            ent = entities.dup()
            ent[:artifact] = cur_art.class
            entities_detected(msg, ent)
        end

        # normalized found entities, expect normalize() method yield normalized entities
        normalize(entities) { | e |
            entities[e.type] = e;
        }

        a = []
        entities.each_pair { | k, v | a << v }               # collect all found entities in "a" array
        a.sort!() { |aa, bb| aa.start_at <=> bb.start_at  }  # sort found entities by its location in the message


        # perform replacing found entities fragments in initial
        # string with normalized version of the entities
        a.each_index { | i |
            e = a[i]
            msg[e.start_at .. e.end_at - 1] = e.to_s  # replace fragment in original message
            dt = e.start_at + e.length - e.end_at
            e.end_at = e.start_at + e.length
            for j in (i + 1)..(a.length-1)
                a[j].end_at = a[j].end_at + dt
                a[j].start_at += dt
            end
        }

        if cur_art && cur_art.kind_of?(StdFormater)
            self << cur_art.format(msg, level, entities) # print formatted message
        else
            self << format(msg, level, entities) # print formatted message
        end

        return a
    end

    def format(msg, level, entities = {})
        return msg if @format.nil?
        level, sign = @@signs_map[level]
        eval "\"#{@format}\""
    end

    def normalize(entities)
    end

    def endup()
        flush()
        $stderr, $stdout = @stderr, @stdout
    end

    def flush()
        if @buffer.length > 0
            expose("#{@buffer.join('')}", 0)
            @buffer.clear()
        end
    end

    def time(format = "%H:%M:%S %d/%b/%Y") Time.now.strftime(format) end

    # called when the given line has number of detected entities
    def entities_detected(msg, entities)
    end
end

module StdFormater
    def format(msg, level, entities = {})
        msg
    end
end
