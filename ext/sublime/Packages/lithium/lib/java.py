
import os, sublime, re

from core import LiLog, LiHelper

class LiJava:
    # retrieve java package and return it
    # @return ( <regions including package keyword>, <package_name> )
    @classmethod
    def java_package(clz, view, syntax = 'java'):
        if syntax == 'java':
            expand_scope = 'source.java meta.namespace.package.identifier.java'
            regs = view.find_by_selector('source.java meta.namespace.package.identifier.java meta.path.java')
            if regs is not None and len(regs) > 0:
                return view.expand_to_scope(regs[0].a, expand_scope), view.substr(regs[0])
            else:
                regs = view.find_by_selector('source.java meta.namespace.package.identifier.java entity.name.namespace.package.java')
                if regs is not None and len(regs) > 0:
                    return view.expand_to_scope(regs[0].a, expand_scope), view.substr(regs[0])
                else:
                    return None, None
        elif syntax == 'kotlin':
            regs = view.find_by_selector('source.Kotlin entity.name.package.kotlin')
            if regs is not None and len(regs) > 0:
                return regs[0], view.substr(regs[0])
            else:
                return None, None
        else:
            raise "Syntax '%s' is not supported" % syntax

    # retrieve current class name and return it
    @classmethod
    def java_classname(clz, view, syntax = 'java'):
        if syntax == 'java':
            regions = view.find_by_selector("source.java meta.class.identifier.java entity.name.class.java")
            if regions is None or len(regions) == 0:
                return None
            else:
                return view.substr(regions[0])
        elif syntax == 'kotlin':
            regions = view.find_by_selector("source.Kotlin entity.name.type.class.kotlin")
            if regions is None or len(regions) == 0:
                return None
            else:
                return view.substr(regions[0])
        else:
            raise "Syntax '%s' is not supported" % syntax

    # Collect JAVA imports
    # @return: [ [ region, "<package_name>", isStatic], ... ]
    # "region" points to the whole import line ("import" ... is included)
    @classmethod
    def java_imports(clz, view, syntax = 'java'):
        if syntax ==  'java':
            regions = view.find_by_selector("source.java meta.import.java meta.path.java")
            if regions is None or len(regions) == 0:
                return None
            else:
                scope = "source.java meta.import.java"
                res   = []
                for region in regions:
                    expanded_reg = view.expand_to_scope(region.a, scope)
                    import_pkg   = re.sub("\s\s+" , " ", view.substr(region)).strip().strip(';')
                    is_static    = re.match(r'^\s*import\s+static\s+', view.substr(expanded_reg)) != None
                    res.append([ expanded_reg, import_pkg, is_static])

                return res
        else:
            # this code probably will be required for other JVM languages since they may
            # not define a specific scope name for import sections
            region    = sublime.Region(0, view.size())
            hold      = False
            import_re = r"^import\s+(static\s+)?([^ :;\-]+)\s*"
            imports   = []
            for line_region in view.lines(region):
                line = view.substr(line_region).strip()

                if len(line) > 0:
                    if hold:
                        idx = line.find("*/")
                        if idx >= 0:
                            hold = False
                            line = line[0:idx].strip()
                            if len(line) == 0:
                                continue
                        else:
                            continue

                    idx = line.find("//")
                    if idx >= 0:
                        line = line[0:idx].strip()
                        if len(line) == 0:
                            continue

                    if line.startswith("/*"):
                        hold = True
                        continue

                    mt = re.match(import_re, line)
                    if mt is not None:
                        static_str = mt.group(1)
                        if static_str is not None:
                            imports.append([ line_region, "import static %s" % mt.group(2), True ])
                        else:
                            imports.append([ line_region, "import %s" % mt.group(2), False ])
                    else:
                        if not line.startswith("package"):
                            break

            if len(imports) > 0:
                return imports
            else:
                return None

    # detect package name by class basing on imports, package
    # @return (package, type)
    @classmethod
    def java_detect_class_package(clz, view, class_name):
        imports = clz.java_imports(view)
        if imports is not None and len(imports) > 0:
            find_package = [ x[1] for x in imports if x[1].endswith("." + class_name)]
            if len(find_package) > 0:
                find_package = find_package[0].strip()
                return (find_package[0 : len(find_package) - len(class_name) - 1], 'import')

        fn = os.path.basename(view.file_name())
        fn = fn[0 : fn.rfind('.java')]
        if fn == class_name:
            return (clz.java_package(view)[1], 'package')
        elif os.path.exists(os.path.join(os.path.dirname(view.file_name()), class_name + '.java')):
            return (clz.java_package(view)[1], 'package')
        else:
            return None, None

    # return symbol that includes full dot path
    # @return (symbol, pkg_name, class_name)
    @classmethod
    def java_view_symbol(clz, view, syntax = 'java'):
        symbol, region, scope = LiHelper.view_symbol(view)

        LiLog.info(
            "java_view_symbol(): symbol = '%s', scopes = '%s', view_clazz = '%s', view_pkg = '%s'" % (symbol, scope, clz.java_classname(view), clz.java_package(view))
        )

        if symbol is not None:
            if syntax == 'java':
                class_name = None
                pkg_name   = None
                pkg_type   = None
                if LiHelper.has_in_scope(view, region.a, 'meta.path.java'):
                    full_class_name = view.substr(view.expand_to_scope(region.a, 'meta.path.java'))
                    i = full_class_name.rfind('.')
                    if i > 0:
                        pkg_name   = full_class_name[0:i]
                        pkg_type   = 'inline'
                        class_name = full_class_name[i + 1:]
                # scope of package declaration
                elif LiHelper.has_in_scope(view, region.a, 'entity.name.class.java'):
                    class_name = view.substr(view.expand_to_scope(region.a, 'entity.name.class.java'))
                # scope of class reference
                elif LiHelper.has_in_scope(view, region.a, 'storage.type.class.java'):
                    class_name = view.substr(view.expand_to_scope(region.a, 'storage.type.class.java'))
                elif LiHelper.has_in_scope(view, region.a, 'entity.other.inherited-class.java'):
                    class_name = view.substr(view.expand_to_scope(region.a, 'entity.other.inherited-class.java'))

                # means the class refers to class definition
                if LiHelper.has_in_scope(view, region.a, 'meta.class.identifier.java'):
                    pkg_name = view.substr(view.expand_to_scope(region.a, 'meta.class.identifier.java'))
                    pkg_type = 'inline'

                if pkg_name is None and class_name is not None:
                    pkg_name, pkg_type = clz.java_detect_class_package(view, class_name);

                LiLog.info("%s.java_view_symbol(): pkgs = '%s', pkg_type = '%s', class_name = '%s', symb = '%s'" % (clz.__name__, pkg_name, pkg_type, class_name, symbol))

                return pkg_name, pkg_type, class_name,
            elif syntax == 'kotlin':
                pass
            else:
                raise "Syntax '%s' is not supported" % syntax
        else:
            return None, None, None

        reg = view.expand_to_scope(region.a, 'meta.path.java')
        if symbol is None:
            return None
        #
        #  Java scopes
        #
        # source.java meta.import.java meta.path.java support.type.package.java:
        #
        # import [abc.cde].ee;

        # source.java meta.import.java meta.path.java support.class.import.java
        #
        # import abc.cde.[ee];

        # source.java meta.import.java keyword.control.import.java
        #
        # [import] abc.cde.ee;

        # source.java meta.class.java meta.class.body.java meta.block.java meta.method.java meta.method.body.java
        # meta.instantiation.java meta.path.java support.class.java
        #
        # new java.util.[HashMap]();

        # source.java meta.class.java meta.class.body.java meta.block.java meta.method.java meta.method.body.java
        # meta.instantiation.java meta.path.java support.type.package.java
        # new java.[util].HashMap();

        pkg_name   = []
        class_name = []
        const_name = []
        parts      = []
                            # source.java meta.namespace.package.identifier.java meta.path.java variable.namespace.java
        pkg_name_scope   = 'support.type.package.java' #
        class_name_scope = [ 'support.class.java', 'support.class.import.java' ]
        const_name_scope = 'constant.other.java'

        if LiHelper.has_in_scope(view, region.a, pkg_name_scope):
            pkg_name.append(symbol);
        elif LiHelper.has_in_scope(view, region.a, class_name_scope):
            class_name.append(symbol);
        elif LiHelper.has_in_scope(view, region.a, const_name_scope):
            const_name.append(symbol)
        elif LiHelper.has_in_scope(view, region.a, 'entity.name.class.java'):
            pkg_name   = clz.java_package(view)[1].split('.')
            class_name = [ symbol ]
        elif LiHelper.has_in_scope(view, region.a, 'entity.other.inherited-class.java'):
            class_name = [ symbol ]

        # lookup back and forward to expand symbol
        for direction in [ False, True ]:
            ps = region.a
            while True:
                ps = view.find_by_class(ps, direction, sublime.CLASS_PUNCTUATION_START)

                if ps >= 0  and view.substr(ps) == '.':
                    ws = view.find_by_class(ps, direction, sublime.CLASS_WORD_START)
                    wr = view.word(ws)

                    if LiHelper.has_in_scope(
                        view, ws,
                        [ 'comment.line.double-slash.java',
                          'variable.function.java',
                          'variable.language.java' ]):
                        break

                    word  = view.substr(wr)

                    index = 0
                    if direction:
                        index = max(len(pkg_name), len(class_name), len(const_name))

                    if LiHelper.has_in_scope(view, ws, pkg_name_scope):
                        pkg_name.insert(index, word)
                    elif LiHelper.has_in_scope(view, ws, class_name_scope):
                        class_name.insert(index, word)
                    elif LiHelper.has_in_scope(view, ws, const_name_scope):
                        const_name.insert(index, word)
                    elif LiHelper.has_in_scope(view, ws, 'entity.name.class.java'):
                        pkg_name   = clz.java_package(view)[1].split('.')
                        class_name = [ word ]
                    elif LiHelper.has_in_scope(view, ws, 'entity.other.inherited-class.java'):
                        class_name = [ word ]

                    if not direction:
                        symbol = word + "." + symbol
                    else:
                        symbol = symbol + "." + word

                    parts.insert(index, word)
                else:
                    break

        if len(class_name) == 0:
            #  Direct reference to a constant:
            #  a = CONSTANT
            if len(const_name) > 0 and len(pkg_name) == 0:
                class_name = [ clz.java_classname(view) ]
                pkg_name   = clz.java_package(view)[1].split('.')
            elif len(parts) > 0:
                class_name = [ parts[len(parts) - 1] ]
            else:
                class_name = [ symbol ]


        if len(pkg_name) == 0 and len(class_name) > 0:
            cn      = None
            imports = clz.java_imports(view)
            if imports is not None and len(imports) > 0:
                for item in class_name:
                    cn = item if cn is None else cn + "." + item

                    find_package = [ x[1] for x in imports if x[1].endswith("." + cn)]

                    if len(find_package) > 0:
                        find_package = find_package[0]
                        find_package = find_package.split(' ')[1].strip()

                        if len(find_package) > len(cn):
                            pkg_name = find_package[0 : len(find_package) - len(cn) - 1]
                            pkg_name = pkg_name.split('.')
                            break

            if len(pkg_name) == 0:
                filename   = view.file_name()
                class_path = os.path.join(os.path.dirname(filename), class_name[0] + ".java")
                if os.path.isfile(class_path):
                    pkg_name = clz.java_package(view)[1].split('.')

        LiLog.debug("%s.java_view_symbol(): pkgs = '%s', class_name = '%s', const = '%s', symb = '%s'" % (clz.__name__, pkg_name, class_name, const_name, symbol))

        pkg_name   = '.'.join(pkg_name)   if len(pkg_name) > 0 else None
        class_name = '.'.join(class_name) if len(class_name) > 0 else None
        const_name = '.'.join(const_name) if len(const_name) > 0 else None

        symbol = '' if pkg_name is None else pkg_name
        if len(symbol) > 0:
            symbol = symbol + "." + class_name
        else:
            symbol = class_name

        if const_name is not None:
            symbol = symbol + "." + const_name

        return symbol, pkg_name, class_name, const_name
