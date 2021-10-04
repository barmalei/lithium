require 'lithium/file-artifact/remote'

require 'fileutils'
require 'lithium/file-artifact/command'
require 'lithium/java-artifact/base'
require 'lithium/std-core'




code = Artifact.exec("git", "symbolic-ref --short -q HEAD") { | inp, out, th |
    puts out.readlines
}

puts code.exit
