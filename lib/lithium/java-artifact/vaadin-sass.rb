require 'lithium/file-artifact/command'
require 'lithium/java-artifact/base'
require 'lithium/utils'


class BuildVaadinSass < FileCommand
    required JAVA

    def initialize(*args)
        super
    end

    def build()
        fp = fullpath()
        on = "#{File.basename(fp, 'scss')}css"

        r = exec4(java().java(), '-cp ', "'#{fullpath('/WEB-INF/lib/*')}'",
                  "com.vaadin.sass.SassCompiler",
                  fp,
                  File.join(File.dirname(fp), on))

        raise 'SASS error' if r != 0
    end

    def what_it_does() "Generate '#{@name}' CSS" end
end

