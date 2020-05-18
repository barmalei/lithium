import sublime, sublime_plugin

import subprocess, threading
import os, io, platform, json, re, sys, json
import webbrowser
from itertools import groupby

from datetime import datetime

from   urllib.request import urlopen
from   urllib.parse   import quote

# in-line settings
settings = {
    'path'          : "ruby /Users/brigadir/projects/.lithium/lib/lithium.rb",
    'li_opts'       : { "verbosity" : "2",  "std": "SublimeStd"},
    'output_panel'  : "lithium",
    'output_error_panel'  : "lithium_errors",
    'output_font_size'  : 11,
    'debug'         : False,
    'output_syntax' : 'Packages/Lithium/lithium.tmLanguage',
    'place_detectors': [
        r"\[\[([^\[\]\(\)\{\}\?\!\<\>\^\,\~\`]+)\:([0-9]+)\]\][\:]*(.*)"
    ],

    'doc_servers' : {
        'dash': {
            '*' : {
                'url': 'dash-plugin://keys=%s&query=%s'
            },

            # copied from Dash plug-in
            "keys_map": {
              "ActionScript"          : ["actionscript"],
              "Boo"                   : ["unity3d"],
              "C"                     : ["c", "glib", "gl2", "gl3", "gl4", "manpages"],
              "C99"                   : ["c", "glib", "gl2", "gl3", "gl4", "manpages"],
              "C++"                   : ["cpp", "net", "boost", "qt", "cvcpp", "cocos2dx", "c", "manpages"],
              "C++11"                 : ["cpp", "net", "boost", "qt", "cvcpp", "cocos2dx", "c", "manpages"],
              "Clojure"               : ["clojure"],
              "CoffeeScript"          : ["coffee"],
              "ColdFusion"            : ["cf"],
              "CSS"                   : ["css", "bootstrap", "foundation", "less", "awesome", "cordova", "phonegap"],
              "Dart"                  : ["dartlang", "polymerdart", "angulardart"],
              "Elixir"                : ["elixir"],
              "Erlang"                : ["erlang"],
              "Go"                    : ["go", "godoc"],
              "GoSublime"             : ["go", "godoc"],
              "GoSublime-Go"          : ["go", "godoc"],
              "Groovy"                : ["groovy"],
              "Haskell"               : ["haskell"],
              "Haskell-SublimeHaskell": ["haskell"],
              "Literate Haskell"      : ["haskell"],
              "HTML"                  : ["html", "svg", "css", "bootstrap", "foundation", "awesome", "statamic", "javascript", "jquery", "jqueryui", "jquerym", "angularjs", "backbone", "marionette", "meteor", "moo", "prototype", "ember", "lodash", "underscore", "sencha", "extjs", "knockout", "zepto", "cordova", "phonegap", "yui"],
              "Jade"                  : ["jade"],
              "Java"                  : ["java", "javafx", "grails", "groovy", "playjava", "spring", "cvj", "processing", "javadoc"],
              "JavaScript"            : ["javascript", "jquery", "jqueryui", "jquerym", "angularjs", "backbone", "marionette", "meteor", "sproutcore", "moo", "prototype", "bootstrap", "foundation", "lodash", "underscore", "ember", "sencha", "extjs", "knockout", "zepto", "yui", "d3", "svg", "dojo", "coffee", "nodejs", "express", "mongoose", "moment", "require", "awsjs", "jasmine", "sinon", "grunt", "chai", "html", "css", "cordova", "phonegap", "unity3d", "titanium"],
              "Kotlin"                : ["kotlin"],
              "Less"                  : ["less"],
              "Lisp"                  : ["lisp"],
              "Lua"                   : ["lua", "corona"],
              "Markdown"              : ["markdown"],
              "MultiMarkdown"         : ["markdown"],
              "Objective-C"           : ["iphoneos", "macosx", "appledoc", "cocos2d", "cocos3d", "kobold2d", "sparrow", "cocoapods", "c", "manpages"],
              "Objective-C++"         : ["cpp", "iphoneos", "macosx", "appledoc", "cocos2d", "cocos2dx", "cocos3d", "kobold2d", "sparrow", "cocoapods", "c", "manpages"],
              "Objective-J"           : ["cappucino"],
              "OCaml"                 : ["ocaml"],
              "Perl"                  : ["perl", "manpages"],
              "PHP"                   : ["php", "wordpress", "drupal", "zend", "laravel", "yii", "joomla", "ee", "codeigniter", "cakephp", "phpunit", "symfony", "typo3", "twig", "smarty", "phpp", "html", "statamic", "mysql", "sqlite", "mongodb", "psql", "redis"],
              "Processing"            : ["processing"],
              "Puppet"                : ["puppet"],
              "Python"                : ["python", "django", "twisted", "sphinx", "flask", "tornado", "sqlalchemy", "numpy", "scipy", "salt", "cvp"],
              "R"                     : ["r"],
              "Ruby"                  : ["ruby", "rubygems", "rails"],
              "Ruby on Rails"         : ["ruby", "rubygems", "rails"],
              "(HTML) Rails"          : ["ruby", "rubygems", "rails", "html", "svg", "css", "bootstrap", "foundation", "awesome", "statamic", "javascript", "jquery", "jqueryui", "jquerym", "angularjs", "backbone", "marionette", "meteor", "moo", "prototype", "ember", "lodash", "underscore", "sencha", "extjs", "knockout", "zepto", "cordova", "phonegap", "yui"],
              "(JavaScript) Rails"    : ["ruby", "rubygems", "rails", "javascript", "jquery", "jqueryui", "jquerym", "angularjs", "backbone", "marionette", "meteor", "sproutcore", "moo", "prototype", "bootstrap", "foundation", "lodash", "underscore", "ember", "sencha", "extjs", "knockout", "zepto", "yui", "d3", "svg", "dojo", "coffee", "nodejs", "express", "mongoose", "moment", "require", "awsjs", "jasmine", "sinon", "grunt", "chai", "html", "css", "cordova", "phonegap", "unity3d"],
              "(SQL) Rails"           : ["ruby", "rubygems", "rails"],
              "Ruby Haml"             : ["haml"],
              "Rust"                  : ["rust"],
              "Sass"                  : ["sass", "compass", "bourbon", "neat", "css"],
              "Scala"                 : ["scala", "akka", "playscala", "scaladoc"],
              "Shell-Unix-Generic"    : ["bash", "manpages"],
              "SQL"                   : ["mysql", "sqlite", "psql"],
              "TCL"                   : ["tcl"],
              "TSS"                   : ["titanium"],
              "TypeScript"            : ["typescript", "javascript", "react", "nodejs", "jquery", "jqueryui", "jquerym", "angularjs", "backbone", "marionette", "meteor", "sproutcore", "moo", "prototype", "bootstrap", "foundation", "lodash", "underscore", "ember", "sencha", "extjs", "knockout", "zepto", "yui", "d3", "svg", "dojo", "express", "mongoose", "moment", "require", "awsjs", "jasmine", "sinon", "grunt", "chai", "html", "css", "cordova", "phonegap", "unity3d", "titanium"],
              "YAML"                  : ["yaml"],
              "XML"                   : ["xml", "titanium"]
            }
        },

        'solr':  {
            'Java' : {
                'url' : 'http://localhost:8983/solr/{core}/select?q=id:*/{word}*'
            },

            'Python' : {
                'url' : 'http://localhost:8983/solr/{core}/select?q={word}%20AND%20id:*.html'
            },

            'Ruby' : {
                'url' : 'http://localhost:8983/solr/{core}/select?q=id:*/{word}.html'
            },

            'JavaScript' : {
                'url' : 'http://localhost:8983/solr/{core}/select?q=id:*/{word}*'
            },

            'html_template' : """
            <style>
            body {
                margin: 4px;
            }
            div {
                width: 400px;
            }
            </style>
            <body>
            <div>
            %s
            </div>
            </body>
            """
        }
    }
}

def li_is_debug():
    return settings.get('debug')

# DEBUG: convert view to its string representation
def  li_view_to_s(view):
    if view == None:
        return "view is [ NONE ]"
    name = view.file_name()
    if name == None:
        name = "NONE"
    win = view.window()
    if win == None:
        wid = "NONE"
    else:
        wid = win.id()
    return "view [ id = " + str(view.id()) + ", name = '" + view.name() + "', winid = " + str(wid) + ", path = " + name + "]"

# Detect lithium project home folder by looking lithium folder up
# Input: pt is initial path
# Input: folder_name a folder name to be detected
# Output: folder that contains folder_name
def li_detect_host_folder(pt, folder_name = ".lithium"):
    if pt != None and os.path.abspath(pt) and os.path.exists(pt):
        if os.path.isfile(pt):
            pt = os.path.dirname(pt)

        cnt = 0
        while pt != "/" and pt != None and cnt < 100:
            if os.path.exists(os.path.join(pt, folder_name)):
                return pt
            else:
                pt = os.path.dirname(pt)
            cnt = cnt + 1

    return None

# Return lithium output view.
# Output: lithium output view
def li_output_view():
    return sublime.active_window().find_output_panel(settings.get('output_panel'))

def li_output_error_view():
    return sublime.active_window().find_output_panel(settings.get('output_error_panel'))

# Append text to output view
# Input: text, view (optional)
def li_append_output_view(text, view = None):
    if view is None:
        view = li_output_view()
    view.run_command('append', { 'characters' :  text, 'force': True, 'scroll_to_end': True })

def li_append_output_error_view(text, view = None):
    if view is None:
        view = li_output_error_view()
    view.run_command('append', { 'characters' :  text, 'force': True, 'scroll_to_end': True })

# Parse output view text to detect locations tuples in.
# Input : view
# Output: [ (filename, line, description), ... ]
def li_parse_output_view(view = None):
    if li_is_debug():
        print("li_parse_output_view() >> ")

    if view is None:
        view = li_output_view()

    paths = []
    delim = "<!<*>!>"
    place_detectors = settings.get('place_detectors')
    for r in place_detectors:
        res = []
        view.find_all(r, sublime.IGNORECASE, "\\1" + delim + "\\2" + delim + "\\3", res)
        for p in res:
            e = p.split(delim)

            fn = e[0].strip() # file name
            ln = e[1].strip() # line
            ms = e[2].strip() # message

            if li_is_debug():
                print("li_parse_output_view() Detected fn = '" + e[0].strip() + "', line = " + e[1])

            paths.append([ fn, ln, ms ])

    if li_is_debug():
        print("li_parse_output_view() res = " + str(paths))
        print("li_parse_output_view() << ")

    return paths

# Parse output text to detect locations tuples in.
# Input: text
# Output:  [ (filename, line, description), ... ]
def li_parse_output(text):
    place_detectors = settings.get('place_detectors')
    paths = []
    for r in place_detectors:
        res = re.findall(r, text) # array of (file, line, desc) tuples are expected
        for path in res:
            paths.append(path)
    return paths

# load deteceted problem
def li_load_problems(path):
    data = []
    with open(path) as file:
        data = json.load(file)
        for entity in data:
            if 'file' in entity:
                ac = entity['artifactClass']

                status = 'I'
                if 'level' in entity:
                    if entity['level'] == 'error':
                        status = 'E'
                    elif entity['level'] == 'warning':
                        status = 'E'

                msg = ''
                if 'message' in entity:
                    msg = entity['message']

                line = '1'
                if 'line' in entity:
                    line = entity['line']

                fp = entity['file']

                #msg = "(%s) [%s] [[%s:%s]]\n(%s) [%s] %s\n" % (status, ac, fp, line, status, ac, msg)
                data.append([ file, line, msg ])
    return data


# Detect place(s) by output view region
def li_parse_output_region(view, region):
    if view is None:
        view = li_output_view()

    if region is None:
        return None
    else:
        line   = view.substr(view.line(region))
        places = li_parse_output(line)

        if li_is_debug():
            print("li_parse_output_region(): detected places = %s" % str(places))

        return places

# Show items
# Input: array of items
def li_show_items(items, done = None):
    l = len(items)
    if l > 0:
        if li_is_debug():
            print("li_show_items() : number of items to be shown: " + str(l))
            for i in range(l):
                item = items[i]
                print("li_show_items() : item[" + str(i) + "] = " + str(item))

        sublime.active_window().show_quick_panel(items, done)
    else:
        if li_is_debug():
            print("li_show_items() : No items have been passed")

# show textual message
def li_show_message(msg):
    sublime.message_dialog(msg)

# Detect project home directory
def li_project_home():
    active_view = sublime.active_window().active_view()

    home = None
    if active_view.file_name() != None:
        home = li_detect_host_folder(active_view.file_name())

    if home is None:
        folders = active_view.window().folders()
        if len(folders) > 0:
            for folder in folders:
                home = li_detect_host_folder(folder)
                if home != None:
                    break

    if home is not None:
        home = os.path.realpath(home) # resolve sym link to real path

    if li_is_debug():
        print("li_project_home(): detected home '%s'" % home)

    return home

# Run lithium command
def li_run(command, output_handler = None, error_handler = None, run_async = True, options = None):
    script_path = settings.get("path")

    if options is None:
        options = dict(settings.get("li_opts")) # ctreate a copy of the object

    if 'basedir' not in options:
        options['basedir'] = li_project_home()

    options_str = ' '.join("-{!s}={!r}".format(key, val) for (key, val) in options.items())

    if li_is_debug():
        print("liCommand.run(): subprocess.Popen = " + script_path + ", opts = " + options_str + ", command = " + command)

    # Python 3.3
    process = subprocess.Popen(script_path + " " + options_str  + " " + command ,
                               shell  = True,
                               stdin  = subprocess.PIPE,
                               stdout = subprocess.PIPE,
                               stderr = subprocess.STDOUT,
                               universal_newlines = False,
                               bufsize = 0)

    # TODO: re-work to python 3.8
    # process = subprocess.run( [script_path , options_str, command],
    #                            shell  = True,
    #                            capture_output = False,
    #                            stdin  = subprocess.PIPE,
    #                            stdout = subprocess.PIPE,
    #                            stderr = subprocess.STDOUT,
    #                            encoding ='utf-8'.
    #                            universal_newlines = False,
    #                            bufsize = 0)

    # show lithium output panel
    # TODO: ???
    sublime.active_window().run_command("show_panel", { "panel": "output.lithium" })

    if run_async:
        def WRITES(process, output_handler, error_handler):
            try:
                for line in io.TextIOWrapper(process.stdout, encoding='utf-8', errors='strict'):
                    if output_handler is not None:
                        output_handler(process, line)

                # tell the last line has been handled
                process.stdout.close()
                if output_handler is not None:
                    output_handler(process, None)
            except Exception as ex:
                print(ex)
                if error_handler is not None:
                    error_handler(command, ex)

        threading.Thread(
            target = WRITES,
            args   = (process, output_handler, error_handler)
        ).start()
    else:
        while True:
            data = process.stdout.read().decode('utf-8')
            try:
                # TODO: ???
                # if panel is not None:
                #     panel.run_command('append', { 'characters' :  data, 'force': True, 'scroll_to_end': True })

                if output_handler is not None:
                    for line in data.split("\n"):
                        output_handler(process, line)

                if process.poll() is not None:
                    # notify the process has been completed
                    if output_handler is not None:
                        output_handler(process, None)
                    break
            except Exception as ex:
                print(ex)
                try:
                    if error_handler is not None:
                        output_error_handler(command, ex)
                except Exception as ex2:
                    print(ex2)
                break

    return process


def li_init_output_view():
    name  = settings.get('output_panel')
    panel = sublime.active_window().create_output_panel(name)

    panel.settings().set("gutter", False)
    panel.settings().set("font_size", settings.get('output_font_size'))
    panel.settings().set("line_numbers", False)
    panel.settings().set("scroll_past_end", False)
    panel.set_name(name)
    panel.set_scratch(True)
    panel.set_read_only(False)
    panel.set_syntax_file(settings.get('output_syntax'))
    panel.settings().set("color_scheme", "lithium.sublime-color-scheme")

    if li_is_debug():
        print("li_init_output_view(): panel = " + str(panel))

    return panel

def li_init_output_error_view():
    name  = settings.get('output_error_panel')
    panel = sublime.active_window().create_output_panel(name)
    panel.settings().set("gutter", False)
    panel.settings().set("font_size", settings.get('output_font_size'))
    panel.settings().set("line_numbers", False)
    panel.settings().set("scroll_past_end", False)
    panel.set_name(name)
    panel.set_scratch(True)
    panel.set_read_only(False)
    panel.set_syntax_file(settings.get('output_syntax'))

    if li_is_debug():
        print("li_init_output_error_view(): panel = " + str(panel))

    return panel

# return string
def java_package(view):
    regs = view.find_by_selector('source.java meta.package-declaration.java meta.path.java entity.name.namespace.java')
    if regs is not None and len(regs) > 0:
        return view.substr(regs[0])
    return None


# Collect imports
# Output: [ [ region, "import <package>"], ... ]
def java_collect_imports(view, syntax = 'java'):
    # if syntax == 'java':
    #     regions = view.find_by_selector("meta.import.java")
    #     if regions is None or len(regions) == 0:
    #         return None
    #     else:
    #         return [ [ region, re.sub("\s\s+" , " ", view.substr(region)).strip().strip(';') ] for region in regions ]
    # else:
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
                if (idx == 0):
                    continue
                line = line[0:idx]

            if line.startswith("//"):
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

# output: [ [ String:import, int:line ] ]
def java_detect_unused_imports(view):
    try:
        paths = []
        def collect(process, line):
            if line is not None:
                res = li_parse_output(line)
                for r in res:
                    paths.append(r)

        li_run("UnusedJavaCheckStyle:\"%s\" " % view.file_name(), collect, None, False)

        if li_is_debug():
            print("java_detect_unused_imports(): detected paths %s" % str(paths))

        re_unused_import = r"\s+([^;:,?!!%^&()|+=></-]+)\s+\[UnusedImports\]$"
        res = []
        for path in paths:
            match = re.search(re_unused_import, path[2])
            if match is not None:
               res.append([ match.group(1), int(path[1]) ])

        if li_is_debug():
            print("java_detect_unused_imports(): detected unused imports %s" % str(res))

        return res
    except Exception as ex:
        sublime.error_message("Lithium command execution has failed('%s')" % ((ex),))


def java_collect_methods(view, symbol):
    imports = java_collect_imports(view)
    detected_package = [ x[1] for x in imports if x[1].endswith("." + symbol)]
    if len(detected_package) > 0:
        symbol = detected_package[0].split(' ')[1]

    methods = []
    def output(process, line):
        if line is not None:
            print(line)
        if line is not None:
            mt = re.search(r'\{([^\{\}]+)\}', line)
            if mt is not None:
                method   = mt.group(1).strip()
                th_index = method.find(' throws ')
                # if th_index > 0:
                #     methods.append(method[0:th_index] + "\n" + method[th_index:])
                # else:
                methods.append( method )

    def error(process, err):
        print("Unexpected error")
        print(err)

    pkg_name = java_package(view)
    if pkg_name is None or symbol.find('.') > 0:
        li_run("ShowClassMethods:%s" % symbol, output, error, False, { "std": "none" })
    else:
        li_run("ShowClassMethods:%s %s" % (symbol, pkg_name), output, error, False, { "std": "none" })

    return methods

class liCommand(sublime_plugin.WindowCommand):
    #panel_lock = threading.Lock()
    process = None
    err_panel = None
    std_entities_path = None

    def is_enabled(self, **args):
        return True
        #return self.process is None
        #return self.process is not None and self.process.poll() is None

    def run(self, **args):
        if self.process is not None:
            print("liCommand(): terminating process")
            self.process.terminate()
            return

        # save current edited view if necessary
        active_view = sublime.active_window().active_view()
        if active_view is not None and active_view.is_dirty():
            active_view.window().run_command('save')

        if li_is_debug():
            print("liCommand.run(): self = " + str(self))

        # fetch command from args list
        command = ""
        if "command" in args:
            command = args["command"]

        if li_is_debug():
            print("liCommand.run(): command = " + command + "," + li_view_to_s(active_view))

        # detect home folder
        li_home = li_project_home()

        # collect place holders values in dictionary
        placeholders = {}
        if li_home is None:
            if li_is_debug():
                print("liCommand.run(): project home directory cannot be detected")
        else:
            hm = li_home
            # wrap with quotas path that contains spaces
            if hm != "\"" and hm.find(" ") > 0:
                hm = "\"" + hm + "\""

            placeholders['home'] = hm
            if li_is_debug():
                print("liCommand.run(): Detected home folder " + str(li_home))

        if active_view.file_name() != None:
            fn = active_view.file_name()
            # wrap with quotas path that contains spaces
            if fn[0] != "\"" and fn.find(" ") > 0:
                placeholders['file'] = "\"" + fn + "\""
            else:
                placeholders['file'] = fn

            if fn is not None and os.path.exists(fn):
                src_folder = li_detect_host_folder(fn, 'src')
                if src_folder is None:
                    placeholders['src_home'] = os.path.join(fn, 'src')
                else:
                    placeholders['src_home'] = os.path.join(src_folder, 'src')

        # apply placeholders to command line
        try:
            command = command.format(**placeholders)
        except KeyError:
            sublime.error_message("Lithium command '%s' cannot be interpolated with %s" % (command, str(placeholders)))

        self.std_entities_path = None
        if li_home is not None:
            self.std_entities_path = os.path.join(li_home, '.lithium', 'std-out-entities.json')
        try:
            if self.std_entities_path is not None and os.path.exists(self.std_entities_path):
                os.remove(self.std_entities_path)
            
            self.panel     = li_init_output_view()
            self.err_panel = li_init_output_error_view()
            self.process   = li_run(command, self.output, self.error)
        except Exception as ex:
            self.process = None
            sublime.error_message("Lithium '%s' command execution has failed('%s')" % (command, str(ex)))

    def error(self, command, err):
        sublime.error_message("Lithium '%s' command execution failed: ('%s')" % (command, str(err)))

    def output(self, process, line):
        if line is None:
            self.process = None
            self.panel = None
            if self.std_entities_path is not None and os.path.exists(self.std_entities_path):
                li_load_problems(self.std_entities_path)
            self.std_entities_path = None
        else:
            li_append_output_view(line, self.panel)

        #else:
            # regions = panel.find_by_selector("li.exception")
            # if len(regions) == 0:
            #     regions = panel.find_by_selector("li.error")
            # #if len(regions) > 0:
             #   panel.show_at_center(regions[0])
            #else:
                #panel.show_at_center(panel.size())

class liTextCommand(sublime_plugin.TextCommand):
    def syntax(self):
        syntax = os.path.basename(self.view.settings().get('syntax'))
        syntax = os.path.splitext(syntax)[0]
        syntax = syntax.lower()
        return syntax

    def is_enabled(self):
        syntaxes = self.enabled_syntaxes()
        if syntaxes is None or len(syntaxes) == 0:
            return True

        syn = self.syntax()
        return syn is not None and syn in syntaxes

    def enabled_syntaxes(self):
        return None

class  liJavaTextCommand(liTextCommand):
    def enabled_syntaxes(self):
        return ( 'kotlin', 'java', 'scala', 'groovy' )

# the command kill comments in Java import sections
class liSortImportsCommand(liJavaTextCommand):
    def run(self, edit, **args):
        #  [ [Region, String:<import [static]? [package];>], ... ]
        imports = java_collect_imports(self.view)

        if imports is not None:
            imports_str = ""
            groups = self.group_imports(imports)

            for index, group in enumerate(groups):
                if index > 0:
                    imports_str = imports_str + "\n\n"

                import_items = [ x[1] for x in group ]
                # for group_item in group
                imports_str = imports_str + ";\n".join(import_items) + ";"

            if len(imports_str) > 0:
                # more gentle clean, but it preserves empty lines between imports
                # for import_item in reversed(imports):
                #     new_reg = self.view.line(import_item[0])
                #     new_reg.b = new_reg.b + 1
                #     self.view.erase(edit, new_reg)

                a = imports[0][0].a
                b = self.view.line(imports[len(imports) - 1][0]).b
                self.view.replace(edit, sublime.Region(a, b), imports_str)

    # input: [ [ Region, String ], ... ]
    # output:[ [ group ], [ group ] ]  where group: [ region, String ], [ region, String ] ..,
    def group_imports(self, imports): # return [ [], [], ... ] grouped by package prefix
        imports = sorted(imports, key = lambda x : x[1])
        groups  = []
        for k, g in groupby(imports, lambda x : x[1][:x[1].rfind('.')] ):
            groups.append(list(g))

        return groups

class liRemoveUnusedImportsCommand(liJavaTextCommand):
    def run(self, edit, **args):
        li_append_output_view("(I) [SUB]  %s: Remove un-used imports\n" % self.__class__.__name__)
        # [ [ String:imp, int:line ] ]
        imports = java_detect_unused_imports(self.view)

        if imports is None or len(imports) == 0:
            li_append_output_view("(W) [SUB]  %s: Un-used imports have not been detected\n" % self.__class__.__name__)

        for imp in reversed(imports):
            line = imp[1]
            region = self.view.full_line((self.view.text_point(line - 1, 0)));
            self.view.show(region)
            self.view.erase(edit, region)
            li_append_output_view("(W) [SUB]  %s: Remove unused import '%s' at line %i\n" % ( self.__class__.__name__, imp[0],line))

class liValidateImportsCommand(liJavaTextCommand):
    def run(self, edit, **args):
        self.view.run_command("li_remove_unused_imports")
        self.view.run_command("li_sort_imports")

class liCompleteImportCommand(liJavaTextCommand):
    found_items = []
    edit        = None
    region      = None
    word        = None

    def run(self, edit, **args):
        li_append_output_view("(I) [SUB]  %s: Completing JAVA import\n" % self.__class__.__name__)

        regions = self.view.sel()
        if regions is not None and len(regions) == 1:
            word = None
            for region in regions:
                self.region = self.view.word(region) # get extended to the current word region
                self.word = self.view.substr(self.region)

            li_append_output_view("(I) [SUB]  %s: completing '%s' word\n" % (self.__class__.__name__,self.word))

            if self.word is not None and len(self.word.strip()) > 1:
                # detect home folder
                li_home = li_project_home()

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
                    self.process     = li_run("FindClassInClasspath:\"%s\" %s.class" % (li_home, self.word), self.output, self.error, False)

                except Exception as ex:
                    self.process = None
                    sublime.error_message("Lithium command execution has failed('%s')" % ((ex),))

    def output(self, process, line):
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
                sublime.message_dialog("To many variants (more than 20) have been found")
            elif l > 0:
                if l == 1 and self.auto_apply:
                    self.class_name_selected(0)
                else:
                    self.found_items.sort(),
                    self.view.show_popup_menu(
                        self.found_items,
                        self.class_name_selected)
            else:
                li_append_output_view("(W) [SUB]  No class has been found for '%s' word" % self.word)
                #sublime.message_dialog("Import '%s' is already declared" % item)


    def class_name_selected(self, index):
        if index >= 0:
            item    = self.found_items[index]
            syntax  = self.syntax()
            imports = java_collect_imports(self.view, syntax)
            if imports is not None and next((x[1] for x in imports if x[1].endswith(item)), None) is not None:
                li_append_output_view("(W) [SUB]  %s: Import '%s' is already declared\n" % (self.__class__.__name__,item))
            else:
                scopes = self.view.scope_name(self.region.begin()).strip().split(" ")

                if li_is_debug():
                    print("liCompleteImportCommand.class_name_selected(): detected syntax '%s' " % syntax)

                if self.inline:
                    self.view.replace(self.edit, self.region, item)
                else:
                    if syntax == 'java':
                        if imports is not None:
                            self.view.insert(self.edit, imports[0][0].a, "import %s;\n" % item)
                        elif len(scopes) == 2 and scopes.index('source.java') >= 0 and scopes.index('support.class.java') >= 0:
                            self.view.replace(self.edit, self.region, 'import %s;' % item)
                        else:
                            self.view.replace(self.edit, self.region, item)
                    elif syntax == 'kotlin':
                        if imports is not None:
                            self.view.insert(self.edit, imports[0][0].a, "import %s\n" % item)
                        elif len(scopes) == 1 and scopes.index('source.Kotlin') >= 0:
                            self.view.replace(self.edit, self.region, 'import %s' % item)
                        else:
                            self.view.replace(self.edit, self.region, item)
                    elif syntax == 'scala':
                        if imports is not None:
                            self.view.insert(self.edit, imports[0][0].a, "import %s\n" % item)
                        elif len(scopes) == 2 and scopes.index('source.scala') >= 0 and scopes.index('support.constant.scala') >= 0:
                            self.view.replace(self.edit, self.region, 'import %s' % item)
                        else:
                            self.view.replace(self.edit, self.region, item)
                    elif syntax == 'groovy':
                        if len(scopes) == 1 and scopes.index('source.groovy') >= 0:
                            self.view.replace(self.edit, self.region, 'import %s' % item)
                        elif imports is not None:
                            self.view.insert(self.edit, imports[0][0].a, "import %s\n" % item)
                        else:
                            self.view.replace(self.edit, self.region, item)

    def error(self, command, err):
        sublime.error_message("Lithium class detection has failed: ('%s')" % (str(err), ))

class liShowClassMethodsCommand(liJavaTextCommand):
    detected_methods = []
    selected_method  = None

    def run(self, edit, **args):
        if "paste" in args:
            regions = self.view.sel()
            if len(regions) > 0:
                region = regions[0]
                word   = self.view.substr(self.view.word(region))
                mt     = re.search(r"([a-zA-Z_][a-zA-Z0-9_]*\s*\([^()]*\))", self.selected_method)
                self.view.insert(edit, region.a, mt.group(1))
            else:
                li_show_message("No region has been detected to place ")
        else:
            word   = None
            for region in self.view.sel():
                word = self.view.substr(self.view.word(region))
                break

            if word is not None and word != '':
                self.detected_methods = []
                self.selected_method = None

                self.detected_methods = java_collect_methods(self.view, word)
                if len(self.detected_methods) > 0:
                    li_show_items(self.detected_methods, self.method_name_selected)
                else:
                    li_show_message("No method has been discovered for %s" % word)
            else:
                li_show_message("Nothing has been selected")

    def method_name_selected(self, index):
        if index >= 0:
            self.selected_method = self.detected_methods[index]
        else:
            self.selected_method = None


# Pattern  InputStr.aeam
class liShowDocCommand(sublime_plugin.TextCommand):
    def run(self, edit, **args):
        file_name, extension = os.path.splitext(self.view.file_name())
        word                 = None
        syntax               = os.path.basename(self.view.settings().get('syntax'))
        syntax               = os.path.splitext(syntax)[0]

        for region in self.view.sel():
            word = self.view.substr(self.view.word(region))
            break

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
        dash_settings = settings.get('doc_servers')['dash']
        keys_map      = settings.get('doc_servers')['dash']['keys_map']
        keys          = keys_map[syntax] if syntax in keys_map else None
        query         = dash_settings.get(syntax)['url'] if syntax in dash_settings else dash_settings['*']['url']
        query         = query % (','.join(keys), quote(word))

        if platform.system() == 'Windows':
            subprocess.call(['start', query], shell=True)
        elif platform.system() == 'Linux':
            subprocess.call([ '/usr/bin/xdg-open', query ])
        else:
            print("liShowDocCommand(): Open dash %s" % query)
            subprocess.call([ '/usr/bin/open', '-g', query ])

    # fetch list of available links to an api doc for the given word  InputStream
    def open_solr_doc(self, syntax, word, show_immediate):
        self.view.set_status('apidoc', '')

        if syntax is not None:
            result = []
            data   = None
            query  = settings['doc_servers']['solr'][syntax]['url'].format(core = syntax, word = word)

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
                    html    = settings['doc_servers']['solr']['html_template']
                    self.view.show_popup(
                        html % (content,),
                        sublime.HIDE_ON_MOUSE_MOVE_AWAY,
                        max_width  = 400,
                        max_height = 200,
                        on_navigate = self.open_link)

        else:
            self.view.set_status('apidoc', '%s search criteria is empty' % syntax)

class liShowLocationsCommand(sublime_plugin.TextCommand):
    locations = []

    def run(self, edit):
        self.locations = li_parse_output_view()

        if len(self.locations) > 0:
            locs = [ ["%s:%s" % (location[0], location[1]), location[2]] for location in self.locations ]
            li_show_items(locs, self.done)
        else:
            li_show_message("No locations have been detected ")

    def done(self, i):
        if i >= 0:
            self.go_to_location(self.locations[i])

    def go_to_location(self, loc):
        if loc is not None:
            win = sublime.active_window()
            win.open_file(loc[0] + ":" + loc[1], sublime.ENCODED_POSITION)
        else:
            li_show_message("No location has been passed")


class liGoToLocationCommand(liShowLocationsCommand):
    def run(self, edit):
        pan_name = sublime.active_window().active_panel()
        panel    = None
        if pan_name == 'output.' + settings.get('output_panel'):
            panel = li_output_view()
        elif pan_name == 'output.' + settings.get('output_error_panel'):
            panel = panel = li_output_error_view()

        if li_is_debug():
            print("liGoToLocationCommand.run() : GO to text command : " + li_view_to_s(panel))

        if panel is not None:
            if li_is_debug():
                print("liGoToLocationCommand.run(): found active output : " + li_view_to_s(panel))

            rset = panel.sel()
            if len(rset) > 0:
                p = li_parse_output_region(panel, rset[0])
                if p == None or len(p) == 0:
                    if li_is_debug():
                        print("liGoToLocationCommand.run() : Path to go could not be detected")

                    super().run(edit)
                else:
                    if li_is_debug():
                        print("liGoToLocationCommand.run() : Path to go was found " + str(p))

                    self.go_to_location(p[0])
                    panel.window().focus_view(view)
        else:
            if li_is_debug():
                print("liGoToLocationCommand.run() : No active view was found")
