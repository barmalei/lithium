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

    def initialize(name)
        name = name.to_s if name.kind_of?(Symbol) || name.kind_of?(Class)
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

    def match(name)
        artname = name.kind_of?(ArtifactName) ? name : ArtifactName.new(name)

        # prefix doesn't match each other
        return false if @prefix != artname.prefix

        unless @path_mask.nil?
            return false if artname.suffix.nil?
            return File.fnmatch(@suffix, artname.suffix, @mask_type)
        else
            return @suffix == artname.suffix
        end
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
        return "Instance of #{self.class.name} => { prefix = '#{@prefix}', suffix = '#{@suffix}', path = '#{@path}', mask = '#{@path_mask}' mask_type = #{mask_type}}"
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
        clazz    = nil
        @artname = args[0].kind_of?(ArtifactName) ? args[0] : ArtifactName.new(args[0])
        clazz    = args[0] if args[0].kind_of?(Class)

        # if there is only one argument then consider as a class or class name
        # In this case name of artifact is fetched as to_s of class
        if args.length == 1
            raise "Class cannot be detected for '#{@artname}'" if clazz.nil? && @artname.prefix.nil?
            clazz = Module.const_get(@artname.prefix[0..-2])   if clazz.nil?
        elsif args.length > 1   # first argument should contain artifact name and the last one should point to class
            if args[-1].kind_of?(String)
                clazz = Module.const_get(args[-1])
            elsif args[-1].kind_of?(Class)
                clazz = args[-1]
            else
                raise "Unknown artifact '#{args[0]}' class"
            end
        else
            raise "No artifact information has been passed"
        end

        raise "Default name can be specified only if an artifact name has not been defined" if args.length > 2 && !@artname.suffix.nil?

        self[:clazz]    = clazz
        self[:block]    = block
        self[:def_name] = args.length > 2 ? args[1] : nil
    end

    def reuse(&block)
        bk = block
        unless self[:block].nil?
            if block.nil?
                bk = self[:block]
            else
                bk = Proc.new {
                    self.instance_eval &self[:block]
                    self.instance_eval &block
                }
            end
        end

        mt = ArtifactMeta.new(@artname, self[:clazz], &bk)
        mt[:def_name] = self[:def_name]
        return mt
    end

    def instantiate(name = nil, &block)
        clazz = self[:clazz]
        raise "Invalid artifact class" if clazz.nil?
        begin
            clazz = Module.const_get(clazz) if clazz.kind_of?(String)
        rescue NameError
            raise "Class '#{clazz}' not found"
        end

        if name.nil?
            name = @artname
        else
            name = ArtifactName.new(name) if name.kind_of?(String)
        end

        return clazz.new(name.suffix.nil? ? self[:def_name] : name.suffix,
            &(block.nil? ? self[:block] : Proc.new {
                self.instance_eval &self[:block]
                self.instance_eval &block
            })
        )
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


#
# Core artifact abstraction.
#  "@name" - name of artifact
#  "@shortname"
#  "@ver"
#
class Artifact
    attr_reader :name, :shortname, :ver, :owner

    # context class is special wrapper object that redirect
    # its methods call to a wrapped (artifact object) target
    # object. Additionally it tracks a current target object
    # from which a method has been called.
    # c
    class Context
        instance_methods.each() { |m|
            if not m.to_s =~ /__[a-z]+__/
                undef_method m if not m.to_s =~ /object_id/
            end
        }

        # keeps artifact call stack
        @@context = []

        def initialize(target)
            raise 'Target has to be defined' if target.nil?
            @target = target
        end

        def method_missing(meth, *args, &block)
            switched = false
            if @@context.last != @target
                @@context.push(@target)
                switched = true
            end
            begin
                return @target.send(meth, *args, &block)
            ensure
                @@context.pop() if switched
            end
        end

        def self.context() @@context.last end
    end

    def Artifact.required(clazz, &block)
        self.send(:define_method, clazz.name.downcase) {
            an = instance_variable_get("@#{clazz.name}")
            begin
                a  = owner.artifact(an.nil? ? clazz.name : an) unless owner.nil?
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
        instance = allocate()
        ctx = Artifact.context
        if instance.owner.nil? && !ctx.nil?
            if ctx.kind_of?(Project)
                instance.owner  = ctx
            elsif !ctx.owner.nil?
                instance.owner = ctx.owner
            end
        end
        instance.send(:initialize, *args, &block)
        Context.new(instance)
    end

    # return artifact instance whose method is currently called
    def Artifact.context() Context.context() end

    def initialize(name, &block)
        # test if the name of the artifact is not nil or empty string
        ArtifactName.nil_name(name)

        @name, @shortname = name, File.basename(name)
        @owner ||= nil  # owner has to be set basing on calling context before initialize method in new

        # block can be passed to artifact
        # it is expected the block setup class instance
        # variables like '{ @a = 10 ... }'
        self.instance_eval(&block) if block
    end

    def owner=(value)
        if value.nil?
            @owner = value
        else
            raise "Invalid project artifact type '#{value.class}'" unless value.kind_of?(Project)
            @owner = value
        end
    end

    def homedir()
        return owner.fullpath unless owner.nil?
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
    def ==(art) art && self.class == art.class && @name == art.name && @ver == art.ver && @owner == art.owner end

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
            art = Project.artifact(art) if art.kind_of?(String)
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
        root.art.requires.each { |a|
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
        base = base[0..-2] if base[-1] == '/'
        path = path[0..-2] if path[-1] == '/'
        return true  if base == path
        return false if base.length == path.length
        i = path.index(base)
        return false if i.nil? || i != 0
        return path[base.length] == '/'
    end

    def homedir()
        if @is_absolute
            unless owner.nil?
                home = owner.homedir
                if Pathname.new(home).absolute?
                    home = home[0, home.length - 1] if home.length > 1 && home[home.length - 1] == '/'
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

    def fullpath(path = @name)
        if path == @name
            return path if @is_absolute
            return Pathname.new(File.join(homedir, path)).cleanpath.to_s
        else
            path = Pathname.new(path).cleanpath
            home = homedir
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

#  Perform and action on a file artifact
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

    def paths_to_list(relative = nil)
        list = []
        list_items(relative) { | path, m|
            list << path
        }
        return list
    end

    def list_items(relative = nil)
        go_to_homedir()

        relative = relative[0, relative.length - 1] if !relative.nil? && relative[-1] == '/'

        Dir[@name].each { | path |
            b = false
            b = (path =~ @regexp_filter) != nil if @regexp_filter

            if b == false && (@ignore_files || @ignore_dirs)
                b = File.directory?(path)
                b = (@ignore_files && !b) || (@ignore_dirs && b)
            end

            if b == false
                mt = File.mtime(path).to_i()
                unless relative.nil?
                    "Relative path '#{relative}' cannot be applied to '#{path}'" unless _contains_path?(relative, path)
                    path = path[relative.length + 1, path.length - relative.length]
                end
                yield path, mt
            end
        }
    end

    def expired?() true end
end

#  Instantiate an artifact depending on condition the artifact name
#  matches. Constructor should get name and block that defines mapping
#  rules:
#  {
#     'regexp_string' | <reg_exp>  => artifact_class | artifact_alias (command name)
#  }
class ArtifactSelector < Artifact
    def initialize(*args)
        super

        # Fetch mapping block
        raise 'Artifact conditional map has not been defined' if @map.nil? || @map.length == 0

        counter = 0
        @map.each_pair { | k, v |
            r = Regexp.new(k) if k.kind_of?(String)

            if r.match(@name)
                raise "Ambiguous artifact selector match for #{@name}" if counter > 0
                counter += 1
                if v.kind_of?(String)
                    raise "Owner for '#{self.class}' class is not defined" if owner.nil?
                    REQUIRE owner.artifact("#{v}:#{@name}")
                elsif v.kind_of?(Class)
                    REQUIRE v.new(@name)
                else
                    raise "Artifact '#{@name}' mapping has wrong type #{v.class}"
                end
            end
        }

        raise "No mapping is available for '#{@name}' artifact" if counter == 0
    end

    def build() end
end

# project artifact
class Project < Directory
    attr_reader :desc

    @@target_project = nil

    def self.target=(prj)
        @@target_project = prj
    end

    def self.target()
        @@target_project
    end

    def self.artifact(name, &block)
        @@target_project.artifact(name, &block)
    end

    def self.create(home, owner = nil)
        @@target_project = Project.new(home, owner) {
            conf = File.join(home, '.lithium', 'project.rb')
            self.instance_eval(File.read(conf)).call if File.exists? conf
        }
        return @@target_project
    end

    def initialize(*args, &block)
        # means artifact meta are not shared with its children project
        @contexts  = {}
        self.owner = args[1] if args.length > 1
        super(args[0], &block)
        @desc ||= File.basename(args[0])
    end

    def top()
        ow = self
        while !ow.owner.nil? do
            ow = ow.owner
        end
        return ow
    end

    #  artifact name can be
    #    -- ArtifactMeta then artifact is created immediately,
    #    -- String or ArtifactName first look in cache, then try to find in a context then try to build by local meta ...
    #    -- Class
    #
    def artifact(name, &block)
        artname = name.kind_of?(ArtifactName) ? name : ArtifactName.new(name)
        return _artifacts[artname] if artname.path_mask.nil? && !_artifacts[artname].nil?  # try to fetch the artifact from cache

        unless artname.path.nil?
            ctx = @contexts[artname.path]
            ctx = @contexts.detect { | p | p[0].match(artname.path) } if ctx.nil?
            return ctx[1].artifact(name, &block) unless ctx.nil?
        end

        # fund local info about the given artifact
        key, meta = find_meta(artname)

        if meta.nil?
            if artname.path.nil? || !match(artname.path)
                # path nil or doesn't match project then delegate finding an artifact in an owner project context
                return owner.artifact(name, &block) unless owner.nil?
            else
                # path matches the project find meta in owner hierarchy and resolve it in the context of the project
                ow = owner
                while !ow.nil? && meta.nil? do
                    key, meta = ow.find_meta(artname)
                    ow = ow.owner
                end
            end
        end

        # TODO: analyze if this should be done in context owner or the child
        if meta.nil?
            # try to treat artifact prefix as a class name
            unless artname.prefix.nil?
                clazz = nil
                begin
                    clazz = Module.const_get(artname.prefix[0..-2])
                rescue NameError
                    raise "Artifact class cannot be detected by '#{artname}'"
                end

                # this type of artifacts cannot be cached, so return it
                return clazz.new(artname.suffix, &block) unless clazz.nil?
            end
            raise NameError.new("No artifact is associated with '#{name}'")
        end

        art = meta.instantiate(artname, &block)

        # key implicitly identifies artifact then store the artifact in cache
        _artifacts[artname] = art if artname == key

        # TODO: the key :clean is never set, since ARTIFACT doesn't support the parameter
        art.cleanup() if meta[:clean] == true
        return art
    end

    def homedir()
        return @name if @is_absolute
        return super
    end

    # { <art_name> => <art_class_instance>, ...}
    def _artifacts()
        @artifacts = {} unless defined? @artifacts
        @artifacts
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
        artname = name.kind_of?(ArtifactName) ? name : ArtifactName.new(name)
        meta    = _meta[artname]
        return _meta.detect { | p | p[0].match(artname) } if meta.nil?
        return [ artname, meta ]
    end

    def expired?() true end

    def build() end

    def what_it_does()
        nil
    end

    def CONTEXT(name, path)
        path = fullpath(File.join('.lithium', path)) unless Pathname.new(path).absolute?
        raise "Context configuration path '#{path}' is invalid" if !File.exists?(path) || File.directory?(path)
        @contexts[ArtifactName.new(name)] = Project.new(homedir, self) {
            self.instance_eval(File.read(path)).call
        }
        @contexts = @contexts.sort.to_h
    end

    #
    # ([name, []] clazz, [&block])
    #
    def ARTIFACT(*args, &block)
        m = ArtifactMeta.new(*args, &block)

        # try to find previously stored meta
        if _meta[m.artname]
            puts "Override previously defined '#{m.artname}' artifact"
            _artifacts.delete(m.artname) if m.artname.path_mask.nil? && _artifacts[m.artname]
        end

        # store meta
        _meta[m.artname] = m

        # sort dictionary by key
        @meta = _meta.sort.to_h
    end

    def REUSE(*args, &block)
        raise "Project '#{self}' doesn't have parent project to re-use its artifacts" if owner.nil?
        artname = ArtifactName.new(args[0])
        meta    = _meta[artname]
        raise "Artifact '#{artname}' is already defined with '#{self}' project" unless meta.nil?

        ow = owner
        while meta.nil? && !ow.nil?
            meta = ow._meta[artname]
            ow   = ow.owner
        end
        raise "Cannot find '#{artname}' in parent projects" if meta.nil?

        _meta[artname] = meta.reuse(&block)
    end

    def REMOVE(name)
    end
end
