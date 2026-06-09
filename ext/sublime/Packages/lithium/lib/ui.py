import sublime, copy

from .core   import LiLog, LiConfig
from .config import JsonConfig

#
# Output Lithium panel class.
#
class LiOutPanel:
    def __init__(self, win, settings:dict):
        if settings is None:
            raise ValueError('Setting is None')

        if not isinstance(settings, dict):
            raise ValueError('Setting is expected to have dict type')

        self.settings = JsonConfig.from_dict(settings)
        self.selected_location = -1
        self.locations = None
        self.name = self.settings['name']
        self.win = win
        self._re_create_view()

    def _re_create_view(self):
        view = self.win.create_output_panel(self.name)
        view.settings().set("gutter", self.settings.as_bool('gutter', False))
        view.settings().set("font_size", self.settings.as_str('font_size'))
        view.settings().set("line_numbers", self.settings.as_bool('line_numbers', False))
        view.settings().set("scroll_past_end", False)
        view.set_name(self.name)
        view.set_scratch(True)
        view.set_read_only(False)
        view.set_syntax_file(self.settings.as_str('syntax'))
        view.settings().set("color_scheme", "lithium.sublime-color-scheme")
        return view

    def append(self, text, clear_locations = True):
        self.get_view().run_command('append', { 'characters' : text, 'force': True, 'scroll_to_end': True })
        if clear_locations is True:
            self.locations = None
            if self.selected_location >= 0:
                self.select_location(self.selected_location, False)

        return self

    def append_err(self, msg:str):
        return self.append(f"(E) [SUB]  {msg}", False)

    def append_warn(self, msg:str):
        return self.append(f"(W) [SUB]  {msg}", False)

    def append_info(self, msg:str):
        return self.append(f"(I) [SUB]  {msg}", False)

    # go to the given location
    def goto_location(self, index):
        assert index is not None

        loc = self.get_location_at(index)
        if loc is not None:
            self.win.open_file(f"{loc[0]}:{loc[1]}", sublime.ENCODED_POSITION)
            self.get_view().show(loc[3])
            return True
        else:
            return False

    def focus(self):
        self.get_view().window().focus_view(self.get_view())
        return self

    # Parse output view text to detect locations tuples in.
    # Input : view
    # Output: [ (filename, line, description, region), ... ]
    def get_locations(self):
        if self.locations is None:
            self.locations = []
            delim = "<!<*>!>"
            for r in LiConfig.of()["location.patterns"]:
                res     = []
                regions = self.get_view().find_all(r, sublime.IGNORECASE, "\\1" + delim + "\\2" + delim + "\\3", res)
                reg_idx = 0
                for p in res:
                    e = p.split(delim)
                    fn = e[0].strip() # file name
                    ln = e[1].strip() # line
                    ms = e[2].strip() # message
                    LiLog.debug("LiOutPanel.get_locations(): Detected location fn = '{fn}', line = {ln}")
                    self.locations.append([ fn, ln, ms, regions[reg_idx] ])
                    reg_idx = reg_idx + 1

            LiLog.debug(f"LiOutPanel.get_locations() detected locations = {self.locations}")
            return copy.deepcopy(self.locations)
        else:
            return copy.deepcopy(self.locations)

    def detect_sel_location_index(self):
        if self.has_locations() is True:
            regions = self.get_view().sel()
            if regions is not None and len(regions) == 1:
                region = self.get_view().line(regions[0])
                i = 0
                for loc in self.get_locations():
                    if region.contains(loc[3]):
                        return i
                    i = i + 1
        return -1

    def has_locations(self):
        return len(self.get_locations()) > 0

    def get_location_at(self, index):
        assert index is not None

        locations = self.get_locations()
        if len(locations) == 0:
            return None
        else:
            return copy.deepcopy(locations[index])

    def clear(self):
        self._re_create_view()
        if self.selected_location >= 0:
            self.select_location(self.selected_location, False)
        self.locations = None
        return self

    def select_location(self, index, select:bool = True):
        assert index is not None

        if self.has_locations() is True:
            self.selected_location = index
            if select is True:
                self.mark_selected_location()
            else:
                self.unmark_selected_location()
                self.selected_location = -1
            return True
        else:
            return False

    def unmark_selected_location(self):
        if self.selected_location >= 0:
            self.get_view().add_regions(
                "li_locations"
                ,regions = [ self.get_location_at(self.selected_location)[3] ]
                ,flags = sublime.HIDDEN
            )
            return True
        else:
            return False

    def mark_selected_location(self):
        if self.selected_location >= 0:
            self.get_view().add_regions(
                "li_locations"
                ,regions = [ self.get_location_at(self.selected_location)[3] ]
                ,scope   = "invalid"
                ,flags   =  sublime.DRAW_SOLID_UNDERLINE | sublime.DRAW_NO_FILL | sublime.DRAW_NO_OUTLINE
            )
            return True
        else:
            return False

    def window(self):
        return self.win

    def show(self):
        self.win.run_command("show_panel", { "panel": f"output.{self.name}" })
        return self

    def destroy(self):
        self.win.destroy_output_panel(self.name)
        self.win = None
        self.name = None
        self.locations = []

    def get_view(self):
        return self.win.find_output_panel(self.name)

class LiView:
    @classmethod
    def view_to_s(cls, view):
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
        return f"view [ id = '{view.id()}', name = '{view.name()}', winid = {wid}, path = '{name}' ]"

