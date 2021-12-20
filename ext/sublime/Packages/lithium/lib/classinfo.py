
import os, sublime, functools, json

from jinja2 import Environment, FileSystemLoader, select_autoescape

class LiClassInfo:
    TEMPLATES_ENV = Environment(
        loader = FileSystemLoader(os.path.join(os.path.dirname(__file__),'templates')),
        # autoescape = select_autoescape(['html', 'xml'])
    )

    def __init__(self, content):
        assert content is not None

        if isinstance(content, str):
            content = json.loads(content)

        assert isinstance(content, dict)

        self.content = content
        self.filters = {
            "methods": {
                "static"     : True,
                "abstract"   : True,
                "public"     : True,
                "protected"  : True,
                "private"    : True,
                "showParent" : False
            },

            "tabs": {
                "page1": True,
                "page2": False
            }
        }

    def render(self):
        def cmp(a, b):
            l1 = a['level']
            l2 = b['level']
            n1 = a['name']
            n2 = b['name']
            if 'static' in l1 and 'static' not in l2:
                return -1

            if 'static' in l2 and 'static' not in l1:
                return 1

            if 'abstract' in l1 and 'abstract' not in l2:
                return -1

            if 'abstract' in l2 and 'abstract' not in l1:
                return 1

            if n1 == n2:
                return 0

            if n1 < n2:
                return -1

            return 1

        return LiClassInfo.TEMPLATES_ENV.get_template('classInfoTemplate.html').render(
            clazz = self.content,
            #methods = sorted(self.content.get('methods'), key = functools.cmp_to_key(cmp)),
            methods = sorted(self.content.get('methods'), key = functools.cmp_to_key(cmp), reverse = True),
            fields = sorted(self.content.get('fields'), key = functools.cmp_to_key(cmp), reverse = True),
            name = self.content.get('name'),
            filters = self.filters.get('methods'),
            ui = self.filters.get('tabs')
        )

    def show(self, view):
        assert view is not None
        view.show_popup(
            self.render(),
            max_width = 900,
            max_height = 700,
            on_navigate = self.filters_updated
        )
        return self

    def filters_updated(self, f):
        prefix = f[0:f.find(':')]
        key    = f[len(prefix) + 1:len(f)]
        if prefix == "filter":
            methods = self.filters['methods']
            if methods.get(key) is not None:
                methods[key] = not methods[key]
        elif prefix == "ui":
            tabs = self.filters['tabs']
            for k in tabs:
                tabs[k] = False
            tabs[key] = True

        sublime.active_window().active_view().update_popup(self.render())


