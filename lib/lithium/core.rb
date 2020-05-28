require 'pathname'
require 'open3'

#  Log takes care about logged expiration state.
#
#  Log assists to calculate proper modified time. If an artifact returns
#  modified time that greater than zero it is compared to logged
#  modified time. The most recent will be return as result.
#
#  Hook module replace "clean", "build_done", "mtime",  "expired?"
#  artifact class methods with "original_<method_name>" methods.
#  It used by LogArtifact to intercept the method calls with "method_missing"
#  method.
module HookMethods
    @@hooked = [ :clean, :build_done, :mtime, :expired? ]

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
        elsif meth == :build_done
            original_build_done() if self.respond_to?(:original_build_done)
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

            # check if attribute accessor method has not been already defined with a class
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
    def logs_home_dir()
        raise 'Cannot detect log directory since project home is unknown' if !homedir()
        h = File.join(homedir, '.lithium', '.logs')
        unless File.exists?(h)
            puts_warning "LOG directory '#{h}' cannot be found. Try to create it ..."
            Dir.mkdir(h)
        end
        return h
    end

    # check if log can be done
    def can_artifact_be_tracked?()
        lith = File.join(homedir, '.lithium')
        if (!File.exists?(lith))
            puts_warning "Artifact state cannot be tracked since since '#{lith}' log directory doesn't exist"
            return false
        else
            return true
        end
    end

    # expire log to make the target artifact expired
    def expire_logs()
        return unless can_artifact_be_tracked?

        p1 = items_log_path()
        File.delete(p1) if is_items_log_enabled? && File.exists?(p1)

        p2 = attrs_log_path()
        File.delete(p2) if is_attrs_log_enabled? && File.exists?(p2)
    end

    def logs_mtime()
        return -1 unless can_artifact_be_tracked?

        p1 = items_log_path()
        p2 = attrs_log_path()
        t1 = File.exists?(p1) && is_items_log_enabled? ? File.mtime(p1).to_i : -1
        t2 = File.exists?(p2) && is_attrs_log_enabled? ? File.mtime(p2).to_i : -1
        return t1 > t2 ? t1 : t2
    end

    def logs_expired?()
        return false unless can_artifact_be_tracked?

        if is_items_log_enabled?
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

    def update_logs()
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
    def load_items_log()
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

    def update_items_log()
        return unless self.class.method_defined?(:list_items)

        d, e, r = false, load_items_log(), {}
        list_items() { |n, t|
            d = true if !d && (e[n].nil? || e[n] != t)  # detect expired item
            r[n] = t  # map to refresh items log
        }

        # save log if necessary
        path = items_log_path()
        if d || r.length != e.length
            File.open(path, 'w') { |f|
                r.each_pair { |name, time|
                    f.printf("%s %i\n", name, time)
                }
            }
        end
    end

    def is_items_log_enabled?()
        true
    end

    def items_log_path()
        if @items_log_id.nil?
            @items_log_path ||= File.join(logs_home_dir, "#{self.class.to_s}_#{self.name.tr("/\\<>:.*{}[]", '_')}")
        else
            @items_log_path ||= File.join(logs_home_dir, @items_log_id)
        end
        @items_log_path
    end

    #############################################################
    #  log attributes specific methods
    #############################################################
    def update_attrs_log()
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

    def list_expired_attrs_as_array()
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

    def is_attrs_log_enabled?()
        true
    end

    def attrs_log_path() items_log_path() + ".ser" end
end

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
class ArtifactName < String
    attr_reader :prefix, :suffix, :path, :path_mask, :mask_type, :clazz, :block

    # return artname as is if it is passed as an instance of artifact name
    def self.new(*args, &block)
        return args[0] if args.length == 1 && args[0].kind_of?(ArtifactName)
        super(*args, &block)
    end

    # 1) (name | class | Symbol)
    # 2) (name | Symbol, clazz)
    def initialize(*args, &block)
        @clazz = nil

        name = args[0]
        if args.length == 1
            if name.kind_of?(Symbol)
                name = name.to_s
            elsif name.kind_of?(Class)
                @clazz = name
                name = @clazz.default_name
                raise "Artifact default name cannot be detected by #{@clazz} class" if name.nil?
            elsif !name.kind_of?(String)
                raise "Invalid artifact name type '#{name.class}'"
            end
        elsif args.length == 2
            name = name.to_s if name.kind_of?(Symbol)
            raise "Invalid class type '#{args[1]}'" if !args[1].nil? && !args[1].kind_of?(Class)
            @clazz = args[1]
        else
            raise "Unexpected number of parameters #{args.length}, #{args}, one or two parameters are expected"
        end

        ArtifactName.nil_name(name)

        @mask_type = File::FNM_DOTMATCH
        @prefix, @path, @path_mask, @suffix = nil, nil, nil, nil
        @prefix = name[/^\w\w+\:/]
        @suffix = @prefix.nil? ? name : name[@prefix.length .. name.length]
        @suffix = nil if !@suffix.nil? && @suffix.length == 0

        @path = @suffix[/((?<![a-zA-Z])[a-zA-Z]:)?[^:]+$/] unless @suffix.nil?
        unless @path.nil?
            mask_index = @path.index(/[\[\]\?\*\{\}]/)
            unless mask_index.nil?
                @path_mask = @path[mask_index, @path.length]
                @path      = @path[0, mask_index]
            end
            @path      = @path.length == 0 ? nil : Pathname.new(@path).cleanpath.to_s
            @mask_type = @mask_type | File::FNM_PATHNAME if @path_mask != '*' || !@path.nil?
        end

        if args.length == 1 && @clazz.nil? && !@prefix.nil?
            begin
                @clazz = Module.const_get(@prefix[0..-2])
            rescue
            end
        end

        @block = block

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

    def inspect()
        "#{self.class.name}: { prefix='#{@prefix}', suffix='#{@suffix}', path='#{@path}', mask='#{@path_mask}' mask_type=#{mask_type}, clazz=#{@clazz}}"
    end

    def ==(an)
        !an.nil? && self.object_id == an.object_id ||
        (an.class == self.class && an.suffix == @suffix && an.prefix == @prefix &&
         an.path == @path && an.path_mask == @path_mask && an.mask_type == @mask_type &&
         an.clazz == @clazz && an.block == @block)
    end

    # re-create the artifact name with new block
    def reuse(&block)
        bk = block
        unless @block.nil?
            sb = @block
            if block.nil?
                bk = sb
            else
                bk = Proc.new {
                    self.instance_eval &sb
                    self.instance_eval &block
                }
            end
        end

        return ArtifactName.new(self, @clazz, &bk)
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
    attr_reader :name, :shortname, :ver, :owner, :createdByMeta, :done

    # context class is special wrapper object that redirect
    # its methods call to a wrapped (artifact object) target
    # object. Additionally it tracks a current target object
    # from which a method has been called.
    # c
    class Proxy
        instance_methods.each { | m |
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

    # set or get default artifact name
    def Artifact.default_name(*args)
        @default_name = args[0] if args.length > 0
        @default_name = File.join('.env', self.name) if @default_name.nil?
        return @default_name
    end

    # stub class to perform chain-able calls
    class AssignRequiredTo
        def initialize(item) @item = item end
        def TO(an) @item[1] = an; return self end
        def OWN() @item[2] = true; return self end
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

        # if artifact name has not been passed let's try to use default one
        args = [ instance.class.default_name ] if (args[0] == nil || args.length == 0) && !instance.class.default_name.nil?

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

    def project()
        ow = owner
        while ow && !ow.kind_of?(Project) do
            ow = ow.owner
        end
        return ow
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

        # if artifact class is detected add it as required
        if meth.length > 2
            begin
                clazz = Module.const_get(meth)
                if clazz < Artifact
                    if args.length > 0
                        return REQUIRE(clazz.new(*args, &block))
                    else
                        return REQUIRE(*args, clazz, &block)
                    end
                end
            rescue NameError
            end
        end

        super(meth, *args, &block)
    end

    # return cloned array of the artifact dependencies
    def requires()
        @requires ||= []
        req = @requires

        # artifacts have to be unique by its names
        req = req.reverse.uniq { | e |
            art = e[0]
            if art.kind_of?(Artifact)
                art.name
            elsif art.kind_of?(Class)
                if art < EnvArtifact  # only one environment of the given type can be required
                    art.name # class name
                else
                    art.default_name
                end
            elsif art.kind_of?(String)
                art
            else
                raise "Unknown artifact type '#{art}' dependency"
            end
        }.reverse

        req.each { | dep |
            yield dep[0], dep[1], dep[2], dep[3]
        }
    end

    # test if the given artifact has expired and need to be built
    def expired?() true end

    # clean method should be implemented to clean artifact related
    # build stuff
    def clean() end

    def to_s() shortname end

    def what_it_does() return "Build '#{to_s}' artifact" end

    # add required for the artifact building dependencies (other artifact)
    def REQUIRE(art, &block)
        raise 'No dependencies have been specified' if art.nil?
        @requires ||= []
        @requires.push([art, nil, false, block])
        return AssignRequiredTo.new(@requires[-1])
    end

    def DISMISS(art)
        raise 'No dependencies have been specified' if art.nil?
        ln1 = ln2 = 0
        if @requires && @requires.length > 0
            ln1 = @requires.length
            @requires.delete_if { | el | el[0] == art }
            ln2 = @requires.length
        end

        raise "'#{art}' DEPENDENCY cannot be found and dismissed" if ln2 == ln1
    end

    # Overload "eq" operation of two artifact instances.
    def ==(art)
        return !art.nil? && self.object_id == art.object_id ||
                (self.class == art.class && @name == art.name && createdByMeta == art.createdByMeta)
    end

    # return last time the artifact has been modified
    def mtime() -1 end

    def Artifact.abbr() 'ART' end

    def Artifact.read_exec_output(stdin, stdout, thread)
        while thread.status != false && thread.status != nil
            begin
                rr = IO.select([ stdout ], nil, nil, 2)
                if !rr.nil? && !rr.empty?
                    for std in rr[0]
                        line = std.readline.rstrip
                        yield line unless line.nil?
                    end
                end
            rescue EOFError => e
                $stdout.flush()
            rescue Exception => e
                STDERR.puts(e)
                STDERR.flush()
                return thread.value
            end
        end
    end

    def Artifact.exec(*args, &block)
        # clone arguments
        args = args.dup

        # use quotas to surround process if necessary
        args[0] = "\"#{args[0]}\"" if !args[0].index(' ').nil? && args[0][0] != "\""

        # merged stderr and stdout
        Open3.popen2e(args.join(' ')) { | stdin, stdout, thread |
            stdin.close
            stdout.set_encoding(Encoding::UTF_8)
            if  block.nil?
                Artifact.read_exec_output(stdin, stdout, thread) { | line |
                    $stdout.puts line
                    $stdout.flush
                }
            else
                block.call(stdin, stdout, thread)
            end
            return thread.value
        }
    end

    # build artifact including all its dependencies
    def Artifact.build(name, &block)
        # !!! instantiate tree artifact in a context of an artifact that calls it
        # !!! the caller artifact is set as an owner of the created artifact
        art = self.new(name, &block)
        tree = ArtifactTree.new(art)
        tree.build()
        return tree.art
    end

    def DONE(&block)
        @done = block
    end
end

# Artifact tree. Provides tree of artifacts that is built basing
# on resolving artifacts dependencies
class ArtifactTree
    attr_accessor :art, :parent, :children, :expired, :expired_by_kid

    def initialize(art, parent = nil, &block)
        raise 'Artifact cannot be nil' if art.nil?

        p = parent.nil? ? Project : parent.art.owner
        if !art.kind_of?(Artifact)
            art = p.artifact(art, &block)
        elsif !block.nil?
            art.instance_eval(&block)
        end

        @children, @art, @parent, @expired, @expired_by_kid = [], art, parent, art.expired?, nil
        build_tree() if parent.nil?
    end

    # build tree starting from the root artifact (identified by @name)
    def build_tree(map = [])
        bt = @art.mtime()

        @art.requires { | dep, assignMeTo, is_own, block |
            foundNode, node = nil, ArtifactTree.new(dep, self, &block)

            if block.nil?  # requires with a custom block cannot be removed from build tree
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

            # build subtree to evaluate expiration
            node.build_tree(map)
            if !@expired && (node.expired || bt.nil? || (bt > 0 && node.art.mtime() > bt))
                @expired = true
                @expired_by_kid = node.art
            end

            # add the new node to tree and process it only if doesn't already exist
            @children << node if foundNode.nil?

            # we have to check if the artifact is assignable to
            # its parent and assign it despite if the artifact has
            # been excluded from the tree

            # has to be placed before recursive build tree method call
            node.art.owner = @art.owner if is_own == true

            if node.art.class < AssignableDependency
                # call special method that is declared with AssignableDependency module
                # to resolve host artifact property name the given dependency artifact has
                # to be stored
                assignMeTo = node.art.assign_me_to if assignMeTo.nil?

                raise "Nil assignable property name for #{node.art.class}:#{node.art.name}" if assignMeTo.nil?

                if @art.respond_to?(assignMeTo.to_sym)
                    @art.send(assignMeTo.to_sym, node.art)
                else
                    asn = "@#{assignMeTo}".to_sym
                    av  = @art.instance_variable_get(asn)
                    if av.kind_of?(Array)
                        # check if the artifact is already in
                        found = av.detect { | art | node.art.object_id == art.object_id }

                        if found.nil?
                            av.push(node.art)
                            @art.instance_variable_set(asn, av)
                        end
                    else
                        @art.instance_variable_set(asn, node.art)
                    end
                end
            end
        }
    end

    def build()
        unless @expired
            puts_warning "'#{@art.name}' : #{@art.class} is not expired"
        else
            @children.each { | node | node.build() }
            if @art.respond_to?(:build)
                prev_art = $current_artifact
                begin
                    $current_artifact = @art
                    wid = @art.what_it_does()
                    puts wid unless wid.nil?
                    @art.pre_build()

                    @art.build()
                    @art.instance_eval(&@art.done) unless @art.done.nil?

                    @art.build_done()
                rescue
                    @art.build_failed()
                    level = !$lithium_options.nil? && $lithium_options.key?('v') ? $lithium_options['v'].to_i : 0
                    puts_exception($!, 0) if level == 0
                    puts_exception($!, 3) if level == 1
                    raise                 if level == 2
                ensure
                    $current_artifact = prev_art
                end
            else
                puts_warning "'#{@art.name}' does not declare build() method"
            end
        end
    end

    def traverse(level = 0, &block)
        @children.each { | node |
            node.traverse(level + 1, &block)
        }
        block.call(self, level)
    end

    def what_it_does() "Build '#{@name}' artifact dependencies tree" end
end

#  Base file artifact
class FileArtifact < Artifact
    attr_reader :is_absolute

    def initialize(name, &block)
        path = Pathname.new(name).cleanpath
        @is_absolute  = path.absolute?
        super(path.to_s, &block)
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
                    return home #if _contains_path?(home, @name)
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
       # TODO: have no idea if the commented code will have a side effect !
       # return path if path.start_with?('.env/')

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
                return File.join(home, path.to_s)
            end
        end
    end

    def build()
    end

    # test if the given path is in a context of the given file artifact
    def match(path)
        raise 'Invalid empty or nil path' if path.nil? || path.length == 0

        # current directory always match
        return true if path == '.'

        mi = path.index(/[\[\]\?\*\{\}]/) # test if the path contains mask

        # cut mask part if it has been detected in the path
        unless mi.nil?
            pp   = path.dup
            path = path[0, mi]
            raise "Path '#{pp}' contains only mask" if path.length == 0
        end

        path  = Pathname.new(path).cleanpath
        home  = Pathname.new(homedir)
        raise "Home '#{home}' is not an absolute path" if path.absolute? && !home.absolute?

        # any relative path is considered as a not matched path
        return false if !path.absolute? && home.absolute?
        return _contains_path?(home.to_s, path.to_s)
    end

    def expired?()
        File.exists?(fullpath) == false
        return false
    end

    def mtime()
        f = fullpath()
        return File.exists?(f) ? File.mtime(f).to_i() : -1
    end

    def puts_items()
        list_items { | p, t |
            puts "logged item = '#{p}' : #{t}"
        }
    end

    def list_items()
        fp = fullpath
        if File.exists?(fp)
            yield fp, File.mtime(fp).to_i
        else
            yield fp, -1
        end
    end

    def search(path)
        return FileArtifact.search(path, self)
    end

    def self.which(cmd)
        exts = ENV['PATHEXT'] ? ENV['PATHEXT'].split(';') : ['']
        ENV['PATH'].split(File::PATH_SEPARATOR).each do |path|
            exts.each { | ext |
                exe = File.join(path, "#{cmd}#{ext}")
                return exe if File.executable?(exe) && !File.directory?(exe)
            }
        end
        return nil
    end

    def self.cpfile(src, dest)
        self.testdir(dest)
        raise "Source '#{src}' file doesn't exist" unless File.exists?(src)
        raise "Source '#{src}' file cannot be dir" if File.directory?(src)
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
        #raise "Path '#{path}' has to be a directory" if !File.directory?(path)

        while path && prev_path != path && (top_path.nil? || prev_path != top_path)
            marker = File.join(path, fname)
            return marker if File.exists?(marker) && (block.nil? || block.call(marker))
            prev_path = path
            path      = File.dirname(path)
            break if path == '.'  # dirname can return "." if there is no available top directory
        end

        return nil
    end

    @search_cache = {}

    def self.search(path, art = $current_artifact)
        return [ File.expand_path(path) ] if File.exists?(path)

        art = Project.current if art.nil? || !art.kind_of?(FileArtifact)
        return [] if art.nil?

        fp = art.fullpath
        fp = File.dirname(fp) unless File.directory?(fp)
        if File.exists?(fp)
            path = Pathname.new(path).cleanpath.to_s
            return [] if @search_cache[fp] && @search_cache[fp][path]

            res = Dir.glob(File.join(fp, '**', path))
            return res if res.length > 0

            @search_cache[fp] = {} unless @search_cache[fp]
            @search_cache[fp][path] = true
        end

        return art.kind_of?(Project) ? [] : FileArtifact.search(path, art.project)
    end

    def self.grep_file(path, pattern, match_all = false, &block)
        raise 'Pattern cannot be nil' if pattern.nil?
        pattern = Regexp.new(pattern) if pattern.kind_of?(String)

        raise "File '#{path}' cannot be found"     unless File.exists?(path)
        raise "File '#{path}' points to directory" unless File.file?(path)

        list = []
        line_num = 0
        File.readlines(path).each { | line |
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

        is_not_mask = path.index(/[\[\]\?\*\{\}]/).nil?
        raise "File '#{path}' cannot be found" if !File.exists?(path) && is_not_mask

        list = []
        if File.directory?(path) || !is_not_mask
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

        is_not_mask = path.index(/[\[\]\?\*\{\}]/).nil?
        raise "Path '#{path}' points to file" if File.file?(path)
        raise "Path '#{path}' doesn't exist"  if !File.exists?(path) && is_not_mask

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

    def self.abbr() 'FAR' end
end

# Permanent file shortcut
class ExistentFile < FileArtifact
    def initialize(*args)
        super
        assert_existence()
    end

    def build()
        assert_existence()
    end

    def mtime()
        assert_existence()
        return super()
    end

    def expired?()
        return false
    end

    def assert_existence()
        fp = fullpath()
        raise "File '#{fp}' doesn't exist" unless File.exists?(fp)
    end
end

# Perform and action on a file artifact
class FileCommand < ExistentFile
    def expired?() true end

    def self.abbr() 'FCM' end
end

# Directory artifact
class Directory < FileArtifact
    def build()
        super
        fp = fullpath
        raise "File '#{fp}' is not a directory" if File.exists?(fp) && !File.directory?(fp)
    end
end

class ExistentDirectory < FileArtifact
    def build()
        super
        fp = fullpath
        raise "File '#{fp}' is not a directory" unless File.directory?(fp)
    end
end

# File mask artifact that can identify set of file artifacts
#
class FileMask < FileArtifact
    def initialize(*args)
        @regexp_filter = nil
        @ignore_dirs   = false
        @ignore_files  = false
        super
        raise 'Files and directories are ignored at the same time' if @ignore_files && @ignore_dirs
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

    def ignore_hidden()
        @regexp_filter = /^[\.].*/
    end

    # called for every detected item as a part of build process
    def build_item(path, m) end

    # list items to array
    def list_items_to_array(rel = nil)
        list = []
        list_items(rel) { | path, m |
            list << path
        }
        return list
    end

    # List items basing on the mask returns items relatively to the
    # passed path
    def list_items(rel = nil)
        go_to_homedir()

        rel = rel[0, rel.length - 1] if !rel.nil? && rel[-1] == '/'

        Dir[@name].each { | path |
            next if @regexp_filter && !(path =~ @regexp_filter)

            if @ignore_files || @ignore_dirs
                b = File.directory?(path)
                next if (@ignore_files && !b) || (@ignore_dirs && b)
            end

            mt = File.mtime(path).to_i
            unless rel.nil?
                "Relative path '#{rel}' cannot be applied to '#{path}'" unless _contains_path?(rel, path)
                path = path[rel.length + 1, path.length - rel.length]
            end

            yield path, mt
        }
    end

    def expired?() true end

    def self.abbr() 'FMS' end
end


module ArtifactContainer
    #  (name : String | ArtifactName | Class)
    def artifact(name, &block)
        raise "Stack is overloaded '#{name}'" if Artifact._calls_stack_.length > 25

        artname = ArtifactName.new(name)

        # check if artifact name points to current project
        return Project.current if artname.to_s == Project.current.name.to_s

        # fund local info about the given artifact
        meta = find_meta(artname)
        if meta.nil?
            unless owner.nil?
                # puts "Container '#{@name}' delegate '#{artname.path}' to owner"
                # if !artname.path.nil? && artname.path.start_with?('../')
                #     return owner.artifact(artname.path_up(), &block)
                # end

                # meta cannot be locally found try to delegate search to owner container
                # if owner exists and artifact name doesn't identify environment artifact
                #unless artname.env_path?
                    # puts "artname.path.nil? = #{artname.path.nil?} !match('#{homedir}', '#{artname.path}') = #{!match(artname.path)}"
                    # return owner.artifact(name, &block) if artname.path.nil? || !match(artname.path)
                #end
            end

            meta = _meta_from_owner(name)
            unless meta.nil?
                # attempt to handle situation when an artifact meta the container has been
                # created is going to be applied to artifact creation. It can indicate we
                # have cyclic come back
                raise "There is no an artifact associated with '#{name}'" if !createdByMeta.nil? && meta.object_id == createdByMeta.object_id
            else
                meta = artname unless artname.clazz.nil?
            end

            raise NameError.new("No artifact is associated with '#{name}' meta = #{meta}") if meta.nil?
        end

        # manage cache
        _remove_from_cache(artname)          unless block.nil?  # remove from cache if a custom block has been passed
        art = _artifact_from_cache(artname)  if block.nil?      # read from cache if custom block has not been passed

        # instantiate artifact with meta if it has not been found in cache
        art = _artifact_by_meta(artname, meta, &block) if art.nil?
        art = _cache_artifact(artname, art)            if block.nil? # cache only if a custom block has been passed

        # if the artifact is a container handling of target (suffix) is delegated to the container
        return art.artifact(artname.suffix) if art.kind_of?(ArtifactContainer)

        return art
    end

    # cache artifact only if it is not identified by a mask or is an artifact container
    def _cache_artifact(name, art)
        name = ArtifactName.new(name)
        if name.path_mask.nil? || art.kind_of?(ArtifactContainer)
            _artifacts_cache[name] = art
        end
        return art
    end

    # fetch an artifact from cache
    def _artifact_from_cache(name)
        name = ArtifactName.new(name)
        unless _artifacts_cache[name].nil?
            return _artifacts_cache[name]
        else
            return nil
        end
    end

    # { art_name:ArtifactName => instance : Artifact ...}
    def _artifacts_cache()
        @artifacts = {} unless defined? @artifacts
        @artifacts
    end

    def _remove_from_cache(name)
        #TODO: WTF?
        # name = ArtifactName.new(name)
        # _artifacts_cache.delete(name) unless _artifacts_cache[name].nil?
    end

    # instantiate the given artifact by its meta
    def _artifact_by_meta(name, meta, &block)
        name  = ArtifactName.new(name)
        clazz = meta.clazz

        art = clazz.new(name.suffix,
            &(block.nil? ? meta.block : Proc.new {
                self.instance_eval &meta.block unless meta.block.nil?
                self.instance_eval &block
            })
        )

        art.createdByMeta = meta
        return art
    end

    def _meta_from_owner(name)
        name = ArtifactName.new(name)
        ow   = owner
        meta = nil
        while !ow.nil? && meta.nil? do
            meta = ow.find_meta(name)
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
        @meta = [] unless defined? @meta
        return @meta
    end

    # find appropriate for the given artifact name registered meta if possible
    def find_meta(name)
        name = relative_art(name)
        return _meta.detect { | p | p.match(name) }
    end

    def ==(prj)
        super(prj) && _meta == prj._meta
    end

    # 1. (class : Class)
    # 2. (name  : String | ArtifactName)
    # 3. (meta  : ArtifavtMeta)
    # 4. (name, class)
    def ARTIFACT(*args, &block)
        # if class has not been passed use default one
        args = args.dup().push(FileMaskContainer) if args.length == 1 && !args[0].kind_of?(ArtifactName) && !args[0].kind_of?(Class)

        # store meta
        name = ArtifactName.new(*args, &block)
        raise "Unknown class for '#{name}' artifact" if name.clazz.nil?
        _meta.push(name)

        # sort meta array
        _meta.sort
    end

    def MATCH(file_mask, &block)
        raise "Block is expected for Match '#{file_mask}'" if block.nil?
        ARTIFACT(file_mask, FileMaskContainer, &block)
    end

    def method_missing(meth, *args, &block)
        if meth.length > 2
            begin
                clazz = Module.const_get(meth)
                return ARTIFACT(*args, clazz, &block) if clazz < Artifact
            rescue NameError
            end
        end

        super
        # switched = false
        # if  @@calls_stack.length == 0 || @@calls_stack.last.original_instance != @original_instance
        #     @@calls_stack.push(self)
        #     switched = true
        # end

        # begin
        #     return @original_instance.send(meth, *args, &block)
        # ensure
        #     @@calls_stack.pop() if switched
        # end
    end


    # return reference to an artifact meta info
    def REF(name)
        name = ArtifactName.new(name)
        meta = find_meta(name)
        if meta.nil?
            meta = _meta_from_owner(name)

            unless meta.nil?
                raise "It seems there is no an artifact associated with '#{name}'" if !createdByMeta.nil? && meta.object_id == createdByMeta.object_id
            else
                meta = name
            end
            raise NameError.new("No artifact is associated with '#{name}'") if meta.nil?
        end
        return meta
    end

    # TODO: this method most likely should be removed
    def REUSE(name, &block)
        raise "Project '#{self}' doesn't have parent project to re-use its artifacts" if owner.nil?
        artname = ArtifactName.new(name)
        meta    = _meta_from_owner(name)
        raise "Cannot find '#{artname}' in parent projects" if meta.nil?

        _meta.push(meta.reuse(&block))

        # sort meta array
        _meta.sort
    end

    def REMOVE(name)
        # TODO: implement it
    end
end

# mask container
class FileMaskContainer < FileMask
    include ArtifactContainer
end

# project artifact
class Project < ExistentDirectory
    attr_reader :desc

    include ArtifactContainer

    @@curent_project = nil

    def self.new(*args, &block)
        @@curent_project = super
        return @@curent_project
    end

    def self.current=(prj)
        @@curent_project = prj
    end

    def self.current()
        @@curent_project
    end

    def self.artifact(name, &block)
        @@curent_project.artifact(name, &block)
    end

    def self.build(name, &block)
       return @@curent_project.build(name, &block)
    end

    def initialize(*args, &block)
        # means artifact meta are not shared with its children project
        self.owner = args[1] if args.length > 1
        super(args[0], &block)
        @desc ||= File.basename(args[0])

        conf = File.join(homedir, '.lithium', 'project.rb')
        if File.file?(conf)
            self.instance_eval(File.read(conf)).call
        else
            puts_warning "Project '#{@desc}' configuration '#{conf}' cannot be found"
        end
    end

    def homedir()
        return @name if @is_absolute
        return super
    end

    def expired?() true end

    def build(name, &block)
        tree = ArtifactTree.new(name, &block)
        tree.build()
        return tree.art
    end

    def what_it_does()
        nil
    end
end

# an artifact has to include the module to be assigned to an attribute of an artifact
# that requires the AssignableDependency artifact
module AssignableDependency
    #  an attribute name the dependency artifact has to be assigned
    def assign_me_to()
        self.class.name.downcase
    end
end

# Option support
module OptionsSupport
    def OPTS(*args)
        @options = options()
        if args.length > 0
            @options = []
            args.each { | o |
                OPT(o)
            }
        end
        return @options.join(' ')
    end

    def OPT(opt)
        @options = options()
        @options.push(opt)
    end

    def OPT?(op)
        @options = options()
        return @options.include?(op)
    end

    def OPTS?()
        @options = options()
        return @options.length > 0
    end

    # return valid not nil attribute value in a case of making it loggable.
    # Otherwise 'option' attribute can equal [] after building (since OPTS)
    # method has been called, but be nil before an artifact building
    def options()
        @options ||= []
        return @options
    end
end

# Environment artifact
class EnvArtifact < Artifact
    include AssignableDependency

    def self.default_name(*args)
        @default_name ||= nil
        if args.length > 0
            raise "Invalid environment artifact '#{name}' name ('.env/<artifact_name>' ie expected)" unless name.start_with?('.env/')
            @default_name = validate_env_name(args[0])
        elsif @default_name.nil?
            @default_name = File.join('.env', self.name)
        end

        return @default_name
    end

    def build() end
end

# The base class to support classpath / path like artifact
module PATH
    def path_valid?
        @is_path_valid ||= false
        return @is_path_valid
    end

    def include_path?(path)
        is_file = false

        bd   = path_base_dir()
        path = File.join(bd, path) if !bd.nil? && !Pathname.new(path).absolute?

        if path[-1] == '/'
            path = path[0..-2]
        elsif File.file?(path)
            is_file = true
            path = File.basename(path)
        end

        paths().each { | path_item |
            path_item = File.basename(path_item) if is_file && File.file?(path_item)
            return true if path_item == path
        }

        return false
    end

    # TODO: think if the code is valid for this particular module
    def path_base_dir
        return project.homedir if respond_to?(project)
        retun nil
    end

    def add_path(path)
        add_paths(path)
    end

    # add path item
    def add_paths(*parts)
        @paths ||= []

        parts.each { | path |
            if path.kind_of?(PATH)
                @paths.concat(path.paths())
            elsif path.kind_of?(String)
                hd = path_base_dir
                path.split(File::PATH_SEPARATOR).each { | path_item |
                    path_item = File.join(hd, path_item) if !hd.nil? && !(Pathname.new path_item).absolute?

                    # TODO: copy paste ArtifactName initialize()
                    mask_index = path_item.index(/[\[\]\?\*\{\}]/)
                    unless mask_index.nil?
                        @paths.concat(FileArtifact.dir(path_item))
                        path_item = path_item[0, mask_index] # remove mask
                    end

                    @paths.push(path_item)
                }
                @is_path_valid = false
            else
                raise "Invalid path type '#{path.class}'"
            end
        }
    end

    def join_path(path)
        return join_paths(path)
    end

    def join_paths(*parts)
        p = PATH.new(path_base_dir())
        p.add_paths(*(paths()))
        p.add_paths(*parts)
        return p
    end

    # clear path
    def clear_path
        @paths = []
        @is_path_valid = true
    end

    def validate_path
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
    end

    def paths
        @paths ||= []
        validate_path()
        return @paths
    end

    def path_empty?
        paths().length == 0
    end

    def to_s
        return path_empty?() ? nil : paths().join(File::PATH_SEPARATOR)
    end
end


class PathClass
    include PATH

    def initialize()
        @dir = nil
        super
    end
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



