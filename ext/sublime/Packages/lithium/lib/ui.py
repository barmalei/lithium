
import sublime, copy, core

#
# Output Lithium panel class.
#
class LiOutPanel:
    def __init__(self, win, settings):
        assert settings is not None, 'Settings have not been defined'
        assert isinstance(settings, dict) or isinstance(settings, core.LiConfig), 'Settings type is unexpected'

        if isinstance(settings, core.LiConfig) is not True:
            settings = core.LiConfig(settings)

        self.settings = settings
        self.selected_location = -1
        self.locations = None
        self.name = self.settings['name']
        self.win = win
        self._re_create_view()

    def _re_create_view(self):
        view = self.win.create_output_panel(self.name)
        view.settings().set("gutter", self.settings['gutter', False])
        view.settings().set("font_size", self.settings['font_size'])
        view.settings().set("line_numbers", self.settings['line_numbers', False])
        view.settings().set("scroll_past_end", False)
        view.set_name(self.name)
        view.set_scratch(True)
        view.set_read_only(False)
        view.set_syntax_file(self.settings['syntax'])
        view.settings().set("color_scheme", "lithium.sublime-color-scheme")
        return view

    def append(self, text, clear_locations = True):
        self.get_view().run_command('append', { 'characters' : text, 'force': True, 'scroll_to_end': True })
        if clear_locations is True:
            self.locations = None
            if self.selected_location >= 0:
                self.select_location(self.selected_location, False)

        return self

    def append_err(self, msg):
        return self.append("(E) [SUB]  %s" % msg, False)

    def append_warn(self, msg):
        return self.append("(W) [SUB]  %s" % msg, False)

    def append_info(self, msg):
        return self.append("(I) [SUB]  %s" % msg, False)

    # go to the given location
    def goto_location(self, index):
        assert index is not None

        loc = self.get_location_at(index)
        if loc is not None:
            self.win.open_file("%s:%s" % (loc[0],loc[1]), sublime.ENCODED_POSITION)
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
            for r in core.SETTINGS["location.patterns"]:
                res     = []
                regions = self.get_view().find_all(r, sublime.IGNORECASE, "\\1" + delim + "\\2" + delim + "\\3", res)
                reg_idx = 0
                for p in res:
                    e = p.split(delim)
                    fn = e[0].strip() # file name
                    ln = e[1].strip() # line
                    ms = e[2].strip() # message
                    core.LiLog.debug("LiOutPanel.get_locations(): Detected location fn = '%s', line = %s" % (fn, ln))
                    self.locations.append([ fn, ln, ms, regions[reg_idx] ])
                    reg_idx = reg_idx + 1

            core.LiLog.debug("LiOutPanel.get_locations() detected locations = %s" % self.locations)
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
        self.locations = None
        if self.selected_location >= 0:
            self.select_location(self.selected_location, False)
        return self

    def select_location(self, index, select = True):
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
        self.win.run_command("show_panel", { "panel": "output.%s" % self.name })
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
    def view_to_s(clazz, view):
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

