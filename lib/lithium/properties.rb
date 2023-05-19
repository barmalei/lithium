require 'lithium/core'

class Properties
    def self.parse(str)
        str = str.gsub!(/(^\s*[!\#].*$)|(^\s+)|(\s+$)|(\\\s*$[\n\r]+)|(^\s*[\n\r]\s*$)/, '')
        unless str.nil?
            str.each_line { | line |
                m = /([^=]+)=(.*)/.match(line)
                yield m[1].strip, m[2].strip unless m.nil?
            }
        end
    end

    def self.fromStr(str)
        props = {}
        parse(str) { | n, v |
            props[n] = v
        }
        return props
    end

    def self.fromFile(path)
        raise "File '#{path}' doesn't exist" unless File.exist?(path)
        raise "Path '#{path}' points to a directory" if File.directory?(path)
        return fromStr(IO.read(path))
    end

    def self.fromMask(mask, find_first = false)
        res = FileArtifact.dir(mask)
        raise "There is no any file that can be identified with '#{mask}'" if res.length == 0
        raise "Few files ('#{res}') have been identified by #{mask}" if res.length > 1 && find_first == false
        return self.fromFile(res[0])
    end

    def self.property(mask, name, find_first = false)
        self.fromMask(mask, find_first)[name]
    end
end
