require 'pathname'
require 'open3'
require 'digest'
require 'tempfile'

$ready_list = []

# Registered with READY code blocks are called when lithium startup 
# initialization is completed
def READY(&block)
    $ready_list.push(block)
end

#  Log takes care about logged expiration state.
#
#  Log assists to calculate proper modified time. If an artifact returns
#  modified time that greater than zero it is compared to logged
#  modified time. The most recent will be return as result.
#
#  Hook module replace "clean", "built", "mtime",  "expired?"
#  artifact class methods with "original_<method_name>" methods.
#  It used by LogArtifact to intercept the method calls with "method_missing"
#  method.
module HookMethods
    @@hooked = [ :clean, :built, :mtime, :expired? ]

    def included(clazz)
        if clazz.kind_of?(Class)
            raise 'No methods for catching have been defined' if !@@hooked

            clazz.instance_methods().each { | m |
                m = m.intern
                HookMethods.hook_method(clazz, m) if @@hooked.index(m)
            }

            def clazz.method_added(m)
                unless @adding
                    @adding = true
                    HookMethods.hook_method(self, m) if @@hooked.index(m) && self.method_defined?(m)
                    @adding = false
                end
            end
        else
            clazz.extend(HookMethods)
        end
    end

    def HookMethods.hook_method(clazz, m)
        clazz.class_eval {
            n = "original_#{m}"
            alias_method n, m.to_s
            undef_method m
        }
    end
end

# The module has to be included in an artifact to track its update date. It is possible
# to control either an artifact items state that has to be returned by implementing
# "list_items()" method or an attribute state that has to be declared via log_attr method
module LogArtifactState
    extend HookMethods

    # catch target artifact methods call to manage artifact expiration state
    def method_missing(meth, *args)
        if meth == :clean
            original_clean()
            expire_logs()
        elsif meth == :built
            original_built()
            update_logs()
        elsif meth == :mtime
            t = logs_mtime()
            return original_mtime() if t < 0
            tt = original_mtime()
            return t > tt ? t : tt
        elsif meth == :expired?
            return logs_expired? || original_expired?
        else
            super
        end
    end

    # class level method a class has to be extends
    module LoggedAttrs
        def log_attr(*args)
            @logged_attrs ||= []
            @logged_attrs += args

            # check if attribute reader method has not been already defined with a class
            # and define it if it doesn't
            args.each { | arg |
                attr_accessor arg unless method_defined?(arg)
            }
        end

        def _log_attrs()
            return [] if @logged_attrs.nil?
            return @logged_attrs
        end

        def each_log_attrs()
            cl    = self.superclass
            attrs = _log_attrs()

            while cl && cl.include?(LogArtifactState)
                p_attrs = cl._log_attrs()
                i_attrs = attrs & p_attrs
                raise "Logged attribute #{i_attrs} has been already defined in '#{cl}' parent class" if i_attrs.length > 0

                attrs = attrs + p_attrs
                cl = cl.superclass
            end

            attrs.each { |e| yield e } if attrs.length > 0
        end

        def has_log_attrs()
            cl = superclass
            _log_attrs().length > 0 || (cl && cl.include?(LogArtifactState) && cl.has_log_attrs())
        end
    end

    # extend class the module included with  "logged_attrs" class method
    def self.included(clazz)
        super
        clazz.extend(LoggedAttrs)
    end

    #############################################################
    #  Common logging API part
    #############################################################
    def logs_home_dir
        hd = homedir
        raise 'Cannot detect log directory since project home is unknown' if hd.nil?
        log_hd = File.join(hd, '.lithium', '.logs')
        unless File.exists?(log_hd)
            puts_warning "LOG directory '#{log_hd}' cannot be found. Try to create it ..."
            Dir.mkdir(log_hd)
        end
        return log_hd
    end

    # check if log can be done
    def can_artifact_be_tracked?
        lith = File.join(homedir, '.lithium')
        return true if File.directory?(lith)

        puts_warning "Artifact state cannot be tracked since since '#{lith}' log directory doesn't exist"
        return false
    end

    # expire log to make the target artifact expired
    def expire_logs
        return unless can_artifact_be_tracked?

        p1 = items_log_path()
        File.delete(p1) if is_items_log_enabled? && File.exists?(p1)

        p2 = attrs_log_path()
        File.delete(p2) if is_attrs_log_enabled? && File.exists?(p2)
    end

    def logs_mtime
        return -1 unless can_artifact_be_tracked?

        p1 = items_log_path()
        p2 = attrs_log_path()
        t1 = File.exists?(p1) && is_items_log_enabled? ? File.mtime(p1).to_i : -1
        t2 = File.exists?(p2) && is_attrs_log_enabled? ? File.mtime(p2).to_i : -1
        return t1 > t2 ? t1 : t2
    end

    def logs_expired?
        return false unless can_artifact_be_tracked?

        if is_items_log_enabled?
            # if there is no items but the items are expected consider it as expired case
            return true if self.class.method_defined?(:list_items) && !File.exists?(items_log_path())

            # check items expiration
            list_expired_items { |n, t|
                return true
            }
        end

        if is_attrs_log_enabled?
            list_expired_attrs { |a, ov|
                return true
            }
        end

        return false
    end

    def update_logs
        return unless can_artifact_be_tracked?

        t = Time.now
        if is_items_log_enabled?
            update_items_log()
            path = items_log_path()
            File.utime(t, t, path) if File.exists?(path)
        end

        if is_attrs_log_enabled?
            update_attrs_log()
            path = attrs_log_path()
            File.utime(t, t, path) if File.exists?(path)
        end
    end

    #############################################################
    #  log items specific methods
    #############################################################

    # return map where key is an item path and value is integer modified time
    def load_items_log
        return unless self.class.method_defined?(:list_items)

        p, e = items_log_path(), {}
        if File.exists?(p)
            File.open(p, 'r') { |f|
                f.each { |i|
                    i = i.strip()
                    j = i.rindex(' ')
                    name, time = i[0, j], i[j + 1, i.length]
                    e[name] = time.to_i
                }
            }
        end
        e
    end

    # list target artifact items that are expired
    def list_expired_items(&block)
        return unless self.class.method_defined?(:list_items)
        e = load_items_log()

        list_items { |n, t|
            raise "Duplicated listed item '#{n}'" if e[n] == -2
            block.call(n, e[n] ? e[n] : -1) if t == -1 || e[n].nil? || e[n].to_i == -1 || e[n].to_i < t

            e[n] = -2 unless e[n].nil? # mark as passed the given item
        }

        # detect deleted items
        e.each_pair { | f, t |
            block.call(f, -2) if t != -2
        }
    end

    def update_items_log
        return unless self.class.method_defined?(:list_items)

        d, e, r = false, load_items_log(), {}
        list_items() { |n, t|
            d = true if !d && (e[n].nil? || e[n] != t)  # detect expired item
            r[n] = t  # map to refresh items log
        }

        # save log if necessary
        path = items_log_path()
        if r.length == 0    # no items means no log
            File.delete(path) if File.exists?(path)
        elsif d || r.length != e.length
            File.open(path, 'w') { |f|
                r.each_pair { |name, time|
                    f.printf("%s %i\n", name, time)
                }
            }
        end
    end

    def is_items_log_enabled?
        true
    end

    def items_log_path
        if @items_log_id.nil?
            @items_log_path ||= File.join(logs_home_dir, "#{self.class.to_s}_#{Digest::MD5.hexdigest(self.name)}")
        else
            @items_log_path ||= File.join(logs_home_dir, @items_log_id)
        end
        @items_log_path
    end

    #############################################################
    #  log attributes specific methods
    #############################################################
    def update_attrs_log
        path = attrs_log_path()
        if self.class.has_log_attrs()
            data = {}
            begin
                self.class.each_log_attrs { |a| data[a] = self.send(a) }
                File.open(path, 'w') { |f| Marshal.dump(data, f) }
            rescue
                File.delete(path)
                raise
            end
        else
            File.delete(path) if File.exists?(path)
        end
    end

    def list_expired_attrs_as_array
        res = []
        list_expired_items { | k, v |
            res.push([k, v]);
        }
        return res
    end

    def LOG_ID(id)
        @items_log_id = id
    end

    def list_expired_attrs(&block)
        # check attributes state expiration

        # collect tracked attributes
        attrs = []
        self.class.each_log_attrs { | a |
            attrs << a
        }

        if self.class.has_log_attrs()
            path = attrs_log_path()

            if File.exists?(path)
                File.open(path, 'r') { | f |
                    d = nil
                    begin
                        d = Marshal.load(f)
                    rescue
                        File.delete(path)
                        raise
                    end

                    raise "Incorrect serialized object type '#{d.class}' (Hash is expected)" if !d.kind_of?(Hash)

                    attrs.each { | a |
                        if !d.key?(a)
                            block.call(a, nil)
                        elsif self.send(a) != d[a]
                            block.call(a, d[a])
                        end
                    }

                    d.each_pair { | k, v |
                        block.call(k, nil) if !attrs.include?(k)
                    }
                }
            elsif attrs.length > 0
                attrs.each { |a|
                    block.call(a, nil)
                }
            end
        end
    end

    def is_attrs_log_enabled?
        true
    end

    def attrs_log_path
        items_log_path() + ".ser"
    end
end

# Option support
module OptionsSupport
    @@NAMED_OPT = /^(\-{0,2})([^=]+)=?([^=]*)?/
    #@@NAMED_OPT = /^(\-{0,2})([^ ]+)\s?([^- ]*)?/

    def OPTS(*args)
        @_options = _options()
        if args.length > 0
            @_options = []
            @_options.push(*args)
        end
        _options().dup
    end

    def OPT(opt)
        _options().push(opt)
    end

    def OPT?(op)
        _options().include?(op) || !self[op].nil?
    end

    def OPTS?
        _options().length > 0
    end

    def []=(n, v = nil)
        raise 'Option name cannot be nil or empty' if n.nil? || n.strip() == ''
        opt   = n.strip()
        opt  += "=#{v.strip}" unless v.nil?
        opts  = _options()

        i = opts.index { | o |
            m = @@NAMED_OPT.match(o)
            !m.nil? && (n == m[2] || n == '-' + m[2] || n == '--' + m[2])
        }

        if i.nil?
            opts.push(opt)
        else
            if opt[0] != '-'
                m = /^(\-{0,2})/.match(opts[i])
                opt = m[1] + opt unless m.nil?
            end
            opts[i] = opt
        end
    end

    def [](n)
        _options().each { | o |
            m = @@NAMED_OPT.match(o)
            return m[3] if !m.nil? && (m[2] == n || '-' + m[2] == n || '--' + m[2] == n)
        }
        return nil
    end

    # return valid not nil attribute value in a case of making it loggable.
    # Otherwise 'option' attribute can equal [] after building (since OPTS)
    # method has been called, but be nil before an artifact building
    def _options
        @_options ||= []
        return @_options
    end
end

#   Artifact name keeps order of artifact following the rules below:
#     1) aliased artifact precede not aliased artifact and sorted alphabetically
#     2) the same aliased artifact with path specified sorted by this path
#     3) path artifacts are sorted from particular case to common
#
#   For example:
#
#   [ "aa:test/", "aa:test/*", "aa:test/**/*", "aa:", "bb:", "compile:test/test/a",
#     "compile:test/**/*", "compile:", "test/com", "test/com/**" ]
class ArtifactName < String
    attr_reader :prefix, :suffix, :path, :path_mask, :mask_type, :clazz, :block

    # return artifact name as is if it is passed as an instance of artifact name
    def self.new(name, clazz = nil, &block)
        if name.kind_of?(ArtifactName)
            raise "ArtifactName('#{name}') instance has to be passed as a single argument of constructor" unless clazz.nil?
            raise "Block cannot be customized for existent ArtifactName('#{name}') class instance"        unless block.nil?
            return name
        else
            super(name, clazz, &block)
        end
    end

    def self.from_class(clazz)

    end

    # Construct artifact name.
    # @param name?  - name of the artifact, name can contain class prefix e.g "ArtifactClass:name"
    # @param clazz? - artifact class
    #
    # ArtifactName(
    #    name  : { String }
    # )
    #
    # ArtifactName(
    #    clazz : { Class < Artifact }
    # )
    #
    # ArtifactName(
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


        name = ArtifactName.assert_notnil_name(name)

        @mask_type = File::FNM_DOTMATCH
        @prefix = name[/^\w\w+\:/]
        @suffix = @prefix.nil? ? name : name[@prefix.length .. name.length]
        @suffix = nil if !@suffix.nil? && @suffix.length == 0

        @path = @path_mask = nil
        @path = @suffix[/((?<![a-zA-Z])[a-zA-Z]:)?[^:]+$/] unless @suffix.nil?
        unless @path.nil?
            @path, @path_mask = FileArtifact.cut_fmask(@path)
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
    # @param name { String, Symbol, Class, ArtifactName } name of artifact
    # @return ArtifactName
    def self.relative_to(name, to)
        artname = ArtifactName.new(name)
        unless artname.path.nil?
            path    = FileArtifact.relative_to(artname.path, to)
            artname = ArtifactName.new(ArtifactName.name_from(artname.prefix, path, artname.path_mask)) unless path.nil?
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
        name = ArtifactName.new(name)

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
        @block = Artifact.combine_blocks(@block, b)
        return self
    end

    def _block(b)
        @block = b
        return self
    end
end

module SelfRegisteredArtifact
    @arts_classes = []

    def self.included(clazz)
        unless @arts_classes.index(clazz).nil?
            puts_warning "Artifact '#{clazz}' has been already registered"
        else
            @arts_classes.push(clazz)
        end
    end

    def self.artifact_classes()
        @arts_classes
    end
end

# Core artifact abstraction.
#  "@name" - name of artifact
class Artifact
    attr_reader :name, :owner, :createdByMeta, :built, :expired, :caller, :requires

    # the particular class static variables
    @default_name  = nil
    @default_block = nil
    @auto_registered_arts = []

    # set or get default artifact name
    def self.default_name(*args)
        @default_name = args[0] if args.length > 0
        @default_name
    end

    def self.default_block(&block)
        @default_block = block unless block.nil?
        @default_block
    end

    def self.SELF_REGISTERED
        unless @auto_registered_arts.index(self.class).nil?
            puts_warning "Artifact '#{self.class}' has been already registered"
        else
            @auto_registered_arts.push(self.class)
        end
    end

    # !!! this method cares about owner and default name setup, otherwise
    # !!! owner and default name initialization depends on when an artifact
    # !!! instance call super
    def self.new(name, owner:nil, &block)
        raise "Invalid name" if name.nil?

        name = self.default_name if name.nil?
        unless owner.nil? || owner.kind_of?(ArtifactContainer)
            raise "Invalid owner '#{owner.class}' type for '#{name}' artifact, an artifact container class instance is expected"
        end

        instance = allocate()
        instance.owner = owner

        begin
            instance.initialize_called = true
            instance.send(:initialize, name, &block)
        ensure
            instance.initialize_called = false
        end
        return instance
    end

    def initialize(name = nil, &block)
        # test if the name of the artifact is not nil or empty string
        name = ArtifactName.assert_notnil_name(name)
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

    # prevent error generation for a number of optional artifact methods
    # that are called by lithium engine:
    #  - built
    #  - build_failed
    #  - before_build
    #
    def method_missing(meth, *args, &block)
        # detect if there is an artifact class exits with the given name to treat it as
        # required artifact. It is done only if we are still in "requires" method call
        if meth.length > 2 && @caller == :require
            # TODO: revised, most likely the code is not required since REQUIRE can be executed outside of constructor
            raise "REQUIRED artifacts can be defined only in '#{self}' artifact constructor" unless initialize_called?

            name = args.length == 0 ? nil : args[0]
            clazz, is_internal = Artifact._name_to_clazz(meth)
            if is_internal
                raise "Block was not defined for updating '#{clazz}:#{name}' requirement" if block.nil?
                @requires ||= []
                art_name = ArtifactName.new(name, clazz)
                idx      = @requires.index { | a | a.is_a?(ArtifactName) && art_name.to_s == a.to_s }
                raise "Required '#{clazz}' artifact cannot be detected" if idx.nil?
                @requires[idx].combine_block(block)
            else
                REQUIRE(name, clazz, &block)
            end
        # TODO: revise the code
        elsif meth.length > 2 && @caller == :built
            name = args.length == 0 ? nil : args[0]
            clazz, is_internal = Artifact._name_to_clazz(meth)
            tree = ArtifactTree.new(clazz.new(name, owner:self.owner.is_a?(ArtifactContainer) ? self : self.owner, &block))
            tree.build
        else
            super(meth, *args, &block)
        end
    end

    def each_required
        @requires ||= []
        req = @requires

        # artifacts have to be unique by its names
        req = req.reverse.uniq { | name | name.is_a?(Artifact) ? name.name : name.to_s }.reverse
        req.each { | dep |
            yield dep
        }
    end

    def before_build(is_expired)
    end

    def build
    end

    def built
        prev = @caller
        begin
            @caller = :built
            self.instance_exec(&@built) unless @built.nil?
        ensure
            @caller = prev
        end
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
                self.instance_exec &block
            ensure
                @caller = prev
            end
        else
            add_reqiured(name, clazz, &block)
        end
    end

    def DISMISS(name, clazz = nil)
        raise 'Passed dismiss artifact name is nil' if name.nil?
        @requires ||= []
        ln = @requires.length
        name = ArtifactName.new(name, clazz).to_s
        @requires.delete_if { | req | req.is_a?(ArtifactName) && req.to_s == name }
        raise "'#{name}' DEPENDENCY cannot be found and dismissed" if ln == @requires.length
    end

    # called after the artifact has been built
    def BUILT(&block)
        @built = block
    end

    def add_reqiured(name = nil, clazz = nil, &block)
        @requires ||= []
        if name.is_a?(Artifact)
            raise "Artifact instance '#{name}' cannot be used as an requirements"
        else
            art_name = ArtifactName.new(name, clazz, &block)
            i = @requires.index { | req | req.is_a?(ArtifactName) && req.to_s == art_name.to_s && req.clazz == art_name.clazz }
            if i.nil?
                @requires.push(art_name)
            else
                puts_warning "Artifact '#{art_name}' requirement has been already defined"
                @requires[i] =  art_name
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

    def self.abbr()
        return @abbr unless @abbr.nil?
        return "%3s" % self.name[0..2].upcase
    end

    # *args - command arguments
    # block - call back to catch output
    def self.exec(*args, &block)
        # clone arguments
        args = args.dup

        # use quotas to surround process if necessary
        args[0] = "\"#{args[0]}\"" if !args[0].index(' ').nil? && args[0][0] != "\""

        # merged stderr and stdout
        Open3.popen2e(args.join(' ')) { | stdin, stdout, thread |
            stdout.set_encoding(Encoding::UTF_8)
            if  block.nil?
                # close stdin
                stdin.close

                while line = stdout.gets do
                    $stdout.puts line
                end
            else
                block.call(stdin, stdout, thread)
            end
            return thread.value
        }
    end

    def self.grep_exec(*args, pattern:nil)
        self.exec(*args) { | stdin, stdout, thread |
            while line = stdout.gets do
                m = pattern.match(line.chomp)
                if m
                    stdout.close
                    if m.length > 1
                        return m[1..]
                    elsif m.length == 1
                        return m[1]
                    else
                        return m[0]
                    end

                end
            end
        }
        return nil
    end

    def self.execInTerm(hd, cmd)
        pl = Gem::Platform.local.os
        if  pl == 'darwin'
            `osascript -e 'tell app "Terminal"
                activate
                do script "cd #{hd}; #{cmd}"
            end tell'`
        else
            raise "Terminal execution is not supported for '#{pl}' platform"
        end
    end

    def self.combine_blocks(block1, block2)
        return block2 if block1.nil?
        return block1 if block2.nil?
        return Proc.new {
            self.instance_exec &block1
            self.instance_exec &block2
        }
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

        @children, @parent, @expired, @expired_by_kid = [], parent, nil, nil

        # If parent is nil then the given tree node is considered as root node.
        # The root node initiate building tree
        build_tree() if parent.nil?
    end

    # build tree starting from the root artifact (identified by @name)
    def build_tree(map = [])
        bt = @art.mtime

        @art.each_required { | name |
            foundNode, node = nil, ArtifactTree.new(name, self)

            # existent of a custom block makes the artifact specific even if an artifact with identical object id is already in build tree
            if name.is_a?(ArtifactName) && name.block.nil?
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
            node.art.assign_me_to(@art) if node.art.is_a?(AssignableDependency)

            # most likely the expired state has to be set here, after assignable dependencies are set
            # since @art.expired? method can require the assigned deps to define its expiration state
            # moreover @art.expired? should not be called here since we can have multiple assignable
            # deps
            if @expired_by_kid.nil? && (node.expired || (bt > 0 && node.art.mtime() > bt))
                @expired = true
                @expired_by_kid = node.art
            end
        }

        # check if expired attribute has not been set (if there ware no deps
        # that expired the given art)
        @expired = @art.expired? if @expired.nil?
        return self
    end

    def build(&block)
        unless @expired
            @art.before_build(false)
            puts_warning "'#{@art.name}' : #{@art.class} is not expired"
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
end

#  Base file artifact
class FileArtifact < Artifact
    @abbr = 'FAR'

    attr_reader :is_absolute

    def initialize(name, &block)
        path = Pathname.new(name).cleanpath
        @is_absolute  = path.absolute?
        super(path.to_s, &block)
    end

    def absolute?
        @is_absolute
    end

    def homedir
        if @is_absolute
            unless owner.nil?
                home = owner.homedir
                if File.absolute_path?(home)
                    home = home[0, home.length - 1] if home.length > 1 && home[home.length - 1] == '/'
                    return home #if FileArtifact.path_start_with?(@name, home)
                end
            end

            return File.dirname(@name)
        else
            return super
        end
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

    # return path that is relative to the artifact homedir
    def relative_to_home
        FileArtifact.relative_to(@name, homedir)
    end

    def q_fullpath(path = @name)
        p = fullpath(path)
        return "\"#{p}\"" unless p.nil?
        return p
    end

    def fullpath(path = @name)
        # TODO: have no idea if the commented code will have a side effect !
        return path if path.start_with?('.env/')

        if path == '.' || path == './'
            return Pathname.new(File.join(Dir.pwd, path)).cleanpath.to_s
        elsif path == @name
            return path if @is_absolute
            return res = Pathname.new(File.join(homedir, path)).cleanpath.to_s
        else
            path = Pathname.new(path).cleanpath
            home = homedir

            if path.absolute?
                path = path.to_s
                home = home[0, home.length - 1] if home.length > 1 && home[home.length - 1] == '/'
                raise "Path '#{path}' is not relative to '#{home}' home" unless FileArtifact.path_start_with?(path, home)
                return path
            else
                return File.join(home, path.to_s)
            end
        end
    end

    # test if the given path is in a context of the given file artifact
    def match(path)
        raise 'Invalid empty or nil path' if path.nil? || path.length == 0

        # current directory always match
        # TODO: most likely the commented code below is incorrect
        #return true if path == '.'

        pp = path.dup
        path, mask = FileArtifact.cut_fmask(path)
        raise "Path '#{pp}' includes mask only" if path.nil?

        path  = Pathname.new(path).cleanpath
        home  = Pathname.new(homedir)
        raise "Home '#{home}' is not an absolute path" if path.absolute? && !home.absolute?

        # any relative path is considered as a not matched path
        return false if !path.absolute? && home.absolute?
        return FileArtifact.path_start_with?(path.to_s, home.to_s)
    end

    def mtime
        f = fullpath()
        return File.exists?(f) ? File.mtime(f).to_i : -1
    end

    def puts_items
        list_items { | p, t |
            puts "logged item = '#{p}' : #{t}"
        }
    end

    def list_items(rel = nil)
        fp = fullpath
        if File.exists?(fp)
            yield fp, File.mtime(fp).to_i
        else
            yield fp, -1
        end
    end

    def list_items_to_array(rel = nil)
        list = []
        list_items(rel) { | path, m |
            list << path
        }
        return list
    end

    def search(path)
        FileArtifact.search(path, self)
    end

    def assert_dirs(*args)
        self.class.assert_dirs(*args)
    end

    def assert_files(*args)
        self.class.assert_files(*args)
    end

    def self.path_start_with?(path, to)
        to   = to[0..-2]   if to[-1]   == '/'
        path = path[0..-2] if path[-1] == '/'

        return true  if to == path
        return false if to.length == path.length
        i = path.index(to)
        return false if i.nil? || i != 0
        return path[to.length] == '/'
    end

    #  path = [base]/...
    def self.relative_to(path, to)
        path, mask = self.cut_fmask(path)
        path  = Pathname.new(path).cleanpath
        to    = Pathname.new(to)
        return nil if (path.absolute? && !to.absolute?) || (!path.absolute? && to.absolute?) || !path_start_with?(path.to_s, to.to_s)
        return path.relative_path_from(to).to_s
    end

    def self.fmask?(path)
        not path.index(/[\[\]\?\*\{\}]/).nil?
    end

    def self.cut_fmask(path)
        mi = path.index(/[\[\]\?\*\{\}]/) # test if the path contains mask

        # cut mask part if it has been detected in the path
        mask = nil
        unless mi.nil?
            path = path.dup
            mask = path[mi, path.length]
            path = path[0, mi]
            path = nil if path.length == 0
        end

        return path, mask
    end

    def self.which(cmd)
        exts = ENV['PATHEXT'] ? ENV['PATHEXT'].split(';') : ['']
        ENV['PATH'].split(File::PATH_SEPARATOR).each do | path |
            path = path.sub('\\', '/') if File::PATH_SEPARATOR == ';'
            exts.each { | ext |
                exe = File.join(path, "#{cmd}#{ext}")

                # checking file is mandatory, since for example folder
                # '/Users/brigadir/projects/.lithium/lib/lithium' is
                # executable because 'lithium' script exists
                return exe if File.executable?(exe) && File.file?(exe)
            }
        end
        return nil
    end

    def self.cpfile(src, dest)
        self.testdir(dest)
        raise "Source '#{src}' file is a directory or doesn't exist" unless File.file?(src)
        raise "Destination '#{dest}' cannot be file" if File.file?(dest)
        FileUtils.mkdir_p(dest) unless File.exists?(dest)
        FileUtils.cp(src, dest)
    end

    def self.cpdir(src, dest, em = nil)
        self.testdir(src) && self.testdir(dest)

        Dir.foreach(src) { |path|
            next if path == '.' || path == '..' || (em && (path =~ em) != nil)
            dpath, spath = dest/path, src/path

            if File.directory?(spath)
                Dir.mkdir(dpath)
                cpdir(spath, dpath, em)
            else
                File.cp(spath, dpath)
            end
        }
    end

    def self.assert_dirs(*args)
        path = File.join(*args)
        raise "Expected directory '#{path}' doesn't exist or points to a file" unless File.directory?(path)
        return path
    end

    def self.assert_files(*args)
        path = File.join(*args)
        raise "Expected file '#{path}' doesn't exist or points to a directory" unless File.file?(path)
        return path
    end

    def self.testdir(dir)
        raise 'Directory cannot be nil' if dir.nil?
    end

    def self.look_directory_up(path, fname, top_path = nil)
        self.look_path_up(path, fname, top_path) { | nm | File.directory?(nm) }
    end

    def self.look_file_up(path, fname, top_path = nil)
        self.look_path_up(path, fname, top_path) { | nm | !File.directory?(nm) }
    end

    def self.look_path_up(path, fname, top_path = nil, &block)
        path      = File.expand_path(path)
        top_path  = File.expand_path(top_path) unless top_path.nil?
        prev_path = nil

        #raise "Path '#{path}' doesn't exist" unless File.exists?(path)
        #raise "Path '#{path}' has to be a directory" unless File.directory?(path)

        while path && prev_path != path && (top_path.nil? || prev_path != top_path)
            marker = File.join(path, fname)
            return marker if File.exists?(marker) && (block.nil? || block.call(marker))
            prev_path = path
            path      = File.dirname(path)
            break if path == '.'  # dirname can return "." if there is no available top directory
        end

        return nil
    end

    # track not found items
    @search_cache = {}

    # search the given path
    def self.search(path, art = $current_artifact, &block)
        if File.exists?(path)
            return [ File.expand_path(path) ] if block.nil?
            return block.call(path)
        end

        art = Project.current if art.nil? || !art.kind_of?(FileArtifact)
        if art.nil?
            return [] if block.nil?
            return
        end

        # test if current artifact points to path we are searching
        fp = art.fullpath
        if fp.end_with?(path)
            return  [ fp ] if block.nil?
            return block.call(fp)
        else
            hd  = $current_artifact.homedir
            hfp = File.join(hd, path)
            if File.exists?(hfp)
                return  [ hfp ] if block.nil?
                return block.call(hfp)
            end
        end

        fp = File.dirname(fp) unless File.directory?(fp)
        if File.exists?(fp)
            path = Pathname.new(path).cleanpath.to_s
            if @search_cache[fp] && @search_cache[fp][path]
                return [] if block.nil?
                return
            end

            res = Dir.glob(File.join(fp, '**', path))
            if res.length > 0
                return res if block.nil?
                res.each { | found_item |
                    block.call(found_item)
                }
            end

            @search_cache[fp] = {} unless @search_cache[fp]
            @search_cache[fp][path] = true
        end

        return art.kind_of?(Project) ? [] : FileArtifact.search(path, art.project, &block)
    end

    # TODO: grep and grep_file a bit weird names
    def self.grep_file(path, pattern, match_all = false, &block)
        raise 'Pattern cannot be nil' if pattern.nil?
        pattern = Regexp.new(pattern) if pattern.kind_of?(String)

        raise "File '#{path}' is a directory or doesn't exist" unless File.file?(path)

        list = []
        line_num = 0

        File.readlines(path, :encoding => 'UTF-8').each { | line |
            line_num += 1
            line = line.chomp.strip
            next if line.length == 0
            mt = pattern.match(line)
            unless mt.nil?
                matched_part = mt[0]
                if mt.length > 1
                    matched_part = ''
                    for i in (1 .. mt.length - 1)
                        matched_part = matched_part + mt[i]
                    end
                end

                if block.nil?
                    list.push({
                        :path         => path,
                        :line_num     => line_num,
                        :line         => line,
                        :matched_part => matched_part
                    })
                else
                    block.call(path, line_num, line, matched_part)
                end

                break unless match_all
            end
        }

        return block.nil? ? list : nil
    end

    def self.grep(path, pattern, match_all = false, &block)
        raise 'Pattern cannot be nil' if pattern.nil?
        pattern = Regexp.new(pattern) if pattern.kind_of?(String)

        pp, mask = FileArtifact.cut_fmask(path)
        raise "File '#{path}' cannot be found" if !File.exists?(path) && mask.nil?

        list = []
        if File.directory?(path) || mask
            FileArtifact.dir(path, true) { | item |
                res = FileArtifact.grep_file(item, pattern, match_all, &block)
                list.concat(res) unless res.nil?
            }
        else
            list = FileArtifact.grep_file(path, pattern, match_all, &block)
        end

        return block.nil? ? list : nil
    end

    def self.dir(path, ignore_dirs = true, &block)
        raise 'Path cannot be nil'            if path.nil?

        pp, mask = FileArtifact.cut_fmask(path)
        raise "Path '#{path}' points to file" if File.file?(path)
        raise "Path '#{path}' doesn't exist"  if !File.exists?(path) && mask.nil?

        list = []
        Dir[path].each { | item |
            next if ignore_dirs && File.directory?(item)
            if block.nil?
                list.push(item)
            else
                block.call(item)
            end
        }

        return block.nil? ? list : nil
    end

    def self.tmpfile(data = nil, &block)
        raise 'Unknown passed block' if block.nil?

        tmp_file = Tempfile.new('tmp_file')
        begin
            unless data.nil?
                if data.kind_of?(String)
                    tmp_file.puts(data)
                elsif data.kind_of?(Array)
                    data.each { | line |
                        tmp_file.puts(line)
                    }
                else
                    tmp_file.puts(data.to_s)
                end
                tmp_file.close()
            end

            block.call(tmp_file)
        ensure
            tmp_file.close()
            tmp_file.unlink()
        end
    end

    def self.exists?(path, ignore_dirs = true)
        pp, mask = FileArtifact.cut_fmask(path)
        raise "File '#{path}' cannot be found" if !File.exists?(path) && mask.nil?

        if File.directory?(path) || mask
            FileArtifact.dir(path, ignore_dirs) { | item |
                return true
            }
        else
            return File.exists?(path)
        end
    end
end

# Permanent file shortcut
class ExistentFile < FileArtifact
    def initialize(name)
        super
        assert_existence()
    end

    def build
        assert_existence()
    end

    def mtime
        assert_existence()
        return super()
    end

    def list_items(rel = nil)
        assert_existence()
        super
    end

    def assert_existence
        fp = fullpath()
        raise "File '#{fp}' doesn't exist" unless File.exists?(fp)
    end
end

# Directory artifact
class Directory < FileArtifact
    def expired?
        !File.directory?(fullpath)
    end

    def build
        super
        fp = fullpath
        raise "File '#{fp}' is not a directory" if File.file?(fp)
    end

    def mkdir
        FileUtils.mkdir_p(fullpath) unless File.exists?(fullpath)
    end

    # return itself as a single item
    def list_items
        go_to_homedir()
        Dir[@name].each { | path |
            mt = File.mtime(path).to_i
            yield path, mt
        }
    end
end

# Directory content artifact
class DirectoryContent < Directory
    include LogArtifactState

    def build()
        super
        fp = fullpath
        raise "File '#{fp}' is not a directory" if File.file?(fp)
    end

    # return itself as a single item
    def list_items
        go_to_homedir()
        Dir[File.join(@name, '*')].each { | path |
            mt = File.mtime(path).to_i
            yield path, mt
        }
    end
end

class ExistentDirectory < FileArtifact
    def build()
        super
        fp = fullpath
        raise "File '#{fp}' is not a directory or doesn't exist" unless File.directory?(fp)
    end
end

# File mask artifact that can identify set of file artifacts
class FileMask < FileArtifact
    @abbr = 'FMS'

    def initialize(name, &block)
        super
        @regexp_filter ||= nil
        @ignore_dirs   ||= false
        @ignore_files  ||= false
        raise 'Files and directories are ignored at the same time' if @ignore_files && @ignore_dirs
    end

    def build
        list_items { | p, mt |
            build_item(p, mt)
        }
    end

    def ignore_hidden
        @regexp_filter = /^[\.].*/
    end

    # called for every detected item as a part of build process
    def build_item(path, m) end

    # List items basing on the mask returns items relatively to the
    # passed path
    def list_items(rel = nil)
        go_to_homedir

        Dir[@name].each { | path |
            next if @regexp_filter && !(path =~ @regexp_filter)

            if @ignore_files || @ignore_dirs
                b = File.directory?(path)
                next if (@ignore_files && !b) || (@ignore_dirs && b)
            end

            mt = File.mtime(path).to_i
            unless rel.nil?
                path = FileArtifact.relative_to(rel)
                "Relative path '#{rel}' cannot be applied to '#{path}'" if path.nil?
            end

            yield path, mt
        }
    end
end

#
#   <WITH>  <OPTS>  <TARGETS>  <ARGS>
#     |       |        |          |
#     |       |        |          +--- test
#     |       |        |   +--- [ file_list ]
#     |       |        +---|
#     |       |            +--- path_to_tmp_file (contains files to be processed)
#     |       |
#     |       +--- e.g -cp classes:lib
#     |
#     +--- e.g java
#
class RunTool < FileMask
    include LogArtifactState
    include OptionsSupport

    log_attr :_options, :arguments

    def initialize(name)
        @targets_from_file
        super

        @arguments ||= []
        @arguments = $lithium_args.dup if @arguments.length == 0 && $lithium_args.length > 0
    end

    # ec - Process::Status
    def error_exit_code?(ec)
        ec.exitstatus != 0
    end

    # can be overridden to transform paths,
    # e.g. convert path to JAVA file to a class name
    def transform_target_path(path)
        path
    end

    def WITH
        raise 'Run tool name is not defined'
    end

    # @return Array
    def WITH_OPTS
        OPTS()
    end

    # @param src - array of [ path1, path2, ... pathN ] or path to file
    # @return array
    def WITH_TARGETS(src)
        return [] if src.nil?
        return src.is_a?(String) ? [ "\"#{src}\"" ] : src
    end

    def run_with_output_handler
        @output_handler
    end

    def build(&block)
        super

        begin
            tmp, src, len = nil, [], 0
            if @targets_from_file
                tmp = Tempfile.open('lithium')
                begin
                    list_items { | path, t |
                        tmp.puts(transform_target_path(path))
                        len = len + 1
                    }
                ensure
                   tmp.close
                end
                src = tmp.path
            else
                list_items{ | path, t |
                    src.push("\"#{transform_target_path(path)}\"")
                }
                len = src.length
            end

            puts_warning "Source files cannot be detected by '#{@name}'" if src.nil?

            cmd = [ WITH() ] + WITH_OPTS() + WITH_TARGETS(src) + @arguments

            go_to_homedir()
            ec = block.nil? ? Artifact.exec(*cmd) : Artifact.exec(*cmd, &block)

            if error_exit_code?(ec)
                # TODO: simplify detailed level fetching
                level = !$lithium_options.nil? && $lithium_options.key?('v') ? $lithium_options['v'].to_i : 0
                raise "'#{self.class}' has failed cmd = '#{cmd}'" if level == 2
                raise "'#{self.class}' has failed"
            end
            puts "#{len} source files have been processed with '#{self.class}'"
        ensure
            tmp.unlink unless tmp.nil?
        end
    end
end

class RunShell < RunTool
    def WITH
        'bash'
    end
end

module ArtifactContainer
    # Create and return artifact identified by the given name.
    #  @param name: { String, Symbol, ArtifactName, Class }
    #  @return Artifact
    def artifact(name, clazz = nil, &block)
        artname = ArtifactName.new(name, clazz)

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
        art = _artifact_by_meta(artname, meta, &block) if art.nil?
        art = _cache_artifact(artname, art)            if block.nil? # cache only if a custom block has been passed

        # if the artifact is a container handling of target (suffix) is delegated to the container
        return art.is_a?(ArtifactContainer) ? art.artifact(artname.suffix) : art
    end

    # cache artifact only if it is not identified by a mask or is an artifact container
    def _cache_artifact(artname, art)
        raise "Invalid '#{artname.class}' parameter type, ArtifactName instance is expected" unless artname.kind_of?(ArtifactName)
        if artname.path_mask.nil? || art.kind_of?(ArtifactContainer)
            _artifacts_cache[artname] = art
        end
        return art
    end

    # fetch an artifact from cache
    def _artifact_from_cache(artname)
        raise "Invalid '#{artname.class}' parameter type, ArtifactName instance is expected" unless artname.kind_of?(ArtifactName)
        unless _artifacts_cache[artname].nil?
            return _artifacts_cache[artname]
        else
            return nil
        end
    end

    # { art_name:ArtifactName => instance : Artifact ...}
    def _artifacts_cache
        @artifacts = {} unless defined? @artifacts
        @artifacts
    end

    def _remove_from_cache(name, clazz = nil)
        name = ArtifactName.new(name, clazz)
        _artifacts_cache.delete(name) unless _artifacts_cache[name].nil?
    end

    # instantiate the given artifact by its meta
    def _artifact_by_meta(artname, meta, &block)
        raise "Invalid '#{artname.class}' parameter type, ArtifactName instance is expected" unless artname.kind_of?(ArtifactName)
        clazz = meta.clazz

        art = clazz.new(artname.suffix, owner:self,
            &(block.nil? && clazz.default_block.nil? ? meta.block : Proc.new {
                self.instance_exec &clazz.default_block unless clazz.default_block.nil?
                self.instance_exec &meta.block unless meta.block.nil?
                self.instance_exec &block unless block.nil?
            })
        )

        art.createdByMeta = meta
        return art
    end

    # meta hosts ArtifactName instances
    def _meta
        @meta = [] unless defined? @meta
        return @meta
    end

    # Find appropriate for the given artifact name a registered meta
    # @param name: { String, Symbol, Class, ArtifactName } artifact name
    # @param recursive: { boolean } flag that says if meta has to be search over
    # the all parent hierarchy starting from "from" container
    #
    # @return (ArtifactName, ArtifactContainer)
    def match_meta(name, recursive = false)
        art_name = ArtifactName.relative_to(name, homedir)
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
    #   name : { String, ArtifactName }
    # )
    #
    def DEFINE(name, clazz = nil, &block)
        artname = ArtifactName.new(name, clazz, &block)
        raise "Unknown class for '#{artname}' artifact" if artname.clazz.nil?

        # delete artifact meta if it already exists
        old_meta, old_meta_ow = match_meta(artname)
        old_meta_ow._meta.delete(old_meta) unless old_meta.nil?

        _meta.push(artname)
         # sort meta array
        _meta.sort!
    end

    def MATCH(file_mask, &block)
        raise "Block is expected for MATCH '#{file_mask}'" if block.nil?
        DEFINE(file_mask, FileMaskContainer, &block)
    end

    def OTHERWISE(&block)
        DEFINE('**/*', OTHERWISE, &block)
    end

    def method_missing(meth, *args, &block)
        # TODO: review this code
        if meth.length > 2 && @caller != :require && @caller != :built
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
        name  = ArtifactName.new(name, clazz)

        # find meta currently defined in the given container
        meta, meta_ow = match_meta(name, true)
        raise "Cannot find '#{name}' definition in containers hierarchy" if meta.nil?

        meta_ow._remove_from_cache(name)
        meta_ow._meta.delete(meta)
        meta_ow._meta.sort!

        _meta.push(meta.dup._block(Artifact.combine_blocks(meta.block, block)))
        _meta.sort!
    end

    # TODO: the method doesn't work for predefined artifacts
    # TODO: the method doesn't match the passed name against meta, instead meta is matched against the name.
    # That means  name = "cmd:*" doesn't match meta = "cme:*.java".
    def REMOVE(name)
        artname = ArtifactName.new(name)
        meta, meta_ow = match_meta(name, true)
        raise "Cannot find '#{artname}' definition in containers hierarchy" if meta.nil?
        raise "Artifact '#{artname}' definition cannot be detected in an owner container" if meta_ow._meta.delete(meta).nil?
        meta_ow._meta.sort!
    end

    # define a default block that will be applied to all instances of the given class
    # TODO: check if the method is needed
    def _(clazz, &block)
        clazz.default_block(&block)
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

# mask container
class FileMaskContainer < FileMask
    include ArtifactContainer

    def initialize(name, &block)
        super

        # sort artifacts that have been created with passed block
        _meta.sort!
    end

    def delegate_to_owner_if_meta_cannot_be_found?
        true
    end
end

# project artifact
class Project < ExistentDirectory
    attr_reader :desc

    include ArtifactContainer

    @@curent_project = nil

    def initialize(name, &block)
        super
        @desc ||= File.basename(name)
        LOAD('project.rb')
    end

    def self.new(name, owner:nil, &block)
        @@curent_project = super
        return @@curent_project
    end

    def self.current=(prj)
        @@curent_project = prj
    end

    def self.current
        @@curent_project
    end

    def self.artifact(name, clazz = nil, &block)
        self.current.artifact(name, clazz, &block)
    end

    def self.PROJECT(&block)
        raise "Current project is not known" if self.current.nil?
        self.current.instance_exec &block
    end

    def artifact(name, clazz = nil, &block)
        art_name = ArtifactName.new(name, clazz)
        # detect if the path point to project itself
        return self if (art_name.clazz.nil? || art_name.clazz == self.class) && art_name.to_s == @name
        super
    end

    def PROFILE(name)
        LOAD(File.join($lithium_code, 'profiles', name + '.rb'))
    end

    def LOAD(path)
        path = File.join(homedir, '.lithium', path) unless File.absolute_path?(path)
        unless File.file?(path)
            puts_warning "Project configuration '#{path}' doesn't exist for '#{self}' artifact"
        else
            self.instance_eval(File.read(path)).call
        end
    end

    def homedir
        @is_absolute ? @name : super
    end

    def what_it_does
        nil
    end

    def expired?
        true
    end
end

# an artifact has to include the module to be assigned to an attribute of an artifact
# that requires the AssignableDependency artifact
module AssignableDependency
    #  an attribute name the dependency artifact has to be assigned
    #  @return [attribute_name, is_array]
    def assign_me_as
        [ self.class.name.downcase, false ]
    end

    def assign_me_to(target)
        raise "Target is nil and cannot be assigned with a value provided by #{self.class}:#{self.name}" if target.nil?
        raise "Nil assignable property name for #{self.class}:#{self.name}"                              if assign_me_as.nil?

        attr_name, is_array = assign_me_as()
        attr_name, is_array = target.assign_req_as(self) if target.respond_to?(:assign_req_as)

        new_value = self
        attr_name = "@#{attr_name}"
        cur_value = target.instance_variable_get(attr_name)
        if is_array
            cur_value = [] if cur_value.nil?
            target.instance_variable_set(attr_name, cur_value.push(new_value)) if cur_value.index(new_value).nil?
        else
            target.instance_variable_set(attr_name, new_value)
        end

        assignable = target.instance_variable_get('@_assignable')
        assignable ||= []
        target.instance_variable_set('@_assignable', assignable.push([attr_name, is_array]).uniq)
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

# The base class to support classpath / path like artifact
module PATHS
    class CombinedPath
        include PATHS

        def initialize(hd = nil)
            @homedir = hd
        end

        def homedir
            @homedir
        end
    end

    def self.new(dir = nil)
        CombinedPath.new(dir)
    end

    def path_valid?
        @is_path_valid ||= false
        return @is_path_valid
    end

    def INCLUDE?(path)
        matched_path(path) >= 0
    end

    def FILTER(fpath)
        @paths ||= []
        if @paths.length > 0
            @paths = @paths.filter { | path |
                match_two_paths(fpath, path) == false
            }
        end
    end

    def matched_path(path)
        paths().each_index { | index |
            path_item = paths[index]
            return index if match_two_paths(path, path_item)
        }

        return -1
    end

    def match_two_paths(path, path_item)
        is_file  = false
        bd       = homedir
        has_mask = FileArtifact.fmask?(path)

        unless has_mask
            path = File.join(bd, path) unless bd.nil? || File.absolute_path?(path)
            if path[-1] == '/'
                path = path[0..-2]
            elsif File.file?(path)
                is_file = true
                path = File.basename(path)
            end
        end

        if has_mask
            return true if File.fnmatch?(path, path_item)
        else
            path_item = File.basename(path_item) if is_file && File.file?(path_item)
            return true if path_item == path
        end

        return false
    end

    # add path item
    def JOIN(*parts)
        @paths ||= []

        return JOIN(*(parts[0])) if parts.length == 1 && parts[0].kind_of?(Array)

        parts.each { | path |
            if path.kind_of?(PATHS)
                @paths.concat(path.paths())
            elsif path.kind_of?(String)
                hd = homedir
                path.split(File::PATH_SEPARATOR).each { | path_item |
                    path_item = File.join(hd, path_item) unless hd.nil? || File.absolute_path?(path_item)

                    pp, mask = FileArtifact.cut_fmask(path_item)
                    unless mask.nil?
                        @paths.concat(FileArtifact.dir(path_item))
                        @paths.push(pp)
                    else
                        @paths.push(path_item)
                    end
                }
            else
                raise "Unknown path type '#{path.class}' cannot be joined"
            end
        }
        @is_path_valid = false if parts.length > 0
        return self
    end

    # clear path
    def CLEAR
        @paths = []
        @is_path_valid = true
        return self
    end

    def paths
        @paths ||= []
        unless path_valid?
            res   = []
            files = {}
            @paths ||= []

            @paths.each { | path |
                puts_warning "File '#{path}' doesn't exists (#{@paths.length})" unless File.exists?(path)

                path = path[0..-2] if path[-1] == '/'
                key = path
                key = File.basename(path) if File.file?(path) # check if the path is file

                if files[key].nil?
                    files[key] = path
                    res.push(path)
                else
                    path_x = files[key]
                    if path_x == path
                        puts_warning "Duplicated '#{path}' path is detected"
                    else
                        puts_warning "Duplicated file is detected:"
                        puts_warning "   ? '#{path_x}'"
                        puts_warning "   ? '#{path}'"
                    end
                end
            }

            @paths = res
            @is_path_valid = true
        end
        return @paths
    end

    def EMPTY?
        paths().length == 0
    end

    def list_items
        @paths ||= []
        @paths.each {  | p |
            yield p, 1
        }
    end

    def to_s(*args)
        if EMPTY?
            return nil if args.length == 0
            return args.join(File::PATH_SEPARATOR)
        else
            pp = paths()
            return pp.join(File::PATH_SEPARATOR) if args.length == 0
            return [].concat(pp).concat(args).join(File::PATH_SEPARATOR)
        end
    end
end

# The artifact is used to handle **/* file mask,
class OTHERWISE < FileMask
    def initialize(name, &block)
        super(name) {} # prevent passing &block to super with empty one
        raise "Block is required for '#{self.class}' artifact" if block.nil?
        @callback = block
        @ignore_dirs = true
        @build_ext_pattern = true
    end

    def build
        if @build_ext_pattern
            exts = []
            list_items { | f, m |
                ext = File.extname(f)
                exts.push(ext) if !ext.nil? && ext != '' && !exts.include?(ext)
            }

            exts.each { | ext |
                self.instance_exec("**/*#{ext}", &@callback)
            }
        else
            list_items { | f, m |
                self.instance_exec(f, &@callback)
            }
        end
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
            @sdk_home = FileArtifact.which(tool_name)
            @sdk_home = File.dirname(File.dirname(@sdk_home)) unless @sdk_home.nil?
        end

        if @sdk_home.nil? || !File.exist?(@sdk_home)
            puts_error "SDK #{self.class} home '#{@sdk_home}' cannot be found"
            puts_error 'Configure/install SDK if it is required for a project'
        else
            puts "SDK #{self.class}('#{@name}') home: '#{File.realpath(@sdk_home)}'"
        end
    end

    def what_it_does
        "Initialize #{self.class} '#{@name}' environment"
    end

    def tool_path(nm)
        File.join(@sdk_home, 'bin', nm)
    end

    def tool_name
        self.class.tool_name
    end

    def tool_version(version_opt = '--version', pattern = /([0-9]+\.[0-9]+(\.[0-9]+|_[0-9]+)?)/)
        @version = Artifact.grep_exec(tool_path(tool_name()), version_opt, pattern:pattern)
        @version = @version[0] unless @version.nil?
        @version
    end

    def self.tool_name
        @tool_name
    end
end

