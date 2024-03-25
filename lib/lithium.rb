require 'pathname'

# !==================================================================
#  "basedir" is starting folder to lookup lithium project definition
#
    #   1) passing an absolute path of the artifact looks for a "basedir"
#      (and as a result an owner project) basing on the absolute path
#   2) passing an absolute path of the artifact looks for a "basedir"
#      ans "basedir" as an option makes possible to build an external
#      artifact in a context of the given project
# !==================================================================
$lithium_version    = '5.4.0'
$lithium_date       = 'Jul 2023'
$lithium_code       = File.dirname(File.expand_path(__dir__).gsub("\\", '/'))
$lithium_options    = Hash[ ARGV.take_while { | a | a[0] == '-' }.collect() { | a | a[1..-1].split('=') } ]  # -name=value
$lithium_args       = ARGV.dup[($lithium_options.length + 1) .. -1]
$lithium_args     ||= []

# modify ruby modules lookup path
$: << File.join($lithium_code, 'lib')

artifact        = ARGV[ $lithium_options.length ]
artifact_path   = artifact.nil? ? nil : artifact[/((?<![a-zA-Z])[a-zA-Z]:)?[^:]+$/]
artifact_prefix = artifact.nil? ? nil : (artifact_path.nil? ? artifact : artifact.chomp(artifact_path))

if $lithium_options.has_key?('basedir')
    bd = $lithium_options['basedir']
    raise 'Nil basedir has been passed' if bd.nil?
    basedir = File.realpath(bd)
    raise "Invalid '#{basedir}' project base directory has been passed" unless File.directory?(basedir)
    Dir.chdir basedir
else
    basedir = Dir.pwd
end

# if artifact path is an absolute and "basedir" has not been passed as
# an option then basedir is computed by passed artifact path if possible
# otherwise pwd is used
unless artifact_path.nil?
    i = artifact_path.index(/[\?\*\{\}]/)                                # detect mask
    artifact_mask = i ? artifact_path[i, artifact_path.length - i] : nil # store mask
    artifact_path = artifact_path[0, i] if !i.nil? && i >= 0             # cut mask from path

    if File.absolute_path?(artifact_path)
        # resolve link to real path for absolute paths
        artifact_path = File.realpath(artifact_path) if File.exist?(artifact_path)
        unless $lithium_options.has_key?('basedir')
            basedir = artifact_path
            while !File.directory?(basedir) do
                if Pathname.new(basedir).root?
                    basedir = Dir.pwd
                    break
                end
                basedir = File.dirname(basedir)
            end
        end
    elsif artifact_path == '.' || artifact_path == './'
        artifact_path = basedir
    elsif artifact_path.start_with?('./') || artifact_path.start_with?('../')
        artifact_path = File.join(basedir, artifact_path)
    elsif !artifact_path.start_with?('.env/')
        artifact_path = File.join(basedir, artifact_path)
    end

    artifact_path = Pathname.new(artifact_path).cleanpath.to_s
    artifact_path = artifact_path[0 .. -2] if artifact_path.length > 1 && artifact_path[-1] == '/'
end

# start lithium
require 'lithium/core-startup'
STARTUP(artifact, artifact_prefix, artifact_path, artifact_mask, basedir)