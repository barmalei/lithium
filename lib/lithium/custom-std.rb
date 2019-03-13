require 'lithium/core-std'
require 'pathname'


class LithiumStd < Std
    def initialize(format = '(#{level})  #{sign}  #{msg}')
       super
    end
end

class HtmlStd < LithiumStd
    def initialize(format = '<div><b>(#{level})</b>&nbsp;&nbsp;#{sign}&nbsp;&nbsp;#{msg}</div>')
        super
    end

    def normalize(entities)
        fe = entities['file']
        if fe
            ln, bn, dr = entities['line'], File.basename(fe), File.dirname(fe)
            bn = File.join(File.basename(dr), bn) if dr
            yield fe.clone("<a href='txmt://open?url=file://#{fe}&line=#{ln}'>#{bn}</a>")
        end

        ue = entities['url']
        yield ue.clone("<a href=\"javascript:TextMate.system('open #{ue}')\">#{ue}</a>") if ue
    end

    def format(msg, level, entities)
        msg = super(msg, level, entities)
        msg = "<font color='red'>#{msg}</font>" if level == 2
        msg = "<font color='orange'>#{msg}</font>" if level == 3
        msg = "<font color='blue'>#{msg}</font>" if level == 1
        msg.gsub('  ', '&nbsp;&nbsp;')
    end
end

class SublimeStd < LithiumStd
    def normalize(entities)
        fe = entities['file']
        yield fe.clone("[[#{fe}:#{entities['line']}]]") if fe

        le = entities['line']
        yield le.empty if le

        ce = entities['column']
        yield ce.empty if ce
    end
end

