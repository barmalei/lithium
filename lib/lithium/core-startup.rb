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
require 'lithium/java-artifact/ant'

require 'lithium/file-artifact/acquired'

require 'lithium/js-artifact'
require 'lithium/py-artifact'
require 'lithium/rb-artifact'
require 'lithium/php-artifact'
require 'lithium/tt-artifact'
require 'lithium/web-artifact'

require 'lithium/misc-artifact'

# TODO:
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

    JavaCompiler => [
        # Std::RegexpRecognizer.new('\:\s+(?<status>error)\:\s+(?<statusMsg>.*)').classifier('compile'),
        StdPattern.new() {
            location('java', 'scala'); spaces(); group(:level, 'error'); colon(); spaces(); group(:message, '.*$')
        }
    ],

    JDTCompiler => [
        StdPattern.new() {
            num(); dot(); spaces(); group(:level, 'WARNING|ERROR'); spaces(); any('in'); spaces(); group(:location) {
                file('java')
                spaces()
                rbrackets {
                    any("at line ")
                    line()
                }
            }

            MATCHED {
                convert?(:level) { | b |
                    if b == 'WARNING'
                        'warning'
                    elsif b == 'ERROR'
                        'error'
                    end
                }
            }
        }
    ],

    [ KotlinCompiler ] => [
        KotlinCompileErrorPattern.new()
    ],

    [ GroovyCompiler ] => [
        GroovyCompileErrorPattern.new()
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

    TypeScriptCompiler => [
        StdPattern.new {
            group(:location) {
                file('ts')
                rbrackets {
                    line; comma; column;
                }
                colon
            }
            group(:message, '.*$')

            COMPLETE_PATH()
        }
    ],

    JavaCheckStyle => [
        StdPattern.new {
            brackets { identifier(:level) }; spaces; location('java')
        }
    ],

    PMD => [
        StdPattern.new() {
            location('java'); spaces(); group(:message, '.*$')
        }

        # StdPattern.new {
        #     brackets { identifier(:level) }; spaces; location('java')
        # }
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

    [ ValidatePhpScript, RunPhpScript ] => [
        StdPattern.new {
            any('Parse error\:'); any; any('in\s+'); group(:location) {
                file('php'); any('\s+on line\s+'); line;
            }
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

#
# @param  artifact        - original artifact target
# @param  artifact_prefix - artifact prefix including ":". Can be nil
# @param  artifact_path   - artifact path with mask cut. Can be nil
# @param  basedir         - a related location the lithium has been started
#
def STARTUP(artifact, artifact_prefix, artifact_path, artifact_mask, basedir)
    # print header
    dt = DateTime.now.strftime("%H:%M:%S.%L")
    puts "+#{'—'*77}+"
    puts "│ Lithium (build tool) v#{$lithium_version} (#{$lithium_date})  sandtube@gmail.com (c) #{dt} │"
    puts "+#{'—'*77}+"
    $stdout.flush()

    if artifact_prefix.nil? && artifact_path.nil?
        puts 'No command or arguments have been specified'
        File.open(File.join($lithium_code, 'lib', 'lithium.txt'), 'r') { | f |
            print while f.gets
        }
        exit(-1)
    end

    # collect projects hierarchy into array
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
            std_clazz = std_s == 'none' ? nil : Module.const_get(std_s)
        rescue NameError
            raise "Unknown stdout / stderr class name '#{std_s}'"
        end
    end

    if std_clazz
        std_i = std_clazz.new(prjs_stack.last)
        raise 'Output handler class has to inherit Std class' unless std_i.kind_of?(Std)
    end

    # load projects hierarchy artifacts
    prjs_stack.each { | prj_home | prj = Project.new(prj_home, prj) }

    # reg self registered artifact in lithium project if they have not been defined yet
    top_prj = prj.top
    AutoRegisteredArtifact.artifact_classes.each { | clazz |
        meta = ArtifactName.new(clazz)
        top_prj.ARTIFACT(meta) if prj.find_meta(meta).nil?
    }

    # build target artifact including its dependencies
    target_artifact = ArtifactName.name_from(artifact_prefix, artifact_path, artifact_mask)

    puts "TARGET artifact: '#{target_artifact}'"
    built_art = Project.build(target_artifact)

    INFO.info(built_art) if $lithium_options.key?('i')

    # introspect property of an artifact
    if $lithium_options.key?('i:p')
        props = $lithium_options['i:p'].split(',')
        props.each { | prop |
            val = built_art
            prop.split('.').each { | part |
                if part.start_with?('@')
                    val = val.instance_variable_get(part.to_sym)
                else
                    val = val.send(part.to_sym)
                end
            }

            puts "    #{prop} = #{val}"
        }
    end

    puts "#{DateTime.now.strftime('%H:%M:%S.%L')} Building of '#{artifact}' has been done"
end
