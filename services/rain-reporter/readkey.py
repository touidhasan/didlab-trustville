import json, sys
def find(o, want):
    if isinstance(o, dict):
        for k, v in o.items():
            if isinstance(v, str) and want in k.lower().replace(" ", "_"):
                return v
            r = find(v, want)
            if r: return r
    if isinstance(o, list):
        for v in o:
            r = find(v, want)
            if r: return r
    return None
print(find(json.load(open(sys.argv[1])), sys.argv[2]))
