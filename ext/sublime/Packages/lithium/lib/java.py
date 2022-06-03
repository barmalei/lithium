
import os, sublime, re

from core import LiLog, LiHelper

class LiJava:
    # retrieve java package and return it
    @classmethod
    def java_package(clz, view):
        # old value 'source.java meta.package-declaration.java meta.path.java entity.name.namespace.java' has been
        # updated in sublime 4131
        regs = view.find_by_selector('source.java meta.namespace.package.identifier.java meta.path.java variable.namespace.java')

        if regs is not None and len(regs) > 0:
            return view.substr(regs[0])
        else:
            return None

    # retrieve current class name and return it
    @classmethod
    def java_view_classname(clz, view):
        regions = view.find_by_selector("entity.name.class.java")
        #source.java meta.class.identifier.java entity.name.class.java
        if regions is None or len(regions) == 0:
            return None
        else:
            return view.substr(regions[0])

    # Collect JAVA imports
    # Output: [ [ region, "import <package>"], ... ]
    @classmethod
    def java_view_imports(clz, view, syntax = 'java'):
        # if syntax == 'java':
        #     regions = view.find_by_selector("keyword.control.import.java")
        #     if regions is None or len(regions) == 0:
        #         return None
        #     else:
        #         return [ [ region, re.sub("\s\s+" , " ", view.substr(region)).strip().strip(';') ] for region in regions ]

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
                        imports.append([ line_region, "import static %s" % mt.group(2) ])
                    else:
                        imports.append([ line_region, "import %s" % mt.group(2) ])
                else:
                    if not line.startswith("package"):
                        break

        if len(imports) > 0:
            return imports
        else:
            return None

    # return symbol that includes full dot path
    @classmethod
    def java_view_symbol(clz, view, region = None):
        symbol, region, scope = LiHelper.view_symbol(view, region)

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
            pkg_name   = clz.java_package(view).split('.')
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
                        pkg_name   = clz.java_package(view).split('.')
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
                class_name = [ clz.java_view_classname(view) ]
                pkg_name   = clz.java_package(view).split('.')
            elif len(parts) > 0:
                class_name = [ parts[len(parts) - 1] ]
            else:
                class_name = [ symbol ]


        if len(pkg_name) == 0 and len(class_name) > 0:
            cn      = None
            imports = clz.java_view_imports(view)
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
                    pkg_name = clz.java_package(view).split('.')

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
