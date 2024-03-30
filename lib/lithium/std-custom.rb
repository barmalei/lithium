require 'lithium/std-core'

module LogStdPattern
    def log_io
        if @log_io.nil? && !@prj_home.nil?
            log_file = File.join(@prj_home, '.lithium', 'std-out-entities.json')
            File.delete(log_file) if File.exist?(log_file)

            @log_io = File.open(log_file, 'a')
            @log_io.puts '['

            at_exit {
                unless @log_io.nil?
                    @log_io.puts ']'
                    @log_io.close
                end
            }
        end
        return @log_io
    end

    def pattern_matched(msg, pattern, match)
        io = log_io()
        unless io.nil?
            entry = match.to_json_obj(true)
            entry[:patternClass]  = pattern.class.name
            entry[:artifactClass] = $current_artifact.nil? ? nil : $current_artifact.class.name
            entry[:errorLevel]    = pattern.level
            log_io.puts entry.to_json
        end
        return msg
    end
end

class LithiumStd < Std
    # to enable saving matched messages as JSON un-comment the code blow
    # JSON file can be useful to provide errors list to a IDE as a file
    #include LogStdPattern

    @@signs_map = ['I', 'W', 'E', 'X']

    def initialize(prj_home = nil)
        super()
        @prj_home = prj_home
    end

    def format(msg, level, parent)
        slevel   = @@signs_map[level]
        artclass = $current_artifact.nil? ? 'STR' : $current_artifact.class.abbr
        "(#{slevel}) [#{artclass}]  #{msg}"
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
        elsif match.has_group?(:current_location)
            path = $current_artifact.fullpath
            return match.replace(:current_location, "[[#{path}:%{line}]]").to_s if !path.nil? && File.exist?(path)
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
