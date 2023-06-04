require 'lithium/core-file-artifact'

class CompileSass < FileMask
    def initialize(name, &block)
        super
        @sass_path ||= Files.which('sass')
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

        raise 'Sass compiler failed' if Files.exec(@sass_path, "#{q_fullpath(path)} \"#{out}\"")  != 0
    end

    def what_it_does() "Compile '#{@name}' sass to CSS" end
end


class RunHtml < ExistentFile
    def build
        super
        `open #{fullpath()}`
    end
end
