require 'pathname'

require 'lithium/utils'

#  TODO: Problem list
#   + Project.current should be replaced with target
#   + $project_home usage has to be reduced
#   + Setup of owner has to be done before calling initialization method basing on current context
#   + normalize homedir()
#   + Lithium project defined artifact has to be re-populated with owner of current project otherwise
#      compile/run common artifact will get lithium as its owner
#      - Shared flag has been added to say if teh given artifact has to be instantiated in context
#        of the calling project context. May be shared should be defined on the level of artifact ?
#   - usage of $lithium_code should be minimized
#   + def_name in meta usage ?
#   + re-use artifact implementation
#
#   Artifact name keeps order of artifact following the rules below:
#     1) aliased artifact precede not aliased artifact and sorted alphabetically
#     2) the same aliased artifact with path specified sorted by this path
#     3) path artifacts are sorted from particular case to common
#
#   For example:
#
#   [ "aa:test/", "aa:test/*", "aa:test/**/*", "aa:", "bb:", "compile:test/test/a",
#     "compile:test/**/*", "compile:", "test/com", "test/com/**" ]
#
class ArtifactName < String
    attr_reader :prefix, :suffix, :path, :path_mask, :mask_type

    # return artname as is if it is passed as an instance of artifact name
    def self.new(name)
        return name if name.kind_of?(ArtifactName)
        super(name)
    end

    def initialize(name)
        if name.kind_of?(Class)
            name = name.default_name.nil? ? name.to_s : name.default_name
        elsif name.kind_of?(Symbol)
            name = name.to_s
        end

        ArtifactName.nil_name(name)

        @mask_type = File::FNM_DOTMATCH
        @prefix, @path, @path_mask, @suffix = nil, nil, nil, nil
        @prefix = name[/^\w\w+\:/]
        @suffix = @prefix.nil? ? name : name[@prefix.length .. name.length]
        @suffix = nil if !@suffix.nil? && @suffix.length == 0

        @path = @suffix[/((?<![a-z])[a-z]:)?[^:]+$/] unless @suffix.nil?
        unless @path.nil?
            mask_index = @path.index(/[\[\]\?\*\{\}]/)
            unless mask_index.nil?
                @path_mask  = @path[mask_index, @path.length]
                @path       = @path[0, mask_index]
            end
            @path      = @path.length == 0 ? nil : Pathname.new(@path).cleanpath.to_s
            @mask_type = @mask_type | File::FNM_PATHNAME if @path_mask != '*' || !@path.nil?
        end

        super(name)
    end

    def self.nil_name(name, msg = 'Artifact name')
        raise "#{msg} cannot be nil" if name.nil? || (name.kind_of?(String) && name.strip.length == 0)
    end

    def self.name_from(prefix, path, path_mask)
        path = nil if !path.nil? && path.length == 0
        name  = ''
        name += path                                               unless path.nil?
        name  = path.nil? ? path_mask : File.join(name, path_mask) unless path_mask.nil?
        name  = prefix + name                                      unless prefix.nil?
        return name
    end

    def env_path?()
        return !path.nil? && path.start_with?(".env/")
    end

    def match(name)
        artname = ArtifactName.new(name)

        # prefix doesn't match each other
        return false if @prefix != artname.prefix

        unless @path_mask.nil?
            return false if artname.suffix.nil? || (artname.env_path? ^ env_path?)
            return File.fnmatch(@suffix, artname.suffix, @mask_type)
        else
            return @suffix == artname.suffix
        end
    end

    # TODO: correct the method to take in account mask and file mask
    def path=(path)
        @path = path
    end

    def <=>(p)
        if p == self
            return 0
        elsif p.nil? || !p.kind_of?(self.class)
            return -1
        elsif p.prefix == @prefix
            return 0                                                      if @suffix == p.suffix
            return -1                                                     if p.suffix.nil?
            return 1                                                      if @suffix.nil?
            return File.fnmatch(@suffix, p.suffix, @mask_type)  ?  1 : -1 unless @path_mask.nil?
            return File.fnmatch(p.suffix, @suffix, p.mask_type) ? -1 :  1 unless p.path_mask.nil?
            return self.to_s <=> p.to_s
        else
            return -1 if p.prefix.nil?
            return  1 if @prefix.nil?
            return @prefix <=> p.prefix
        end
    end

    def inspect()
        return "#{self.class.name}: { prefix='#{@prefix}', suffix='#{@suffix}', path='#{@path}', mask='#{@path_mask}' mask_type=#{mask_type} }"
    end
end

# Artifact meta info class that keeps:
#     :clazz    - detected class of the given artifact
#     :block    - initialization block of the given artifact
#     :def_name - default path of the given artifact
#     :clean    - boolean flag that say if artifact has to be cleaned up before building
class ArtifactMeta < Hash
    attr_reader :artname

    def initialize(*args, &block)
        if args[-1].kind_of?(ArtifactMeta)
            cm              = args[-1]
            @artname        = args.length > 1 ? args[0] : cm.artname
            self[:clazz]    = cm[:clazz]
            self[:def_name] = cm[:def_name]

            if block.nil?
                self[:block] = cm[:block]
            elsif cm[:block].nil?
                self[:block] = block
            else
                sb = cm[:block]
                self[:block] = Proc.new {
                    self.instance_eval &sb
                    self.instance_eval &block
                }
            end
        else
            @artname = ArtifactName.new(args[0])
            clazz    = args[0].kind_of?(Class) ? args[0]  : nil

            # if there is only one argument then consider as a class or class name
            # In this case name of artifact is fetched as to_s of class
            if args.length == 1
                raise "Class cannot be detected for '#{@artname}'" if clazz.nil? && @artname.prefix.nil?

                if clazz.nil?
                    begin
                        cn    = @artname.prefix[0..-2]
                        clazz = Module.const_get(cn)
                    rescue
                        raise "Artifact class cannot be resolved by artifact name '#{cn}'"
                    end
                end
            elsif args.length > 1   # first argument should contain artifact name and the last one should point to class
                if args[-1].kind_of?(String)
                    clazz = Module.const_get(args[-1])
                elsif args[-1].kind_of?(Class)
                    clazz = args[-1]
                else
                    raise "Unknown artifact '#{args[0]}' class"
                end
            else
                raise 'No artifact information has been passed'
            end

            if args.length > 2 && !@artname.suffix.nil?
                raise "Default name cannot be specified since artifact '#{@artname}' already defines target name"
            end

            self[:clazz]    = clazz
            self[:block]    = block
            self[:def_name] = args.length > 2 ? args[1] : nil
        end
    end

    def reuse(&block)
        bk = block
        unless self[:block].nil?
            sb = self[:block]
            if block.nil?
                bk = sb
            else
                bk = Proc.new {
                    self.instance_eval &sb
                    self.instance_eval &block
                }
            end
        end

        mt = ArtifactMeta.new(@artname, self[:clazz], &bk)
        mt[:def_name] = self[:def_name]
        return mt
    end

    def ==(meta)
        !meta.nil? && meta.class == self.class && meta[:clazz] == self[:clazz] && meta[:block] == self[:block] && meta[:def_name] == self[:def_name]
    end

    def to_s
        "#{self.class} : { " + super + " artname = '#{artname}' }"
    end

    def inspect()
        return "#{self.class.name}: { class='#{self[:clazz]}', def_val='#{self[:def_value]}', artname='#{@artname}' }"
    end
end

# version utility class
class Version
    attr_reader :version

    def initialize(version) @version = version end
    def <=>(v) self.compare(@version, v.to_s) end
    def to_s() return @version end

    def self.compare(ver1, ver2)
        ver1 = '' if ver1.nil?
        ver2 = '' if ver2.nil?
        return 0 if  ver1 == ver2
        pvers1, pvers2 = ver1.split('.'), ver2.splitplit('.')
        pvers1.each_index { |i|
          break     if pvers2.length <= i
          return -1 if pvers1[i] < pvers2[i]
          return  1 if pvers1[i] > pvers2[i]
        }
        pvers1.length > pvers2.length ? 1 : -1
    end
end


module AutoRegisteredArtifact
    @arts_classes = []

    def self.included(clazz)
        @arts_classes.push(clazz)
    end

    def self.artifact_classes()
        @arts_classes
    end
end

# Core artifact abstraction.
#  "@name" - name of artifact
#  "@shortname"
#  "@ver"
class Artifact
    attr_reader :name, :shortname, :ver, :owner, :createdByMeta

    # context class is special wrapper object that redirect
    # its methods call to a wrapped (artifact object) target
    # object. Additionally it tracks a current target object
    # from which a method has been called.
    # c
    class Proxy
        instance_methods.each() { |m|
            if not m.to_s =~ /__[a-z]+__/
                undef_method m if not m.to_s =~ /object_id/
            end
        }

        # keeps artifact call stack
        @@calls_stack = []

        def initialize(original)
            raise 'Target has to be defined' if original.nil?
            @original_instance = original
        end

        def top()
            ow = self
            while !ow.owner.nil? do
                ow = ow.owner
            end
            return ow
        end

        def original_instance
            @original_instance
        end

        def ==(prx)
            prx && original_instance == prx.original_instance
        end

        def method_missing(meth, *args, &block)
            switched = false

            #puts "method_missing():  stack size = #{@@calls_stack.length}  is last proxy ? =  #{defined? @@calls_stack.last.original_instance.expired?}"

            if  @@calls_stack.length == 0 || @@calls_stack.last.original_instance != @original_instance
                @@calls_stack.push(self)
                switched = true
            end

            begin
                return @original_instance.send(meth, *args, &block)
            ensure
                @@calls_stack.pop() if switched
            end
        end

        def self.last_caller() @@calls_stack.last end

        def self._calls_stack_() @@calls_stack end
    end

    @default_name = nil

    def Artifact.default_name(*args)
        @default_name = args[0] if args.length > 0
        @default_name ||= nil
        return @default_name
    end

    def Artifact.required(clazz, &block)
        self.send(:define_method, clazz.name.downcase) {
            #an = instance_variable_get("@#{clazz.name}")
            an = nil
            begin
                a  = owner.artifact(an.nil? ? clazz :  an) unless owner.nil?
                return a unless a.nil?
            rescue NameError => e
            end
            nil
        }

        rname = "#{clazz.name}__requires"
        alias_method rname, "requires"
        undef_method "requires"

        self.send(:define_method, 'requires') {
            r = self.send(rname.intern)
            r << self.send(clazz.name.downcase)
            return r
        }
    end

    # !!! this method creates wrapped with context class artifact
    # !!! to keep track for the current context (instance
    # !!! where a method has been executed)
    def Artifact.new(*args,  &block)
        instance       = allocate()
        instance_proxy = Proxy.new(instance)
        last_caller    = Artifact.last_caller

        unless last_caller.nil?
            if last_caller.kind_of?(ArtifactContainer)
                instance_proxy.owner = last_caller
            elsif !last_caller.owner.nil?
                instance_proxy.owner = last_caller.owner
            end
        end
        instance.send(:initialize, *args, &block)
        return instance_proxy
    end

    # return artifact instance whose method is currently called
    def Artifact.last_caller() Proxy.last_caller end

    def Artifact._calls_stack_() Proxy._calls_stack_ end

    def initialize(name, &block)
        # test if the name of the artifact is not nil or empty string
        name = validate_artifact_name(name)

        @name, @shortname = name, File.basename(name)
        #@owner ||= nil  # TODO: owner has to be set basing on calling context before initialize method in new ?

        # block can be passed to artifact
        # it is expected the block setup class instance
        # variables like '{ @a = 10 ... }'
        self.instance_eval(&block) if block
    end

    def validate_artifact_name(name)
        ArtifactName.nil_name(name)
        name
    end

    def createdByMeta=(m)
        @createdByMeta = m
    end

    def owner=(value)
        if value.nil?
            @owner = value
        else
            raise "Invalid project artifact type '#{value.class}'" unless value.kind_of?(ArtifactContainer)
            @owner = value
        end
    end

    def homedir()
        return owner.homedir unless owner.nil? # if has a container the artifact belongs
        return File.expand_path(Dir.pwd)
    end

    # prevent error generation for a number of optional artifact methods
    # that are called by lithium engine:
    #  - build_done
    #  - build_failed
    #  - pre_build
    #
    def method_missing(meth, *args, &block)
        return if meth == :build_done || meth == :build_failed || meth == :pre_build
        super(meth, *args, &block)
    end

    # return cloned array of the artifact dependencies
    def requires()
        @requires ||= []
        @requires.dup()
    end

    # test if the given artifact has expired and need to be built
    def expired?() true end

    # cleanup method should be implemented to clean artifact related
    # build stuff
    def cleanup() end

    def to_s() shortname end

    def what_it_does() return "Build '#{to_s}' artifact" end

    # add required for the artifact building dependencies (other artifact)
    def REQUIRE(*args)
        @requires ||= []
        args.each { | aa | @requires << aa }
    end

    # Overload "eq" operation of two artifact instances.
    def ==(art)
        art && self.class == art.class && @name == art.name && @ver == art.ver && owner == art.owner
    end

    # return last time the artifact has been modified
    def mtime() -1 end
end

# Artifact tree. Provides tree of artifacts that is built basing
# on resolving artifacts dependencies
class ArtifactTree < Artifact
    attr_reader :root_node

    # tree node structure
    class Node
        attr_accessor :art, :parent, :children, :expired, :expired_by_kid

        def initialize(art, parent=nil)
            raise 'Artifact cannot be nil' if art.nil?

            # TODO: make sure this is more proper way of artifact building than commented below
            if art.kind_of?(String)
                if parent.nil?
                    art = Project.artifact(art)
                else
                    art = parent.art.owner.artifact(art)
                end
            end
            #art = Project.artifact(art) if art.kind_of?(String)
            #
            @children, @art, @parent, @expired, @expired_by_kid = [], art, parent, art.expired?, nil
        end

        # traverse tree with the given block starting from the tree node
        def traverse(&block)
            traverse_(self, 0, &block)
        end

        def traverse_kids(&block)
            @children.each { |n| traverse_(n, 0, &block) }
        end

        def traverse_(root, level, &block)
            root.children.each { |n|
                traverse_(n, level+1, &block)
            }
            block.call(root, level)
        end
    end

    def initialize(*args)
        super
        @show_mtime ||= true
    end

    # build tree starting from the root artifact (identified by @name)
    def build()
        @root_node = Node.new(@name)
        build_tree(@root_node)
    end

    def norm_tree()
        norm_tree_exp(@root_node)
        norm_tree_ver(@root_node)
    end

    def build_tree(root)
        root.art.requires.each { | a |
            kid_node, p = Node.new(a, root), root
            while p && p.art != kid_node.art
                p = p.parent
            end
            raise "'#{root.art}' has CYCLIC dependency on '#{p.art}'" if p
            root.children << kid_node
            build_tree(kid_node)
        }
    end

    def show_tree() puts tree2string(nil, @root_node) end

    def norm_tree_ver(root, map={})
        # !!! key building code should be optimized
        key = root.art.name + root.art.class.to_s
        if map[key].nil?
            map[key] = root
            root.children.each { |i| norm_tree_ver(i, map) }
            root.children = root.children.compact()
        else
            #puts "Cut dependency branch '#{root.art}'"
            root.parent.children[root.parent.children.index(root)], item  = nil, map[key]
            if Version.compare(root.art.ver, item.art.ver) == 1
                puts "Replace branch '#{item.art}' with version #{root.art.ver}"
                item.art = root.art
            end
        end
    end

    def norm_tree_exp(root)
        bt = root.art.mtime()
        root.children.each { | kid |
            norm_tree_exp(kid)
            if !root.expired && (kid.expired || bt.nil? || (bt > 0 && kid.art.mtime() > bt))
                root.expired = true
                root.expired_by_kid = kid.art
            end
        }
    end

    def tree2string(parent, root, shift=0)
        pshift, name = shift, root.art.to_s()

        e = (root.expired ? '*' : '') +  (root.expired_by_kid ? "*[#{root.expired_by_kid}]" : '') + (@show_mtime ? ": #{root.art.mtime}" : '')
        s = "#{' '*shift}" + (parent ? '+-' : '') + "#{name}(#{root.art.class})"  + e
        b = parent && root != parent.children.last
        if b
            s, k = "#{s}\n#{' '*shift}|", name.length/2 + 1
            s = "#{s}#{' '*k}|" if root.children.length > 0
        else
            k = shift + name.length/2 + 2
            s = "#{s}\n#{' '*k}|" if root.children.length > 0
        end

        shift = shift + name.length/2 + 2
        root.children.each { |i|
            rs, s = tree2string(root, i, shift), s + "\n"
            if b
                rs.each_line { |l|
                    l[pshift] = '|'
                    s = s + l
                }
            else
                s = s + rs
            end
        }
        return s
    end

    def what_it_does() "Build '#{@name}' artifact dependencies tree" end
end

#  Base file artifact
class FileArtifact < Artifact
    attr_reader :is_absolute, :is_permanent

    def initialize(name, &block)
        name = Pathname.new(name)
        name = name.cleanpath
        @is_absolute  = name.absolute?
        @is_permanent = false
        super(name.to_s, &block)
        assert_existence()
    end

    def _contains_path?(base, path)

        puts "FileArtifact._contains_path?(): base = '#{base}' path = '#{path}'"


        base = base[0..-2] if base[-1] == '/'
        path = path[0..-2] if path[-1] == '/'
        return true  if base == path
        return false if base.length == path.length
        i = path.index(base)
        return false if i.nil? || i != 0
        return path[base.length] == '/'
    end

    def homedir()
        puts "FileArtifact.homedir(): is_absolute = #{@is_absolute}, owner = '#{owner}' name = #{@name} clazz = #{self.class}"

        if @is_absolute
            unless owner.nil?
                home = owner.homedir
                if Pathname.new(home).absolute?
                    home = home[0, home.length - 1] if home.length > 1 && home[home.length - 1] == '/'

                    puts "FileArtifact.homedir(): HOME = #{home} owner.homedir = #{owner.homedir}:#{owner.class} name = #{@name} clazz = #{self.class}" if _contains_path?(home, @name)
                    return home if _contains_path?(home, @name)
                end
            end

            return File.dirname(@name)
        else
            return super
        end
    end

    def go_to_homedir()
        Dir.chdir(homedir)
    end

    def relative_art(name)
        artname = ArtifactName.new(name)
        unless artname.path.nil?
            path    = relative_path(artname.path)
            artname = ArtifactName.new(ArtifactName.name_from(artname.prefix, path, artname.path_mask)) unless path.nil?
        end
        return artname
    end

    def relative_path(path = @name)
        mi = path.index(/[\[\]\?\*\{\}]/)
        unless mi.nil?
            path = path[0, mi]
            return nil if path.length == 0
        end

        path  = Pathname.new(path).cleanpath
        home  = Pathname.new(homedir)
        return nil if (path.absolute? && !home.absolute?) || (!path.absolute? && home.absolute?) || !_contains_path?(home.to_s, path.to_s)

        return path.relative_path_from(home).to_s
    end

    def fullpath(path = @name)
        return path if path.start_with?('.env/')

        if path == @name
            return path if @is_absolute
            return Pathname.new(File.join(homedir, path)).cleanpath.to_s
        else
            path = Pathname.new(path).cleanpath
            home = homedir

            puts "FileArtifact.fullpath(): home = #{home}, path = #{path}"

            if path.absolute?
                path = path.to_s
                home = home[0, home.length - 1] if home.length > 1 && home[home.length - 1] == '/'
                raise "Path '#{path}' cannot be relative to '#{home}'" unless _contains_path?(home, path)
                return path
            else
                File.join(home, path.to_s)
            end
        end
    end

    # test if the given path is in a context of the given file artifact
    def match(path)
        raise 'Invalid empty or nil path' if path.nil? || path.length == 0

        # current directory
        return true if path == '.'

        mi = path.index(/[\[\]\?\*\{\}]/)
        unless mi.nil?
            pp   = path.dup
            path = path[0, mi]
            raise "Path '#{pp}' contains only mask" if path.length == 0
        end

        path  = Pathname.new(path).cleanpath
        home  = Pathname.new(homedir)
        raise "Home '#{home}' is not an absolute path" if path.absolute? && !home.absolute?

        return false if !path.absolute? && home.absolute?
        return _contains_path?(home.to_s, path.to_s)
    end

    def build
        assert_existence()
    end

    def expired?() false end

    def mtime()
        assert_existence()
        f = fullpath()
        return File.exists?(f) ? File.mtime(f).to_i() : -1
    end

    def assert_existence()
        if @is_permanent
            fp = fullpath()
            raise "File '#{fp}' doesn't exist" unless File.exists?(fp)
        end
    end
end

# Permanent file shortcut
class PermanentFile < FileArtifact
    def initialize(*args)
        @is_permanent = true
        super
    end
end

# Perform and action on a file artifact
class FileCommand < PermanentFile
    def expired?() true end
end

# Directory artifact
class Directory < FileArtifact
    def initialize(*args)
        super
        fp = fullpath
        raise "File '#{fp}' is not a directory" unless File.directory?(fp)
    end
end

# File mask artifact that can identify set of file artifacts
class FileMask < FileArtifact
    def initialize(*args)
        @regexp_filter = nil
        @ignore_dirs   = false
        @ignore_files  = false
        super
        raise "Files and directories are ignored at the same time" if @ignore_files && @ignore_dirs
    end

    def print()
        list_items { | p, m |
            puts p
        }
    end

    def build()
        list_items { | p, m |
            build_item(p, m)
        }
    end

    def build_item(path, m) end

    def paths_to_list(rel = nil)
        list = []
        list_items(rel) { | path, m|
            list << path
        }
        return list
    end

    def list_items(rel = nil)
        go_to_homedir()

        rel = rel[0, rel.length - 1] if !rel.nil? && rel[-1] == '/'

        Dir[@name].each { | path |
            b = false
            b = (path =~ @regexp_filter) != nil if @regexp_filter

            if b == false && (@ignore_files || @ignore_dirs)
                b = File.directory?(path)
                b = (@ignore_files && !b) || (@ignore_dirs && b)
            end

            if b == false
                mt = File.mtime(path).to_i()
                unless rel.nil?
                    "Relative path '#{rel}' cannot be applied to '#{path}'" unless _contains_path?(rel, path)
                    path = path[rel.length + 1, path.length - rel.length]
                end
                yield path, mt
            end
        }
    end

    def expired?() true end
end

module ArtifactContainer
    def artifact(name, shift ='',  &block)
        raise "Stack is overloaded '#{name}'" if Artifact._calls_stack_.length > 100

        artname = ArtifactName.new(name)

        # check if artifact name points to current project
        return Project.current if artname.to_s == Project.current.name.to_s

        # fund local info about the given artifact
        meta = find_meta(artname)

        #puts "#{self.class}.artifact(): own = '#{owner}' current = '#{self.name}' name = #{name} meta = #{meta} hm = #{homedir}"

        if meta.nil?
            # meta cannot be locally found try to delegate search to owner
            # path nil or doesn't match project then delegate finding an artifact in an owner project context
            return owner.artifact(name, &block) if !owner.nil? && (artname.path.nil? || !match(artname.path))
            meta = _meta_from_owner(artname)

            unless meta.nil?
                raise "It seems there is no an artifact associated with '#{name}'" if !createdByMeta.nil? && meta.object_id == createdByMeta.object_id
            else
                meta = _meta_by_name(artname)
            end
            raise NameError.new("No artifact is associated with '#{name}'") if meta.nil?
        end

        # manage cache
        _remove_from_cache(artname, meta) unless block.nil?
        art = _artifact_from_cache(artname, meta)
        art = _artifact_by_meta(artname, meta, &block) if art.nil?

        # always cache container
        if art.kind_of?(ArtifactContainer)
            art = _cache_artifact(artname, meta, art)
            return art.artifact(artname.suffix)
        else
            return _cache_artifact(artname, meta, art)
        end
    end

    def _cache_artifact(artname, meta, art)
        if art.kind_of?(ArtifactContainer)
            _artifacts_cache[meta.artname] = art
        elsif artname == meta.artname
            _artifacts_cache[artname] = art
        end
        return art
    end

    def _artifact_from_cache(name, meta)
        artname = ArtifactName.new(name)
        if !meta.nil? && meta[:clazz].included_modules.include?(ArtifactContainer)
            return _artifacts_cache[meta.artname]
        elsif !_artifacts_cache[artname].nil? && artname.path_mask.nil?
            return _artifacts_cache[artname]
        else
            return nil
        end
    end

    # { <art_name> => <art_class_instance>, ...}
    def _artifacts_cache()
        @artifacts = {} unless defined? @artifacts
        @artifacts
    end

    def _remove_from_cache(artname, meta)
        artname = ArtifactName.new(name)
        if meta[:clazz].included_modules.include?(ArtifactContainer)
            _artifacts_cache.delete(meta.artname) if _artifacts_cache[meta.artname]
        elsif artname.path_mask.nil?
            _artifacts_cache.delete(artname) if _artifacts_cache[artname]
        end
        nil
    end

    def _artifact_by_meta(name, meta, &block)
        artname = ArtifactName.new(name)

        clazz = meta[:clazz]
        raise 'Invalid nil artifact class' if clazz.nil?
        begin
            clazz = Module.const_get(clazz) if clazz.kind_of?(String)
        rescue NameError
            raise "Class '#{clazz}' not found"
        end

        art = clazz.new(artname.suffix.nil? ? meta[:def_name] : artname.suffix,
            &(block.nil? ? meta[:block] : Proc.new {
                self.instance_eval &meta[:block] unless meta[:block].nil?
                self.instance_eval &block
            })
        )

        art.createdByMeta = meta

        # TODO: the key :clean is never set, since ARTIFACT doesn't support the parameter
        art.cleanup() if meta[:clean] == true
        return art
    end

    def _meta_by_name(name)
        artname = ArtifactName.new(name)
        begin
            return ArtifactMeta.new(artname) unless artname.prefix.nil?
        rescue NameError => e
        end
        return nil
    end

    def _meta_from_owner(name)
        artname = ArtifactName.new(name)
        ow   = owner
        meta = nil
        while !ow.nil? && meta.nil? do
            meta = ow.find_meta(artname)
            ow = ow.owner
        end
        return meta;
    end

    # ArtifacName => {
    #     block:    block,
    #     clazz:    class,
    #     def_name: name
    # }
    def _meta()
        @meta = {} unless defined? @meta
        return @meta
    end

    def find_meta(name)
        artname = relative_art(name)
        meta    = _meta[artname]
        return meta unless meta.nil?

        meta  = _meta.detect { | p | p[0].match(artname) }
        return meta[1] unless meta.nil?
        return nil
    end

    def ==(prj)
        super(prj) && _meta == prj._meta
    end

    # ([name, []] clazz, [&block])
    def ARTIFACT(*args, &block)
        if args[-1].kind_of?(Class)
            m = ArtifactMeta.new(*args, &block)
        else
            args = args.dup()
            args.push(FileMaskContainer)
            m = ArtifactMeta.new(*args, &block)
        end

        # try to find previously stored meta
        #puts "Override previously defined '#{m.artname}' artifact" if _meta[m.artname]

        # store meta
        _meta[m.artname] = m

        # sort dictionary by key
        @meta = _meta.sort.to_h
    end

    def REF(name)
        artname = ArtifactName.new(name)
        meta = find_meta(artname)
        if meta.nil?
            meta = _meta_from_owner(artname)

            unless meta.nil?
                raise "It seems there is no an artifact associated with '#{name}'" if !createdByMeta.nil? && meta.object_id == createdByMeta.object_id
            else
                meta = _meta_by_name(artname)
            end
            raise NameError.new("No artifact is associated with '#{name}'") if meta.nil?
        end
        return meta
    end

    def REUSE(*args, &block)
        raise "Project '#{self}' doesn't have parent project to re-use its artifacts" if owner.nil?
        artname = ArtifactName.new(args[0])
        meta    = _meta[artname]

        # TODO: throws exception for containers
        #raise "Artifact '#{artname}' is already defined with '#{self}' project" unless meta.nil?

        ow = owner
        while meta.nil? && !ow.nil?
            meta = ow._meta[artname]
            ow   = ow.owner
        end
        raise "Cannot find '#{artname}' in parent projects" if meta.nil?

        _meta[artname] = meta.reuse(&block)
    end

    def REMOVE(name)
        # TODO: implement it
    end
end


class FileMaskContainer < FileMask
    include ArtifactContainer

    # def homedir()
    #     puts "FileMaskContainer.homedir(): #{owner}"

    #     return owner.homedir()
    # end
end


# project artifact
class Project < Directory
    attr_reader :desc

    include ArtifactContainer

    @@curent_project = nil

    def self.current=(prj)
        @@curent_project = prj
    end

    def self.current()
        @@curent_project
    end

    def self.artifact(name, &block)
        @@curent_project.artifact(name, &block)
    end

    def self.create(home, owner = nil)
        @@curent_project = Project.new(home, owner) {
            conf = File.join(home, '.lithium', 'project.rb')
            self.instance_eval(File.read(conf)).call if File.exists? conf
        }
        return @@curent_project
    end

    def initialize(*args, &block)
        # means artifact meta are not shared with its children project
        self.owner = args[1] if args.length > 1
        super(args[0], &block)
        @desc ||= File.basename(args[0])
    end

    # TODO: comment it
    def new_artifact(&block)
        art = block.call
        return art
    end

    def homedir()
        return @name if @is_absolute
        return super
    end

    def expired?() true end

    def build() end

    def what_it_does()
        nil
    end
end

class EnvArtifact < Artifact
    def self.default_name(*args)
        @default_name ||= nil
        if args.length > 0
            @default_name = validate_env_name(args[0])
        elsif @default_name.nil?
            @default_name = ".env/#{self.name}"
        end

        return @default_name
    end

    def self.validate_env_name(name)
        raise "Environment artifact cannot be assigned with '#{name}' name. Use '$/<artifact_name>' name pattern" if name[0] != '$' || name[1] != '/'
        name
    end

    # def validate_artifact_name(name)
    #     EnvArtifact.validate_env_name(name)
    # end
end

class GroupByExtension < FileMask
    def initialize(*args, &block)
        @callback = nil
        super
    end

    def DO(&block)
        @callback = block
    end

    def build()
        exts = []
        list_items { |f, m|
            ext = File.extname(f)
            exts.push(ext) if !ext.nil? && ext != "" && !exts.include?(ext)
        }

        exts.each { | ext |
            name = "#{@name}#{ext}"
            puts "Detect '#{ext}' to be compiled as '#{name}'"
            @callback.call(ext)
        }
    end
end

puts "HELLo WIN_10"

