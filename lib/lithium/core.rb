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
            attr_accessor *args
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
            block.call(n, e[n] ? e[n] : -1) if t == -1 || e[n].nil? || e[n].to_i == -1 || e[n].to_i < t
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
        @items_log_path ||= File.join(logs_home_dir, "#{self.class.to_s}_#{self.name.tr("/\\<>:.*{}[]", '_')}")
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
                name = name.default_name
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

    def Artifact.default_name(*args)
        @default_name = args[0] if args.length > 0
        @default_name ||= nil
        return @default_name
    end

    # stub class to perform chain-able calls
    class AssignRequiredTo
        def initialize(item) @item = item end
        def TO(an) @item[1] = an; return self end
        def OWN() @item[2] = true; return self end
    end

    def Artifact.REQUIRE(art, &block)
        raise 'Dependency cannot be null artifact' if art.nil?
        @requires ||= []
        @requires.push([art, nil, nil, block])
        return AssignRequiredTo.new(@requires[-1])
    end

    def Artifact.requires_as_array()
        @requires ||= []
        @requires
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
        args = [ instance.default_name ] if args.length == 0 && !instance.default_name.nil?

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
        super(meth, *args, &block)
    end

    # return cloned array of the artifact dependencies
    def requires()
        @requires ||= []
        req = self.class.requires_as_array + @requires
        req = req.reverse.uniq { | e |
            art = e[0]
            if art.kind_of?(Artifact)
                art.name
            elsif art.kind_of?(Class)
                art.default_name
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
        @requires.push([art, nil, nil, block])
        return AssignRequiredTo.new(@requires[-1])
    end

    # Overload "eq" operation of two artifact instances.
    def ==(art)
        art && self.class == art.class && @name == art.name && @ver == art.ver && owner == art.owner
    end

    # return last time the artifact has been modified
    def mtime() -1 end

    def Artifact._read_std_(std, out)
        while (rr = IO.select([ std ], nil, nil, 2)) != nil
            next if rr.empty?
            begin
                l = std.readline.encode('utf-8').rstrip()
                out.puts l if l
            rescue IOError => e
                break
            end
        end
    end

    def Artifact.exec(*args, &block)
        # clone arguments
        args = args.dup

        # use quotas to surround process if necessary
        args[0] = "\"#{args[0]}\"" if !args[0].index(' ').nil? && args[0][0] != "\""

        Open3.popen3(args.join(' ')) { | stdin, stdout, stderr, thread |
            stdin.close
            stdout.set_encoding(Encoding::UTF_8)
            stderr.set_encoding(Encoding::UTF_8)

            block.call(stdin, stdout, stderr, thread) unless block.nil?

            while thread.status != false && thread.status != nil
                begin

                    # thread.wakeup if !thread.alive? && thread.status != false

                    # the line can block forever with "thread.value" or  "Process.waitpid(thread[:pid])"
                    #return thread.value if Process.waitpid(thread[:pid])


                #rescue Errno::ESRCH #Errno::ECHILD
                #rescue Exception => e
                rescue Errno::ECHILD
                    begin
                        _read_std_(stdout, $stdout)
                        _read_std_(stderr, $stdout)
                    rescue
                    end

                    return thread.value
                end

                _read_std_(stdout, $stdout)
                _read_std_(stderr, $stdout)
            end

            return thread.value
        }
    end

    def Artifact.build(name, &block)
        art = self.new(name, &block)
        art.build()
        return art
    end

    def DONE(&block)
        @done = block
    end
end

# Artifact tree. Provides tree of artifacts that is built basing
# on resolving artifacts dependencies
class ArtifactTree < Artifact
    attr_reader :root_node

    # tree node structure
    class Node
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
        @show_mtime = true
        @show_owner = true
        super
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
        puts "build_tree(): root = #{root.art}"

        root.art.requires { | dep, assignMeTo, is_own, block |
            node, parent = Node.new(dep, root, &block), root
            while parent && parent.art != node.art
                parent = parent.parent
            end

            puts "build_tree(): root = #{root.art}, dependecy = #{node.art},(#{is_own})->#{root.art.owner}"

            raise "#{root.art.class}:'#{root.art}' has CYCLIC dependency on #{parent.art.class}:'#{parent.art}'" unless parent.nil?

            root.children << node
            build_tree(node)

            node.art.owner = root.art.owner if is_own == true

            if !assignMeTo.nil? || node.art.class < AssignableDependecy

                # if an attribute name the dependency has to be assigned has not bee defined
                # that means we have get using AssignableDependecy API
                assignMeTo = node.art.assign_me_to if assignMeTo.nil?

                raise "Invalid attribute name 'node.art' artifact has to be assigned" if assignMeTo.nil?

                asn = "@#{assignMeTo.to_s}".to_sym
                av  = root.art.instance_variable_get(asn)
                if av.kind_of?(Array)
                    av.push(node.art)
                    root.art.instance_variable_set(asn, av)
                else
                    root.art.instance_variable_set(asn, node.art)
                end
            end
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

        e = (root.expired ? '*' : '') + (root.expired_by_kid ? "*[#{root.expired_by_kid}]" : '') + (@show_mtime ? ":#{root.art.mtime}" : '') + (@show_owner ? " <#{root.art.owner}>" : '')
        s = "#{' '*shift}" + (parent ? '+-' : '') + "#{name}(#{root.art.class})"  + e
        b = parent && root != parent.children.last
        if b
            s, k = "#{s}\n#{' '*shift}|", name.length/2 + 1
            s = "#{s}#{' '*k}|" if root.children.length > 0
        else
            k = shift + name.length/2 + 2
            s = "#{s}\n#{' '*k}|" if root.children.length > 0
        end

        shift = shift + name.length / 2 + 2
        root.children.each { | i |
            rs, s = tree2string(root, i, shift), s + "\n"
            if b
                rs.each_line { | l |
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

    def self.cpdir(src, dest, em=nil)
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

    def self.grep(file, pattern)
        raise 'Pattern cannot be nil' if pattern.nil?
        pattern = Regexp.new(pattern) if pattern.kind_of?(String)
        File.readlines(file).each { |l|
            return Regexp.last_match if l =~ pattern
        }
        nil
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
end


module ArtifactContainer
    #  (name : String | ArtifactName | Class)
    def artifact(name, &block)
        raise "Stack is overloaded '#{name}'" if Artifact._calls_stack_.length > 15

        artname = ArtifactName.new(name)

        # check if artifact name points to current project
        return Project.current if artname.to_s == Project.current.name.to_s

        # fund local info about the given artifact
        meta = find_meta(artname)

        if meta.nil?
            # meta cannot be locally found try to delegate search to owner
            # path nil or doesn't match project then delegate finding an artifact in an owner project context
            return owner.artifact(name, &block) if !owner.nil? && !artname.env_path? && (artname.path.nil? || !match(artname.path))

            meta = _meta_from_owner(name)

            unless meta.nil?
                # attempt to handle situation when an artifact meta the container has been
                # created is going to be applied to artifact creation. It can indicate we
                # have cyclic come back
                raise "It seems there is no an artifact associated with '#{name}'" if !createdByMeta.nil? && meta.object_id == createdByMeta.object_id
            else
                meta = artname unless artname.clazz.nil?
            end

            raise NameError.new("No artifact is associated with '#{name}' meta = #{meta}") if meta.nil?
        end

        # manage cache
        _remove_from_cache(artname) unless block.nil?  # remove from cache if a custom block has been passed
        art = _artifact_from_cache(artname)

        # instantiate artifact with meta if it has not been found in cache
        art = _artifact_by_meta(artname, meta, &block) if art.nil?
        art = _cache_artifact(artname, art)

        # if the artifact is a container handling of target (suffix) is delegated to the container
        return art.artifact(artname.suffix) if art.kind_of?(ArtifactContainer)

        # return artifact
        return art
    end

    # cache artifact only if it is not identified by a mask or is an artifact container
    def _cache_artifact(name, art)
        name = ArtifactName.new(name)
        _artifacts_cache[name] = art if name.path_mask.nil? || art.kind_of?(ArtifactContainer)
        return art
    end

    # fetch an artifact from cache
    def _artifact_from_cache(name)
        name = ArtifactName.new(name)
        return _artifacts_cache[name] unless _artifacts_cache[name].nil?
    end

    # { art_name:ArtifactName => instance : Artifact ...}
    def _artifacts_cache()
        @artifacts = {} unless defined? @artifacts
        @artifacts
    end

    def _remove_from_cache(name)
        name = ArtifactName.new(name)
        _artifacts_cache.delete(name) unless _artifacts_cache[name].nil?
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

# an artifact has to include the module to be assigned to an attribute of an artifact
# that requires the AssignableDependecy artifact
module AssignableDependecy
    #  an attribute name the dependency artifact has to be assigned
    def assign_me_to()
        self.class.name.downcase
    end
end

# Option support
module OptionsSupport
    def OPTS(*args)
        @options ||= []
        if args.length > 0
            @options = []
            args.each { | o |
                OPT(o)
            }
        end
        return @options.join(' ')
    end

    def OPT(opt)
        @options ||= []
        @options.push(opt)
    end

    def OPT?(op)
        @options ||= []
        return @options.include?(op)
    end

    def OPTS?()
        @options ||= []
        return @options.length > 0
    end
end

# Environment artifact
class EnvArtifact < Artifact
    include AssignableDependecy

    def self.default_name(*args)
        @default_name ||= nil
        if args.length > 0
            @default_name = validate_env_name(args[0])
        elsif @default_name.nil?
            @default_name = File.join('.env', self.name)
        end

        return @default_name
    end

    def self.validate_env_name(name)
        raise "Environment artifact cannot be assigned with '#{name}' name. Use '.env/<artifact_name>' name pattern" unless name.start_with?('.env/')
        name
    end

    def build() end
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
