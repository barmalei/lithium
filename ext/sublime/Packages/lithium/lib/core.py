import os, json, sublime_plugin, sublime, io, threading, re, traceback, subprocess, datetime


from .config import JsonConfig, Config

class LiConfig(JsonConfig):
    li_config: Config | None = None

    @classmethod
    def of(cls) -> Config:
        if cls.li_config is None:
            path = os.path.join(
                os.path.dirname(os.path.dirname(__file__)),
                'lithium.sublime-settings'
            )
            # don't use log to avoid recursion
            print(f"Loading lithium plugin configuration from '{path}' file")
            cls.li_config = cls.by_path(path)
        return cls.li_config

# Log API
class LiLog:
    format_str = "[%s] %s"

    @classmethod
    def is_debug(cls) -> bool:
        return LiConfig.of().as_bool('log.debug', False)

    @classmethod
    def is_warn(cls) -> bool:
        return LiConfig.of().as_bool('log.warning', True)

    @classmethod
    def is_info(cls) -> bool:
        return LiConfig.of().as_bool('log.info', True)

    @classmethod
    def debug(cls, msg:str):
        if cls.is_debug():
            print(cls.format('DEBUG', msg))

    @classmethod
    def warn(cls, msg:str):
        if cls.is_warn():
            print(cls.format('WARN', msg))

    @classmethod
    def info(cls, msg:str):
        if cls.is_info():
            print(LiLog.format('INFO', msg))

    @classmethod
    def format(cls, level:str, msg:str):
        return datetime.datetime.now().strftime("%H:%M:%S.%f") + " " + LiLog.format_str % (level, msg)

# various helper methods
class LiHelper:
    # convert scope string to array of scope members
    @classmethod
    def scope_to_array(cls, scope):
        assert scope is not None, 'Passed scope is not defined'
        scopes = scope.split(' ')
        return [item for item in scopes if item != '']

    # test if the scope member is in the given array for the given location
    @classmethod
    def has_in_scope(cls, view, point, scopes):
        assert scopes is not None, 'Passed scopes are not defined'

        if not isinstance(scopes, list):
            scopes = [ scopes ]

        scopes_array = cls.scope_to_array(view.scope_name(point))
        for scope in scopes:
            if scope in scopes_array:
                return True

        return False

    # Parse output text to detect locations tuples in.
    # Input: text
    # Output:  [ (filename, line, description), ... ]
    @classmethod
    def detect_locations(cls, text):
        paths = []
        for r in LiConfig.of()["location.patterns"]:
            res = re.findall(r, text) # array of (file, line, desc) tuples are expected
            for path in res:
                paths.append(path)
        return paths

    @classmethod
    def current_view(cls):
        if sublime.active_window() is None:
            return None
        else:
            return sublime.active_window().active_view()

    #  return selected region -> (region, <region substr>)
    @classmethod
    def sel_region(cls, view = None):
        if view is None:
            view = cls.current_view()

        if view is not None:
            regions = view.sel()
            if regions is not None and len(regions) == 1:
                region = view.word(regions[0])
                return (region, view.substr(region))

        return (None, None)

    # return current symbol as (symbol, region, scope)
    @classmethod
    def view_symbol(cls, view, region = None):
        if view is not None:
            symb = None
            if region is None:
                region, symb = cls.sel_region(view)
                if region is None:
                    LiLog.debug(f"{cls.__name__}.view_symbol(): Region is NONE, symbol cannot be detected")
                    return None
            else:
                symb = view.substr(region)
                LiLog.debug(f"{cls.__name__}.view_symbol(): ({symb}, {view.scope_name(region.begin())})")

            return symb, region, view.scope_name(region.begin())

        LiLog.debug(f"{cls.__name__}.view_symbol(): View is NONE, symbol cannot be detected")
        return None

    # Detect lithium project home folder by looking lithium folder up
    # Input: pt is initial path
    # Input: folder_name a folder name to be detected
    # Output: folder that contains folder_name
    @classmethod
    def detect_host_folder(cls, pt, folder_name = ".lithium"):
        LiLog.debug(f"{cls.__name__}.li_detect_host_folder(): initial path = '{pt}'")

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
            LiLog.warn(f"{cls.__name__}.detect_host_folder() invalid initial folder '{pt}'")

        return None

    # load detected problem
    @classmethod
    def load_problems(cls, path):
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
                            status = 'W'

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
    def detect_project_home(cls) -> str | None:
        active_view = LiHelper.current_view()

        home = LiHelper.detect_host_folder(active_view.file_name()) if active_view.file_name() != None else None
        if home is None:
            folders = active_view.window().folders()
            if len(folders) > 0:
                for folder in folders:
                    home = LiHelper.detect_host_folder(folder)
                    if home != None:
                        break

        if home is not None:
            home = os.path.realpath(home) # resolve sym link to real path

        LiLog.debug(f"{cls.__name__}.detect_project_home(): home = '{home}'")
        return home

    # Run lithium command
    @classmethod
    def exec(cls, command, output_handler = None, error_handler = None, run_async = True, options:dict = None):
        assert command is not None and len(command) > 0, 'Command has not been defined'

        script_path = LiConfig.of().as_str("lithium.command", "lithium")
        script_path = os.path.expanduser(script_path)
        if options is None:
            options = LiConfig.of().get("lithium.opts", {})

        if 'basedir' not in options:
            bd = cls.detect_project_home()
            if bd is None:
                sublime.error_message("Project home cannot be detected. Check if '.lithium' folder exits in project root folder")
                return
            options['basedir'] = bd

        options_str = ' '.join("-{!s}={!r}".format(key, val) for (key, val) in options.items())

        LiLog.debug(f"{cls.__name__}.exec(): script_path = '{script_path}', opts = '{options_str}', command = '{command}' , run_async = {run_async}")

        process = subprocess.Popen( #
            #[script_path , options_str, command],
            f"{script_path} {options_str} {command}",
            shell  = True,
            stdin  = subprocess.PIPE,
            stdout = subprocess.PIPE,
            stderr = subprocess.STDOUT,
            universal_newlines = False,
            bufsize = 1
        )

        # process = subprocess.run( #
        #     #[script_path , options_str, command],
        #     f"{script_path} {options_str} {command}",
        #     shell  = True,
        #     stdin  = subprocess.PIPE,
        #     stdout = subprocess.PIPE,
        #     stderr = subprocess.STDOUT,
        #     universal_newlines = False,
        #     bufsize = 0
        # )


        if run_async:
            LiLog.debug("Run process as async one")

            def WRITES(process, output_handler, error_handler):
                try:
                    for line in io.TextIOWrapper(process.stdout, encoding = 'utf-8', errors='strict'):
                        if output_handler is not None:
                            output_handler(process, line)

                    # outs, errs = process.communicate()
                    # for line in outs.split("\n"):
                    #     if output_handler is not None:
                    #         output_handler(process, line + "\n")

                    # if errs is not None:
                    #     for line in errs.split("\n"):
                    #         if output_handler is not None:
                    #             output_handler(process, line + "\n")

                    # tell the last line has been handled
                    process.stdout.close()
                    if output_handler is not None:
                        output_handler(process, None)
                except Exception as ex:
                    traceback.print_exception(ex)
                    if error_handler is not None:
                        error_handler(command, ex)

            threading.Thread(
                target = WRITES,
                args   = (process, output_handler, error_handler)
            ).start()
        else:
            LiLog.debug("Run process as blocking one")

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
                        traceback.print_exception(ex2)
                    break

        return process


class LiCommandBase:
    def debug(self, msg:str):
        LiLog.debug(msg)
        return self

    def warn(self, msg:str):
        LiLog.warn(msg)
        return self

    def info(self, msg:str):
        LiLog.info(msg)
        return self

    def exec(self, *args):
        return Lithium.exec(*args)

    def settings(self) -> Config:
        return LiConfig.of()

    def symbol(self):
        return LiHelper.view_symbol(self.view)[0]

    def home(self) -> str | None:
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
