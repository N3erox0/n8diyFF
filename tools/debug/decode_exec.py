import json, sys

def load(path):
    with open(path, 'r', encoding='utf-8') as f:
        return json.load(f)

data = load('/tmp/exec.json')
raw = data['data']['data']
arr = json.loads(raw) if isinstance(raw, str) else raw   # 扁平化数组（可能是字符串）
def resolve(v, depth=0):
    if isinstance(v, str) and v.isdigit() and depth < 8:
        idx = int(v)
        if idx < len(arr):
            return resolve(arr[idx], depth + 1)
    return v

err = resolve(arr[5]) if len(arr) > 5 else None
print('=== ERROR OBJECT ===')
print(json.dumps(err, ensure_ascii=False)[:1500] if not isinstance(err, str) else err)
print()
for i in (15, 19, 20, 22):
    if i < len(arr):
        val = resolve(arr[i])
        print(f'[{i}] =', json.dumps(val, ensure_ascii=False)[:600] if not isinstance(val, str) else val[:600])
print()
print('=== STACK ===')
if len(arr) > 23:
    st = resolve(arr[23])
    print(st[:800] if isinstance(st, str) else json.dumps(st, ensure_ascii=False)[:800])
