require 'net/http'
require 'uri'

require 'lithium/core'

class RemoteFile < FileArtifact
    attr_reader :uri

    def initialize(name, &block)
        super
        @uri ||= $lithium_args[0]
    end

    def build()
        uri = URI.parse(@uri)
        m = method("#{uri.scheme.downcase}_fetch")
        raise "Unsupported protocol '#{uri.scheme}'" if m.nil?
        m.call(uri)
    end

    def expired?
        !File.exists?(fullpath) || File.size(fullpath) == 0
    end

    def what_it_does()
        "Download '#{@name}'\n    from '#{@uri}'"
    end

    def clean()
        fp = fullpath()
        File.delete(lp) if File.file?(fp)
    end
end

class HTTPRemoteFile < RemoteFile
    def http_fetch(uri)
        Net::HTTP.get_response(uri) { | res |
            raise "Failed (#{res.code}) to get data by '#{uri}'"if res.code != '200'
            File.open(fullpath, 'w') { | f |
                res.read_body { | data |
                    f.write(data)
                }
            }
        }
    end
end
