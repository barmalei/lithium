require 'digest'

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
# "list_items" method or an attribute state that has to be declared via log_attr method
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
            t = detect_logs_mtime()
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
        unless File.exist?(log_hd)
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
        File.delete(p1) if items_log_enabled? && File.exist?(p1)

        p2 = attrs_log_path()
        File.delete(p2) if attrs_log_enabled? && File.exist?(p2)
    end

    def detect_logs_mtime
        return -1 unless can_artifact_be_tracked?

        p1 = items_log_path()
        p2 = attrs_log_path()
        t1 = File.exist?(p1) && items_log_enabled? ? File.mtime(p1).to_i : -1
        t2 = File.exist?(p2) && attrs_log_enabled? ? File.mtime(p2).to_i : -1
        return t1 > t2 ? t1 : t2
    end

    def logs_expired?
        return false unless can_artifact_be_tracked?

        if items_log_enabled?
            # if there is no items but the items are expected consider it as expired case
            #return true if self.class.method_defined?(:list_items) && !File.exist?(items_log_path())
            # check items expiration
            list_expired_items { |n, t|
                return true
            }
        end

        if attrs_log_enabled?
            list_expired_attrs { |a, ov|
                return true
            }
        end

        return false
    end

    def update_logs
        return unless can_artifact_be_tracked?

        t = Time.now
        if items_log_enabled?
            update_items_log()
            path = items_log_path()
            File.utime(t, t, path) if File.exist?(path)
        end

        if attrs_log_enabled?
            update_attrs_log()
            path = attrs_log_path()
            File.utime(t, t, path) if File.exist?(path)
        end
    end

    #############################################################
    #  log items specific methods
    #############################################################

    # return map where key is an item path and value is integer modified time
    def load_items_log
        p, e = items_log_path(), {}
        if File.exist?(p)
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
            # raise "Duplicated listed item '#{n}'" if e[n] == -2
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
        list_items { |n, t|
            d = true if !d && (e[n].nil? || e[n] != t)  # detect expired item
            r[n] = t  # map to refresh items log
        }

        # save log if necessary
        path = items_log_path()
        if r.length == 0    # no items means no log
            File.delete(path) if File.exist?(path)
        elsif d || r.length != e.length
            File.open(path, 'w') { |f|
                r.each_pair { |name, time|
                    f.printf("%s %i\n", name, time)
                }
            }
        end
    end

    def items_log_enabled?
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
                self.class.each_log_attrs { | a |
                    # call attribute successor method
                    data[a] = self.send(a)
                }
                File.open(path, 'w') { | f | Marshal.dump(data, f) }
            rescue
                File.delete(path)
                raise
            end
        else
            File.delete(path) if File.exist?(path)
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

            if File.exist?(path)
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

    def attrs_log_enabled?
        true
    end

    def attrs_log_path
        items_log_path() + ".liser"
    end
end
