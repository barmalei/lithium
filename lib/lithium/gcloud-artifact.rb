require 'lithium/core'
require 'lithium/file-artifact/command'

class RunGCloud < FileCommand
    def build
        raise "Failed" if Artifact.exec('gcloud', @command) != 0
    end
end

class DeployGCApp < FileCommand
    include OptionsSupport

    def initialize(*args)
        super
        @version ||= '0.0'
        @project ||= 'noname'

        OPT "--project=#{@project}"
        OPT "--version=#{@version}"
        OPT "--quiet"
    end

    def build
        raise "Failed" if Artifact.exec('gcloud', app) != 0
    end

    def what_it_does() "Deploy google app" end

    def self.abbr() 'DGA' end
end

