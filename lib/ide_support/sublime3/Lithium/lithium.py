import sublime, sublime_plugin, subprocess, threading, functools, os, datetime, io

settings = {
    'path'          : "lithium",
    'output_panel'  : "lithium",
    'output_font_size'  : 11,
    'debug'         : False,
    'std_formatter' : "SublimeStd",
    'output_syntax' : 'Packages/Lithium/lithium.tmLanguage',
    'place_detector': [
        r"\[\[([^\[\]\(\)\{\}\?\!\<\>\^\,\~\`]+)\:([0-9]+)\]\][\:]*(.*)"
    ]
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

def EXEC_LI(command, handler, error_handler):
    def WRITES(process, panel, handler, error_handler):
        #sublime.set_timeout(lambda: self.do_write(text), 1)
        try:
            panel.run_command('append', { 'characters' :  "(INF) Lithium Sublime 3 plugin\n" })
            for line in io.TextIOWrapper(process.stdout, encoding='utf-8', errors='strict'):
                panel.run_command('append', { 'characters' :  line, 'force': True, 'scroll_to_end': True })
                handler(process, panel, line)

            # tell the last lkine has been handled
            process.stdout.close()
            handler(process, panel, None)
        except Exception as ex:
            print(ex)
            error_handler(command, ex)
            
    panel         = LI_PANEL()
    script_path   = settings.get("path")
    std_formatter = settings.get("std_formatter")

    if li_is_debug():
        print("liCommand.run(): subprocess.Popen = " + script_path + " -std=" + std_formatter + " " + command)

    process = subprocess.Popen(script_path + " -std=" + std_formatter + " " + command,
                               shell  = True,
                               stdin  = subprocess.PIPE,
                               stdout = subprocess.PIPE,
                               stderr = subprocess.STDOUT,
                               universal_newlines = False,
                               bufsize = 0)
    threading.Thread(
        target = WRITES,
        #args   = (panel, )
        args   = (process, panel, handler, error_handler)
    ).start()


    sublime.active_window().run_command("show_panel", { "panel": "output.lithium" })
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
        #sreturn self.process is not None and self.process.poll() is None

    def run(self, **args):
        if self.process is not None:
            print("Termenating process")
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
