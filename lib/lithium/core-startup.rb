require 'date'

require 'lithium/core'
require 'lithium/core-command'
require 'lithium/std-pattern'
require 'lithium/std-core'
require 'lithium/std-custom'

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

# Proposed pattern definition syntacsis
#  -> {
#     PATTERN(JavaExceptionLocPattern.new).TO(JavaFileRunner)

#     PATTERN {
#         any('^\s*File\s+'); group(:location) { dquotes { file('py') }; any(',\s*line\s+'); line; }
#     }.TO(ValidatePythonScript, RunPythonScript)
# }

# STD recognizers
PATTERNS ({
    JavaFileRunner => [
       # '\s+at\s+(?<class>[a-zA-Z_$][\-0-9a-zA-Z_$.]*)\s*\((?<file>${file_pattern}\.(java|kt|scala))\:(?<line>[0-9]+)\)'
       JavaExceptionLocPattern.new()
    ],

    [ JavaCompiler, PMD ] => [
        # Std::RegexpRecognizer.new('\:\s+(?<status>error)\:\s+(?<statusMsg>.*)').classifier('compile'),
        JavaCompileErrorPattern.new()
    ],

    [ ValidatePythonScript, RunPythonScript ] => [
        # '\s*File\s+\"(?<file>${file_pattern}\.py)\"\,\s*line\s+(?<line>[0-9]+)')
        StdPattern.new {
            any('^\s*File\s+'); group(:location) { dquotes { file('py') }; any(',\s*line\s+'); line; }
        }
    ],

    [ ValidateRubyScript, RunRubyScript ] => [

    ],

    ValidateXML  => [
        FileLocPattern.new('xml')
    ],

    RunNodejs => [
        FileLocPattern.new('js')
    ],

    JavaCheckStyle => [
        # '\[[a-zA-Z]+\]\s+(?<file>${file_pattern}\.java):(?<line>[0-9]+):(?<column>[0-9]+)?'
        StdPattern.new {
            brackets { identifier(:level) }; spaces; location('java')
        }
    ],

    JavaScriptHint => [
        # '^(?<file>${file_pattern}\.js):\s*line\s*(?<line>[0-9]+)\s*\,\s*col\s+(?<column>[0-9]+)?'
        StdPattern.new {
            any('^\s*')
            group(:location) {
                file('js'); colon; line; any('\s*col\s+'); column?
                column
            }
        }
    ],

    RunPhpScript => [
        # '\s*Parse error\:(?<file>${file_pattern}\.php)\s+in\s+on\s+line\s+(?<line>[0-9]+)'
        StdPattern.new {
            any('\s*Parse error\:'); group(:location) { file('php'); any('\s+in\s+on\s+'); line }
        }
    ],

    RunMaven => [
        # '\[ERROR\]\s+(?<file>${file_pattern}\.[a-zA-Z_]+)\:\[(?<line>[0-9]+)\s*,\s*(?<column>[0-9]+)\]'
        StdPattern.new {
            any('^\[ERROR\]\s+'); group(:location) { file; colon; brackets { line; any('\s*,\s*'); column? }; }
        },

        # '(?<file>${file_pattern}\.[a-zA-Z_]+)\:(?<line>[0-9]+)\:(?<column>[0-9]+)'
        StdPattern.new {
           any('^(\[INFO\]|\[WARNING\]|\[ERORR\])\s*'); location;
        },

        JavaExceptionLocPattern.new()
    ],

    Artifact => [
        URLPattern.new,
        FileLocPattern.new
    ]
})

def BUILD_ARTIFACT(name, &block)
    $current_artifact = nil

    # instantiate tree artifact in a context of project to have proper owner set
    tree = Project.current.new_artifact {
        ArtifactTree.new(name)
    }

    tree.build()
    tree.norm_tree()
    return BUILD_ARTIFACT_TREE(tree.root_node)
end

def BUILD_ARTIFACT_TREE(root, level = 0)
    raise 'Nil artifact cannot be built' if root.nil?
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
            art.instance_eval(&art.done) unless art.done.nil?

            art.build_done()
        rescue
            art.build_failed()
            level = $lithium_options.key?('verbosity') ? $lithium_options['verbosity'].to_i : 0
            puts_exception($!, 0) if level == 0
            puts_exception($!, 3) if level == 1
            raise if level == 2
            return false
        ensure
            $current_artifact = nil
        end
    else
        puts_warning "'#{art.name}' does not declare build() method"
    end
    return true
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
    $stdout.flush()

    if artifact_prefix.nil? && artifact_path.nil?
        puts 'No command or arguments have been specified'
        File.open(File.join($lithium_code, 'lib', 'lithium.txt'), 'r') { | f |
            print while f.gets
        }
        exit(-1)
    end

    # load projects hierarchy
    prjs_stack = []
    path       = basedir
    prj        = nil
    while !path.nil? do
        path = FileArtifact.look_directory_up(path, '.lithium')
        unless path.nil?
            path = File.dirname(path)
            prjs_stack.unshift(path) if path != $lithium_code
            path = File.dirname(path)
        end
    end

    # add lithium if there is no project home has been identified
    prjs_stack.push(File.dirname($lithium_code)) if prjs_stack.length == 0

    # initialize stdout / stderr handler
    std_clazz = LithiumStd
    if $lithium_options['std']
        std_s = $lithium_options['std'].strip()
        begin
            std_clazz = std_s == 'null' ? nil : Module.const_get(std_s)
        rescue NameError
            raise "Unknown stdout / stderr class name '#{std_s}'"
        end
    end

    if std_clazz
        std_i = std_clazz.new(prjs_stack.last)
        raise 'Output handler class has to inherit Std class' unless std_i.kind_of?(Std)
    end

    # load projects hierarchy artifacts
    prjs_stack.each { | prj_home | prj = Project.create(prj_home, prj) }

    # reg self registered artifact in lithium project if they have not been defined yet
    top_prj = prj.top
    AutoRegisteredArtifact.artifact_classes.each { | clazz |
        meta = ArtifactName.new(clazz)
        top_prj.ARTIFACT(meta) if prj.find_meta(meta).nil?
    }

    # build target artifact including its dependencies
    target_artifact = ArtifactName.name_from(artifact_prefix, artifact_path, artifact_mask)

    puts "TARGET artifact: '#{target_artifact}'"
    if BUILD_ARTIFACT(target_artifact)
        puts "#{DateTime.now.strftime('%H:%M:%S.%L')} '#{artifact}' has been built successfully"
    else
        puts_error "#{DateTime.now.strftime('%H:%M:%S.%L')} Building of '#{artifact} has failed"
    end
end

