require 'lithium/file-artifact/remote'

require 'rexml/document'
require 'fileutils'
require 'pathname'
require 'lithium/utils'
require 'lithium/file-artifact/command'
require 'lithium/core-std'

def LOC_MAVEN(group, id, ver)
    p = File.expand_path("~/.m2/repository")
    return nil unless File.exists?(p)
    group = group.gsub(".", "/") if group.index('.') != nil

    puts "p = #{p} group = #{group} id = #{id} ver = #{ver}"

    p = File.join(p, group, id, ver, "#{id}-#{ver}.jar")
 #   raise "Maven artifact '#{p}' cannot be found" if !File.exists?(p)
    puts_warning "cannot find #{p}" if !File.exists?(p)
    return nil if !File.exists?(p)
    return p
end

# class LocalMavenJar < AquaredFile
#     def initialize(group, id, ver)
#         @destination
#         super "#{id}-#{ver}.jar"
#     end
# end


class POMFile < PermanentFile
    include LogArtifactState
    include StdFormater

    def initialize(name, &block)
        super(FileUtil.look_file_up(fullpath(name), "pom.xml", homedir), &block)
    end

    def list_items()
        f = fullpath
        yield f, File.mtime(f).to_i
    end
end


class DownloadPOMDeps < POMFile
    def initialize(name, &block)
        super(name, &block)

        @properties      ||= {}
        @ignore_optional ||= true
        @destination     ||= "lib"
        @files, @rfiles = [], []



        raise "Destination directory '#{@destination}' doesn't exists" unless File.directory?(fullpath(@destination))

        artifacats = {}
        load_dep_from(@name, artifacats, false)

        artifacats.each_pair { |k, v|
            next if v["manager"]

            fid, fgr, fvr = v["id"], v["group"], v["ver"]

            if @scopes && v.has_key?("scope") && @scopes.index(v["scope"])
                puts_warning "Ignore '#{@name}'->'#{fid}-#{fvr}' because of scope '#{fsc}'"
                next
            end

            if @ignore_optional && v.has_key?("optional") && v["optional"] == 'true'
                puts_warning "Ignore optional '#{@name}'->'#{fid}-#{fvr}' dependency"
                next
            end

            n = "#{fid}-#{fvr}.jar"
            @files  << File.join(@destination, n)
            @rfiles << LOC_MAVEN(fgr, fid, fvr)
        }
    end

    def load_dep_from(xml, artifacts, isparent)
        xml = (Pathname.new(xml)).absolute? ? xml : fullpath(xml)
        raise "File '#{xml}' doesn't exist" if !File.exist?(xml)

        File.open(xml, 'r') { |f|
            xpath = '/project/properties/*'
            REXML::Document.new(f).get_elements(xpath).each { |n|
                @properties[n.name] = n.text
            }
        }

        bb = true
        File.open(xml, 'r') { |f|
            REXML::Document.new(f).get_elements('/project/parent').each { |n|
                bb = false;
                p = n.get_text("relativePath")
                if p.nil?
                    p = File.join(File.dirname(xml), "../pom.xml")
                    p = File.expand_path(p)
                    unless File.exists?(p)
                        puts_warning "Parent POM '#{p}'' cannot be found"
                        next
                    end
                else
                    p = File.expand_path(File.join(File.dirname(xml), p.to_s))
                end

                puts "Load parent '#{p.to_s}' artifacts"
                load_dep_from(p.to_s, artifacts, true)
            }
        }

        File.open(xml, 'r') { |f|
            xpath = '/project/dependencies/*'
            xpath = '/project/dependencyManagement/dependencies/*' if isparent

            REXML::Document.new(f).get_elements(xpath).each { |n|
                fgr, fvr, fid, fsc, fop = n.get_text('groupId'),
                                          n.get_text('version'),
                                          n.get_text('artifactId'),
                                          n.get_text('scope'),
                                          n.get_text('optional')

                raise "Unknown artifact group #{n}" if !fgr
                raise "Unknown artifact id #{n}"    if !fid
                fgr, fid = resolve_variables(fgr.to_s), resolve_variables(fid.to_s)

                key  = "#{fgr}:#{fid}"
                desc = artifacts[key] if artifacts.has_key?(key)
                desc = { "id"=>fid, "group"=>fgr, "manager"=>isparent } if !desc

                desc["ver"]      = resolve_variables(fvr.to_s) if fvr
                desc["scope"]    = resolve_variables(fsc.to_s) if fsc
                desc["optional"] = resolve_variables(fop.to_s) if fop
                desc["manager"]  = isparent
                artifacts[key] = desc
            }
        }
    end

    def resolve_variables(p)
        if p[0..0] == '$'
            v = p[2..p.length-2]
            if @properties[v]
                p = @properties[v]
            else
                puts_warning "Cannot resolve '#{v}' variable"
                return nil
            end
        end
        return p
    end

    def expired?()

        puts ">>>> #{@files}"

        @files.each { |f|
            p = fullpath(f)
            return true unless File.exists?(p)
        }
        return false
    end

    def cleanup()
        @files.each { |f|
            f = fullpath(f)
            next if !File.exists?(f)
            File.delete(f)
        }
    end

    def build()
        cleanup()
        dest = fullpath(@destination)
        @rfiles.each_index { |i|
            src = @rfiles[i]
            FileUtils.cp(src, dest) if !src.nil?
        }
    end
end

class MavenJarFile < HTTPRemoteFile
    attr_reader :group, :id

    def self.parseName(name)
        m = /(.*)\-(\d+\.\d+)(\.\d+)?([-.]\w+)?\.jar$/.match(File.basename(name))
        raise "Incorrect maven artifact name '#{name}'" if m.nil? || m.length < 3
        id     ||= m[1]
        group  ||= m[1]
        ver    ||= m[2] + (m[3] ? m[3] : '') +  (m[4] ? m[4] : '')
        group = group.tr('.', '/')
        [group, id, ver]
    end

    def initialize(*args)
        super

        info = MavenJarFile.parseName(@name) if !@group || !@id || !@ver
        @group ||= info[0]
        @id    ||= info[1]
        @ver   ||= info[2]
        @group = @group.gsub(".", "/") if @group.index('.') != nil

        @url ||= 'http://mirrors.ibiblio.org/pub/mirrors/maven2'
    end

    def build()
        p = LOC_MAVEN(@group, @id, @ver)
        if p != nil

        else
            fetch(remote_path(), fullpath())
        end
    end

    def requires()
        p = fetch_pom()
        return super if p.nil?
        super

        File.open(p, 'r') { |f|
            REXML::Document.new(f).get_elements('/project/dependencies/*').each { |n|
                fgr, fvr, fid = n.get_text('groupId').to_s, n.get_text('version').to_s, n.get_text('artifactId').to_s

                fsc = n.get_text('scope').to_s if @scopes
                if fsc && @scopes.index(fsc)
                    puts_warning "Ignore '#{@name}'->'#{fid}-#{fvr}' because of scope '#{fsc}'"
                    next
                end

                fop = n.get_text('optional') if @ignore_optional
                if fop && fop.to_s() == 'true'
                    puts_warning "Ignore optional '#{@name}'->'#{fid}-#{fvr}' dependency"
                    next
                end

                n = "#{File.dirname(@name)}/#{fid}-#{fvr}.jar"
                @requires << MavenJarFile.new(n) {
                    @group, @ver, @id = fgr, fvr, fid
                }
            }
        }
        @requires
    end

    protected

    def remote_dir() "#{@group}/#{@id}/#{@ver}/" end
    def remote_path() "#{remote_dir()}#{@id}-#{@ver}.jar" end
    def remote_pom_path() "#{remote_dir()}#{@id}-#{@ver}.pom" end

    def fetch_pom()
        pn  = "#{@id}-#{@ver}.pom"
        pom = fullpath(File.join(File.dirname(@name), pn))
        begin
            fetch(remote_pom_path(), pom) if !File.exists?(pom) || File.size(pom) == 0
        rescue  RemoteFileNotFound
            puts_warning "POM '#{pn}' cannot be fetched"
            return nil
        end
        return pom
    end
end

class RunMaven < POMFile
    def initialize(name, &block)
        super

        @maven_path ||= FileUtil.which('mvn')
        @targets    ||= [ "clean", "install" ]
        @options    ||= ""
        raise "maven path cannot be detected" unless @maven_path
        raise "maven path cannot be detected" unless File.exists?(@maven_path)
    end

    def expired?
        true
    end

    def build
        path = fullpath()
        raise "Target mvn artifact cannot be found '#{path}'" unless File.exists?(path)

        Dir.chdir(File.dirname(path));
        raise "Maven running failed" if exec4("#{@maven_path} #{@options} #{@targets.join(' ')}") != 0
    end

    def what_it_does() "Run maven: '#{@target}'" end
end

class MavenCompile < RunMaven
    def initialize(*args)
        super
        @targets = [ "compile" ]
    end

    def expired?
        false
    end

    def list_items()
        dir = File.join(File.dirname(fullpath()), 'src', "**", "*")
        FileMask.new(dir).list_items { |f, t|
            yield f, t
        }

        super { |f, t|
            yield f, t
        }
    end
end

