require 'date'

require 'lithium/core'
require 'lithium/core-command'
require 'lithium/core-std'
require 'lithium/custom-std'

require 'lithium/java-artifact/compiler'
require 'lithium/java-artifact/runner'
require 'lithium/java-artifact/jar'
require 'lithium/java-artifact/misc'
require 'lithium/java-artifact/checkstyle'
require 'lithium/java-artifact/vaadin-sass'
require 'lithium/java-artifact/mvn'

require 'lithium/file-artifact/acquired'

require 'lithium/js-artifact'
require 'lithium/py-artifact'
require 'lithium/rb-artifact'
require 'lithium/php-artifact'
require 'lithium/tt-artifact'
require 'lithium/web-artifact'

require 'lithium/misc-artifact'

# specify how deep an exception has to be shown
Std.backtrace(0)

# STD recognizers
STD_RECOGNIZERS({
    JavaFileRunner => [
       Std::FileLocRecognizer.new('\s+at\s+(?<class>[a-zA-Z_$][\-0-9a-zA-Z_$.]*)\s*\((?<file>${file_pattern}\.(java|kt|scala))\:(?<line>[0-9]+)\)')
    ],

    [ JavaCompiler, PMD ] => [ Std::FileLocRecognizer.new() ],

    [ ValidatePythonScript, RunPythonScript ] => [
        Std::FileLocRecognizer.new('\s*File\s+\"(?<file>${file_pattern}\.py)\"\,\s*line\s+(?<line>[0-9]+)')
    ],

    [ ValidateRubyScript, RunRubyScript ] => [
        Std::FileLocRecognizer.new(ext: 'rb')
    ],

    ValidateXML  => [ Std::FileLocRecognizer.new(ext: 'xml') ],

    RunNodejs    => [ Std::FileLocRecognizer.new(ext: 'js')  ],

    CheckStyle   => [ Std::FileLocRecognizer.new('\[[a-zA-Z]+\]\s+(?<file>${file_pattern}\.java):(?<line>[0-9]+):(?<column>[0-9]+):') ],

    RunPhpScript => [ Std::FileLocRecognizer.new('\s*Parse error\:(?<file>${file_pattern}\.php)\s+in\s+on\s+line\s+(?<line>[0-9]+)')  ],

    RunMaven     => [
        Std::FileLocRecognizer.new('\s*\[ERROR\]\s+(?<file>${file_pattern}\.[a-zA-Z_]+)\:\[(?<line>[0-9]+)\s*,\s*(?<column>[0-9]+)\]')
    ],

    'default'    => [ /.*(?<url>\b(http|https|ftp|ftps|sftp)\:\/\/[^ \t]*)/  ] # URL recognizer
})

def BUILD_ARTIFACT(name)
    $current_artifact = nil

    tree = Project.current.new_artifact {
        ArtifactTree.new(name)
    }

    tree.build()
    tree.norm_tree()
    BUILD_ARTIFACT_TREE(tree.root_node)
end

def BUILD_ARTIFACT_TREE(root, level = 0)
    raise "Nil artifact cannot be built" if root.nil?
    unless root.expired
        puts "'#{root.art.name}' : #{root.art.class} is not expired", 'There is nothing to be done!' if level == 0
        return false
    end

    art = root.art
    root.children.each { | node | BUILD_ARTIFACT_TREE(node, level + 1) }
    if art.respond_to?(:build)
        begin
            $current_artifact = art
            wid = art.what_it_does()
            puts wid unless wid.nil?
            art.pre_build()
            art.build()
        rescue
            art.build_failed()
            raise
        ensure
            $current_artifact = nil
        end
        art.build_done()
    else
        puts_warning "'#{art.name}' does not declare build() method"
    end
    true
end

#
# @param  artifact - original artifact target
# @param  artifact_prefix - artifact prefix including ":". Can be nil
# @param  artifact_path   - artifact path with mask cut. Can be nil
# @param  basedir         - a related location the lithium has been started
#
def STARTUP(artifact, artifact_prefix, artifact_path, artifact_mask, basedir)
    # print header
    dt = DateTime.now.strftime("%H:%M:%S.%L")
    puts "+#{'—'*73}+"
    puts "│ Lithium - build tool v#{$lithium_version} (#{$lithium_date})  ask@zebkit.org (c) #{dt} │"
    puts "+#{'—'*73}+"
    if artifact_prefix.nil? && artifact_path.nil?
        puts 'No command or arguments have been specified'
        File.open(File.join($lithium_code, 'lib', 'lithium.txt'), 'r') { |f|
            print while f.gets
        }
        exit(-1)
    end

    # initialize stdout/stderr handler
    std_clazz = LithiumStd
    if $lithium_options['std']
        std_s = $lithium_options['std'].strip()
        std_clazz = std_s == 'null' ? nil : Module.const_get(std_s)
    end

    if std_clazz
        std_f = $lithium_options['stdformat']
        std_i = std_f ? std_clazz.new(std_f) : std_clazz.new()
        raise 'Output handler class has to inherit Std class' unless std_i.kind_of?(Std)
        at_exit() { std_i.flush() }
    end

    # load projects hierarchy
    prjs_stack = []
    path       = basedir
    prj        = nil
    while !path.nil?  do
        path = FileUtil.look_directory_up(path, '.lithium')
        unless path.nil?
            path = File.dirname(path)
            prjs_stack.unshift(path) if path != $lithium_code
            path = File.dirname(path)
        end
    end

    # add lithium if there is no project home has been identified
    if prjs_stack.length == 0
        prjs_stack.push(File.dirname($lithium_code))
    end

    prjs_stack.each { | prj_home | prj = Project.create(prj_home, prj) }

    # reg self registered artifact in lithium project if they have not been defined yet
    top_prj = prj.top
    AutoRegisteredArtifact.artifact_classes.each { | clazz |
        artname = ArtifactName.new(clazz)
        top_prj.ARTIFACT(clazz) if prj._meta[artname].nil?
    }

    # build target artifact including its dependencies
    target_artifact = ArtifactName.name_from(artifact_prefix, artifact_path, artifact_mask)

    puts "TARGET artifact: '#{target_artifact}'"
    BUILD_ARTIFACT(target_artifact)
    puts "#{DateTime.now.strftime('%H:%M:%S.%L')} '#{artifact}' has been built successfully"
end