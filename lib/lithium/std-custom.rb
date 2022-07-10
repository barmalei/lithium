require 'lithium/std-core'

class LithiumStd < Std
    # TODO: remove one of the following line
    @@signs_map = ['INF', 'WAR', 'ERR', 'EXC']
    @@signs_map = ['I', 'W', 'E', 'X']

    def initialize(prj_home = nil)
        super()
        @log_io, @log_file, @prj_home = nil, nil, prj_home

        unless @prj_home.nil?
            @log_file = File.join(@prj_home, '.lithium', 'std-out-entities.json')
            File.delete(@log_file) if File.exist?(@log_file)

            at_exit {
                finalize()
            }
        end
    end

    def finalize
        unless @log_io.nil?
            @log_io.puts ']'
            @log_io.close
            @log_file = nil
        end
    end

    def format(msg, level, parent)
        slevel   = @@signs_map[level]
        artclass = $current_artifact.nil? ? 'STR' : $current_artifact.class.abbr
        "(#{slevel}) [#{artclass}]  #{msg}"
    end

    def pattern_matched(msg, pattern, match)
        unless @log_file.nil?
            comma = ','
            if @log_io.nil?
                @log_io = File.open(@log_file, 'a')
                @log_io.puts '['
                comma = ''
            end

            entry = match.to_json_obj(true)
            entry[:patternClass]  = pattern.class.name
            entry[:artifactClass] = $current_artifact.nil? ? nil : $current_artifact.class.name
            entry[:errorLevel]    = pattern.level

            @log_io.puts comma + entry.to_json
        end
        return msg
    end
end

class SublimeStd < LithiumStd
    def pattern_matched(msg, pattern, match)
        msg = super

        # if match.has_group?(:message)
        #     match = match.replace(:message, '')
        # end

        if match.has_group?(:location)
            path = match[:file][:value]
            return match.replace(:location, "[[#{path}:%{line}]]").to_s if !path.nil? && File.exist?(path)
        end

        return msg
    end
end

class VSCodeStd < LithiumStd
    def pattern_matched(msg, pattern, match)
        msg = super
        if match.has_group?(:location)
            return match.replace?(:location, 'file://%{file}#%{line}').to_s if match.has_group?(:location)
        end
        return msg
    end
end
