extends SceneTree
## Self-test of the mods' Python (scripts/mods/py_vm.gd), no game needed:
##   timeout 120 tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools_scripts/pytest_vm.gd
## Each case is [source, expected print output] — or an expected error type after "!".

const VM = preload("res://scripts/mods/py_vm.gd")

const CASES := [
	["print(1 + 2 * 3, 7 // 2, -7 // 2, 7 % 3, -7 % 3, 2 ** 10, 7 / 2)", "7 3 -4 1 2 1024 3.5"],
	["print(1 == 1.0, 'a' == 1, [1, 2] == [1, 2], (1,) == [1], None is None)", "True False True False True"],
	["x = [1, 2, 3]\nx.append(4)\nprint(x, len(x), x[-1], x[1:3], x[::-1], x[::2])", "[1, 2, 3, 4] 4 4 [2, 3] [4, 3, 2, 1] [1, 3]"],
	["d = {'a': 1}\nd['b'] = 2\nprint(d, d.get('c', 0), list(d.items()), 'a' in d)", "{'a': 1, 'b': 2} 0 [('a', 1), ('b', 2)] True"],
	["s = 'Hello'\nprint(s.upper(), s.lower(), s[1:], s * 2, s.replace('l', 'L'), ','.join(['a', 'b']))", "HELLO hello ello HelloHello HeLLo a,b"],
	["def f(a, b=2, *args, c=3, **kw):\n    return a + b + c + sum(args) + len(kw)\nprint(f(1), f(1, 1, 1, 1, c=0, z=9))", "6 5"],
	["def fib(n):\n    return n if n < 2 else fib(n - 1) + fib(n - 2)\nprint([fib(i) for i in range(10)])", "[0, 1, 1, 2, 3, 5, 8, 13, 21, 34]"],
	["total = 0\nfor i in range(10):\n    if i == 7:\n        break\n    if i % 2:\n        continue\n    total += i\nelse:\n    total = -1\nprint(total)", "12"],
	["i = 0\nwhile i < 5:\n    i += 1\nelse:\n    print('done', i)", "done 5"],
	["def outer():\n    n = 0\n    def inc():\n        nonlocal n\n        n += 1\n        return n\n    inc(); inc()\n    return inc()\nprint(outer())", "3"],
	["g = 1\ndef f():\n    global g\n    g = 5\nf()\nprint(g)", "5"],
	["class A:\n    k = 10\n    def __init__(self, x):\n        self.x = x\n    def get(self):\n        return self.x + self.k\nclass B(A):\n    def get(self):\n        return super().get() * 2\nprint(B(1).get(), isinstance(B(1), A), A(2).get())", "22 True 12"],
	["class V:\n    def __init__(s, x, y): s.x, s.y = x, y\n    def __add__(s, o): return V(s.x + o.x, s.y + o.y)\n    def __repr__(s): return f'V({s.x}, {s.y})'\n    def __eq__(s, o): return s.x == o.x and s.y == o.y\nprint(V(1, 2) + V(3, 4), V(1, 1) == V(1, 1))", "V(4, 6) True"],
	["try:\n    1 / 0\nexcept ZeroDivisionError as e:\n    print('caught', e)\nfinally:\n    print('fin')", "caught division by zero\nfin"],
	["class MyErr(ValueError): pass\ntry:\n    raise MyErr('bad')\nexcept ValueError as e:\n    print(type(e).__name__, e)", "MyErr bad"],
	["try:\n    {}['x']\nexcept (KeyError, IndexError) as e:\n    print('key', repr(e))", "key KeyError(\"'x'\")"],
	["a, *b, c = [1, 2, 3, 4]\nx, (y, z) = 1, (2, 3)\nprint(a, b, c, x, y, z)", "1 [2, 3] 4 1 2 3"],
	["print(f'{3.14159:.2f} {42:>5} {1234567:,} {0.25:.0%} {\"x\"!r} {7=}')", "3.14    42 1,234,567 25% 'x' 7=7"],
	["print('{} and {name:.1f}'.format('a', name=2.26), '%s=%d' % ('n', 5), '%.3f' % 1.5)", "a and 2.3 n=5 1.500"],
	["print(sorted([3, 1, 2], reverse=True), sorted(['bb', 'a', 'ccc'], key=len), max([1, 5, 2]), min(4, 2, key=lambda v: -v))", "[3, 2, 1] ['a', 'bb', 'ccc'] 5 4"],
	["print({k: v * 2 for k, v in [('a', 1), ('b', 2)]}, [x * y for x in range(3) for y in range(3) if x != y])", "{'a': 2, 'b': 4} [0, 0, 0, 2, 0, 2]"],
	["print(list(zip([1, 2], 'ab')), list(enumerate('xy', 1)), list(map(str, [1, 2])), any([0, 1]), all([]))", "[(1, 'a'), (2, 'b')] [(1, 'x'), (2, 'y')] ['1', '2'] True True"],
	["import math\nfrom random import randint\nprint(math.floor(2.7), math.sqrt(16), round(2.5), round(3.5), round(1.25, 1), 1 <= randint(1, 6) <= 6)", "2 4.0 2 4 1.2 True"],
	["print(int('42') + int(3.9), float('1.5'), str(10) + '!', bool([]), 3 if [] else 4)", "45 1.5 10! False 4"],
	["x = 5\nprint(0 < x < 10, 0 < x > 10, x not in [1, 2], 'ell' in 'hello')", "True False True True"],
	["l = [1]\nm = l\nl += [2]\nprint(m, (1, 2) + (3,), [0] * 3)", "[1, 2] (1, 2, 3) [0, 0, 0]"],
	["def deco(f):\n    def w(*a):\n        return f(*a) + 1\n    return w\n@deco\ndef g(x):\n    return x * 2\nprint(g(5))", "11"],
	["if (n := 10) > 5:\n    print(n)", "10"],
	["print(divmod(7, 2), abs(-3), pow(2, 5, 3), hex(255), bin(5), chr(65), ord('a'))", "(3, 1) 3 2 0xff 0b101 A 97"],
	["s = 0\nfor i in range(1000000):\n    s += i\nprint(s)", "!TimeoutError"],
	["while True:\n    try:\n        pass\n    except:\n        pass", "!TimeoutError"],
	["def r(n):\n    return r(n + 1)\nr(0)", "!RecursionError"],
	["print(undefined_name)", "!NameError"],
	["x = (1, 2)\nx[0] = 3", "!TypeError"],
	["[1, 2][5]", "!IndexError"],
	["1 + 'a'", "!TypeError"],
	["def f():\n    print(y)\n    y = 1\nf()", "!UnboundLocalError"],
	["if True\n    pass", "!SyntaxError"],
	["def f():\nreturn 1", "!IndentationError"],
	["import os", "!ModuleNotFoundError"],
	["print(1,\n  2)\nprint('x')", "1 2\nx"],
	["print('a' 'b', \"\"\"multi\nline\"\"\", r'\\n', 0x10, 1_000, 1e3, .5)", "ab multi\nline \\n 16 1000 1000.0 0.5"],
	["x = [3, 1, 2]\nx.sort()\nx.reverse()\nx.insert(0, 9)\nx.remove(1)\nprint(x, x.pop(), x.index(9), [1, 1].count(1))", "[9, 3] 2 0 2"],
	["class It:\n    def __init__(s): s.i = 0\n    def __iter__(s): return s\n    def __next__(s):\n        s.i += 1\n        if s.i > 3: raise StopIteration\n        return s.i\nprint(list(It()), sum(x for x in It()))", "[1, 2, 3] 6"],
	["assert 1 == 2, 'nope'", "!AssertionError"],
	["d = {}\nd[[1]] = 2", "!TypeError"],
	["print(1 if 0 else 2 if 0 else 3, not 0, [] or 'x', 1 and 0)", "3 True x 0"],
	["print(type(1) == int, type('a').__name__ if hasattr(type('a'), '__name__') else 'str', isinstance(True, int))", "True str True"],
	["def f(*, k): return k\nprint(f(k=2), (lambda *a, **k: (a, k))(1, b=2))", "2 ((1,), {'b': 2})"],
]


func _init() -> void:
	var ok := 0
	var bad := 0
	for c in CASES:
		var vm := VM.new()
		vm.budget(200000)
		var out := []
		vm.print_hook = func(s: String) -> void: out.append(s)
		vm.sources["main"] = c[0]
		var r: Dictionary = vm.run_module("main", c[0], "main.py")
		vm.dispose()
		var got := "\n".join(PackedStringArray(out))
		var want := String(c[1])
		var pass_it := false
		if want.begins_with("!"):
			pass_it = r.has("error") and String(r.error).contains(want.substr(1))
			if r.has("error"):
				got = String(r.error).replace("\n", " | ")
		else:
			pass_it = not r.has("error") and got == want
			if r.has("error"):
				got += " ERROR " + String(r.error).replace("\n", " | ")
		if pass_it:
			ok += 1
		else:
			bad += 1
			print("FAIL: ", String(c[0]).replace("\n", "⏎"), "\n   want: ", want.replace("\n", "⏎"), "\n   got:  ", got.replace("\n", "⏎"))
	# speed: a few hundred thousand steps should take well under a second
	var vm2 := VM.new()
	vm2.budget(5000000)
	var t0 := Time.get_ticks_msec()
	var r2: Dictionary = vm2.run_module("main", "s = 0\nfor i in range(100000):\n    s += i * 2 % 7\n", "main.py")
	vm2.dispose()
	print("speed: 100k loop turns in %d ms %s" % [Time.get_ticks_msec() - t0, "" if not r2.has("error") else String(r2.error)])
	print("PYTEST %d ok, %d failed" % [ok, bad])
	quit(1 if bad > 0 else 0)
