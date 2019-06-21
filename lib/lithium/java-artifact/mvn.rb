require 'lithium/file-artifact/remote'

require 'rexml/document'
require 'fileutils'
require 'pathname'
require 'lithium/file-artifact/command'
require 'lithium/core-std'

def LOC_MAVEN(group, id, ver)
    p = File.expand_path("~/.m2/repository")
    raise "Maven local repo '#{p}' cannot be detetced" unless File.exists?(p)
    group = group.gsub('.', '/') if group.index('.') != nil
    return File.join(p, group, id, ver, "#{id}-#{ver}.jar")
end

# class LocalMavenJar < AquaredFile
#     def initialize(group, id, ver)
#         @destination
#         super "#{id}-#{ver}.jar"
#     end
# end



class MavenArtifact < CopyOfFile
    attr_reader :id, :group

    def initialize(*args)
        super

        name = File.dirname(@name) == '.' ? @name : File.basename(@name)
        if @id.nil?
            m = /(.*)\-(\d+\.\d+)(\.\d+)?([-.]\w+)?\.[a-zA-Z]+$/.match(name)
            raise "Incorrect maven artifact name '#{name}'" if m.nil? || m.length < 3
            @id     ||= m[1]
            @group  ||= m[1]
            @ver    ||= m[2] + (m[3] ? m[3] : '') +  (m[4] ? m[4] : '')
            @group = @group.tr('.', '/')
        end

        @source = LOC_MAVEN(@group, @id, @ver)

        unless File.exists?(@source)
            p = File.expand_path("~/.m2/repository")
            `find #{p}/. -name #{name}`.each_line { | fp |
                @source = File.expand_path(fp.chomp)
                break
            }
        end
    end
end


class POMFile < PermanentFile
    include LogArtifactState
    include StdFormater

    def initialize(name, &block)
        pom = FileArtifact.look_file_up(fullpath(name), 'pom.xml', homedir)
        raise "POM file cannot be detected by '#{fullpath(name)}'" if pom.nil?
        super(pom, &block)
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
            next if v['manager']

            fid, fgr, fvr = v['id'], v['group'], v['ver']

            if @scopes && v.has_key?("scope") && @scopes.index(v['scope'])
                puts_warning "Ignore '#{@name}'->'#{fid}-#{fvr}' because of scope '#{fsc}'"
                next
            end

            if @ignore_optional && v.has_key?('optional') && v['optional'] == 'true'
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
                desc = { 'id' => fid, 'group' => fgr, 'manager' => isparent } if !desc

                desc['ver']      = resolve_variables(fvr.to_s) if fvr
                desc['scope']    = resolve_variables(fsc.to_s) if fsc
                desc['optional'] = resolve_variables(fop.to_s) if fop
                desc['manager']  = isparent
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

                n = File.join(File.dirname(@name), "#{fid}-#{fvr}.jar")
                @requires << MavenJarFile.new(n) {
                    @group, @ver, @id = fgr, fvr, fid
                }
            }
        }
        @requires
    end

    protected

    def remote_dir()       File.join(@group, @id, @ver)                  end
    def remote_path()      File.join(remote_dir(), "#{@id}-#{@ver}.jar") end
    def remote_pom_path()  File.join(remote_dir(), "#{@id}-#{@ver}.pom") end

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
    include OptionsSupport

    def initialize(name, &block)
        super

        @maven_path ||= FileArtifact.which('mvn')
        @targets    ||= [ 'clean', 'install' ]
        raise 'maven path cannot be detected' unless @maven_path
        raise "maven path '#{@maven_path}' is invalid" unless File.exists?(@maven_path)
    end

    def expired?
        true
    end

    def build
        path = fullpath()
        raise "Target mvn artifact cannot be found '#{path}'" unless File.exists?(path)

        Dir.chdir(File.dirname(path));
        raise 'Maven running failed' if Artifact.exec(@maven_path, OPTS(),  @targets.join(' ')) != 0
    end

    def what_it_does() "Run maven: '#{@target}'" end
end

class CompileMaven < RunMaven
    def initialize(*args)
        super
        @targets = [ 'compile' ]
    end

    def expired?
        false
    end

    def list_items()
        dir = File.join(File.dirname(fullpath()), 'src', '**', '*')
        FileMask.new(dir).list_items { |f, t|
            yield f, t
        }

        super { |f, t|
            yield f, t
        }
    end
end


m = MavenArtifact.new("commons-validator-1.4.0.jar")
puts "id = #{m.id} group = #{m.group} ver = #{m.ver}"

m = MavenArtifact.new("jnc-easy-config-1.2.0-SNAPSHOT.jar")
puts "id = #{m.id} group = #{m.group} ver = #{m.ver}"

