import re



reg_exp = r"([^\{\}]+)"
value  = "{public final native void java.lang.Object.notify()}"
mt = re.search(reg_exp, value)

print("!!!!!!!!!!!!!!!!! %s" % mt.group(1))

