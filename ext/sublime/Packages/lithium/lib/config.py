import os, re, json, yaml, copy

from abc import abstractmethod
from typing import Any

from .utils import get_value_by_path


class Config:
    INCLUDE_PATTERN = re.compile(r'^\s*from\s*<(.*)>\s*$')
    VARIABLE_PATTERN = re.compile(r'\$\{([a-zA-Z][a-zA-Z0-9_\-\.]*)\}')

    class NopeValue:
        def __str__(self):
            return '<Nope>'

    def __init__(self, content: str | None = None):
        self._set_content(self.parse(content) if content is not None else {})

    def has_key(self, key: str) -> bool:
        assert key is not None

        value = self._content
        for sub_key in key.split('.'):
            if sub_key not in value:
                return False
            else:
                value = value[sub_key]
        return True

    def as_str(self, key: str, def_value: str | NopeValue = NopeValue()) -> str | None:
        v = self.get(key, def_value)
        return None if v is None else str(v)

    def as_bool(self, key: str, def_value: bool | NopeValue = NopeValue()) -> bool:
        v = self.get(key, def_value)
        if v in ('True', 'true', True):
            return True
        elif v in ('False', 'false', False):
            return False
        else:
            raise ValueError(f'Invalid boolean {v} value')

    def as_int(self, key: str, def_value: int | NopeValue = NopeValue()) -> int:
        v = self.get(key, def_value)
        if v is None:
            raise ValueError('Integer property cannot be None')
        else:
            return int(str(v))

    def as_array(self, key: str, def_value: list | NopeValue = NopeValue()) -> list | None:
        v = self.get(key, def_value)
        if v is None:
            return v
        elif isinstance(v, list):
            return copy.deepcopy(v)
        else:
            raise RuntimeError(f"Invalid '{key}' property list type: '{v.__class__}'")

    def as_dict(self, key: str) -> dict:
        def traverse(d: dict):
            for k, v in d.items():
                if v is not None:
                    if isinstance(v, str):
                        d[k] = self.interpolate(v)
                    elif isinstance(v, dict):
                        d[k] = traverse(v)
                    elif isinstance(v, list):
                        d[k] = [traverse(e) for e in v]
            return d

        value = self.get(key)
        if value is None:
            return {}
        elif not isinstance(value, dict):
            raise RuntimeError(f"Invalid '{key}' property type: '{value.__class__}'")
        else:
            return traverse(copy.deepcopy(value))

    def subprops(self, key: str):
        props = self.__class__()
        props._set_content(self.as_dict(key))
        return props

    def as_obj(self, clz, prefix: str | None = None):
        return (
            clz(**self.subprops(prefix)._get_content())
            if prefix is not None
            else clz(**self._get_content())
        )

    def get(self, key: str, def_value: Any = NopeValue()) -> Any:
        v = None
        try:
            v = self[key]
        except KeyError as e:
            if isinstance(def_value, Config.NopeValue):
                raise e
            else:
                return def_value

        if v is None:
            return None
        elif isinstance(v, str):
            v = self.interpolate(v)
            m = re.match(Config.INCLUDE_PATTERN, v)
            return self.load(m[1].strip()) if m is not None else v
        elif isinstance(v, dict) or isinstance(v, list):
            return copy.deepcopy(v)
        else:
            return v

    def interpolate(self, value, pos=0):
        m = Config.VARIABLE_PATTERN.search(value, pos)
        if m is not None:
            start = m.start()
            end = m.end()
            interpolated_value = self.interpolate_value(m[1])
            if interpolated_value is not None:
                return self.interpolate(
                    value[0:start] + str(interpolated_value) + value[end:],
                    start + len(str(interpolated_value)),
                )
        return value

    def interpolate_value(self, name):
        return self.get(name)

    def update(self, key: str, value: Any):
        raise NotImplementedError()

    def _get_content(self):
        return self._content

    def _set_content(self, content: dict):
        self._content = content

    def __str__(self):
        return str(self._get_content())

    def __getitem__(self, key):
        return get_value_by_path(self._get_content(), key)

    @abstractmethod
    def parse(self, content: str) -> dict:
        raise NotImplementedError()

    @abstractmethod
    def load(self, path: str) -> str:
        raise NotImplementedError()

    @classmethod
    def from_dict(cls, data: dict):
        c = cls()
        c._set_content(copy.deepcopy(data))
        return c

    @classmethod
    def by_path(cls, path: str):
        if path is None or len(path.strip()) == 0:
            raise ValueError('Path to config is empty or None')

        path = path.strip()
        if not os.path.exists(path) or os.path.isdir(path):
            raise IOError(f"Invalid '{path}' configuration path")

        with open(path, 'r') as file:
            return cls(file.read())


class JsonConfig(Config):
    def parse(self, content: str) -> dict:
        return json.loads(content)


class YamlConfig(Config):
    def parse(self, content: str) -> dict:
        return yaml.safe_load(content)

