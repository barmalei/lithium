require 'json'
require 'lithium/std-pattern'

$PATTERNS = {}

def PATTERNS(args)
    # normalize keys and values
    args.each_pair { | key, patterns |
        # normalize keys
        keys = []
        if key.kind_of?(Array)
            keys = keys.concat(key)
        else
            keys.push(key)
        end

        keys.each { | key |
            raise "Pattern key has to be a class" unless key.kind_of?(Class)
            key = key.name
            $PATTERNS[key] = [] unless $PATTERNS.has_key?(key)
            $PATTERNS[key].push(*patterns)
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

def puts_exception(*args)
    if Std.std
        Std.std.puts_exception(*args)
    else
        puts args
    end
end

class Std
    @@std = nil  # singleton object static variable

    # Make std singleton object
    def Std.new(*args, &block)
        @@std.flush() if @@std
        @@std = super(*args, &block)
        $stdout = @@std
        $stderr = @@std
        @@std
    end

    def Std.std() @@std end

    def initialize()
        @buffer = []
    end

    def <<(msg)
        STDOUT << msg
        STDOUT.flush()
    end

    def puts(*args)
        args.each { | a |
            a = a.to_s
            write((a.length == 0 || a[-1, 1] != "\n") ? "#{a}\n" : a)
        }
    end

    def print(*args) args.each { | a | write(a.to_s) } end

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

    def write(msg, level = -1)
        msg = msg.to_s
        if msg.length > 0
            level = $! ? 3 : 0 if level == -1
            begin
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
            rescue Exception => e
                # fatal error has happened in Std implementation
                begin
                    STDERR.puts 'Fatal error has occurred:'
                    STDERR.puts " #{$!.message}:"
                    e.backtrace.each { | line | STDERR.puts "     #{line}" }
                rescue
                end
            end
        end
    end

    def puts_exception(e, bts = -1)
        expose("#{e.message}\n", 3)
        bt  = e.backtrace()
        max = bts < 0 ? bt.length : [bts, bt.length].min
        for i in 0..max - 1
            expose(" from  #{bt[i]}\n", 3)
        end
    end

    #
    #  This method is called every time a new message is written into std.
    #  It triggers calling format method for incoming message that does entity
    #  recognition and normalization
    #
    def expose(msg, level = 0)
        # collect artifact related recognized entities
        cur_art = $current_artifact  # current artifact

        parent_class = cur_art.nil? ? Artifact : cur_art.class
        while parent_class do
            patterns = $PATTERNS[parent_class.name]

            if !patterns.nil? && patterns.length > 0
                patterns.each { | pt |
                    mt = pt.match(msg)

                    unless mt.nil?
                        msg   = pattern_matched(msg, pt, mt)
                        level = mt.level if mt.level > level
                    end
                }
                break
            end
            parent_class = parent_class.superclass
        end

        # check if an artifact has a custom formatter
        if !cur_art.nil? && cur_art.kind_of?(StdFormater)
            self << cur_art.format(msg, level) # print formatted message
        else
            self << format(msg, level) # print formatted message
        end
    end

    def pattern_matched(msg, pattern, match)
        msg
    end

    def format(msg, level)
        msg
    end

    def flush()
        if @buffer.length > 0
            expose("#{@buffer.join('')}", 0)
            @buffer.clear()
        end
    end

    def time(format = "%H:%M:%S %d/%b/%Y") Time.now.strftime(format) end
end

module StdFormater
    def format(msg, level)
        msg
    end
end

