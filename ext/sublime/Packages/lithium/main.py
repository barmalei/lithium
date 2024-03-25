import sublime, sublime_plugin, subprocess, os, platform, json, re, sys, webbrowser

from itertools      import groupby
from urllib.request import urlopen
from urllib.parse   import quote

LI_MODULES = {
    'core': [ 'LiHelper', 'LiTextCommand', 'LiWindowCommand'] , 'java': [ 'LiJava' ], 'ui': [], 'classinfo': [ 'LiClassInfo']
}

# reload lib modules
import importlib, imp
sys.path.append(os.path.join(os.path.dirname(__file__), 'lib'))
for mod_name in LI_MODULES.keys():
    try:
        importlib.import_module(mod_name)
        importlib.reload(module)
    except AttributeError:
        fp, pathname, description = imp.find_module(mod_name)
        imp.load_module(mod_name, fp, pathname, description)
    globals()[mod_name] = __import__(mod_name, globals(), locals(), LI_MODULES[mod_name])
    for value_name in LI_MODULES[mod_name]:
        globals()[value_name] = getattr(globals()[mod_name], value_name)

OUTPUT_PAN_SET = {}

def OUTPUT(target):
    win = None;
    if isinstance(target, sublime.Window):
        win = target
    elif isinstance(target, sublime.View):
        win = target.window()
    elif isinstance(target, sublime_plugin.WindowCommand):
        win = target.window
    elif isinstance(target, sublime_plugin.TextCommand):
        win = target.view.window()
    else:
        win = sublime.active_window()

    output = OUTPUT_PAN_SET.get(win.id())
    if output is None:
        output = ui.LiOutPanel(win, core.SETTINGS["output_panel"])
        OUTPUT_PAN_SET[win.id()] = output

    return output

class LiEventListener(sublime_plugin.EventListener):
    def on_new_window(self, window):
        pass

    def on_pre_close_window(self, window):
        pass

    def on_pre_close_project(self, window):
        output = OUTPUT_PAN_SET.get(window.id())
        if output is not None:
            output.destroy()
            OUTPUT_PAN_SET.pop(window.id())

        if output is not None:
            core.LiLog.info("Project window '%s' has been closed, destroy lithium output panel" % window.id())
        else:
            core.LiLog.info("Project window '%s' has been closed, no lithium output panel was created for this window" % window.id())

# open POM if it is available for the current project
class LiOpenPomCommand(LiWindowCommand):
    def is_enabled(self, **args):
        return True

    def run(self, **args):
        home, fn = self.home(), None
        if home is not None:
            fn = os.path.join(home, 'pom.xml')

        if home is not None and os.path.exists(fn):
            sublime.active_window().open_file(fn)
        else:
            sublime.error_message("POM file cannot be identified in '%s' home" % home)


class LiOpenLithiumRbCommand(LiWindowCommand):
    def is_enabled(self, **args):
        return True

    def run(self, **args):
        home, fn = self.home(), None
        if home is not None:
            fn = os.path.join(home, '.lithium', 'project.rb')

        if home is not None and os.path.exists(fn):
            sublime.active_window().open_file(fn)
        else:
            sublime.error_message("'.lithium/project.rb' file cannot be identified in '%s' home" % home)


class LiCommand(LiWindowCommand):
    def __init__(self, *args):
        super().__init__(*args)
        self.process = None

    def is_enabled(self, **args):
        return True

    def run(self, **args):
        terminated_process_msg = None

        if self.has_active_process_run():
            self.debug("LiCommand.run(): check if existing active process can be terminated")

            if sublime.ok_cancel_dialog("There is an active process still running. Are you sure you want to terminate it?", "Terminate") is True:
                if self.has_active_process_run():
                    self.process.terminate()
                    terminated_process_msg = "Previous process has been terminated"
                else:
                    sublime.message_dialog("Previous process has been already completed")
                self.process = None
            elif self.has_active_process_run():
                sublime.message_dialog("The new process cannot be started since there is running old process")
                return
        else:
            self.process = None

        # save current edited view if necessary
        active_view = LiHelper.current_view()
        if active_view is not None and active_view.is_dirty():
            active_view.window().run_command('save')

        # fetch command from args list
        command = ""
        if "command" in args:
            command = args["command"]

        self.debug("LiCommand.run(): command = '%s'" % command)

        # detect home folder
        li_home = self.home()

        # collect place holders values in dictionary
        placeholders = {}
        if li_home is None:
            self.warn("LiCommand.run(): project home directory cannot be detected!")
        else:
            hm = li_home
            # wrap with quotas path that contains spaces
            if hm != "\"" and hm.find(" ") > 0:
                hm = "\"" + hm + "\""

            placeholders['home'] = hm
            self.debug("LiCommand.run(): Detected home folder '%s'" % li_home)

        if active_view.file_name() != None:
            fn = active_view.file_name()
            # wrap with quotas path that contains spaces
            if fn[0] != "\"" and fn.find(" ") > 0:
                placeholders['file'] = "\"" + fn + "\""
            else:
                placeholders['file'] = fn

            filename, ext = os.path.splitext(fn)
            if ext is not None and ext != '':
                placeholders['src_ext'] = ext

            if fn is not None and os.path.exists(fn):
                src_folder = LiHelper.detect_host_folder(fn, 'src')

                if src_folder is None:
                    if os.path.isfile(fn):
                        src_home = os.path.join(os.path.dirname(fn), 'src')
                        if os.path.exists(src_home):
                            placeholders['src_home'] = src_home
                        else:
                            placeholders['src_home'] = os.path.dirname(fn)
                    else:
                        placeholders['src_home'] = os.path.join(fn, 'src')
                else:
                    placeholders['src_home'] = os.path.join(src_folder, 'src')

            symb = LiHelper.view_symbol(active_view)[0]
            if symb is not None:
                 placeholders['symbol'] = symb

        # apply placeholders to command line
        try:
            command = command.format(**placeholders)
        except KeyError:
            sublime.error_message("Lithium command '%s' cannot be interpolated with %s" % (command, str(placeholders)))

        try:
            OUTPUT(self).clear()
            if terminated_process_msg is not None:
                OUTPUT(self).append_err(terminated_process_msg)
            OUTPUT(self).show()

            self.process = self.exec(command, self.match_output, self.error_output)
        except Exception as ex:
            self.process = None
            sublime.error_message("Lithium '%s' command execution has failed('%s')" % (command, str(ex)))

    def has_active_process_run(self):
        return self.process is not None and self.process.returncode is None

    def error_output(self, command, err):
        sublime.error_message("Lithium '%s' command execution failed: ('%s')" % (command, str(err)))

    def match_output(self, process, line):
        if line is None:
            self.process = None
        else:
            OUTPUT(self).append(line)

class LiJavaTextCommand(LiTextCommand):
    def enabled_syntaxes(self):
        return ( 'kotlin', 'java', 'scala', 'groovy')

# the command kill comments in Java import sections
class LiSortImportsCommand(LiJavaTextCommand):
    def run(self, edit, **args):
        #  [ [Region, String:<import [static]? [package];>], ... ]
        imports = LiJava.java_imports(self.view)

        if imports is not None:
            imports_str = ""
            groups = self.group_imports(imports)

            for index, group in enumerate(groups):
                if index > 0:
                    imports_str = imports_str + "\n\n"

                import_items = [ "import static %s" % x[1] if x[2] else "import %s" % x[1] for x in group ]
                # for group_item in group
                imports_str = imports_str + ";\n".join(import_items) + ";"

            if len(imports_str) > 0:
                a = imports[0][0].a
                b = self.view.line(imports[len(imports) - 1][0]).b
                self.view.replace(edit, sublime.Region(a, b), imports_str)

    # input: [ [ Region, String ], ... ]
    # output:[ [ group ], [ group ] ]  where group: [ region, String ], [ region, String ] ..,
    def group_imports(self, imports): # return [ [], [], ... ] grouped by package prefix
        # add "a." prefix to key to sort java package first
        imports = sorted(imports, key = lambda x : 'a.' + x[1] if x[1].startswith('java.') or x[1].startswith('javax.') else x[1])
        groups  = []
        for k, g in groupby(imports, lambda x : x[1][:x[1].find('.')] ):
            groups.append(list(g))

        return groups

class LiRemoveUnusedImportsCommand(LiJavaTextCommand):
    re_unused_import = r"\s+([^;:,?!!%^&()|+=></-]+)\.\s+\[UnusedImports\]$"

    def run(self, edit, **args):
        OUTPUT(self).append_info("%s: Remove un-used imports\n" % self.__class__.__name__)

        self.exec(
            "UnusedJavaCheckStyle:\"%s\" " % self.view.file_name(),
            self.match_output,
            self.error_output,
            False
        )

        if self.unused_imports is None or len(self.unused_imports) == 0:
            OUTPUT(self).append_warn("(%s: Unused imports have not been detected\n" % self.__class__.__name__)
        else:
            for imp in reversed(self.unused_imports):
                line = imp[1]
                region = self.view.full_line((self.view.text_point(line - 1, 0)));
                self.view.show(region)
                self.view.erase(edit, region)
                OUTPUT(self).append_warn("%s: Remove unused import '%s' at line %i\n" % ( self.__class__.__name__, imp[0],line))

    def exec(self, *args):
        self.unused_imports = []
        return super().exec(*args)

    def error_output(self, command, err):
        sublime.error_message("Lithium '%s' command execution failed: ('%s')" % (command, str(err)))

    def match_output(self, process, line):
        if line is not None:
            locations = LiHelper.detect_locations(line)
            for loc in locations:
                match = re.search(LiRemoveUnusedImportsCommand.re_unused_import, loc[2])
                if match is not None:
                    self.debug("LiRemoveUnusedImportsCommand.match_output(): matched line = %s, import = '%s'" % (loc[1], match.group(1)))
                    self.unused_imports.append([ match.group(1), int(loc[1]) ])

class LiValidateImportsCommand(LiJavaTextCommand):
    def run(self, edit, **args):
        self.view.run_command("li_remove_unused_imports")
        self.view.run_command("li_sort_imports")

class LiCompleteImportCommand(LiJavaTextCommand):
    def run(self, edit, **args):
        OUTPUT(self).append_info("%s: Completing JAVA import\n" % self.__class__.__name__)

        self.region, self.word = LiHelper.sel_region(self.view)

        if self.region is not None:
            OUTPUT(self).append_info("%s: completing '%s' word\n" % (self.__class__.__name__, self.word))

            if self.word is not None and len(self.word.strip()) > 1:
                # detect home folder
                self.inline = False
                if 'inline' in args:
                    self.inline = args['inline']

                self.auto_apply = False
                if 'auto_apply' in args:
                    self.auto_apply = args['auto_apply']

                # if word is not None and word != '':
                try:
                    self.found_items = []
                    self.edit        = edit
                    self.process     = self.exec(
                        "FindInClasspath:\"%s\" %s.class" % (os.path.join(".env", self.syntax().upper()), self.word),
                        self.match_output,
                        self.error_output,
                        False
                    )
                except Exception as ex:
                    self.process = None
                    sublime.error_message("Lithium command execution has failed('%s')" % ((ex),))

    def match_output(self, process, line):
        # None means end of LI process
        if line is not None:
            rx = r"\[(.*)\s*=>\s*(.*)\]"
            m = re.search(rx, line)
            if m is not None:
                class_name = m.group(2)
                class_name = class_name.replace('/', '.')
                class_name = re.sub('\.class$', '', class_name)
                self.found_items.append(class_name)
        else:
            l = len(self.found_items)
            if l > 20:
                OUTPUT(self).append_warn("Too many variants detected:\n%s" % "\n    ".join(self.found_items))
                sublime.message_dialog("To many variants (more than 20) have been found")
            elif l > 0:
                if l == 1 and self.auto_apply:
                    self.class_name_selected(0)
                else:
                    pkg_name, pkg_type = LiJava.java_detect_class_package(self.view, self.word, self.syntax())

                    self.found_items.sort()
                    found_items = [ e + " (*)" if pkg_name is not None and e.startswith(pkg_name + ".") else e for e in self.found_items ]
                    self.view.show_popup_menu(
                        found_items,
                        self.class_name_selected)
            else:
                OUTPUT(self).append_warn("No class has been found for '%s' word\n" % self.word)
                #sublime.message_dialog("Import '%s' is already declared" % item)

    def class_name_selected(self, index):
        if index >= 0:
            item    = self.found_items[index]
            syntax  = self.syntax()
            imports = LiJava.java_imports(self.view, syntax)
            if imports is not None and next((x[1] for x in imports if x[1].endswith(item)), None) is not None:
                OUTPUT(self).append_warn("%s: Import '%s' is already declared\n" % (self.__class__.__name__,item))
            else:
                scopes = self.view.scope_name(self.region.begin()).strip().split(" ")
                index_to_insert  = 0
                import_to_insert = "import %s" % item

                self.debug("LiCompleteImportCommand.class_name_selected(): detected syntax '%s' " % syntax)

                if self.inline:
                    self.view.replace(self.edit, self.region, item)
                else:
                    # detect a place to insert the import
                    if imports is not None and len(imports) > 0:
                        for imp in imports:
                            cmp_imp = "import %s" % imp[1] if imp[2] is False else "import static %s" % imp[1]
                            if import_to_insert > cmp_imp:
                                index_to_insert = index_to_insert + 1
                            else:
                                break

                    if syntax == 'java':
                        if imports is not None and len(imports) > 0:
                            if index_to_insert >= len(imports):
                                self.view.insert(self.edit, imports[len(imports) - 1][0].b, "\n%s;" % import_to_insert)
                            else:
                                self.view.insert(self.edit, imports[index_to_insert][0].a, "%s;\n" % import_to_insert)
                        elif len(scopes) == 2 and scopes.index('source.java') >= 0 and scopes.index('support.class.java') >= 0:
                            self.view.replace(self.edit, self.region, '%s;' % import_to_insert)
                        else:
                            pkg_reg, pkg_name = LiJava.java_package(self.view, syntax)
                            self.view.insert(self.edit, pkg_reg.b + 1, "\n\n%s;" % import_to_insert)
                    elif syntax == 'kotlin':
                        if imports is not None:
                            self.view.insert(self.edit, imports[0][0].a, "%s\n" % import_to_insert)
                        elif len(scopes) == 1 and scopes.index('source.Kotlin') >= 0:
                            self.view.replace(self.edit, self.region, '%s' % import_to_insert)
                        else:
                            self.view.replace(self.edit, self.region, item)
                    elif syntax == 'scala':
                        if imports is not None:
                            self.view.insert(self.edit, imports[0][0].a, "%s\n" % import_to_insert)
                        elif len(scopes) == 2 and scopes.index('source.scala') >= 0 and scopes.index('support.constant.scala') >= 0:
                            self.view.replace(self.edit, self.region, '%s' % import_to_insert)
                        else:
                            self.view.replace(self.edit, self.region, item)
                    elif syntax == 'groovy':
                        if len(scopes) == 1 and scopes.index('source.groovy') >= 0:
                            self.view.replace(self.edit, self.region, '%s' % import_to_insert)
                        elif imports is not None:
                            self.view.insert(self.edit, imports[0][0].a, "%s\n" % import_to_insert)
                        else:
                            self.view.replace(self.edit, self.region, item)

    def error_output(self, command, err):
        sublime.error_message("Lithium class detection has failed: ('%s')" % (str(err), ))

class LiShowClassMethodsCommand(LiJavaTextCommand):
    filters     = [ True, True, True ]
    filters_map = { 'public': 0, 'static': 1, 'abstract': 2 }
    content     = """
        <html>
            <style>
                div.headerFilter a {
                    text-decoration:none;
                    color: black;
                }
            </style>
            <body style='width:900px;padding:0px;margin:0px;'>
                <div class='headerFilter' style='margin:0px;background-color:sandybrown;color:red;padding:6px;font-weight:bold;font-size:14px;'>
                    %s &nbsp;|&nbsp;
                    <a href='filter:0'>public [%s]</a>
                    <a href='filter:1'>static [%s]</a>
                    <a href='filter:2'>abstract [%s]</a>
                </div>
                <ul>%s</ul>
            </body>
        </html>
    """

    def run(self, edit, **args):
        if "paste" in args:
            region, word = LiHelper.sel_region(self.view)
            if region is not None:
                mt  = re.search(r"([a-zA-Z_][a-zA-Z0-9_]*\s*\([^()]*\))", self.selected_method)
                self.view.insert(edit, region.a, mt.group(1))
            else:
                sublime.error_message("No region has been detected to place ")
        else:
            self.package_name, self.package_type, self.class_name = LiJava.java_view_symbol(self.view)

            if self.package_name is not None:
                self.full_class_name = self.package_name + "." + self.class_name
                self.exec(
                    "LiJavaToolRunner:methods:%s" % self.full_class_name,
                    self.match_output,
                    self.error_output,
                    False, { "std": "none" }
                )

                if len(self.detected_methods) > 0:
                    self.show()
                else:
                    sublime.error_message("No method has been discovered for %s" % self.full_class_name)
            else:
                sublime.error_message("Nothing has been selected")

    def exec(self, *args):
        self.selected_method  = None
        self.detected_methods = []
        return super().exec(*args)

    def selected(self, a):
        pref = 'filter:'
        if a.startswith(pref):
            index = int(a[len(pref):])
            value = LiShowClassMethodsCommand.filters[index]
            LiShowClassMethodsCommand.filters[index] = not value
            self.show()

    def method_name_selected(self, index):
        if index >= 0:
            self.selected_method = self.detected_methods[index]
        else:
            self.selected_method = None

    def match_output(self, process, line):
        if line is not None:
            print(line)
            mt = re.search(r'\{([^\{\}]+)\}', line)
            if mt is not None:
                method = mt.group(1).strip()
                self.detected_methods.append(method)

    def error_output(self, process, err):
        OUTPUT(self).append_err("Unexpected error\n")
        OUTPUT(self).append_err(err)

    def show(self):
        l = len(self.detected_methods)
        if l > 0:
            links       = []
            filters     = LiShowClassMethodsCommand.filters
            filters_map = LiShowClassMethodsCommand.filters_map
            for i in range(l):
                bb = True
                for key in filters_map:
                    value = filters[filters_map[key]]
                    if value == False and self.detected_methods[i].find(key) >= 0:
                        bb = False
                        break;
                if bb:
                    new_item = self.detected_methods[i].replace('<', "&lt;")
                    new_item = new_item.replace('>', "&gt;")
                    links.append("<li><a href='%s'>%s</a></li>" % ('none', new_item))

            marks = [ 'x' if f is True else '-' for f in filters ]
            self.view.show_popup(
                LiShowClassMethodsCommand.content % (self.full_class_name, marks[0], marks[1], marks[2], "\n".join(links)),
                max_width = 1500,
                max_height = 700,
                on_navigate = self.selected
            )
        else:
            self.debug("LiShowClassMethodsCommand.show() : No items have been passed")


class LiGotoClassCommand(LiJavaTextCommand):
    def run(self, edit, **args):
        view = self.view
        if view is None or view.is_auto_complete_visible():
            self.warn("View is not available")
            return

        package, pkg_type, class_name = LiJava.java_view_symbol(view)
        if class_name is None:
            self.warn("Class name cannot be detected")
        else:
            full_class_name = package + "." + class_name if package is not None else class_name
            sublime.active_window().run_command(
                "show_overlay",
                { "overlay": "goto", "show_files" : "true", "text": full_class_name.replace('.', '/') }
            )


class LiShowClassModuleCommand(LiJavaTextCommand):
    content = """
        <html>
            <body style='width:900px;'>
                <div class='headerFilter' style='margin:0px;background-color:sandybrown;color:white;padding:6px;font-size:14px;'>
                    %s
                </div>
                <ul>%s</ul>
            </body>
        </html>
    """

    def run(self, edit, **args):
        if args.get('clazz') is not None:
            word = args.get('clazz')
        else:
            package, pkg_type, class_name = LiJava.java_view_symbol(self.view)

        if package is not None:
            self.full_class_name = package + "." + class_name
            self.exec(
                "LiJavaToolRunner:module:%s" % self.full_class_name, self.match_output, self.error_output, False, { "std": "none" }
            )

            if len(self.detected_modules) > 0:
                self.show()
            else:
                sublime.error_message("No module has been discovered for %s" % self.full_class_name)
        else:
            self.full_class_name = None
            sublime.error_message("Nothing has been selected")

    def exec(self, *args):
        self.detected_modules = []
        return super().exec(*args)

    def match_output(self, process, line):
        if line is not None:
            print(line)
            mt = re.search(r'\[([^\[\]]+) => .*\]', line)
            if mt is not None:
                module = mt.group(1).strip()
                self.detected_modules.append( module )

    def error_output(self, process, err):
        OUTPUT(self).append_err("Unexpected error\n")
        OUTPUT(self).append_err(err)

    def show(self):
        items = [ '<li>%s</li>' % module for module in self.detected_modules ]
        self.view.show_popup(
            LiShowClassModuleCommand.content % (self.full_class_name, "\n".join(items)),
            max_width = 1200,
            max_height = 700,
            on_navigate = None
        )

# show class info
class LiShowClassInfoCommand(LiJavaTextCommand):
    def run(self, edit, **args):
        if args.get('clazz') is not None:
            word = args.get('clazz')
        else:
            pkg, pkg_type, class_name = LiJava.java_view_symbol(self.view)

        if pkg is not None:
            full_class_name = pkg + "." + class_name

            self.exec("LiJavaToolRunner:classInfo:%s" % full_class_name, self.match_output, self.error_output, False, { "std": "none" })
            if len(self.matched_results) > 0:
                LiClassInfo(json.loads(''.join(self.matched_results))).show(self.view)
            else:
                sublime.error_message("No module has been discovered for %s" % full_class_name)
        else:
            sublime.error_message("Class name and package cannot be fetched")

    def exec(self, *args):
        self.matched_flags = []
        self.matched_results = []
        return super().exec(*args)

    def match_output(self, process, line):
        if line is not None:
            if len(self.matched_flags) == 0:
                if line.find("{{{=(") >= 0:
                    self.matched_flags.append(True)
            else:
                if line.find(")=}}}") >= 0:
                    self.matched_flags.pop(0)
                else:
                    print(line)
                    self.matched_results.append(line)

    def error_output(self, process, err):
        OUTPUT(self).append_err("Unexpected error\n")
        OUTPUT(self).append_err(err)


# Show class field value JAVA command
class LiShowClassFieldCommand(LiJavaTextCommand):
    content = """
        <html>
            <body style='width:400px;'>
                <h3>%s</h3>
                <code>
                %s
                </code>
            </body>
        </html>
    """

    def run(self, edit, **args):
        pkg, pkg_type, class_name = LiJava.java_view_symbol(self.view)
        if pkg is not None:
            full_class_name = pkgf + "." + class_name
            self.exec(
                "LiJavaToolRunner:field:%s" % full_class_name, self.match_output, self.error_output, False, { "std": "none" }
            )

            if self.outputText is not None and len(self.outputText) > 0:
                self.outputText = "\n".join(self.outputText)
                self.symbol     = full_class_name

                mt = re.search(r'\{\{\{([^{}]+)\}\}\}', self.outputText, re.MULTILINE)
                if mt is not None:
                    self.detected_field = mt.group(1);
                    self.detected_field = self.detected_field.replace("\n", "<br/>")
                    self.show()
            else:
                sublime.error_message("No field value has been discovered for %s" % full_class_name)
        else:
            sublime.error_message("Nothing has been selected")

    def exec(self, *args):
        self.outputText = []
        return super().exec(*args)

    def match_output(self, process, line):
        if line is not None:
            self.outputText.append(line)

    def error_output(self, process, err):
        OUTPUT(self).append_err("Unexpected error\n")
        OUTPUT(self).append_err(err)

    def show(self):
        self.view.show_popup(
            LiShowClassFieldCommand.content % (self.symbol, self.detected_field),
            max_width = 700,
            max_height = 500,
            on_navigate = None
        )

# Pattern  InputStr.name
class LiShowDocCommand(LiTextCommand):
    def run(self, edit, **args):
        file_name, extension = os.path.splitext(self.view.file_name())
        word                 = args.get('keyword')
        syntax               = args.get('syntax')

        if syntax is None:
            syntax = os.path.basename(self.view.settings().get('syntax'))
            syntax = os.path.splitext(syntax)[0]

        if word is None:
            res = LiHelper.view_symbol(self.view)
            if res is not None:
                word = res[0]

        if word is not None and word != '':
            type = args['type']
            show_immediate = args['show_immediate'] if 'show_immediate' in args else False

            if type == 'solr':
                self.open_solr_doc(syntax, word, show_immediate)
            else:
                self.open_dash_doc(syntax, word)

    def open_link(self, link):
        webbrowser.open(link)

    def open_dash_doc(self, syntax, word):
        prx   = 'doc_servers.dash'
        keys  = self.settings()[prx + '.keys_map.' + syntax, None]
        query = self.settings()[prx + '.' + syntax + '.url', self.settings()[prx + '.*.url']]
        query = query % (','.join(keys), quote(word))

        if platform.system() == 'Windows':
            subprocess.call(['start', query], shell=True)
        elif platform.system() == 'Linux':
            subprocess.call([ '/usr/bin/xdg-open', query ])
        else:
            self.debug("LiShowDocCommand().open_dash_doc(): Open dash '%s'" % query)
            subprocess.call([ '/usr/bin/open', '-g', query ])

    # fetch list of available links to an api doc for the given word  InputStream
    def open_solr_doc(self, syntax, word, show_immediate):
        self.view.set_status('apidoc', '')

        if syntax is not None:
            result = []
            data   = None
            query  = self.settings()['doc_servers.solr.' + syntax + '.url'].format(core = syntax, word = word)

            try:
                with urlopen(query) as response:
                    data = json.loads(response.read().decode('utf-8'))
            except Exception as ex:
                sublime.error_message("Cannot find %s:'%s'(%s)" % (syntax, word, str(ex)))
                return

            for doc in data['response']['docs']:
                path     = os.path.realpath(doc['resourcename'][0])
                basename = os.path.basename(path)
                dirname  = os.path.dirname(path)
                title    = os.path.basename(dirname) + "/" + basename
                result.append("<a style='display:block;' href='file://{path}'>{title}</a>".format(path = path, title = title))

            if len(result) > 0:
                self.view.set_status('apidoc', "'%s' search for '%s'" % (syntax, quote(word)))

                if show_immediate == True:
                    self.open_link("file://" + os.path.realpath(data['response']['docs'][0]['resourcename'][0]))
                else:
                    content = "".join(result)
                    html    = self.settings()['doc_servers.solr.html_template']
                    self.view.show_popup(
                        html % (content,),
                        sublime.HIDE_ON_MOUSE_MOVE_AWAY,
                        max_width  = 400,
                        max_height = 200,
                        on_navigate = self.open_link)

        else:
            self.view.set_status('apidoc', '%s search criteria is empty' % syntax)


class LiShowLocationsCommand(LiTextCommand):
    def run(self, edit, **args):
        tp = args.get('type')

        self.panel = OUTPUT(self)
        if self.panel.has_locations() is True:
            self.panel.unmark_selected_location()
            if tp == 'next':
                self.next()
            elif tp == 'prev':
                self.prev()
            elif tp == 'goto':
                idx = self.panel.detect_sel_location_index()
                if idx >= 0:
                    self.panel.goto_location(idx);
                    self.panel.focus()
                else:
                    sublime.error_message("liGoToLocationCommand.run(): There is no an active view to go")
            else:
                locs = [ ["%s:%s" % (location[0], location[1]), location[2]] for location in self.panel.get_locations() ]
                sublime.active_window().show_quick_panel(
                    locs,
                    self.done,
                    selected_index = self.panel.selected_location,
                    on_highlight = self.selected
                )
        else:
            sublime.error_message("No a location has been detected")

    def done(self, i):
        if i >= 0:
            self.panel.goto_location(i)
        self.panel.unmark_selected_location()

    def next(self):
        index = self.panel.selected_location + 1
        if len(self.panel.get_locations()) <= index:
            index = 0

        if self.panel.select_location(index) is True:
            self.panel.goto_location(index)

    def prev(self):
        index = self.panel.selected_location - 1
        if index < 0:
            index = len(self.panel.get_locations()) - 1

        if self.panel.select_location(index) is True:
            self.panel.goto_location(index)

    def selected(self, i):
        if i >= 0:
            if self.panel.select_location(i):
                self.panel.goto_location(i)
        else:
            self.panel.append_warn("Unknown selected item\n")

# The standard open_file doesn't recognize row and column in file name
# but the window.open_file does it. This command is wrapper around
# window.open_file call
class LiOpenFileCommand(LiWindowCommand):
    def run(self, file):
        self.window.open_file(file, sublime.ENCODED_POSITION)

