import re
import functools
import time
import math

from typing import Any, Mapping, Callable


def get_value_by_path(value: dict, key: str, sep: str = '.'):
    if key is None:
        raise ValueError('Key cannot be None')

    for sub_key in key.split(sep):
        if sub_key in value:
            value = value[sub_key]
        else:
            raise KeyError(f"'{key}' doesn't point to an attribute")

    return value


def set_value_by_path(value: dict, key: str, updater: Callable[[str, Any], Any]):
    if key is None:
        raise ValueError('Key cannot be None')

    cnt, keys = 0, key.split('.')
    for sub_key in keys:
        if isinstance(value, (tuple, list)):
            for vv in value:
                set_value_by_path(vv, '.'.join(keys[cnt:]), updater)
        elif sub_key in value:
            if cnt == len(keys) - 1:
                value[sub_key] = updater(sub_key, value[sub_key])
            else:
                value = value[sub_key]
        else:
            raise KeyError(f"'{key}' doesn't point to an attribute")
        cnt = cnt + 1


class ValueTransformer:
    def __init__(
        self,
        value_transfomer: Callable[[str | None, Any], Any],
        key_transformer: Callable[[str, Any], str | None] | None = None,
    ):
        if value_transfomer is None:
            raise ValueError('Value transformer has not been defined')

        self.value_transfomer = value_transfomer
        self.key_transformer = key_transformer

    def __call__(self, value: Any, key: str | None = None) -> Any:
        if isinstance(value, dict):
            res = {}
            for k, v in value.items():
                nr = self.value_transfomer(k, v)
                if nr == v and isinstance(v, (dict, list, set, tuple)):
                    nr = self(v, k)
                nk = k if self.key_transformer is None else self.key_transformer(k, v)
                if nk is not None:
                    res[nk] = nr
            return res
        elif isinstance(value, list):
            return [self(v) for v in value]
        elif isinstance(value, tuple):
            return tuple([self(v) for v in value])
        elif isinstance(value, set):
            res_set = set()
            for v in value:
                res_set.add(self(v))
            return res_set
        else:
            return self.value_transfomer(key, value)

    @classmethod
    def none_filter(cls):
        return ValueTransformer(lambda k, v: v, lambda k, v: None if v is None else k)


class AttributesMatcher:
    def __init__(self, matches: Mapping[str, str]):
        if matches is None or len(matches) == 0:
            raise ValueError('Matches is empty or none')

        self.matches = {k: re.compile(v) for k, v in matches.items()}

    def test(self, attrs: Mapping[str, Any]) -> bool:
        for k, v in self.matches.items():
            if k not in attrs or v.fullmatch(attrs[k]) is None:
                return False
        return True


def exp_retryable(attempts:int = 5):
    MAX_ATTEMPTS = 30

    if attempts <= 0 or attempts > MAX_ATTEMPTS:
        raise ValueError(f"Number of attempts is out of the range: [1,{MAX_ATTEMPTS}]")

    def wrapper(func):
        @functools.wraps(func)
        def wrapper_attempts(*args, **kwargs):
            for i in range(0, attempts):
                try:
                    return func(*args, **kwargs)
                except BaseException as e:
                    if i + 1 == attempts:
                        raise e
                    else:
                        timeout = math.exp(i + 1) * 0.250
                        time.sleep(timeout)

            return None

        return wrapper_attempts

    return wrapper
