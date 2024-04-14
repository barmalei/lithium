require 'net/http'
require 'uri'

require 'lithium/core-file-artifact'

class RemoteFile < FileArtifact
    attr_reader :uri

    def initialize(name, &block)
        super
        @uri ||= $lithium_args[0]
    end

    def build()
        raise 'Remote artifact URI was not specified' if @uri.nil?
        uri = URI.parse(@uri)
        m = method("#{uri.scheme.downcase}_fetch")
        raise "Unsupported protocol '#{uri.scheme}'" if m.nil?
        m.call(uri)
    end

    def expired?
        !File.exist?(fullpath) || File.size(fullpath) == 0
    end

    def what_it_does()
        "Download '#{@name}'\n    from '#{@uri}'"
    end

    def clean()
        fp = fullpath()
        File.delete(lp) if File.file?(fp)
    end
end

class HttpRemoteFile < RemoteFile
    def https_fetch(uri)
        http_fetch(uri)
    end

    def fetch(uri)
        response = Net::HTTP.get_response(uri)
        case response
          when Net::HTTPSuccess then
            response
          when Net::HTTPRedirection then
            location = response['location']
            puts_warning("Redirected to '#{location}'")
            fetch(URI(location))
          else
            raise "HTTP code = '#{response.code}', msg = '#{response.message}' error"
        end
    end

    def http_fetch(uri)
        r = fetch(uri)
        open(fullpath, 'wb') { | file |
            file.write(r.body)
        }
    end
end
