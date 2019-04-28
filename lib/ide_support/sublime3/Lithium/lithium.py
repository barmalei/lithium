
import sublime, sublime_plugin, subprocess, threading, functools, os, datetime

li_debug = True
li_active_output_view = None
li_output_views = {}

# reg exp to detect path to files
# TODO: has to be corrected to use unified output provided with
# lithium
place_detector = [
    r"\[\[([^\[\]\(\)\{\}\?\!\<\>\^\,\~\`]+)\:([0-9]+)\]\][\:]*(.*)",       # JAVA error and JAVA exception
  #  r"\[WARN\]\s+([^\[\]\:\(\)\{\}\?\!\<\>\^\,\~\`]+)\:\s*([0-9]+)\:\s*[0-9]+\:\s*(.*)"     # JAVA style sheet
  #  r"\(ERR\)\s+\?\s+js\:\s*\"([^\[\]\:\(\)\{\}\?\!\<\>\^\,\~\`]+)\",\s+line\s+([0-9]+)",  # JS
  #  r"\(ERR\)\s+\?\s+([^\[\]\:\(\)\{\}\?\!\<\>\^\,\~\`]+)\:\s+([0-9]+)\:"                  # GROOVY
]

li_path = "ruby Z:/projects/.lithium/lib/lithium.rb"

def  li_is_debug():
    global li_is_debug
    return li_debug

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
# return array that contains list of detected files and lines if the files:
# [ [path, lineNumber ], ...  ]
def li_paths_by_output(view):
    if li_is_debug():
        print("li_paths_by_output() >> ")

    paths = []
    delim = "<!<*>!>"
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

        win.run_command("show_panel", {"panel": "output.lithium"})

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
                    print("li_show_paths.done() " + str(i)+ ", " + paths[i][0] + "," + paths[i][1])
                    win.open_file(paths[i][0] + ":" + paths[i][1], sublime.ENCODED_POSITION)

            win.show_quick_panel([ [ v[0] + ":" + v[1], v[2]] for v in paths], done)
        else:
            if li_is_debug():
                print("li_show_paths() : No paths have been found")


class liCommand(sublime_plugin.TextCommand):
    def get_view(self):
        if not hasattr(self, "current_view"):
            self.current_view = sublime.active_window().active_view()
        return self.current_view

    def run(self, edit, **args):
        # save current edited view if necessary
        if self.get_view().is_dirty():
            self.get_view().window().run_command('save')

        if li_is_debug():
            print("liCommand.run(): self = " + str(self))

        # fetch command from args list
        self.command = ""
        if "command" in args:
            self.command = args["command"]

        view = self.get_view()
        if li_is_debug():
            print("liCommand.run(): command = " + self.command + "," + li_view_to_s(view))

        # detect home folder
        li_home = None
        if view.file_name() != None:
            li_home = detect_li_project_home(view.file_name())
        if li_home == None:
            folders = self.get_view().window().folders()
            if len(folders) > 0:
                for folder in folders:
                    li_home = detect_li_project_home(folder)
                    if li_home != None:
                        break

        placeholders = {}

        if li_home == None:
            if li_is_debug():
                print("liCommand.run(): project home directory cannot be detected")
        else:
            placeholders['home'] = li_home
            if li_is_debug():
                print("liCommand.run(): Detected home folder " + str(li_home))

        if view.file_name() != None:
            placeholders['file'] = view.file_name()

        try:
            self.command = self.command.format(**placeholders)
        except KeyError:
            sublime.error_message("Lithium command '" + str(self.command) + "' cannot be interpolated with " + str(placeholders))

        if li_is_debug():
            print("liCommand.run(): subprocess.Popen = " + "lithium -std=SublimeStd " + self.command)

        # run command as a subprocess
        process = subprocess.Popen(li_path + " -std=SublimeStd " + self.command, shell=True, stdout = subprocess.PIPE)

        # read the started process output and print it in put buffer
        while True:
            line = stdout.read()
            self.output(line.strip(), edit)
            if process.poll() is not None:
                return process.returncode

    def output(self, value, edit, panel_name="lithium"):
        if not hasattr(self, 'output_panel'):
            self.output_panel = self.get_view().window().get_output_panel(panel_name)
            if li_is_debug():
                print("liCommand.output(): create output view: " + li_view_to_s(self.output_panel))
        else:
            if li_is_debug():
                print("liCommand.output(): created view has been found: " + li_view_to_s(self.output_panel))

        panel = self.output_panel
        panel.settings().set("gutter", False)
        panel.settings().set("font_size", 12)
        panel.set_name("lithium")
        panel.set_scratch(True)
        panel.set_read_only(False)
        panel.set_syntax_file('Packages/Lithium/lithium.tmLanguage')

        if li_is_debug():
            print("liCommand.output(): setup output view panel content: " + li_view_to_s(panel))

        #edit = panel.begin_edit() // sublime 2
        panel.erase(edit, sublime.Region(0, panel.size()))
        panel.insert(edit, panel.size(), str(datetime.datetime.today()) + "  ")
        panel.insert(edit, panel.size(), "'" + self.command + "'\n")
        panel.insert(edit, panel.size(), value.decode('utf-8'))
        #panel.end_edit(edit) //sublime 2

        panel.set_read_only(True)
        if li_is_debug():
            print("liCommand.output(): show output view panel: " + li_view_to_s(panel))

        self.get_view().window().run_command("show_panel", {"panel": "output." + panel_name})

        regions = panel.find_by_selector("li.exception")
        if len(regions) == 0:
            regions = panel.find_by_selector("li.error")
        if len(regions) > 0:
            panel.show_at_center(regions[0])
        else:
            panel.show_at_center(panel.size())

        # stick output panel to edited file window
        global li_output_views
        wid = self.get_view().window().id()
        li_output_views[wid] = panel


class liPrintScopeCommand(sublime_plugin.TextCommand):
    def run(self, edit):
        v = sublime.active_window().active_view()
        n = v.scope_name(v.sel()[0].a)
        print("Scope: " + n)


class LiEventListener(sublime_plugin.EventListener):
    def on_close(self, view):
        if li_is_debug():
            print("LiEventListener.on_close() : " + li_view_to_s(view))

    def on_activated(self, view):
        if li_is_debug():
            print("LiEventListener.on_activated() : " + li_view_to_s(view))
        if view.name() == 'lithium':
            global li_active_output_view
            li_active_output_view = view

    def on_deactivated(self, view):
        if li_is_debug():
            print("LiEventListener.on_deactivated() : " + li_view_to_s(view))
        global li_active_output_view
        li_active_output_view = None


class liGoCommand(sublime_plugin.TextCommand):
    def run(self, edit):
        global li_active_output_view

        if li_is_debug():
            print("liGoCommand.run() : GO to text command : " + li_view_to_s(li_active_output_view))

        if li_active_output_view != None:
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
            # li_show_paths(li_output_view)


class liShowPathsCommand(sublime_plugin.TextCommand):
    def run(self, edit):
        global li_active_output_view
        if li_is_debug():
            print("liShowPathsCommand.run() : Show paths : " + li_view_to_s(li_active_output_view))
        if li_active_output_view != None:
            li_show_paths(li_active_output_view)
        else:
            if li_is_debug():
                print("liShowPathsCommand.run() : cannot find activate 'lithium' view")

            wid = sublime.active_window().id()
            global li_output_views
            if wid in li_output_views:
                v = li_output_views[wid]
                if li_is_debug():
                    print("liShowPathsCommand.run() : Found 'lithium' " + li_view_to_s(v) + " by win id = " + str(wid))
                li_show_paths(v, sublime.active_window())


