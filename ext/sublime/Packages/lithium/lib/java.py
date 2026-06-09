import os, sublime, re

from .core import LiLog, LiHelper


def parse_java_classname(clazz):
    reg_exp = r"(([a-zA-Z][a-zA-Z0-9_]*\.)*)([a-zA-Z][a-zA-Z0-9_$]*)"
    m = re.match(reg_exp, clazz)

    if m is None:
        raise RuntimeError(f"Invalid '{clazz}' class full name")

    pkg = m.group(1)[:-1]
    if pkg is not None and len(pkg) == 0:
        pkg = None

    class_name = m.group(3)
    if class_name is None or len(class_name) == 0:
        raise RuntimeError(f"Class name cannot be detected in '{clazz}'")

    return (pkg, class_name)


class LiJava:
    # retrieve java package and return it
    # @return ( <regions including package keyword>, <package_name> )
    @classmethod
    def java_package(cls, view, syntax:str = 'java'):
        if syntax == 'java':
            expand_scope = 'source.java meta.namespace.package.identifier.java'
            pkg_scopes   = [
                'source.java meta.namespace.package.identifier.java meta.path.java',
                'source.java meta.namespace.package.identifier.java entity.name.namespace.package.java'
            ]

            for pkg_scope in pkg_scopes:
                regs = view.find_by_selector(pkg_scope)
                if regs is not None and len(regs) > 0:
                    return view.expand_to_scope(regs[0].a, expand_scope), view.substr(regs[0])
            return None, None
        elif syntax == 'kotlin':
            regs = view.find_by_selector('source.Kotlin entity.name.package.kotlin')
            if regs is not None and len(regs) > 0:
                pkg = view.substr(regs[0])
                ln  = len(pkg)
                pkg = pkg.strip("\n")
                return sublime.Region(regs[0].a, regs[0].b - ln + len(pkg)), pkg
            else:
                return None, None
        elif syntax == 'scala':
            regs = view.find_by_selector('source.scala meta.namespace.scala entity.name.namespace.header.scala')
            if regs is not None and len(regs) > 0:
                return regs[0], view.substr(regs[0])
            else:
                return None, None
        elif syntax == 'groovy':
            regs = view.find_by_selector('source.groovy meta.package.groovy storage.type.package.groovy')
            if regs is not None and len(regs) > 0:
                return regs[0], view.substr(regs[0])
            else:
                return None, None
        else:
            raise BaseException(f"Syntax '{syntax}' is not supported")

    # retrieve current class name and return it
    # @return  [ class_name, ...]
    @classmethod
    def java_classnames(cls, view, syntax:str = 'java'):
        if syntax == 'java':
            regions = view.find_by_selector("source.java meta.class.identifier.java entity.name.class.java")
        elif syntax == 'kotlin':
            regions = view.find_by_selector("source.Kotlin entity.name.type.class.kotlin")
        elif syntax == 'groovy':
            regions = view.find_by_selector("source.groovy meta.definition.class.groovy entity.name.type.class.groovy")
        elif syntax == 'scala':
            regions = view.find_by_selector('source.scala meta.class.body.scala meta.class.identifier.scala keyword.declaration.class.scala')
        else:
            raise BaseException(f"Syntax '{syntax}' is not supported")

        if regions is None or len(regions) == 0:
            return None
        else:
            return [ view.substr(region) for region in regions ]

    # Collect JAVA imports
    # @return: [ [ region, "<package_name>", isStatic], ... ]
    # "region" points to the whole import line ("import" ... is included)
    @classmethod
    def java_imports(cls, view, syntax:str = 'java'):
        if syntax ==  'java':
            regions = view.find_by_selector("source.java meta.import.java meta.path.java")
            if regions is None or len(regions) == 0:
                return None
            else:
                scope = "source.java meta.import.java"
                res   = []
                for region in regions:
                    expanded_reg = view.expand_to_scope(region.a, scope)
                    import_pkg   = re.sub("\\s\\s+" , " ", view.substr(region)).strip().strip(';')
                    is_static    = re.match(r'^\s*import\s+static\s+', view.substr(expanded_reg)) != None
                    res.append([ expanded_reg, import_pkg, is_static])

                return res
        elif syntax == 'scala':
            regions = view.find_by_selector("source.scala meta.import.scala")
            if regions is None or len(regions) == 0:
                return None
            else:
                res = []
                for region in regions:
                    expanded_reg = view.substr(region)
                    mt = re.match(r"^\s*import\s+([a-zA-Z0-9._]+)", expanded_reg)
                    if mt is not None:
                        import_pkg = mt.group(1)
                        res.append([region, import_pkg, False])
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
                            imports.append([ line_region, mt.group(2), True ])
                        else:
                            imports.append([ line_region, mt.group(2), False ])
                    elif not line.startswith("package"):
                        break

            return imports if len(imports) > 0 else None

    # detect package name by class basing on imports, package
    # @return (package, type)
    @classmethod
    def java_detect_class_package(cls, view, class_name:str, syntax:str = 'java'):
        imports = cls.java_imports(view, syntax)
        if imports is not None and len(imports) > 0:
            find_package = [ x[1] for x in imports if x[1].endswith("." + class_name)]
            if len(find_package) > 0:
                find_package = find_package[0].strip()
                return (find_package[0 : len(find_package) - len(class_name) - 1], 'import')

        fn = os.path.basename(view.file_name())
        fn = fn[0 : fn.rfind('.java')]
        if fn == class_name or os.path.exists(os.path.join(os.path.dirname(view.file_name()), class_name + '.java')):
            return (cls.java_package(view)[1], 'package')
        else:
            return None, None

    # return symbol that includes full dot path
    # @return (symbol, pkg_name, class_name)
    @classmethod
    def java_view_symbol(cls, view, syntax:str = 'java'):
        symbol, region, scope = LiHelper.view_symbol(view)

        LiLog.info(
            f"java_view_symbol(): symbol = '{symbol}', scopes = '{scope}', view_clazz = '{cls.java_classnames(view)}', view_pkg = '{cls.java_package(view)}'"
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
                    pkg_name, pkg_type = cls.java_detect_class_package(view, class_name);

                LiLog.info(f"{cls.__name__}.java_view_symbol(): pkgs = '{pkg_name}', pkg_type = '{pkg_type}', class_name = '{class_name}', symb = '{symbol}'")

                return pkg_name, pkg_type, class_name,
            elif syntax == 'kotlin':
                pass
            else:
                raise BaseException(f"Syntax '{syntax}' is not supported")
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
            pkg_name   = cls.java_package(view)[1].split('.')
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
                        pkg_name   = cls.java_package(view)[1].split('.', syntax)
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
                class_name = cls.java_classnames(view, syntax)
                pkg_name   = cls.java_package(view)[1].split('.', syntax)
            elif len(parts) > 0:
                class_name = [ parts[len(parts) - 1] ]
            else:
                class_name = [ symbol ]


        if len(pkg_name) == 0 and len(class_name) > 0:
            cn      = None
            imports = cls.java_imports(view, syntax)
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
                    pkg_name = cls.java_package(view, syntax)[1].split('.')

        LiLog.debug(f"{cls.__name__}.java_view_symbol(): pkgs = '{pkg_name}', class_name = '{class_name}', const = '{const_name}', symb = '{symbol}'")

        pkg_name   = '.'.join(pkg_name)   if len(pkg_name) > 0 else None
        class_name = '.'.join(class_name) if len(class_name) > 0 else None
        const_name = '.'.join(const_name) if len(const_name) > 0 else None

        symbol = '' if pkg_name is None else pkg_name
        symbol = f"{symbol}.{class_name}" if len(symbol) > 0 else class_name

        if const_name is not None:
            symbol = f"{symbol}.{const_name}"

        return symbol, pkg_name, class_name, const_name
