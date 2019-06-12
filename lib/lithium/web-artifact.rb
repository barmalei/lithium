require 'lithium/core'
require 'lithium/file-artifact/command'

class CompileSass < FileMask
    def initialize(*args)
        super
        @sass_path ||= FileArtifact.which('sass')
        raise 'Sass compiler cannot be found' if @sass_path.nil?
    end

    def build_item(path, mt)
        out = fullpath(path)
        nm  = File.basename(out)
        ext = File.extname(nm)

        if ext.nil?
            out = out.concat(".css")
        else
            out = out[0..-(ext.length + 1)].concat(".css")
        end

        raise 'Sass compiler failed' if Artifact.exec(@sass_path, "\"#{fullpath(path)}\" \"#{out}\"")  != 0
    end

    def what_it_does() "Compile '#{@name}' sass to CSS" end
end


class OpenHTML < FileCommand
    def build()
        `open #{fullpath()}`
    end
end
