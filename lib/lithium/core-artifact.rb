require 'pathname'

require 'lithium/utils'
require 'lithium/core-loggable'

#   Artifact name keeps order of artifact following the rules below:
#     1) aliased artifact precede not aliased artifact and sorted alphabetically
#     2) the same aliased artifact with path specified sorted by this path
#     3) path artifacts are sorted from particular case to common
#
#   For example:
#
#   [ "aa:test/", "aa:test/*", "aa:test/**/*", "aa:", "bb:", "compile:test/test/a",
#     "compile:test/**/*", "compile:", "test/com", "test/com/**" ]
class ArtifactPath < String
    attr_reader :prefix, :suffix, :path, :path_mask, :mask_type, :clazz, :block

    # return artifact name as is if it is passed as an instance of artifact name
    def self.new(name, clazz = nil, &block)
        if name.kind_of?(ArtifactPath)
            raise "ArtifactPath('#{name}') instance has to be passed as a single argument of constructor" unless clazz.nil?
            raise "Block cannot be customized for existent ArtifactPath('#{name}') class instance"        unless block.nil?
            return name
        else
            super(name, clazz, &block)
        end
    end

    # Construct artifact name.
    # @param name?  - name of the artifact, name can contain class prefix e.g "ArtifactClass:name"
    # @param clazz? - artifact class
    #
    # ArtifactPath(
    #    name  : { String }
    # )
    #
    # ArtifactPath(
    #    clazz : { Class < Artifact }
    # )
    #
    # ArtifactPath(
    #    name  : { String }
    #    clazz : {Class < Artifact, nil}
    # )
    #
    def initialize(name, clazz = nil, &block)
        @clazz = clazz
        if name.kind_of?(Class)
            raise "Input '#{clazz}' class argument is ambiguous since it is already defined as '#{name}' class" unless clazz.nil?
            @clazz = name
            name   = nil
        end

        if name.nil? && !@clazz.nil?
            name = @clazz.default_name
            raise "Artifact default name cannot be detected by '#{@clazz}'' class" if name.nil?
        end

        name = ArtifactPath.assert_notnil_name(name)

        @mask_type = File::FNM_DOTMATCH
        @prefix = name[/^\w\w+\:/]
        @suffix = @prefix.nil? ? name : name[@prefix.length .. name.length]
        @suffix = nil if !@suffix.nil? && @suffix.length == 0

        @path = @path_mask = nil
        @path = @suffix[/((?<![a-zA-Z])[a-zA-Z]:)?[^:]+$/] unless @suffix.nil?
        unless @path.nil?
            @path, @path_mask = Files.cut_fmask(@path)
            @path      = Pathname.new(@path).cleanpath.to_s unless @path.nil?
            @mask_type = @mask_type | File::FNM_PATHNAME    if     @path_mask != '*' || !@path.nil?
        end

        if @clazz.nil? && !@prefix.nil?
            begin
                @clazz = Module.const_get(@prefix[0..-2])
            rescue
            end
        end

        raise "Class '#{@clazz}' is not an Artifact class for '#{name}' name" unless @clazz.nil? || @clazz < Artifact
        @block = block

        super(name)
    end

    #
    # Make the specified artifact path relative to the given path.
    # @param path - { String, Symbol, Class, ArtifactPath } path of an artifact
    # @param to - string path to make the given artifact path relative to
    # @return ArtifactPath
    def self.relative_to(path, to)
        artname = ArtifactPath.new(path)
        unless artname.path.nil?
            path = Files.relative_to(artname.path, to)
            unless path.nil?
                return ArtifactPath.new(ArtifactPath.name_from(artname.prefix, path, artname.path_mask))
            end
        end
        return artname
    end

    def self.assert_notnil_name(name)
        raise "Artifact name '#{name}' is nil, empty or is not an instance of String class" if name.nil? || !name.kind_of?(String) || name.strip.length == 0
        name.strip
    end

    def self.name_from(prefix, path, path_mask)
        path = nil if !path.nil? && path.length == 0
        name  = path.nil? ? '' : path
        name  = path.nil? ? path_mask : File.join(name, path_mask) unless path_mask.nil?
        name  = prefix + name                                      unless prefix.nil?
        return name
    end


    def env_path?
        !path.nil? && path.start_with?('.env/')
    end

    def match(name)
        name = ArtifactPath.new(name)

        # prefix doesn't match each other
        return false if @prefix != name.prefix
        unless @path_mask.nil?
            # Condition "(name.env_path? ^ env_path?)" helps to prevent eating environment
            # artifact with file masks. For instance imagine we have file mask "**/*"
            # defined in project.rb, in this case the artifact will match '.env/JAVA' what
            # cause the instantiated artifact will have invalid type
            return false if name.suffix.nil? || (name.env_path? ^ env_path?) # one of the path is environment but not both
            return File.fnmatch(@suffix, name.suffix, @mask_type)
        else
            return @suffix == name.suffix
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

    def inspect
        "#{self.class.name}: { prefix='#{@prefix}', suffix='#{@suffix}', path='#{@path}', mask='#{@path_mask}' mask_type=#{mask_type}, clazz=#{@clazz}}, block = #{@block}"
    end

    def ==(an)
        !an.nil? && self.object_id == an.object_id ||
        (an.class == self.class && an.suffix == @suffix && an.prefix == @prefix &&
         an.path == @path && an.path_mask == @path_mask && an.mask_type == @mask_type &&
         an.clazz == @clazz && an.block == @block)
    end

    def combine_block(b)
        @block = Block.combine_blocks(@block, b)
        return self
    end

    def _block(b)
        @block = b
        return self
    end
end

# Core artifact abstraction.
#  "@name" - name of artifact
class Artifact
    attr_reader :name, :owner, :createdByMeta, :built, :expired, :caller, :requires

    # the particular class static variables
    @default_name  = nil
    @default_block = nil
    @default_block_inherit = true

    # set or get default artifact name
    def self.default_name(*args)
        @default_name = args[0] if args.length > 0
        @default_name
    end

    def self.default_block
        return @default_block, @default_block_inherit
    end

    # TODO: naming convention ?
    def self._(inherit = true, &block)
        @default_block = block unless block.nil?
        @default_block_inherit = inherit
        @default_block
    end

    def self.run_default_block(instance, clazz)
        dbf, inh = clazz.default_block
        pclazz   = clazz.superclass
        self.run_default_block(instance, pclazz) if inh != false && (pclazz <= Artifact)  == true
        instance.instance_exec(&dbf) unless dbf.nil?
    end

    # !!! this method cares about owner and default name setup, otherwise
    # !!! owner and default name initialization depends on when an artifact
    # !!! instance call super
    def self.new(name = nil, owner:nil, &block)
        name = self.default_name if name.nil?
        unless owner.nil? || owner.kind_of?(ArtifactContainer)
            raise "Invalid owner '#{owner.class}' type for '#{name}' artifact, an artifact container class instance is expected"
        end

        instance = allocate()
        instance.owner = owner
        begin
            instance.initialize_called = true
            self.run_default_block(instance, instance.class)
            if name.nil?
                instance.send(:initialize, &block)
            else
                instance.send(:initialize, name, &block)
            end
            ArtifactPath.assert_notnil_name(instance.name)
        ensure
            instance.initialize_called = false
        end
        return instance
    end

    def initialize(name = nil, &block)
        # test if the name of the artifact is not nil or empty string
        @name = name

        # block can be passed to artifact
        # it is expected the block setup class instance
        # variables like '{ @a = 10 ... }'
        self.instance_exec(&block) if block
    end

    def inspect
        "#{self.class}:#{@name}"
    end

    # top owner (container) artifact
    def top
        ow = self
        while !ow.owner.nil? do
            ow = ow.owner
        end
        return ow
    end

    def createdByMeta=(m)
        @createdByMeta = m
    end

    def initialize_called=(v)
        @_init_called = v
    end

    def initialize_called?
       @_init_called == true
    end

    def owner=(value)
        if value.nil?
            @owner = value
        else
            raise "Invalid project artifact type '#{value.class}'" unless value.kind_of?(ArtifactContainer)
            @owner = value
        end
    end

    def project
        ow = owner
        while ow && !ow.kind_of?(Project) do
            ow = ow.owner
        end
        return ow
    end

    def homedir
        return owner.homedir unless owner.nil? # if has a container the artifact belongs
        return File.expand_path(Dir.pwd)
    end

    def go_to_homedir(&block)
        chdir(homedir, &block)
    end

    def chdir(dir, &block)
        if block.nil?
            Dir.chdir(dir)
        else
            pwd = Dir.pwd
            begin
                Dir.chdir(dir)
                block.call
            ensure
                Dir.chdir(pwd) unless pwd.nil?
            end
        end
    end

    # prevent error generation for a number of optional artifact methods
    # that are called by lithium engine:
    #  - built
    #  - build_failed
    #  - before_build
    #
    def method_missing(meth, *args, &block)
        # detect if there is an artifact class exits with the given name to treat it as
        # required artifact. It is done only if we are still in "require" method call
        if meth.length > 2 && @caller == :require
            # TODO: revised, most likely the code is not required since REQUIRE can be executed outside of constructor
#            raise "REQUIRED artifacts can be defined only in '#{self}' artifact constructor" unless initialize_called?

            name = args.length == 0 ? nil : args[0]
            clazz, is_internal = Artifact._name_to_clazz(meth)
            if is_internal
                raise "Block was not defined for updating '#{clazz}:#{name}' requirement" if block.nil?
                @requires ||= []
                art_name = ArtifactPath.new(name, clazz)
                idx      = @requires.index { | a | art_name.to_s == a.to_s }
                raise "Required '#{clazz}' artifact cannot be detected" if idx.nil?
                @requires[idx].combine_block(block)
            else
                REQUIRE(name, clazz, &block)
            end
        else
            super(meth, *args, &block)
        end
    end

    # build the given artifact within context of the given artifact
    def ENCLOSE(name, clazz = nil, &block)
        path = ArtifactPath.new(name, clazz)
        art  = path.clazz.new(path.suffix, owner:self.is_a?(ArtifactContainer) ? self : self.owner, &block)
        tree = ArtifactTree.new(art)
        tree.build
    end

    def each_required
        @requires ||= []
        req = @requires
        req = req.reverse.uniq { | artname |
            # test if required is assignable artifact and if another assignable for the same (not array)
            # property has been already defined remove it from required
            if !artname.clazz.nil? && artname.clazz < AssignableDependency && !artname.clazz.assign_as_array?
                "@#{artname.clazz.assign_with_name}"
            elsif artname.clazz.nil?
                artname.to_s
            else
                "#{artname.clazz.name}:#{artname.to_s}"
            end
        }.reverse

        req.each { | dep |
            yield dep
        }
    end

    def before_build(is_expired)
    end

    def build
    end

    def built
        self.instance_exec(&@built) unless @built.nil?
    end

    def build_failed
    end

    # test if the given artifact has expired and need to be built
    def expired?
        true
    end

    # clean method should be implemented to clean artifact related
    # build stuff
    def clean() end

    def what_it_does
        "Build '#{self.class}:#{@name}' artifact"
    end

    # Overload "eq" operation of two artifact instances.
    def ==(art)
        return !art.nil? && self.object_id == art.object_id ||
                (self.class == art.class && @name == art.name && createdByMeta == art.createdByMeta)
    end

    # return last time the artifact has been modified
    def mtime
        -1
    end

    def to_s
        File.basename(@name)
    end

    # @param art : { String, Symbol, Class } - artifact can be one of the following type:
    # block - custom block for artifact or if art is nil block is build method for
    def REQUIRE(name = nil, clazz = nil, &block)
        if name.nil? && clazz.nil?
            raise "REQUIRE block has to be defined for '#{self.name}' artifact"                        if block.nil?
            raise "REQUIRE block is called within another REQUIRE() method of '#{self.name}' artifact" if @caller == :require
            prev = @caller
            begin
                @caller = :require
                self.instance_exec(&block)
            ensure
                @caller = prev
            end
        else
            add_reqiured(name, clazz, &block)
        end
    end

    def DISMISS(name, clazz = nil)
        @requires ||= []
        ln = @requires.length
        artname = ArtifactPath.new(name, clazz)
        @requires.delete_if { | req | req.to_s == artname.to_s && req.clazz == artname.clazz }
        raise "'#{artname}' DEPENDENCY cannot be found and dismissed" if ln == @requires.length
    end

    # called after the artifact has been built
    def BUILT(&block)
        @built = block
    end

    def add_reqiured(name = nil, clazz = nil, &block)
        @requires ||= []
        if name.is_a?(Artifact)
            raise "Artifact instance '#{name}' cannot be used as a required artifact"
        else
            art_name = ArtifactPath.new(name, clazz, &block)
            i = @requires.index { | req | req.to_s == art_name.to_s && req.clazz == art_name.clazz }
            if i.nil?
                @requires.push(art_name)
            else
                puts_warning "Artifact '#{art_name}' requirement has been already defined"
                @requires[i] = art_name
            end
        end
    end

    def EXPIRED?(call_super = false, &block)
        @expired = block
        @call_super = call_super
        class << self
            def expired?
                !@expired.nil? && instance_exec(&@expired) || (@call_super && super)
            end
        end
    end

    def self.abbr
        return @abbr unless @abbr.nil?
        return "%3s" % self.name[0..2].upcase
    end

    def self._name_to_clazz(name)
        raise 'Nil class name' if name.nil?
        name = name.to_s       if name.is_a?(Symbol)
        raise "'#{name.class}' class name is not a string Symbol class instance" unless name.is_a?(String)
        name = name.strip
        raise "'#{name}' class name is too short" if name.length < 3

        clazz, is_internal = nil, false
        name, is_internal = name[..-2].to_sym, true if name[-1] == '!'
        begin
             clazz = Module.const_get(name)
        rescue
            puts_error "'#{name}' cannot be mapped to an artifact class"
            raise $!
        end

        raise "'#{clazz}' doesn't inherit an Artifact class" unless clazz < Artifact
        return clazz, is_internal
    end
end

# Artifact tree. Provides tree of artifacts that is built basing
# on resolving artifacts dependencies
class ArtifactTree
    @@full_tree = false

    attr_accessor :art, :parent, :children, :expired, :expired_by_kid

    def initialize(art, parent = nil, &block)
        raise 'Artifact cannot be nil' if art.nil?

        if art.kind_of?(Artifact)
            raise "Instantiated artifact '#{art.class}:#{art.name}' cannot be applied to a block" unless block.nil?
            @art = art
        else
            raise "Parent artifact cannot be nil for '#{art}' artifact definition" if parent.nil?
            own = parent.art.kind_of?(ArtifactContainer) ? parent.art : parent.art.owner
            raise "Owner of '#{art}' artifact cannot be detected by '#{parent.art}' parent artifact" if own.nil?
            @art = own.artifact(art, &block)
        end

        @children, @parent, @expired, @expired_by_kid = [], parent, false, nil

        # If parent is nil then the given tree node is considered as root node.
        # The root node initiate building tree
        build_tree() if parent.nil?
    end

    # build tree starting from the root artifact (identified by @name)
    def build_tree(map = [])
        bt, @children = @art.mtime, []

        @art.each_required { | name |
            foundNode, node = nil, ArtifactTree.new(name, self)

            # existent of a custom block makes the artifact specific even if an artifact with identical object id is already in build tree
            if name.block.nil? && @@full_tree == false
                # optimize tree to exclude dependencies that are already in the tree
                foundNode = map.detect { | n | node.art.object_id == n.art.object_id  }
                # save in list if a new artifact has been detected
                map.push(node) if foundNode.nil?
            end

            # cyclic dependency detection
            parent = self
            while parent && parent.art != node.art
                parent = parent.parent
            end
            raise "#{@art.class}:'#{art}' has CYCLIC dependency on #{parent.art.class}:'#{parent.art}'" unless parent.nil?

            # build sub-tree to evaluate expiration
            if foundNode.nil?
                node.build_tree(map)
                # add the new node to tree and process it only if doesn't already exist
                @children << node
            end

            # we have to check if the artifact is assignable to
            # its parent and assign it despite if the artifact has
            # been excluded from the tree
            #
            # resolve assign_me_as  property that says to which property the instance of the
            # dependent artifact has to be assigned
            node.art.assign_me_to(@art) if node.art.class < AssignableDependency

            # most likely the expired state has to be set here, after assignable dependencies are set
            # since @art.expired? method can require the assigned deps to define its expiration state
            # moreover @art.expired? should not be called here since we can have multiple assignable
            # deps
            if @expired_by_kid.nil? && (node.expired || (bt > 0 && node.art.mtime() > bt))
                @expired = true
                @expired_by_kid = node.art
            end
        }

        # check if expired attribute has not been set (if there were no deps
        # that expired the given art)
        @expired = @art.expired? if @expired != true
        return self
    end

    def build(&block)
        unless @expired
            @art.before_build(false)
            puts_warning "#{@art.class}:'#{@art.name}' is not expired"
        else
            @children.each { | node |
                node.build()
            }

            prev_art = $current_artifact
            begin
                $current_artifact = @art
                wid = @art.what_it_does()

                puts wid unless wid.nil?
                @art.before_build(true)
                @art.build(&block)
                @art.built()
            rescue
                @art.build_failed()
                level = !$lithium_options.nil? && $lithium_options.key?('v') ? $lithium_options['v'].to_i : 0
                puts_exception($!, 0) if level == 0
                puts_exception($!, 3) if level == 1
                raise                 if level > 1
            ensure
                $current_artifact = prev_art
            end
        end
        return @art
    end

    def traverse(level = 0, &block)
        @children.each { | node |
            node.traverse(level + 1, &block)
        }
        block.call(self, level)
    end

    def self.full_tree
        @@full_tree = true
    end
end

module ArtifactContainer
    # Create and return artifact identified by the given name.
    #  @param name: { String, Symbol, ArtifactPath, Class }
    #  @return Artifact
    def artifact(name, clazz = nil, &block)
        artname = ArtifactPath.new(name, clazz)

        # fund local info about the given artifact
        meta, meta_ow = match_meta(artname)
        if meta.nil?
            unless owner.nil?
                # There are two types of container: project and file mask containers. File mask containers
                # exist only in a context of a project and should share common artifacts through a
                # common project (if the artifact is not defined on the level of the container). It helps
                # to avoid duplication of multiple artifacts created with the same meta. For instance
                # JAVA artifact instance for java compiler (.*) and Java runner mask containers have to
                # the same if it is not re-defined on the level of the container.
                return owner.artifact(artname, &block) if delegate_to_owner_if_meta_cannot_be_found?
                meta, meta_ow = owner.match_meta(artname, true)
            end

            if meta.nil?
                meta = artname unless artname.clazz.nil?
            else
                # attempt to handle situation an artifact meta of the given container has been
                # created is going to be applied to artifact creation. It can indicate we
                # have cyclic come back
                raise "There is no an artifact META associated with '#{name}'" if !createdByMeta.nil? && meta.object_id == createdByMeta.object_id
            end

            raise "No artifact definition is associated with '#{name}'" if meta.nil?
        end

        # manage cache
        _remove_from_cache(artname)          unless block.nil?  # remove from cache if a custom block has been passed
        art = _artifact_from_cache(artname)  if block.nil?      # read from cache if custom block has not been passed

        # instantiate artifact with meta if it has not been found in cache
        art = _artifact_by_meta(artname.suffix, meta, &block) if art.nil?
        art = _cache_artifact(artname, art)                   if block.nil? # cache only if a custom block has been passed

        # if the artifact is a container handling of target (suffix) is delegated to the container
        return art.is_a?(ArtifactContainer) ? art.artifact(artname.suffix) : art
    end

    # cache artifact only if it is not identified by a mask or is an artifact container
    def _cache_artifact(artname, art)
        raise "Invalid '#{artname.class}' parameter type, ArtifactPath instance is expected" unless artname.kind_of?(ArtifactPath)
        if artname.path_mask.nil? || art.kind_of?(ArtifactContainer)
            _artifacts_cache[artname] = art
        end
        return art
    end

    # fetch an artifact from cache
    def _artifact_from_cache(artname)
        raise "Invalid '#{artname.class}' parameter type, ArtifactPath instance is expected" unless artname.kind_of?(ArtifactPath)
        unless _artifacts_cache[artname].nil?
            return _artifacts_cache[artname]
        else
            return nil
        end
    end

    # { art_name:ArtifactPath => instance : Artifact ...}
    def _artifacts_cache
        @artifacts = {} unless defined? @artifacts
        @artifacts
    end

    def _remove_from_cache(name, clazz = nil)
        name = ArtifactPath.new(name, clazz)
        _artifacts_cache.delete(name) unless _artifacts_cache[name].nil?
    end

    # instantiate the given artifact by its meta
    def _artifact_by_meta(name, meta, &block)
        raise "'#{meta}' definition does not define class for '#{name}' artifact" if meta.clazz.nil?
        art   = meta.clazz.new(name, owner:self, &Block.combine_blocks(meta.block, block))
        art.createdByMeta = meta
        return art
    end

    # meta hosts ArtifactPath instances
    def _meta
        @meta = [] unless defined? @meta
        return @meta
    end

    # Find appropriate for the given artifact name a registered meta
    # @param name: { String, Symbol, Class, ArtifactPath } artifact name
    # @param recursive: { boolean } flag that indicates if searching a meta
    # should be done in parent hierarchy as well
    #
    # @return (ArtifactPath, ArtifactContainer)
    def match_meta(name, recursive = false)
        art_name = ArtifactPath.relative_to(name, homedir)
        meta = _meta.detect { | m |
            m.match(art_name)
        }

        return meta, self unless meta.nil?
        return owner.match_meta(name, recursive) if recursive == true && !owner.nil?
        return nil
    end

    def ==(prj)
        super(prj) && _meta == prj._meta
    end

    #
    # DEFINE(
    #   name  : { String },
    #   clazz : { Class < Artifact, nil}
    # )
    #
    # DEFINE(
    #   clazz : { Class < Artifact }
    # )
    #
    # DEFINE(
    #   name : { String, ArtifactPath }
    # )
    #
    def DEFINE(name, clazz = nil, &block)
        artname = ArtifactPath.new(name, clazz, &block)
        raise "Unknown class for '#{artname}' artifact" if artname.clazz.nil?

        # delete artifact meta if it already exists
        old_meta, old_meta_ow = match_meta(artname)
        old_meta_ow._meta.delete(old_meta) unless old_meta.nil?

        _meta.push(artname)
         # sort meta array
        _meta.sort!
    end

    def method_missing(meth, *args, &block)
        # TODO: review this code
        if meth.length > 2 && @caller != :require
            clazz, is_reuse = Artifact._name_to_clazz(meth)
            name = args.length == 0 ? nil : args[0]
            if is_reuse
                REUSE(name, clazz, &block)
            else
                DEFINE(name, clazz, &block)
            end
        else
            super
        end
    end

    def REUSE(name, clazz = nil, &block)
        name  = ArtifactPath.new(name, clazz)

        # find meta currently defined in the given container
        meta, meta_ow = match_meta(name, true)
        raise "Cannot find '#{name}' definition in containers hierarchy" if meta.nil?

        meta_ow._remove_from_cache(name)
        meta_ow._meta.delete(meta)
        meta_ow._meta.sort!

        _meta.push(meta.dup._block(Block.combine_blocks(meta.block, block)))
        _meta.sort!
    end

    def REMOVE(name, clazz = nil)
        name = File.join(homedir, name) if name.start_with?('./') || name.start_with?('../')
        own = self
        while !own.nil?
            artpath = ArtifactPath.new(name, clazz)
            artpath = ArtifactPath.relative_to(artpath, own.homedir)
            own._meta.delete_if { | m | artpath.match(m) }
            own._meta.sort!
            own = own.owner
        end
    end

    def delegate_to_owner_if_meta_cannot_be_found?
        false
    end

    def BUILD(name = nil, clazz = nil, &block)
        art       = artifact(name, clazz, &block)
        container = art.owner
        while !container.nil? do
            tree = ArtifactTree.new(container)
            tree.build()
            container = container.owner
        end

        tree = ArtifactTree.new(art)
        tree.build()
        return tree.art
    end
end

# Environment artifact
class EnvArtifact < Artifact
    include AssignableDependency

    def self.default_name(*args)
        @default_name ||= nil

        if args.length > 0
            raise "Invalid environment artifact '#{args[0]}' name ('.env/<artifact_name>' is expected)" unless args[0].start_with?('.env/')
            @default_name = args[0]
        elsif @default_name.nil?
            @default_name = File.join('.env', self.name)
        end

        return @default_name
    end

    def expired?
        false
    end
end

class SdkEnvironmen < EnvArtifact
    include LogArtifactState
    include OptionsSupport

    log_attr :sdk_home

    # name of a tool (mvn, java) that has to be used to lookup SDK home directory
    # the field should be defined on the level of appropriate SDK environment
    # class
    @tool_name = nil

    def initialize(name, &block)
        super

        unless @sdk_home
            @sdk_home = Files.which(tool_name, true)
            @sdk_home = File.dirname(File.dirname(@sdk_home)) unless @sdk_home.nil?
        end

        if @sdk_home.nil? || !File.exist?(@sdk_home)
            @sdk_home = force_sdkhome_detection()
        end

        if @sdk_home.nil? || !File.exist?(@sdk_home)
            puts_error "SDK #{self.class} home '#{@sdk_home}' cannot be found or nil, check if '#{tool_name}' tool name is valid"
            puts_error 'Configure/install SDK if it is required for a project'
        else
            puts "SDK #{self.class}('#{@name}') home: '#{File.realpath(@sdk_home)}'"
        end
    end

    def force_sdkhome_detection
        nil
    end

    def what_it_does
        "Initialize #{self.class} '#{@name}' environment"
    end

    def tool_path(nm)
        File.join(@sdk_home, 'bin', nm)
    end

    def tool_name
        @tool_name.nil? ? self.class.tool_name : @tool_name

        #return self.class.tool_name
    end

    def tool_version(version_opt = '--version', pattern = /([0-9]+\.[0-9]+(\.[0-9]+|_[0-9]+)?)/)
        @version = Files.grep_exec(tool_path(tool_name()), version_opt, pattern:pattern)
        @version = @version[0] unless @version.nil?
        @version
    end

    def self.tool_name
        @tool_name
    end

    def self.detect_tool_name(*args)
        tool = args.detect { | e | !Files.which(e).nil? }
        tool.nil? ? nil : File.basename(tool)
    end
end

class EnvironmentPath < EnvArtifact
    include LogArtifactState
    include PATHS
    include AssignableDependency[:paths, true]

    log_attr :paths
end

