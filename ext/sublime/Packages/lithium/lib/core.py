
import os, json, sublime_plugin, sublime, io, threading, re, traceback, subprocess, copy, datetime

# path to the lithium settings
LI_SETTINGS_FILE = os.path.join(
    os.path.dirname(os.path.dirname(__file__)),
    'lithium.sublime-settings'
)

class LiConfig:
    """
        Utility configuration class. Helps to load and access JSON formatted file properties.
    """
    def __init__(self, path):
        assert path is not None, 'Empty configuration content'

        if isinstance(path, str) is True:
            assert path is not None and len(path.strip()) > 0
            path = path.strip()

            if not os.path.exists(path) or os.path.isdir(path):
                raise IOError("Invalid '{}' configuration path".format(path))

            self.content = None
            with open(path) as file:
                self.content = json.load(file)
        else:
            self.content = copy.deepcopy(path)

    def __getitem__(self, key):
        assert key is not None

        defValue         = None
        isDefValuePassed = isinstance(key, tuple)
        if isDefValuePassed:
            defValue = key[1]
            key      = key[0]

        value = self.content
        for sub_key in key.split('.'):
            value = value.get(sub_key)
            if value is None and not isDefValuePassed:
                raise AttributeError("Configuration '{}' attribute cannot be found".format(key))
            elif value is None:
                return defValue

        if isinstance(value, dict) or isinstance(value, list):
            return copy.deepcopy(value)
        else:
            return value

# lithium package settings
SETTINGS = LiConfig(LI_SETTINGS_FILE)

# Log API
class LiLog:
    format_str = "[%s] %s"

    @classmethod
    def is_debug(clz):
        return SETTINGS['log.debug', False]

    @classmethod
    def is_warn(clz):
        return SETTINGS['log.warning', True]

    @classmethod
    def is_info(clz):
        return SETTINGS['log.info', True]

    @classmethod
    def debug(clz, msg):
        if clz.is_debug():
            print(clz.format('DEBUG', msg))
            #print(LiLog.format_str % ('DEBUG', msg))

    @classmethod
    def warn(clz, msg):
        if clz.is_warn():
            print(clz.format('WARN', msg))

    @classmethod
    def info(clz, msg):
        if clz.is_info():
            print(LiLog.format('INFO', msg))

    @classmethod
    def format(clz, level, msg):
        return datetime.datetime.now().strftime("%H:%M:%S.%f") + " " + LiLog.format_str % ('INFO', msg)

# various helper methods
class LiHelper:
    # convert scope string to array of scope members
    @classmethod
    def scope_to_array(clz, scope):
        assert scope is not None, 'Passed scope is not defined'
        scopes = scope.split(' ')
        return [item for item in scopes if item != '']

    # test if the scope member is in the given array for the given location
    @classmethod
    def has_in_scope(clz, view, point, scopes):
        assert scopes is not None, 'Passed scopes are not defined'

        if not isinstance(scopes, list):
            scopes = [ scopes ]

        scopes_array = clz.scope_to_array(view.scope_name(point))
        for scope in scopes:
            if scope in scopes_array:
                return True

        return False

    # Parse output text to detect locations tuples in.
    # Input: text
    # Output:  [ (filename, line, description), ... ]
    @classmethod
    def detect_locations(clz, text):
        paths = []
        for r in SETTINGS["location.patterns"]:
            res = re.findall(r, text) # array of (file, line, desc) tuples are expected
            for path in res:
                paths.append(path)
        return paths

    @classmethod
    def current_view(clz):
        if sublime.active_window() is None:
            return None
        else:
            return sublime.active_window().active_view()

    #  return selected region -> (region, <region substr>)
    @classmethod
    def sel_region(clz, view = None):
        if view is None:
            view = clz.current_view()

        if view is not None:
            regions = view.sel()
            if regions is not None and len(regions) == 1:
                region = view.word(regions[0])
                return (region, view.substr(region))

        return (None, None)

    # return current symbol as (symbol, region, scope)
    @classmethod
    def view_symbol(clz, view, region = None):
        if view is not None:
            symb = None
            if region is None:
                region, symb = clz.sel_region(view)
                if region is None:
                    LiLog.debug("%s.view_symbol(): Region is NONE, symbol cannot be detected" % clz.__name__)
                    return None
            else:
                symb = view.substr(region)
                LiLog.debug("%s.view_symbol(): (%s, %s)" % (clz.__name__, symb, view.scope_name(region.begin())))

            return symb, region, view.scope_name(region.begin())

        LiLog.debug("%s.view_symbol(): View is NONE, symbol cannot be detected" % clz.__name__)
        return None

    # Detect lithium project home folder by looking lithium folder up
    # Input: pt is initial path
    # Input: folder_name a folder name to be detected
    # Output: folder that contains folder_name
    @classmethod
    def detect_host_folder(clz, pt, folder_name = ".lithium"):
        LiLog.debug("%s.li_detect_host_folder(): initial path = '%s'" % (clz.__name__, pt))

        if pt != None and os.path.abspath(pt) and os.path.exists(pt):
            if os.path.isfile(pt):
                pt = os.path.dirname(pt)
            cnt = 0
            while pt != '/' and pt != None and cnt < 100:
                if os.path.exists(os.path.join(pt, folder_name)):
                    return pt
                else:
                    pt = os.path.dirname(pt)
                cnt = cnt + 1
        else:
            LiLog.warn("%s.detect_host_folder() invalid initial folder '%s'" % (clz.__name__, pt))

        return None

    # load detected problem
    @classmethod
    def load_problems(clz, path):
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

# lithium stuff
class Lithium:
    # Detect a project home directory
    @classmethod
    def detect_project_home(clz):
        active_view = LiHelper.current_view()

        home = None
        if active_view.file_name() != None:
            home = LiHelper.detect_host_folder(active_view.file_name())

        if home is None:
            folders = active_view.window().folders()
            if len(folders) > 0:
                for folder in folders:
                    home = LiHelper.detect_host_folder(folder)
                    if home != None:
                        break

        if home is not None:
            home = os.path.realpath(home) # resolve sym link to real path

        LiLog.debug("%s.detect_project_home(): home = '%s'" % (clz.__name__, home))
        return home

    # Run lithium command
    @classmethod
    def exec(clz, command, output_handler = None, error_handler = None, run_async = True, options = None):
        assert command is not None and len(command) > 0, 'Command has not been defined'

        script_path = SETTINGS["lithium.command", "lithium"]
        if options is None:
            options = SETTINGS["lithium.opts", {}]

        if 'basedir' not in options:
            bd = clz.detect_project_home()
            if bd is None:
                sublime.error_message("Project home cannot be detected. Check if '.lithium' folder exits in project root folder")
                return
            options['basedir'] = bd

        options_str = ' '.join("-{!s}={!r}".format(key, val) for (key, val) in options.items())

        LiLog.debug("%s.exec(): script_path = '%s', opts = '%s', command = '%s'" % (clz.__name__, script_path , options_str, command))

        # Python 3.3
        process = subprocess.Popen(
            script_path + " " + options_str  + " " + command,
            shell  = True,
            stdin  = subprocess.PIPE,
            stdout = subprocess.PIPE,
            stderr = subprocess.STDOUT,
            universal_newlines = False,
            bufsize = 0
        )

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
                    if output_handler is not None:
                        for line in data.split("\n"):
                            output_handler(process, line)

                    if process.poll() is not None:
                        # notify the process has been completed
                        if output_handler is not None:
                            output_handler(process, None)
                        break
                except Exception as ex:
                    traceback.print_exc()
                    try:
                        if error_handler is not None:
                            error_handler(command, ex)
                    except Exception as ex2:
                        print(ex2)
                    break

        return process


class LiCommandBase:
    def debug(self, msg):
        LiLog.debug(msg)
        return self

    def warn(self, msg):
        LiLog.warn(msg)
        return self

    def info(self, msg):
        LiLog.info(msg)
        return self

    def exec(self, *args):
        return Lithium.exec(*args)

    def settings(self):
        return SETTINGS

    def home(self):
        return Lithium.detect_project_home()


class LiTextCommand(sublime_plugin.TextCommand, LiCommandBase):
    def syntax(self):
        syntax = os.path.basename(self.view.settings().get('syntax'))
        syntax = os.path.splitext(syntax)[0]
        syntax = syntax.lower()
        return syntax

    def is_enabled(self):
        syntaxes = self.enabled_syntaxes()
        syn      = self.syntax()
        return syntaxes is None or len(syntaxes) == 0 or (syn is not None and syn in syntaxes)

    def enabled_syntaxes(self):
        return None

class LiWindowCommand(sublime_plugin.WindowCommand, LiCommandBase):
    pass
