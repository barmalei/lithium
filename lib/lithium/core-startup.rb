require 'date'

require 'lithium/core'
require 'lithium/core-command'
require 'lithium/std-pattern'
require 'lithium/std-core'
require 'lithium/std-custom'

require 'lithium/java-artifact/compiler'
require 'lithium/java-artifact/runner'
require 'lithium/file-artifact/archive'
require 'lithium/java-artifact/jar'
require 'lithium/java-artifact/misc'
require 'lithium/java-artifact/checkstyle'
require 'lithium/java-artifact/vaadin-sass'
require 'lithium/java-artifact/mvn'
require 'lithium/java-artifact/gradle'
require 'lithium/java-artifact/ant'

require 'lithium/file-artifact/acquired'

require 'lithium/js-artifact'
require 'lithium/py-artifact'
require 'lithium/rb-artifact'
require 'lithium/php-artifact'
require 'lithium/tt-artifact'
require 'lithium/dart-artifact'
require 'lithium/gcloud-artifact'
require 'lithium/web-artifact'
require 'lithium/c-artifact'

require 'lithium/xml-artifact'

# TODO:
# Proposed pattern definition syntactic
#  -> {
#     PATTERN(JavaExceptionLocPattern.new).TO(JavaFileRunner)

#     PATTERN {
#         any('^\s*File\s+'); group(:location) { dquotes { file('py') }; any(',\s*line\s+'); line; }
#     }.TO(ValidatePythonScript, RunPythonScript)
# }

# STD recognizer
PATTERNS ({
    JavaFileRunner => [
       # '\s+at\s+(?<class>[a-zA-Z_$][\-0-9a-zA-Z_$.]*)\s*\((?<file>${file_pattern}\.(java|kt|scala))\:(?<line>[0-9]+)\)'
       JavaExceptionLocPattern.new()
    ],

    JavaCompiler => [
        # Std::RegexpRecognizer.new('\:\s+(?<status>error)\:\s+(?<statusMsg>.*)').classifier('compile'),
        StdPattern.new() {
            location('java', 'scala'); spaces(); group(:level, 'error|warning'); colon(); spaces(); group(:message, '.*$')
        }
    ],

    CppCompiler => [
        StdPattern.new() {
            location('cpp', 'c'); spaces(); group(:level, 'error|note'); colon(); spaces(); group(:message, '.*$')
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
                convert?(:level) { | l |
                    return l.downcase() if ['WARNING', 'ERROR'].include?(l)
                }
            }
        }
    ],

    KotlinCompiler => [
        KotlinCompileErrorPattern.new()
    ],

    ScalaCompiler => [
         StdPattern.new {
            group(:message, '\-\-\s*\[E[0-9]+\]\s+[^:]+'); colon; spaces; location('scala');
        }
    ],

    GroovyCompiler => [
        GroovyCompileErrorPattern.new()
    ],

    [ ValidatePythonScript, RunPythonScript ] => [
        StdPattern.new {
            any('^\s*File\s+'); group(:location) { dquotes { file('py') }; any(',\s*line\s+'); line; }
        }
    ],

    ValidateRubyScript => [

    ],

    RunRubyScript  => [
        StdPattern.new(2) {
            any('^\s*from\s+'); location('rb')
            COMPLETE_PATH()
        }
    ],

    ValidateXML => [
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

    # test.dart:8:1: Error: Variables must be declared using the keywords 'const', 'final', 'var' or a type name.
    [ ValidateDartCode, RunDartCode ] => [
        StdPattern.new {
            location('dart')
            any('\s+Error:\s*')
            group(:message, '.*$')
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

    RunGradle => [
        # '\[ERROR\]\s+(?<file>${file_pattern}\.[a-zA-Z_]+)\:\[(?<line>[0-9]+)\s*,\s*(?<column>[0-9]+)\]'
        StdPattern.new {
            any('e\:\s*'); group(:location) { file; colon; any('\s*'); rbrackets { line; any('\s*,\s*'); column? }; colon; group(:message, '.*$') }
        },

        JavaExceptionLocPattern.new()
    ],

    #e: /Users/brigadir/projects/newtask/src/main/kotlin/com/signicat/interview/security/TokenFactory.kt: (30, 31): Expecting an element

    Artifact => [
        URLPattern.new,
        StdPattern.new(2) {
            any('^\s*from\s+'); location('rb')
            COMPLETE_PATH()
        },
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
    prjs_stack.each { | prj_home | prj = Project.new(prj_home, owner:prj) }

    # print header
    dt = DateTime.now.strftime("%H:%M:%S.%L")
    unless $lithium_options.has_key?('header') && $lithium_options['header'] != '2'
        puts "+#{'—'*73}+"
        puts "│ Lithium (build tool) v#{$lithium_version} (#{$lithium_date})  ask@zebkit.org (c) #{dt} │"
        puts "+#{'—'*73}+"
        $stdout.flush()
    else
        puts "#{dt} Running lithium v#{$lithium_version}" if $lithium_options['header'] == '1'
    end

    # call block that has to be run after lithium has been initialized and ready to process
    $ready_list.each { | block |
        block.call
    }

    # build target artifact including its dependencies
    target_artifact = ArtifactName.name_from(artifact_prefix, artifact_path, artifact_mask)

    puts "TARGET '#{target_artifact}' in '#{Project.current}' home"
    built_art = Project.current.BUILD(target_artifact)

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
