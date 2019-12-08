import sublime, sublime_plugin

import subprocess, threading
import os, io, platform, json, re
import webbrowser

from   urllib.request import urlopen
from   urllib.parse   import quote

# in-line settings
settings = {
    'path'          : "lithium",
    'li_opts'       : "-verbosity=2",
    'output_panel'  : "lithium",
    'output_font_size'  : 11,
    'debug'         : False,
    'std_formatter' : "SublimeStd",
    'output_syntax' : 'Packages/Lithium/lithium.tmLanguage',
    'place_detector': [
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

# detect lithium project home folder by looking lithium folder up
def detect_li_project_home(pt):
    if pt != None and os.path.abspath(pt) and os.path.exists(pt):
        if os.path.isfile(pt):
            pt = os.path.dirname(pt)

        cnt = 0
        while pt != "/" and pt != None and cnt < 100:
            if os.path.exists(os.path.join(pt, ".lithium")):
                return pt
            else:
                pt = os.path.dirname(pt)
            cnt = cnt + 1

    return None

#
# return array that contains list of detected files and lines in the files:
# [ [path, lineNumber ], ...  ]
def li_paths_by_output(view):
    if li_is_debug():
        print("li_paths_by_output() >> ")

    paths = []
    delim = "<!<*>!>"
    place_detector = settings.get('place_detector')
    for r in place_detector:
        res = []
        view.find_all(r, sublime.IGNORECASE, "\\1" + delim + "\\2" + delim + "\\3", res)
        for p in res:
            e = p.split(delim)

            fn = e[0].strip() # file name
            ln = e[1].strip() # line
            ms = e[2].strip() # message

            if li_is_debug():
                print("li_paths_by_output() Detected fn = '" + e[0].strip() + "', line = " + e[1])

            paths.append([ fn, ln, ms ])

    if li_is_debug():
        print("li_paths_by_output() res = " + str(paths))
        print("li_paths_by_output() << ")

    return paths

def li_path_by_region(view, region):
    if region == None:
        return None
    n = view.scope_name(region.a)
    path = [None, "-1"]
    if n:
        n = n.strip()
        if n == u'source.lithium li.path li.path.name':
            nr = view.extract_scope(region.a)
            path[0] = view.substr(nr)
            path[1] = view.substr(view.extract_scope(nr.b + 2))
        elif n == u'source.lithium li.path li.path.line':
            nr = view.extract_scope(region.a)
            path[1] = view.substr(nr)
            path[0] = view.substr(view.extract_scope(nr.a - 2))
    if path[0] == None:
        return None
    return path

def li_show_paths(view, win=None):
    if li_is_debug():
        print("li_show_paths() : Show paths : " + li_view_to_s(view))

    if view != None:
        if win == None:
            win = sublime.active_window()

        paths = li_paths_by_output(view)
        l     = len(paths)

        if l > 0:
            if li_is_debug():
                print("li_show_paths() : number of paths found : " + str(l))
                for i in range(l):
                    path = paths[i]
                    print("li_show_paths() : path[" + str(i) + "] = " + path[0])

            def done(i):
                if i >= 0:
                    win.open_file(paths[i][0] + ":" + paths[i][1], sublime.ENCODED_POSITION)

            win.show_quick_panel([ [ v[0] + ":" + v[1], v[2]] for v in paths], done)
        else:
            if li_is_debug():
                print("li_show_paths() : No paths have been found")

def LI_HOME():
    active_view = sublime.active_window().active_view()

    li_home = None
    if active_view.file_name() != None:
        li_home = detect_li_project_home(active_view.file_name())
    if li_home == None:
        folders = active_view.window().folders()
        if len(folders) > 0:
            for folder in folders:
                li_home = detect_li_project_home(folder)
                if li_home != None:
                    break
    return li_home


def EXEC_LI(command, handler, error_handler, async = True):
    panel         = LI_PANEL()
    script_path   = settings.get("path")
    std_formatter = settings.get("std_formatter")

    if li_is_debug():
        print("liCommand.run(): subprocess.Popen = " + script_path + " -std=" + std_formatter + " " + command)

    process = subprocess.Popen(script_path + " -std=" + std_formatter + " " + settings.get("li_opts") + " " + command,
                               shell  = True,
                               stdin  = subprocess.PIPE,
                               stdout = subprocess.PIPE,
                               stderr = subprocess.STDOUT,
                               universal_newlines = False,
                               bufsize = 0)

    # show lithium output panel
    sublime.active_window().run_command("show_panel", { "panel": "output.lithium" })

    if async:
        def WRITES(process, panel, handler, error_handler):
            try:
                for line in io.TextIOWrapper(process.stdout, encoding='utf-8', errors='strict'):
                    panel.run_command('append', { 'characters' :  line, 'force': True, 'scroll_to_end': True })
                    handler(process, panel, line)

                # tell the last line has been handled
                process.stdout.close()
                handler(process, panel, None)
            except Exception as ex:
                print(ex)
                error_handler(command, ex)


        threading.Thread(
            target = WRITES,
            args   = (process, panel, handler, error_handler)
        ).start()
    else:
        while True:
            data = process.stdout.read().decode('utf-8')
            try:
                panel.run_command('append', { 'characters' :  data, 'force': True, 'scroll_to_end': True })

                for line in data.split("\n"):
                    handler(process, panel, line)

                if process.poll() is not None:
                    # notify the process has been completed
                    handler(process, panel, None)
                    break
            except Exception as ex:
                print(ex)
                try:
                    error_handler(command, ex)
                except Exception as ex2:
                    print(ex2)
                break

    return process


def LI_PANEL():
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
    return panel

class liCommand(sublime_plugin.WindowCommand):
    #panel_lock = threading.Lock()
    process = None

    def is_enabled(self, **args):
        return True
        #return self.process is None
        #return self.process is not None and self.process.poll() is None

    def run(self, **args):
        if self.process is not None:
            print("Terminating process")
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
        li_home = LI_HOME()

        # collect place holders values in dictionary
        placeholders = {}
        if li_home == None:
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
                fn = "\"" + fn + "\""
            placeholders['file'] = fn

        # apply placeholders to command line
        try:
            command = command.format(**placeholders)
        except KeyError:
            sublime.error_message("Lithium command '%s' cannot be interpolated with %s" % (command, str(placeholders)))

        try:
            self.process = EXEC_LI(command, self.output, self.error)
        except Exception as ex:
            self.process = None
            sublime.error_message("Lithium '%s' command execution has failed('%s')" % (command, str(ex)))

    def error(self, command, err):
        sublime.error_message("Lithium '%s' command execution failed: ('%s')" % (command, str(err)))

    def output(self, process, panel, line):
        if line is None:
            self.process = None
        #else:
            # regions = panel.find_by_selector("li.exception")
            # if len(regions) == 0:
            #     regions = panel.find_by_selector("li.error")
            # #if len(regions) > 0:
             #   panel.show_at_center(regions[0])
            #else:
                #panel.show_at_center(panel.size())

class liPrintScopeCommand(sublime_plugin.TextCommand):
    def run(self, edit):
        v = sublime.active_window().active_view()
        n = v.scope_name(v.sel()[0].a)
        print("Scope: " + n)


class liShowClassesCommand(sublime_plugin.TextCommand):
    found_items = []
    edit        = None
    region      = None

    def is_enabled(self):
        syntax = self.syntax()
        return syntax == 'kotlin' or syntax == 'java' or syntax == 'scala' or syntax == 'groovy'

    def syntax(self):
        syntax = os.path.basename(self.view.settings().get('syntax'))
        syntax = os.path.splitext(syntax)[0]
        syntax = syntax.lower()
        return syntax

    def run(self, edit, **args):

        regions = self.view.sel()
        if regions is not None and len(regions) == 1:
            word = None
            for region in regions:
                self.region = self.view.word(region) # get extended to the current word region
                word = self.view.substr(self.region)

            if word is not None and len(word.strip()) > 1:
                # detect home folder
                li_home = LI_HOME()

                self.pattern = "%s"
                if 'pattern' in args:
                    self.pattern = args['pattern']

                self.auto_apply = False
                if 'auto_apply' in args:
                    self.auto_apply = args['auto_apply']

                # if word is not None and word != '':
                try:
                    self.found_items = []
                    self.edit        = edit
                    self.process     = EXEC_LI("FindClassInClasspath:\"%s\" %s.class" % (li_home, word), self.output, self.error, False)
                except Exception as ex:
                    self.process = None
                    sublime.error_message("Lithium command execution has failed('%s')" % ((ex),))

    def output(self, process, panel, line):
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
                sublime.message_dialog("To many variants (more than 20) have been found ")
            elif l > 0:
                if l == 1 and self.auto_apply:
                    #print("Scope name: " + self.region.)
                    self.class_name_selected(0)
                else:
                    self.found_items.sort(),
                    self.view.show_popup_menu(
                        self.found_items,
                        self.class_name_selected)

    def class_name_selected(self, index):
        if index >= 0:
            item = self.found_items[index]

            sn = self.view.scope_name(self.region.begin())
            sn = sn.strip()
            scopes = sn.split(" ")

            syntax = self.syntax()

            print("SYN = " + syntax)
            if syntax == 'java':
                if len(scopes) == 2 and scopes.index('source.java') >= 0 and scopes.index('support.class.java') >= 0:
                    item = 'import %s;' % item
            elif syntax == 'kotlin':
                if len(scopes) == 1 and scopes.index('source.Kotlin') >= 0:
                    item = 'import %s' % item
            elif syntax == 'scala':
                if len(scopes) == 2 and scopes.index('source.scala') >= 0 and scopes.index('support.constant.scala') >= 0:
                    item = 'import %s' % item
            elif syntax == 'groovy':
                if len(scopes) == 1 and scopes.index('source.groovy') >= 0:
                    item = 'import %s' % item

            self.view.replace(self.edit, self.region, item)

    def error(self, command, err):
        sublime.error_message("Lithium class detection has failed: ('%s')" % (str(err), ))

# Pattern  InputStream
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
            print("Call dash %s" % query)
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

class liGoCommand(sublime_plugin.TextCommand):
    def run(self, edit):
        li_active_output_view = sublime.active_window().find_output_panel(settings.get('output_panel'))

        if li_is_debug():
            print("liGoCommand.run() : GO to text command : " + li_view_to_s(li_active_output_view))

        if li_active_output_view is not None:
            if li_is_debug():
                print("liGoCommand.run(): found active output : " + li_view_to_s(li_active_output_view))

            rset = li_active_output_view.sel()
            if len(rset) > 0:
                p = li_path_by_region(li_active_output_view, rset[0])
                if p == None:
                    if li_is_debug():
                        print("liGoCommand.run() : No path to go was found")
                    li_show_paths(li_active_output_view)
                else:
                    if li_is_debug():
                        print("liGoCommand.run() : Path to go was found " + p[0])
                    view = li_active_output_view.window().open_file(p[0] + ":" + p[1], sublime.ENCODED_POSITION)
                    li_active_output_view.window().focus_view(view)
        else:
            # global li_output_view
            if li_is_debug():
                print("liGoCommand.run() : No active view was found")

class liShowPathsCommand(sublime_plugin.TextCommand):
    def run(self, edit):
        li_active_output_view = sublime.active_window().find_output_panel(settings.get('output_panel'))

        if li_is_debug():
            print("liShowPathsCommand.run() : Show paths : " + li_view_to_s(li_active_output_view))

        if li_active_output_view is not None:
            li_show_paths(li_active_output_view)
