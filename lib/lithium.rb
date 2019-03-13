require 'pathname'

$lithium_version    = "3.0.0"
$lithium_date       = "Mar 2019"
$lithium_code       = File.dirname(File.expand_path(__dir__).gsub("\\", '/'))
options             = Hash[ ARGV.take_while { | a | a[0] == '-' }.collect() { | a | a[1..-1].split('=') } ]  # -name=value
artifact            = ARGV[ options.length ]
artifact_path       = artifact.nil? ? nil : artifact[/((?<![a-z])[a-z]:)?[^:]+$/]
artifact_prefix     = artifact.nil? ? nil : (artifact_path.nil? ? artifact : artifact.chomp(artifact_path))
$arguments          = ARGV.dup[(options.length + 1) .. -1]
$arguments        ||= []

# modify ruby modules lookup path
$: << File.join($lithium_code, 'lib')
require 'lithium/utils'

# For the sake of completeness correct windows letter case
$lithium_code = FileUtil.correct_win_path($lithium_code)

# artifact name is not a path
if artifact_path.nil?
    basedir = Dir.pwd
else
    i = artifact_path.index(/[\?\*\{\}]/)                                  # cut mask
    artifact_mask = i ? artifact_path[i, artifact_path.length - i] : nil   # store mask
    artifact_path = artifact_path[0, i - 1] if i && i > 0                  # cut mask from path
    artifact_path = File.expand_path(artifact_path)                        # expand path to artifact to absolute path

    basedir = artifact_path
    while !File.exists?(basedir) || !File.directory?(basedir) do
        if Pathname.new(basedir).root?
            basedir = Dir.pwd
            break
        end
        basedir = File.dirname(basedir)
    end

    artifact_path = FileUtil.correct_win_path(artifact_path)
    artifact_path = artifact_path[0 .. -2] if artifact_path.length > 1 && artifact_path[-1] == '/'
end


# start lithium
require "lithium/core-startup"
STARTUP(artifact, artifact_prefix, artifact_path, artifact_mask, options, basedir)
