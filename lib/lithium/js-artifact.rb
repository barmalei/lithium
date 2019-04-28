require 'fileutils'
require 'tmpdir'

require 'lithium/core'
require 'lithium/file-artifact/command'
require 'lithium/java-artifact/runner'
require 'lithium/file-artifact/acquired'


class JS < EnvArtifact
    include AutoRegisteredArtifact

    attr :compressorClassName

    def initialize(*args)
        super
        @compressorClassName ||= 'UglifyJavaScript'
    end

    def compressor(path, &block)
        c = Object.const_get(@compressorClassName)
        return c.new(path, &block)
    end

    def what_it_does() "Initialize JavaScript environment '#{@name}'" end
end

# Run JS with nodejs
class RunNodejs < FileCommand
    def build()
        raise "Running of '#{@name}' JS script failed" if Artifact.exec('node', "\"#{fullpath}\"") != 0
    end

    def what_it_does()
        "Run JS '#{@name}' script with nodejs"
    end
end


# compress java script
class CompressJavaScript < FileCommand
    required JS

    def initialize(*args)
        super
    end

    def build()
        f = fullpath()

        if @output_dir
            o = fullpath(File.join(@output_dir, File.basename(f)))
        else
            e = File.extname(f)
            n = File.basename(f).chomp(e)
            o = File.join(File.dirname(f), "#{n}.min#{e}")
        end

        raise "Source '#{f}' JS script file cannot be found "     unless File.exists?(src)
        raise "Destination directory for '#{o}' cannot be found " unless File.exists?(File.dirname(dest))
        raise "Output file is identical to input one '#{f}'"      if f == o

        compress(f, o)
    end

    def compress(src, dest) end

    def what_it_does() "Compress '#{@name}' JS script" end
end

# nodejs uglyfier
class UglifyJavaScript < CompressJavaScript
    attr_accessor :lib, :options

    def initialize(*args)
        super

        unless @lib
            @lib = File.join(owner.homedir, "node_modules", "uglify-js") unless owner.nil?
            @lib = File.join($lithium_code, "node_modules", "uglify-js") if @lib.nil? || !File.exists?(@lib)
        end

        raise "'uglify' node JS module has to be installed in a context of target project ('#{owner}'') " unless File.exists?(@lib)

        @options ||= {}
    end

    def compress(infile, outfile)
        opt = [ File.join(@lib, 'bin', 'uglifyjs') ]
        opt << @options
        opt << infile
        opt << '>'
        opt << outfile
        raise 'JS Uglify failed' if Artifact.exec(opt.join(' ')) != 0
    end

    def what_it_does() "Uglify (nodejs) #{@name}' JS script" end
end


class CompressedJavaScriptFile < FileArtifact
    required JS

    def initialize(*args)
        super

        unless @source
            s = '.min.js'
            i = @name.rindex(s)
            raise "JS compressed file name '#{@name}' cannot be used to identify input file name automatically" if i.nil? || i != (@name.length - s.length)
            @source = @name[0, i + 1] + 'js'
        end
    end

    def expired?()
       return !File.exists?(fullpath())
    end

    def cleanup()
       File.delete(fullpath()) if File.exists?(fullpath())
    end

    def build()
        fp = fullpath(@source)
        raise "Source file '#{fp}' cannot be found" unless File.exists?(fp)
        compress(fp, fullpath())
    end

    def compress(src, dest)
        UglifyJavaScript.new(src)
    end

    def what_it_does() "Compress #{@name} file of '#{@source}' JS script" end
end

class CombinedJavaScript < MetaGeneratedFile
    def build()
        f = File.new(fullpath(), 'w')
        f.write("(function() {\n\n")
        @meta.list_items(true) { |n,t|
            puts " add #{n}"
            f.write(File.readlines(n).join())
            f.write("\n\n")
        }
        f.write("\n\n})();")
        f.close()
    end

    def cleanup()
       File.delete(fullpath()) if File.exists?(fullpath())
    end

    def what_it_does() "Combine JavaScript files into '#{@name}'" end
end

class GenerateJavaScriptDoc < FileArtifact
    def initialize(name)
        super
        @config   ||= nil
        @template ||= nil
        @input    ||= '.'
        raise "Name has to be directory" if File.exists?(fullpath()) && !File.directory?(fullpath())
    end

    def expired?()
       return !File.exists?(fullpath())
    end

    def cleanup
        FileUtils.rmtree(fullpath()) if File.exists?(fullpath()) && File.directory?(fullpath())
    end

    def build
        p = fullpath()
        raise "Invalid artifact path '#{p}'" if File.exists?(p) && !File.directory?(p)

        args = [ 'yuidoc', '-o ', p, '-n', '-C' ]

        unless @template.nil?
            t = fullpath(@template)
            raise "Invalid template path '#{t}'" if !File.exists?(t) || !File.directory?(t)
            args << "-t " << t
        end

        unless @config.nil?
            c = fullpath(@config)
            raise "Invalid template path '#{c}'" if !File.exists?(c) || File.directory?(c)
            args << '-c ' << c
        end

        istmp = false
        i = fullpath(@input)
        raise "Invalid input path '#{i}'" if !File.exists?(i)
        unless File.directory?(i)
            tmp = Dir.mktmpdir()
            FileUtils.cp(i, tmp.to_s)
            i = tmp
            istmp = true
        end

        args << i

        Artifact.exec(*args)

        FileUtils.rmtree(i) if istmp
    end

    def what_it_does()
        "Generate '#{@name}' JavaScript doc by '#{@input}'"
    end
end

