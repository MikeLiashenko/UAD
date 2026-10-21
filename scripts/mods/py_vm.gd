extends "res://scripts/mods/py_parser.gd"
## The interpreter of the mods' Python: walks the trees of py_parser.gd. It runs inside the game
## and sees nothing of it but what the host puts into it (the "uad" module of scripts/mods/mods.gd,
## math, random, the mod's own files) — no files, no network, no engine objects.
##
## Values are the engine's own where Python has the same thing: None = null, bool, int (64-bit),
## float, str = String, list = Array, tuple = a read-only Array, dict = Dictionary. Functions,
## classes, instances, modules, ranges are the small classes below.
##
## Every statement, loop turn and call costs a step; past `step_limit` the run stops with a
## TimeoutError nothing can catch, so an endless loop in a mod costs a moment, not the game.
## Calls nest at most MAX_CALLS deep (the interpreter itself recurses on the engine's stack).

const MAX_CALLS := 48
const MAX_ITEMS := 1000000
const MAX_PRINT := 400

enum { NORMAL, RETURN, BREAK, CONTINUE, RAISE }


class PyFunc extends RefCounted:
	var name := ""
	var params: Array = []
	var defaults: Array = []
	var body
	var is_lambda := false
	var local_names: Dictionary = {}
	var closure = null
	var globals: Dictionary = {}
	var owner = null
	var file := ""


class PyClass extends RefCounted:
	var name := ""
	var bases: Array = []
	var dict: Dictionary = {}
	var mro: Array = []
	var is_exc := false


class PyObj extends RefCounted:
	var cls: PyClass
	var attrs: Dictionary = {}


class PyBound extends RefCounted:
	var fn
	var obj


class PyBuiltin extends RefCounted:
	var name := ""
	var fn: Callable


class PyModule extends RefCounted:
	var name := ""
	var attrs: Dictionary = {}
	var frozen := false


class PyRange extends RefCounted:
	var start := 0
	var stop := 0
	var step := 1

	func size() -> int:
		if step > 0:
			return maxi(0, (stop - start + step - 1) / step)
		return maxi(0, (start - stop - step - 1) / -step)


class PySlice extends RefCounted:
	var lo
	var hi
	var step


class PySuper extends RefCounted:
	var cls: PyClass
	var obj


class Frame extends RefCounted:
	var locals: Dictionary = {}
	## the names a function binds (its locals); null for a module, a class body, a comprehension
	var names = null
	var parent = null
	var globals: Dictionary = {}
	var decl_global: Dictionary = {}
	var decl_nonlocal: Dictionary = {}
	var is_class := false
	var is_comp := false
	var fn = null


var builtins: Dictionary = {}
## Imported modules by name; the host puts its own ones here before a run.
var modules: Dictionary = {}
## The mod's own files that `import name` runs: name → source.
var sources: Dictionary = {}
## Called with each line print() writes.
var print_hook := Callable()
var step_limit := 2000000
var steps := 0
var rng := RandomNumberGenerator.new()

var _exc = null
var _fatal := false
var _ret = null
var _calls := 0
var cur_line := 0
var cur_file := "main.py"
var _frame = null
var _handling: Array = []
var _loading := {}
var _printed := 0
var _missing := RefCounted.new()
var _exc_classes := {}
var _object_cls: PyClass
var _fmt_re := RegEx.create_from_string("^(?:(.)?([<>^=]))?([+\\- ])?(#)?(0)?(\\d+)?([,_])?(?:\\.(\\d+))?([bcdeEfFgGnosxX%])?$")


func _init() -> void:
	rng.randomize()
	_object_cls = _new_class("object", [])
	builtins["object"] = _object_cls
	var tree := [["BaseException", ""], ["Exception", "BaseException"], ["ArithmeticError", "Exception"],
		["ZeroDivisionError", "ArithmeticError"], ["OverflowError", "ArithmeticError"], ["LookupError", "Exception"],
		["KeyError", "LookupError"], ["IndexError", "LookupError"], ["ValueError", "Exception"], ["TypeError", "Exception"],
		["NameError", "Exception"], ["UnboundLocalError", "NameError"], ["AttributeError", "Exception"],
		["RuntimeError", "Exception"], ["RecursionError", "RuntimeError"], ["NotImplementedError", "RuntimeError"],
		["AssertionError", "Exception"], ["ImportError", "Exception"], ["ModuleNotFoundError", "ImportError"],
		["StopIteration", "Exception"], ["MemoryError", "Exception"], ["TimeoutError", "Exception"], ["SyntaxError", "Exception"]]
	for t in tree:
		var bases := [_exc_classes[t[1]]] if String(t[1]) != "" else [_object_cls]
		var c := _new_class(String(t[0]), bases)
		c.is_exc = true
		_exc_classes[t[0]] = c
		builtins[t[0]] = c
	for nm in ["print", "len", "range", "int", "float", "str", "bool", "list", "dict", "tuple", "abs", "min", "max",
			"sum", "round", "sorted", "reversed", "enumerate", "zip", "map", "filter", "any", "all", "isinstance",
			"issubclass", "hasattr", "getattr", "setattr", "callable", "type", "repr", "chr", "ord", "divmod", "pow",
			"hex", "bin", "oct", "super", "format", "iter", "next", "id", "hash"]:
		builtins[nm] = _bi(nm)
	modules["math"] = _math_module()
	modules["random"] = _random_module()


# --- running ----------------------------------------------------------------------------------
## Runs a module's source. {"module": PyModule} or {"error": text, "line": n, "file": name}.
func run_module(mname: String, src: String, file := "") -> Dictionary:
	var p := parse(src)
	if p.has("error"):
		var fname := file if file != "" else mname + ".py"
		var text := "File \"%s\", line %d\n" % [fname, int(p.line)]
		var lines := src.split("\n")
		if int(p.line) >= 1 and int(p.line) <= lines.size():
			text += "    " + lines[int(p.line) - 1].strip_edges() + "\n"
		return {"error": text + String(p.error), "line": int(p.line), "file": fname}
	var m := PyModule.new()
	m.name = mname
	m.attrs["__name__"] = mname
	var fr := Frame.new()
	fr.locals = m.attrs
	fr.globals = m.attrs
	var saved_file := cur_file
	cur_file = file if file != "" else mname + ".py"
	var code := _exec_block(p.body, fr)
	cur_file = saved_file
	if code == RAISE:
		return error_info()
	modules[mname] = m
	return {"module": m}


## Breaks the reference cycles of a VM that is done with (a class lists itself in its mro, a
## function holds the globals that hold it), so its objects are freed.
func dispose() -> void:
	var seen := {}
	var stack: Array = modules.values() + builtins.values() + _exc_classes.values()
	while not stack.is_empty():
		var v = stack.pop_back()
		if not (v is RefCounted) or seen.has(v):
			continue
		seen[v] = true
		if v is PyModule:
			stack.append_array(v.attrs.values())
			v.attrs.clear()
		elif v is PyClass:
			stack.append_array(v.dict.values())
			v.dict.clear()
			v.mro.clear()
			v.bases.clear()
		elif v is PyFunc:
			v.globals = {}
			if v.closure != null:
				stack.append(v.closure)
			v.closure = null
			v.owner = null
		elif v is Frame:
			stack.append_array(v.locals.values())
			v.locals.clear()
			v.parent = null
		elif v is PyObj:
			stack.append_array(v.attrs.values())
			v.attrs.clear()
		elif v is PyBound:
			stack.append(v.fn)
			stack.append(v.obj)
	modules.clear()
	builtins.clear()
	_exc_classes.clear()
	sources.clear()
	_handling.clear()
	_exc = null
	_ret = null
	_frame = null
	print_hook = Callable()


## Calls a Python callable from the host. The result, or null with last_error() set.
func call_py(fn, args: Array = [], kwargs: Dictionary = {}):
	_exc = null
	_fatal = false
	var r = call_value(fn, args, kwargs)
	return null if _exc != null else r


## A fresh budget of steps for the next run.
func budget(n: int) -> void:
	steps = 0
	step_limit = n
	_fatal = false
	_exc = null


func failed() -> bool:
	return _exc != null


## The pending exception as {"error": "File …, line …\nType: message", "line", "file", "type"}.
func error_info() -> Dictionary:
	var e = _exc
	if e == null:
		return {}
	var tname := _type_name(e)
	var msg := _exc_message(e)
	var line := int(e.attrs.get("__line__", 0)) if e is PyObj else 0
	var file := String(e.attrs.get("__file__", cur_file)) if e is PyObj else cur_file
	var text := "File \"%s\", line %d\n" % [file, line]
	var src := ""
	var mname := file.trim_suffix(".py")
	if sources.has(mname):
		src = String(sources[mname])
	if src != "" and line > 0:
		var lines := src.split("\n")
		if line <= lines.size():
			text += "    " + lines[line - 1].strip_edges() + "\n"
	text += tname + (": " + msg if msg != "" else "")
	return {"error": text, "line": line, "file": file, "type": tname}


func _exc_message(e) -> String:
	if e is PyObj:
		var a = e.attrs.get("args", [])
		if a is Array:
			if a.size() == 1:
				return _str(a[0])
			if a.size() > 1:
				return _repr(a)
		return ""
	return _str(e)


func _raise(tname: String, msg: String):
	if _exc != null:
		return
	var c: PyClass = _exc_classes.get(tname, _exc_classes.Exception)
	var o := PyObj.new()
	o.cls = c
	o.attrs["args"] = _tuple([msg])
	o.attrs["__line__"] = cur_line
	o.attrs["__file__"] = cur_file
	_exc = o
	if tname == "TimeoutError" or tname == "MemoryError":
		_fatal = true


## A host function raising a Python exception (the "uad" module): returns null.
func throw(tname: String, msg: String):
	_raise(tname, msg)
	return null


# --- statements -------------------------------------------------------------------------------
func _exec_block(body: Array, f: Frame) -> int:
	for s in body:
		var r := _exec(s, f)
		if r != NORMAL:
			return r
	return NORMAL


func _tick() -> bool:
	steps += 1
	if steps > step_limit:
		_raise("TimeoutError", "the mod ran too long (an endless loop?) and was stopped")
		return false
	return true


func _exec(s: Array, f: Frame) -> int:
	cur_line = int(s[1])
	if not _tick():
		return RAISE
	match int(s[0]):
		S_EXPR:
			_eval(s[2], f)
			return RAISE if _exc != null else NORMAL
		S_ASSIGN:
			var v = _eval(s[3], f)
			if _exc != null:
				return RAISE
			for t in s[2]:
				_assign(t, v, f)
				if _exc != null:
					return RAISE
			return NORMAL
		S_AUG:
			return _aug(s, f)
		S_IF:
			var c = _eval(s[2], f)
			if _exc != null:
				return RAISE
			return _exec_block(s[3] if truthy(c) else s[4], f)
		S_WHILE:
			while true:
				if not _tick():
					return RAISE
				var c = _eval(s[2], f)
				if _exc != null:
					return RAISE
				if not truthy(c):
					return _exec_block(s[4], f)
				var r := _exec_block(s[3], f)
				if r == BREAK:
					return NORMAL
				if r == RETURN or r == RAISE:
					return r
		S_FOR:
			return _for(s, f)
		S_DEF:
			var fn := _make_func(String(s[2]), s[3], s[4], s[6], false, f)
			if _exc != null:
				return RAISE
			var v = fn
			for i in range(s[5].size() - 1, -1, -1):
				var deco = _eval(s[5][i], f)
				if _exc != null:
					return RAISE
				v = call_value(deco, [v], {})
				if _exc != null:
					return RAISE
			_store(String(s[2]), v, f)
			return RAISE if _exc != null else NORMAL
		S_CLASS:
			return _class_stmt(s, f)
		S_RETURN:
			_ret = _eval(s[2], f) if s[2] != null else null
			return RAISE if _exc != null else RETURN
		S_BREAK:
			return BREAK
		S_CONTINUE:
			return CONTINUE
		S_PASS:
			return NORMAL
		S_GLOBAL:
			for nm in s[2]:
				f.decl_global[String(nm)] = true
			return NORMAL
		S_NONLOCAL:
			for nm in s[2]:
				f.decl_nonlocal[String(nm)] = true
			return NORMAL
		S_DEL:
			for t in s[2]:
				_delete(t, f)
				if _exc != null:
					return RAISE
			return NORMAL
		S_ASSERT:
			var c = _eval(s[2], f)
			if _exc != null:
				return RAISE
			if not truthy(c):
				var msg := ""
				if s[3] != null:
					msg = _str(_eval(s[3], f))
					if _exc != null:
						return RAISE
				_raise("AssertionError", msg)
				if msg == "":
					_exc.attrs["args"] = _tuple([])
				return RAISE
			return NORMAL
		S_RAISE:
			return _raise_stmt(s, f)
		S_TRY:
			return _exec_try(s, f)
		S_IMPORT:
			for m in s[2]:
				var mod = _import(String(m[0]))
				if _exc != null:
					return RAISE
				_store(String(m[1]), mod, f)
			return NORMAL
		S_FROM:
			var mod = _import(String(s[2]))
			if _exc != null:
				return RAISE
			for m in s[3]:
				if String(m[0]) == "*":
					var attrs: Dictionary = mod.attrs
					for k in attrs:
						if not String(k).begins_with("_"):
							_store(String(k), attrs[k], f)
				else:
					if not mod.attrs.has(m[0]):
						_raise("ImportError", "cannot import name '%s' from '%s'" % [m[0], s[2]])
						return RAISE
					_store(String(m[1]), mod.attrs[m[0]], f)
			return NORMAL
	_raise("SyntaxError", "unknown statement")
	return RAISE


func _for(s: Array, f: Frame) -> int:
	var it = _eval(s[3], f)
	if _exc != null:
		return RAISE
	if it is PyRange:
		var r: PyRange = it
		var i := r.start
		while (r.step > 0 and i < r.stop) or (r.step < 0 and i > r.stop):
			if not _tick():
				return RAISE
			_assign(s[2], i, f)
			if _exc != null:
				return RAISE
			var code := _exec_block(s[4], f)
			if code == BREAK:
				return NORMAL
			if code == RETURN or code == RAISE:
				return code
			i += r.step
		return _exec_block(s[5], f)
	var items = iterate(it)
	if _exc != null:
		return RAISE
	for v in items:
		if not _tick():
			return RAISE
		_assign(s[2], v, f)
		if _exc != null:
			return RAISE
		var code := _exec_block(s[4], f)
		if code == BREAK:
			return NORMAL
		if code == RETURN or code == RAISE:
			return code
	return _exec_block(s[5], f)


func _aug(s: Array, f: Frame) -> int:
	var t: Array = s[2]
	var op := String(s[3])
	var rhs
	match int(t[0]):
		E_NAME:
			var cur = _lookup(String(t[2]), f)
			if _exc != null:
				return RAISE
			rhs = _eval(s[4], f)
			if _exc != null:
				return RAISE
			_store(String(t[2]), _inplace(op, cur, rhs), f)
		E_ATTR:
			var obj = _eval(t[2], f)
			if _exc != null:
				return RAISE
			var cur = getattr_(obj, String(t[3]))
			if _exc != null:
				return RAISE
			rhs = _eval(s[4], f)
			if _exc != null:
				return RAISE
			var v = _inplace(op, cur, rhs)
			if _exc != null:
				return RAISE
			setattr_(obj, String(t[3]), v)
		E_SUB:
			var obj = _eval(t[2], f)
			if _exc != null:
				return RAISE
			var idx = _eval_index(t[3], f)
			if _exc != null:
				return RAISE
			var cur = getitem(obj, idx)
			if _exc != null:
				return RAISE
			rhs = _eval(s[4], f)
			if _exc != null:
				return RAISE
			var v = _inplace(op, cur, rhs)
			if _exc != null:
				return RAISE
			setitem(obj, idx, v)
	return RAISE if _exc != null else NORMAL


## "+=" on a list grows it in place (other names for it see the change), as in Python.
func _inplace(op: String, a, b):
	if op == "+" and a is Array and not a.is_read_only():
		var items = iterate(b)
		if _exc != null:
			return null
		if a.size() + items.size() > MAX_ITEMS:
			return _raise("MemoryError", "list too long")
		a.append_array(items)
		return a
	return binop(op, a, b)


func _class_stmt(s: Array, f: Frame) -> int:
	var bases := []
	for b in s[3]:
		var bv = _eval(b, f)
		if _exc != null:
			return RAISE
		if not (bv is PyClass):
			_raise("TypeError", "a class can only inherit from classes")
			return RAISE
		bases.append(bv)
	if bases.is_empty():
		bases.append(_object_cls)
	var cf := Frame.new()
	cf.is_class = true
	cf.globals = f.globals
	cf.parent = f if f.names != null or f.is_comp else (f.parent if f.is_class else null)
	cf.locals = {"__name__": String(s[2])}
	var code := _exec_block(s[4], cf)
	if code == RAISE:
		return RAISE
	var c := _new_class(String(s[2]), bases)
	for k in cf.locals:
		c.dict[k] = cf.locals[k]
		if cf.locals[k] is PyFunc:
			(cf.locals[k] as PyFunc).owner = c
	for b in bases:
		if (b as PyClass).is_exc:
			c.is_exc = true
	var v = c
	for i in range(s[5].size() - 1, -1, -1):
		var deco = _eval(s[5][i], f)
		if _exc != null:
			return RAISE
		v = call_value(deco, [v], {})
		if _exc != null:
			return RAISE
	_store(String(s[2]), v, f)
	return NORMAL


func _new_class(cname: String, bases: Array) -> PyClass:
	var c := PyClass.new()
	c.name = cname
	c.bases = bases
	c.mro = [c]
	for b in bases:
		for m in (b as PyClass).mro:
			if not c.mro.has(m):
				c.mro.append(m)
	# object stays last
	if _object_cls != null and c.mro.has(_object_cls) and c != _object_cls:
		c.mro.erase(_object_cls)
		c.mro.append(_object_cls)
	return c


func _raise_stmt(s: Array, f: Frame) -> int:
	if s[2] == null:
		if _handling.is_empty():
			_raise("RuntimeError", "No active exception to reraise")
		else:
			_exc = _handling.back()
		return RAISE
	var v = _eval(s[2], f)
	if _exc != null:
		return RAISE
	if v is PyClass and (v as PyClass).is_exc:
		v = _instantiate(v, [], {})
		if _exc != null:
			return RAISE
	if not (v is PyObj and (v as PyObj).cls.is_exc):
		_raise("TypeError", "exceptions must derive from BaseException")
		return RAISE
	if not v.attrs.has("__line__"):
		v.attrs["__line__"] = cur_line
		v.attrs["__file__"] = cur_file
	_exc = v
	return RAISE


func _exec_try(s: Array, f: Frame) -> int:
	var code := _exec_block(s[2], f)
	if code == RAISE and not _fatal:
		var e = _exc
		for h in s[3]:
			var match_it := h[0] == null
			if not match_it:
				_exc = null
				var typ = _eval(h[0], f)
				if _exc != null:
					break
				match_it = _exc_matches(e, typ)
				_exc = e
			if match_it:
				_exc = null
				if String(h[1]) != "":
					_store(String(h[1]), e, f)
				_handling.append(e)
				code = _exec_block(h[2], f)
				_handling.pop_back()
				break
	elif code == NORMAL:
		code = _exec_block(s[4], f)
	if not s[5].is_empty() and not _fatal:
		var saved_exc = _exc
		var saved_ret = _ret
		_exc = null
		var fin := _exec_block(s[5], f)
		if fin != NORMAL:
			return fin
		_exc = saved_exc
		_ret = saved_ret
	return code


func _exc_matches(e, typ) -> bool:
	if typ is Array:
		for t in typ:
			if _exc_matches(e, t):
				return true
		return false
	if typ is PyClass and e is PyObj:
		return (e as PyObj).cls.mro.has(typ)
	return false


func _import(mname: String):
	if modules.has(mname):
		return modules[mname]
	if sources.has(mname):
		if _loading.has(mname):
			return _raise("ImportError", "circular import of '%s'" % mname)
		_loading[mname] = true
		var saved_ret = _ret
		var r := run_module(mname, String(sources[mname]), mname + ".py")
		_loading.erase(mname)
		_ret = saved_ret
		if r.has("error"):
			if _exc == null:
				_raise("SyntaxError", "%s (%s, line %d)" % [r.error, r.file, int(r.line)])
			return null
		return r.module
	return _raise("ModuleNotFoundError", "No module named '%s'" % mname)


func _make_func(fname: String, params: Array, body, local_names: Dictionary, is_lambda: bool, f: Frame) -> PyFunc:
	var fn := PyFunc.new()
	fn.name = fname
	fn.params = params
	fn.body = body
	fn.is_lambda = is_lambda
	fn.local_names = local_names
	fn.globals = f.globals
	fn.file = cur_file
	# a function sees the functions around it, never a class body
	if f.names != null or f.is_comp:
		fn.closure = f
	elif f.is_class:
		fn.closure = f.parent
	for p in params:
		if p[1] != null:
			fn.defaults.append(_eval(p[1], f))
			if _exc != null:
				return fn
		else:
			fn.defaults.append(_missing)
	return fn


# --- names ------------------------------------------------------------------------------------
func _lookup(nm: String, f: Frame):
	var fr = f
	while fr != null and fr.is_comp:
		if fr.locals.has(nm):
			return fr.locals[nm]
		fr = fr.parent
	if fr != null:
		if fr.decl_global.has(nm):
			return _global(nm, fr.globals)
		if fr.locals.has(nm):
			return fr.locals[nm]
		if fr.names != null and fr.names.has(nm) and not fr.decl_nonlocal.has(nm):
			return _raise("UnboundLocalError", "cannot access local variable '%s' where it is not associated with a value" % nm)
		var p = fr.parent
		while p != null:
			if not p.is_class and p.locals.has(nm) and p.locals != p.globals:
				return p.locals[nm]
			p = p.parent
	return _global(nm, f.globals)


func _global(nm: String, g: Dictionary):
	if g.has(nm):
		return g[nm]
	if builtins.has(nm):
		return builtins[nm]
	return _raise("NameError", "name '%s' is not defined" % nm)


func _store(nm: String, v, f: Frame) -> void:
	if f.is_comp:
		f.locals[nm] = v
		return
	if f.decl_global.has(nm):
		f.globals[nm] = v
		return
	if f.decl_nonlocal.has(nm):
		var p = f.parent
		while p != null:
			if not p.is_class and p.locals.has(nm) and p.locals != p.globals:
				p.locals[nm] = v
				return
			p = p.parent
		_raise("SyntaxError", "no binding for nonlocal '%s' found" % nm)
		return
	f.locals[nm] = v


func _assign(t: Array, v, f: Frame) -> void:
	match int(t[0]):
		E_NAME:
			_store(String(t[2]), v, f)
		E_ATTR:
			var obj = _eval(t[2], f)
			if _exc == null:
				setattr_(obj, String(t[3]), v)
		E_SUB:
			var obj = _eval(t[2], f)
			if _exc != null:
				return
			var idx = _eval_index(t[3], f)
			if _exc == null:
				setitem(obj, idx, v)
		E_TUPLE, E_LIST:
			var items = iterate(v)
			if _exc != null:
				return
			var targets: Array = t[2]
			var star := -1
			for i in targets.size():
				if int(targets[i][0]) == E_STAR:
					star = i
			if star < 0:
				if items.size() != targets.size():
					if items.size() < targets.size():
						_raise("ValueError", "not enough values to unpack (expected %d, got %d)" % [targets.size(), items.size()])
					else:
						_raise("ValueError", "too many values to unpack (expected %d)" % targets.size())
					return
				for i in targets.size():
					_assign(targets[i], items[i], f)
					if _exc != null:
						return
				return
			var after := targets.size() - star - 1
			if items.size() < targets.size() - 1:
				_raise("ValueError", "not enough values to unpack (expected at least %d, got %d)" % [targets.size() - 1, items.size()])
				return
			for i in star:
				_assign(targets[i], items[i], f)
			_assign(targets[star][2], items.slice(star, items.size() - after), f)
			for i in after:
				_assign(targets[star + 1 + i], items[items.size() - after + i], f)
		_:
			_raise("SyntaxError", "cannot assign to expression")


func _delete(t: Array, f: Frame) -> void:
	match int(t[0]):
		E_NAME:
			var nm := String(t[2])
			var d: Dictionary = f.globals if f.decl_global.has(nm) else f.locals
			if not d.erase(nm):
				_raise("NameError", "name '%s' is not defined" % nm)
		E_SUB:
			var obj = _eval(t[2], f)
			if _exc != null:
				return
			var idx = _eval_index(t[3], f)
			if _exc != null:
				return
			if obj is Dictionary:
				if not obj.erase(idx):
					_raise("KeyError", _repr(idx))
			elif obj is Array and not obj.is_read_only():
				if idx is PySlice:
					var ix := _slice_indices(idx, obj.size())
					var keep := []
					var gone := {}
					for i in ix:
						gone[i] = true
					for i in obj.size():
						if not gone.has(i):
							keep.append(obj[i])
					obj.clear()
					obj.append_array(keep)
				else:
					var i := _index(idx, obj.size())
					if _exc == null:
						obj.remove_at(i)
			elif obj is PyObj:
				var m = _class_attr((obj as PyObj).cls, "__delitem__")
				if is_same(m, _missing):
					_raise("TypeError", "'%s' object does not support item deletion" % _type_name(obj))
				else:
					call_value(m, [obj, idx], {})
			else:
				_raise("TypeError", "'%s' object does not support item deletion" % _type_name(obj))
		E_ATTR:
			var obj = _eval(t[2], f)
			if _exc != null:
				return
			if obj is PyObj and (obj as PyObj).attrs.erase(String(t[3])):
				return
			_raise("AttributeError", "'%s' object has no attribute '%s'" % [_type_name(obj), t[3]])
		E_TUPLE, E_LIST:
			for x in t[2]:
				_delete(x, f)


# --- expressions ------------------------------------------------------------------------------
func _eval(e: Array, f: Frame):
	match int(e[0]):
		E_CONST:
			return e[2]
		E_NAME:
			cur_line = int(e[1])
			return _lookup(String(e[2]), f)
		E_BIN:
			var a = _eval(e[3], f)
			if _exc != null:
				return null
			var b = _eval(e[4], f)
			if _exc != null:
				return null
			cur_line = int(e[1])
			return binop(String(e[2]), a, b)
		E_UNARY:
			var v = _eval(e[3], f)
			if _exc != null:
				return null
			cur_line = int(e[1])
			return _unary_op(String(e[2]), v)
		E_NOT:
			var v = _eval(e[2], f)
			return null if _exc != null else not truthy(v)
		E_BOOL:
			var v = null
			for x in e[3]:
				v = _eval(x, f)
				if _exc != null:
					return null
				if bool(e[2]) != truthy(v):
					return v
			return v
		E_CMP:
			var a = _eval(e[2], f)
			if _exc != null:
				return null
			for i in e[3].size():
				var b = _eval(e[4][i], f)
				if _exc != null:
					return null
				cur_line = int(e[1])
				var ok := compare(String(e[3][i]), a, b)
				if _exc != null:
					return null
				if not ok:
					return false
				a = b
			return true
		E_CALL:
			return _eval_call(e, f)
		E_ATTR:
			var obj = _eval(e[2], f)
			if _exc != null:
				return null
			cur_line = int(e[1])
			return getattr_(obj, String(e[3]))
		E_SUB:
			var obj = _eval(e[2], f)
			if _exc != null:
				return null
			var idx = _eval_index(e[3], f)
			if _exc != null:
				return null
			cur_line = int(e[1])
			return getitem(obj, idx)
		E_LIST, E_TUPLE:
			var out := []
			for x in e[2]:
				if int(x[0]) == E_STAR:
					var v = _eval(x[2], f)
					if _exc != null:
						return null
					var items = iterate(v)
					if _exc != null:
						return null
					out.append_array(items)
				else:
					out.append(_eval(x, f))
					if _exc != null:
						return null
			if int(e[0]) == E_TUPLE:
				out.make_read_only()
			return out
		E_DICT:
			var d := {}
			for i in e[2].size():
				if e[2][i] == null:
					var other = _eval(e[3][i], f)
					if _exc != null:
						return null
					if not (other is Dictionary):
						return _raise("TypeError", "'%s' object is not a mapping" % _type_name(other))
					d.merge(other, true)
					continue
				var k = _eval(e[2][i], f)
				if _exc != null:
					return null
				var v = _eval(e[3][i], f)
				if _exc != null:
					return null
				if not _hashable(k):
					return null
				d[k] = v
			return d
		E_IFEXP:
			var c = _eval(e[2], f)
			if _exc != null:
				return null
			return _eval(e[3] if truthy(c) else e[4], f)
		E_LAMBDA:
			return _make_func("<lambda>", e[2], e[3], e[4], true, f)
		E_COMP:
			return _comp(e, f)
		E_FSTR:
			var s := ""
			for part in e[2]:
				if part is String:
					s += part
					continue
				var v = _eval(part[0], f)
				if _exc != null:
					return null
				if String(part[1]) == "r":
					v = _repr(v)
				elif String(part[1]) == "s":
					v = _str(v)
				s += format_value(v, String(part[2]))
				if _exc != null:
					return null
			return s
		E_SLICE:
			return _eval_index(e, f)
		S_ASSIGN:
			# name := value
			var v = _eval(e[3], f)
			if _exc != null:
				return null
			_assign(e[2][0], v, f)
			return v
		E_STAR:
			return _raise("SyntaxError", "can't use starred expression here")
	return _raise("SyntaxError", "unknown expression")


func _eval_index(e: Array, f: Frame):
	if int(e[0]) != E_SLICE:
		return _eval(e, f)
	var s := PySlice.new()
	s.lo = _eval(e[2], f) if e[2] != null else null
	s.hi = _eval(e[3], f) if e[3] != null and _exc == null else null
	s.step = _eval(e[4], f) if e[4] != null and _exc == null else null
	return s


func _eval_call(e: Array, f: Frame):
	var fn = _eval(e[2], f)
	if _exc != null:
		return null
	var args := []
	for a in e[3]:
		args.append(_eval(a, f))
		if _exc != null:
			return null
	if e[6] != null:
		var more = _eval(e[6], f)
		if _exc != null:
			return null
		var items = iterate(more)
		if _exc != null:
			return null
		args.append_array(items)
	var kw := {}
	for i in e[4].size():
		kw[e[4][i]] = _eval(e[5][i], f)
		if _exc != null:
			return null
	if e[7] != null:
		var more = _eval(e[7], f)
		if _exc != null:
			return null
		if not (more is Dictionary):
			return _raise("TypeError", "argument after ** must be a mapping")
		for k in more:
			if not (k is String):
				return _raise("TypeError", "keywords must be strings")
			kw[k] = more[k]
	cur_line = int(e[1])
	return call_value(fn, args, kw)


func _comp(e: Array, f: Frame):
	var cf := Frame.new()
	cf.is_comp = true
	cf.parent = f
	cf.globals = f.globals
	var kind := String(e[2])
	var out = {} if kind == "dict" else []
	_comp_level(e, 0, cf, out)
	return null if _exc != null else out


func _comp_level(e: Array, level: int, cf: Frame, out) -> void:
	var gens: Array = e[5]
	if level >= gens.size():
		if String(e[2]) == "dict":
			var k = _eval(e[3], cf)
			if _exc != null:
				return
			var v = _eval(e[4], cf)
			if _exc == null and _hashable(k):
				out[k] = v
		else:
			var v = _eval(e[3], cf)
			if _exc == null:
				if out.size() >= MAX_ITEMS:
					_raise("MemoryError", "list too long")
					return
				out.append(v)
		return
	var g: Array = gens[level]
	# the first iterable is evaluated in the enclosing scope, the rest inside the comprehension
	var src = _eval(g[1], cf if level > 0 else cf.parent)
	if _exc != null:
		return
	var items = iterate(src)
	if _exc != null:
		return
	for item in items:
		if not _tick():
			return
		_assign(g[0], item, cf)
		if _exc != null:
			return
		var ok := true
		for cond in g[2]:
			var c = _eval(cond, cf)
			if _exc != null:
				return
			if not truthy(c):
				ok = false
				break
		if ok:
			_comp_level(e, level + 1, cf, out)
			if _exc != null:
				return


# --- calls ------------------------------------------------------------------------------------
func call_value(fn, args: Array, kw: Dictionary):
	if not _tick():
		return null
	if fn is PyFunc:
		return _call_func(fn, args, kw)
	if fn is PyBound:
		var a := [fn.obj]
		a.append_array(args)
		return call_value(fn.fn, a, kw)
	if fn is PyBuiltin:
		return fn.fn.call(args, kw)
	if fn is PyClass:
		return _instantiate(fn, args, kw)
	if fn is PyObj:
		var m = _class_attr((fn as PyObj).cls, "__call__")
		if not is_same(m, _missing):
			var a := [fn]
			a.append_array(args)
			return call_value(m, a, kw)
	if fn is Callable:
		return fn.call(args, kw)
	return _raise("TypeError", "'%s' object is not callable" % _type_name(fn))


func _call_func(fn: PyFunc, args: Array, kw: Dictionary):
	if _calls >= MAX_CALLS:
		return _raise("RecursionError", "maximum recursion depth exceeded (%d calls)" % MAX_CALLS)
	var fr := Frame.new()
	fr.names = fn.local_names
	fr.parent = fn.closure
	fr.globals = fn.globals
	fr.fn = fn
	var loc := fr.locals
	var pi := 0
	var star := ""
	var dstar := ""
	var plain := 0
	for p in fn.params:
		if int(p[2]) == 1:
			star = String(p[0])
		elif int(p[2]) == 2:
			dstar = String(p[0])
		elif int(p[2]) == 0:
			plain += 1
			if pi < args.size():
				loc[String(p[0])] = args[pi]
				pi += 1
	if pi < args.size():
		if star == "":
			return _raise("TypeError", "%s() takes %d positional argument%s but %d were given" % [fn.name, plain, "" if plain == 1 else "s", args.size()])
	if star != "":
		loc[star] = _tuple(args.slice(pi))
	var extra := {}
	for k in kw:
		var found := false
		for p in fn.params:
			if (int(p[2]) == 0 or int(p[2]) == 3) and String(p[0]) == String(k):
				found = true
				break
		if found:
			if loc.has(k):
				return _raise("TypeError", "%s() got multiple values for argument '%s'" % [fn.name, k])
			loc[k] = kw[k]
		elif dstar != "":
			extra[k] = kw[k]
		else:
			return _raise("TypeError", "%s() got an unexpected keyword argument '%s'" % [fn.name, k])
	if dstar != "":
		loc[dstar] = extra
	for i in fn.params.size():
		var p: Array = fn.params[i]
		if (int(p[2]) == 0 or int(p[2]) == 3) and not loc.has(String(p[0])):
			if is_same(fn.defaults[i], _missing):
				return _raise("TypeError", "%s() missing required argument: '%s'" % [fn.name, p[0]])
			loc[String(p[0])] = fn.defaults[i]
	_calls += 1
	var saved_file := cur_file
	var saved_line := cur_line
	var saved_frame = _frame
	cur_file = fn.file
	_frame = fr
	var r = null
	if fn.is_lambda:
		r = _eval(fn.body, fr)
	else:
		var code := _exec_block(fn.body, fr)
		if code == RETURN:
			r = _ret
	_ret = null
	_calls -= 1
	cur_file = saved_file
	_frame = saved_frame
	if _exc == null:
		cur_line = saved_line
	return null if _exc != null else r


func _instantiate(c: PyClass, args: Array, kw: Dictionary):
	var o := PyObj.new()
	o.cls = c
	if c.is_exc:
		o.attrs["args"] = _tuple(args)
	var init = _class_attr(c, "__init__")
	if not is_same(init, _missing):
		var a := [o]
		a.append_array(args)
		call_value(init, a, kw)
		if _exc != null:
			return null
	elif (not args.is_empty() or not kw.is_empty()) and not c.is_exc:
		return _raise("TypeError", "%s() takes no arguments" % c.name)
	return o


func _class_attr(c: PyClass, nm: String):
	for k in c.mro:
		if (k as PyClass).dict.has(nm):
			return k.dict[nm]
	return _missing


# --- attributes and items ---------------------------------------------------------------------
const STR_METHODS := ["upper", "lower", "strip", "lstrip", "rstrip", "split", "join", "replace", "startswith",
	"endswith", "find", "rfind", "index", "count", "format", "title", "capitalize", "isdigit", "isalpha",
	"isalnum", "isspace", "isupper", "islower", "zfill", "ljust", "rjust", "center", "splitlines", "partition"]
const LIST_METHODS := ["append", "extend", "insert", "pop", "remove", "index", "count", "sort", "reverse", "copy", "clear"]
const TUPLE_METHODS := ["index", "count"]
const DICT_METHODS := ["get", "keys", "values", "items", "pop", "setdefault", "update", "copy", "clear", "popitem"]


func getattr_(obj, nm: String):
	if obj is PyObj:
		if obj.attrs.has(nm):
			return obj.attrs[nm]
		var v = _class_attr((obj as PyObj).cls, nm)
		if not is_same(v, _missing):
			if v is PyFunc:
				var b := PyBound.new()
				b.fn = v
				b.obj = obj
				return b
			return v
		if nm == "__class__":
			return obj.cls
		if nm == "__dict__":
			return obj.attrs
		return _raise("AttributeError", "'%s' object has no attribute '%s'" % [obj.cls.name, nm])
	if obj is PyClass:
		var v = _class_attr(obj, nm)
		if not is_same(v, _missing):
			return v
		if nm == "__name__":
			return obj.name
		return _raise("AttributeError", "type object '%s' has no attribute '%s'" % [obj.name, nm])
	if obj is PyModule:
		if obj.attrs.has(nm):
			return obj.attrs[nm]
		return _raise("AttributeError", "module '%s' has no attribute '%s'" % [obj.name, nm])
	if obj is PySuper:
		var mro: Array = (obj.obj as PyObj).cls.mro if obj.obj is PyObj else obj.obj.mro
		var i := mro.find(obj.cls)
		for k in range(i + 1, mro.size()):
			if (mro[k] as PyClass).dict.has(nm):
				var v = mro[k].dict[nm]
				if v is PyFunc:
					var b := PyBound.new()
					b.fn = v
					b.obj = obj.obj
					return b
				return v
		if nm == "__init__":
			return _bi("__noop__")
		return _raise("AttributeError", "'super' object has no attribute '%s'" % nm)
	var methods: Array = []
	if obj is String:
		methods = STR_METHODS
	elif obj is Array:
		methods = TUPLE_METHODS if obj.is_read_only() else LIST_METHODS
	elif obj is Dictionary:
		methods = DICT_METHODS
	if methods.has(nm):
		var b := PyBuiltin.new()
		b.name = nm
		b.fn = _method.bind(obj, nm)
		return b
	if obj is PyFunc and nm == "__name__":
		return obj.name
	if obj is PyBuiltin and nm == "__name__":
		return obj.name
	return _raise("AttributeError", "'%s' object has no attribute '%s'" % [_type_name(obj), nm])


func setattr_(obj, nm: String, v) -> void:
	if obj is PyObj:
		obj.attrs[nm] = v
	elif obj is PyClass:
		obj.dict[nm] = v
		if v is PyFunc:
			v.owner = obj
	elif obj is PyModule and not obj.frozen:
		obj.attrs[nm] = v
	else:
		_raise("AttributeError", "'%s' object attribute '%s' is read-only" % [_type_name(obj), nm])


func getitem(obj, idx):
	if obj is Array or obj is String:
		var n: int = obj.size() if obj is Array else obj.length()
		if idx is PySlice:
			var ix := _slice_indices(idx, n)
			if _exc != null:
				return null
			if obj is String:
				var s := ""
				for i in ix:
					s += obj[i]
				return s
			var out := []
			for i in ix:
				out.append(obj[i])
			if obj.is_read_only():
				out.make_read_only()
			return out
		var i := _index(idx, n)
		if _exc != null:
			return null
		return obj[i]
	if obj is Dictionary:
		if obj.has(idx):
			return obj[idx]
		# 2 and 2.0 are the same key in Python
		if idx is float and idx == floorf(idx) and obj.has(int(idx)):
			return obj[int(idx)]
		if idx is int and obj.has(float(idx)):
			return obj[float(idx)]
		return _raise("KeyError", _repr(idx))
	if obj is PyRange:
		var r: PyRange = obj
		var i := _index(idx, r.size())
		return null if _exc != null else r.start + i * r.step
	if obj is PyObj:
		var m = _class_attr((obj as PyObj).cls, "__getitem__")
		if not is_same(m, _missing):
			return call_value(m, [obj, idx], {})
	return _raise("TypeError", "'%s' object is not subscriptable" % _type_name(obj))


func setitem(obj, idx, v) -> void:
	if obj is Dictionary:
		if _hashable(idx):
			obj[idx] = v
		return
	if obj is Array:
		if obj.is_read_only():
			_raise("TypeError", "'tuple' object does not support item assignment")
			return
		if idx is PySlice:
			var items = iterate(v)
			if _exc != null:
				return
			var lo := _clampi_slice(idx.lo, obj.size(), 0)
			var hi := _clampi_slice(idx.hi, obj.size(), obj.size())
			if idx.step != null and int(idx.step) != 1:
				_raise("ValueError", "extended slice assignment is not supported")
				return
			hi = maxi(hi, lo)
			var out: Array = obj.slice(0, lo)
			out.append_array(items)
			out.append_array(obj.slice(hi))
			obj.clear()
			obj.append_array(out)
			return
		var i := _index(idx, obj.size())
		if _exc == null:
			obj[i] = v
		return
	if obj is PyObj:
		var m = _class_attr((obj as PyObj).cls, "__setitem__")
		if not is_same(m, _missing):
			call_value(m, [obj, idx, v], {})
			return
	_raise("TypeError", "'%s' object does not support item assignment" % _type_name(obj))


func _index(idx, n: int) -> int:
	if idx is bool:
		idx = int(idx)
	if not (idx is int):
		_raise("TypeError", "indices must be integers, not %s" % _type_name(idx))
		return 0
	var i: int = idx
	if i < 0:
		i += n
	if i < 0 or i >= n:
		_raise("IndexError", "index out of range")
		return 0
	return i


func _clampi_slice(v, n: int, dflt: int) -> int:
	if v == null:
		return dflt
	var i := int(v)
	if i < 0:
		i += n
	return clampi(i, 0, n)


func _slice_indices(s: PySlice, n: int) -> Array:
	var step := 1 if s.step == null else int(s.step)
	if step == 0:
		_raise("ValueError", "slice step cannot be zero")
		return []
	var out := []
	if step > 0:
		var lo := _clampi_slice(s.lo, n, 0)
		var hi := _clampi_slice(s.hi, n, n)
		var i := lo
		while i < hi:
			out.append(i)
			i += step
	else:
		var lo := n - 1
		if s.lo != null:
			lo = int(s.lo)
			if lo < 0:
				lo += n
			lo = clampi(lo, -1, n - 1)
		var hi := -1
		if s.hi != null:
			hi = int(s.hi)
			if hi < 0:
				hi += n
			hi = clampi(hi, -1, n - 1)
		var i := lo
		while i > hi:
			out.append(i)
			i += step
	return out


func _hashable(k) -> bool:
	if k is Array and not k.is_read_only():
		_raise("TypeError", "unhashable type: 'list'")
		return false
	if k is Dictionary:
		_raise("TypeError", "unhashable type: 'dict'")
		return false
	return true


## The items of an iterable as an Array (a copy), or null with a TypeError.
func iterate(v):
	if v is Array:
		return v.duplicate()
	if v is String:
		var out := []
		for c in v:
			out.append(c)
		return out
	if v is Dictionary:
		return v.keys()
	if v is PyRange:
		var r: PyRange = v
		if r.size() > MAX_ITEMS:
			return _raise("MemoryError", "range too long to make a list of")
		var out := []
		var i := r.start
		for k in r.size():
			out.append(i)
			i += r.step
		return out
	if v is PyObj:
		var it = _class_attr((v as PyObj).cls, "__iter__")
		if not is_same(it, _missing):
			var res = call_value(it, [v], {})
			if _exc != null:
				return null
			if res is PyObj:
				var nx = _class_attr((res as PyObj).cls, "__next__")
				if is_same(nx, _missing):
					return _raise("TypeError", "iter() returned non-iterator")
				var out := []
				while true:
					var x = call_value(nx, [res], {})
					if _exc != null:
						if _exc is PyObj and _exc.cls == _exc_classes.StopIteration:
							_exc = null
							break
						return null
					out.append(x)
					if out.size() > MAX_ITEMS:
						return _raise("MemoryError", "iterator too long")
				return out
			return iterate(res)
	return _raise("TypeError", "'%s' object is not iterable" % _type_name(v))


# --- operators --------------------------------------------------------------------------------
func truthy(v) -> bool:
	if v == null:
		return false
	if v is bool:
		return v
	if v is int:
		return v != 0
	if v is float:
		return v != 0.0
	if v is String:
		return v != ""
	if v is Array or v is Dictionary:
		return not v.is_empty()
	if v is PyRange:
		return v.size() > 0
	if v is PyObj:
		var m = _class_attr((v as PyObj).cls, "__bool__")
		if not is_same(m, _missing):
			return truthy(call_value(m, [v], {}))
		m = _class_attr((v as PyObj).cls, "__len__")
		if not is_same(m, _missing):
			return truthy(call_value(m, [v], {}))
	return true


static func _is_num(v) -> bool:
	return v is int or v is float or v is bool


const DUNDER := {"+": "__add__", "-": "__sub__", "*": "__mul__", "/": "__truediv__", "//": "__floordiv__",
	"%": "__mod__", "**": "__pow__", "&": "__and__", "|": "__or__", "^": "__xor__", "<<": "__lshift__", ">>": "__rshift__", "@": "__matmul__"}


func binop(op: String, a, b):
	if a is PyObj:
		var m = _class_attr((a as PyObj).cls, DUNDER.get(op, ""))
		if not is_same(m, _missing):
			return call_value(m, [a, b], {})
	if b is PyObj:
		var m = _class_attr((b as PyObj).cls, "__r" + String(DUNDER.get(op, "")).substr(2))
		if not is_same(m, _missing):
			return call_value(m, [b, a], {})
	if _is_num(a) and _is_num(b):
		if a is bool:
			a = int(a)
		if b is bool:
			b = int(b)
		var both_int: bool = a is int and b is int
		match op:
			"+":
				return a + b
			"-":
				return a - b
			"*":
				return a * b
			"/":
				if float(b) == 0.0:
					return _raise("ZeroDivisionError", "division by zero")
				return float(a) / float(b)
			"//":
				if float(b) == 0.0:
					return _raise("ZeroDivisionError", "integer division or modulo by zero")
				if both_int:
					var q: int = a / b
					if (a % b != 0) and ((a < 0) != (b < 0)):
						q -= 1
					return q
				return floorf(float(a) / float(b))
			"%":
				if float(b) == 0.0:
					return _raise("ZeroDivisionError", "integer division or modulo by zero")
				if both_int:
					var r: int = a % b
					if r != 0 and ((r < 0) != (b < 0)):
						r += b
					return r
				var rf := fmod(float(a), float(b))
				if rf != 0.0 and ((rf < 0.0) != (float(b) < 0.0)):
					rf += float(b)
				return rf
			"**":
				if both_int and b >= 0:
					var res := 1
					var base: int = a
					var e: int = b
					while e > 0:
						if e & 1:
							res *= base
						base *= base
						e >>= 1
						if not _tick():
							return null
					return res
				if float(a) == 0.0 and float(b) < 0.0:
					return _raise("ZeroDivisionError", "0.0 cannot be raised to a negative power")
				return pow(float(a), float(b))
			"&", "|", "^", "<<", ">>":
				if not both_int:
					return _raise("TypeError", "unsupported operand type(s) for %s: '%s' and '%s'" % [op, _type_name(a), _type_name(b)])
				match op:
					"&":
						return a & b
					"|":
						return a | b
					"^":
						return a ^ b
					"<<":
						if b < 0:
							return _raise("ValueError", "negative shift count")
						return a << b
					">>":
						if b < 0:
							return _raise("ValueError", "negative shift count")
						return a >> b
	if op == "+":
		if a is String and b is String:
			if a.length() + b.length() > MAX_ITEMS * 4:
				return _raise("MemoryError", "string too long")
			return a + b
		if a is Array and b is Array and a.is_read_only() == b.is_read_only():
			if a.size() + b.size() > MAX_ITEMS:
				return _raise("MemoryError", "list too long")
			var out: Array = a.duplicate()
			out.append_array(b)
			if a.is_read_only():
				out.make_read_only()
			return out
	elif op == "*":
		var seq = a if (a is String or a is Array) else b
		var times = b if seq == a else a
		if (seq is String or seq is Array) and (times is int or times is bool) and not (a is String and b is String):
			var n := maxi(int(times), 0)
			var size: int = seq.length() if seq is String else seq.size()
			if size * n > MAX_ITEMS * (4 if seq is String else 1):
				return _raise("MemoryError", "result too long")
			if seq is String:
				return seq.repeat(n)
			var out := []
			for i in n:
				out.append_array(seq)
			if seq.is_read_only():
				out.make_read_only()
			return out
	elif op == "%" and a is String:
		return _percent(a, b)
	elif op == "|" and a is Dictionary and b is Dictionary:
		var d: Dictionary = a.duplicate()
		d.merge(b, true)
		return d
	return _raise("TypeError", "unsupported operand type(s) for %s: '%s' and '%s'" % [op, _type_name(a), _type_name(b)])


func _unary_op(op: String, v):
	if v is bool:
		v = int(v)
	if op == "-" and (v is int or v is float):
		return -v
	if op == "+" and (v is int or v is float):
		return v
	if op == "~" and v is int:
		return ~v
	if v is PyObj:
		var m = _class_attr((v as PyObj).cls, {"-": "__neg__", "+": "__pos__", "~": "__invert__"}[op])
		if not is_same(m, _missing):
			return call_value(m, [v], {})
	return _raise("TypeError", "bad operand type for unary %s: '%s'" % [op, _type_name(v)])


func compare(op: String, a, b) -> bool:
	match op:
		"==":
			return equal(a, b)
		"!=":
			return not equal(a, b)
		"is":
			return _same(a, b)
		"is not":
			return not _same(a, b)
		"in":
			return contains(b, a)
		"not in":
			return not contains(b, a)
		"<":
			return less(a, b)
		">":
			return less(b, a)
		"<=":
			return not less(b, a) if _exc == null else false
		">=":
			return not less(a, b) if _exc == null else false
	return false


func _same(a, b) -> bool:
	if a == null or b == null:
		return a == null and b == null
	if typeof(a) != typeof(b):
		return false
	if a is Object:
		return a == b
	if a is Array or a is Dictionary:
		return is_same(a, b)
	return a == b


func equal(a, b) -> bool:
	if a is PyObj:
		var m = _class_attr((a as PyObj).cls, "__eq__")
		if not is_same(m, _missing):
			return truthy(call_value(m, [a, b], {}))
		return a == b
	if b is PyObj:
		return equal(b, a)
	if _is_num(a) and _is_num(b):
		if a is int and b is int:
			return a == b
		return float(a) == float(b)
	if a == null or b == null:
		return a == null and b == null
	if typeof(a) != typeof(b):
		return false
	if a is Array:
		if a.size() != b.size() or a.is_read_only() != b.is_read_only():
			return false
		for i in a.size():
			if not equal(a[i], b[i]):
				return false
		return true
	if a is Dictionary:
		if a.size() != b.size():
			return false
		for k in a:
			if not b.has(k) or not equal(a[k], b[k]):
				return false
		return true
	if a is Object:
		return a == b
	return a == b


func less(a, b) -> bool:
	if a is PyObj:
		var m = _class_attr((a as PyObj).cls, "__lt__")
		if not is_same(m, _missing):
			return truthy(call_value(m, [a, b], {}))
	if b is PyObj:
		var m = _class_attr((b as PyObj).cls, "__gt__")
		if not is_same(m, _missing):
			return truthy(call_value(m, [b, a], {}))
	if _is_num(a) and _is_num(b):
		return float(a) < float(b) if not (a is int and b is int) else a < b
	if a is String and b is String:
		return a < b
	if a is Array and b is Array:
		for i in mini(a.size(), b.size()):
			if not equal(a[i], b[i]):
				return less(a[i], b[i])
		return a.size() < b.size()
	_raise("TypeError", "'<' not supported between instances of '%s' and '%s'" % [_type_name(a), _type_name(b)])
	return false


func contains(container, item) -> bool:
	if container is String:
		if not (item is String):
			_raise("TypeError", "'in <string>' requires string as left operand, not %s" % _type_name(item))
			return false
		return container.contains(item)
	if container is Dictionary:
		return container.has(item) or (item is int and container.has(float(item))) or (item is float and item == floorf(item) and container.has(int(item)))
	if container is Array:
		for x in container:
			if equal(x, item):
				return true
		return false
	if container is PyRange:
		if not (item is int):
			return false
		var r: PyRange = container
		if r.step > 0:
			return item >= r.start and item < r.stop and (item - r.start) % r.step == 0
		return item <= r.start and item > r.stop and (r.start - item) % (-r.step) == 0
	if container is PyObj:
		var m = _class_attr((container as PyObj).cls, "__contains__")
		if not is_same(m, _missing):
			return truthy(call_value(m, [container, item], {}))
		var items = iterate(container)
		if _exc != null:
			return false
		return contains(items, item)
	_raise("TypeError", "argument of type '%s' is not iterable" % _type_name(container))
	return false


# --- text -------------------------------------------------------------------------------------
func _type_name(v) -> String:
	if v == null:
		return "NoneType"
	if v is bool:
		return "bool"
	if v is int:
		return "int"
	if v is float:
		return "float"
	if v is String:
		return "str"
	if v is Array:
		return "tuple" if v.is_read_only() else "list"
	if v is Dictionary:
		return "dict"
	if v is PyObj:
		return v.cls.name
	if v is PyClass:
		return "type"
	if v is PyFunc:
		return "function"
	if v is PyBound:
		return "method"
	if v is PyBuiltin or v is Callable:
		return "builtin_function_or_method"
	if v is PyModule:
		return "module"
	if v is PyRange:
		return "range"
	if v is PySlice:
		return "slice"
	return type_string(typeof(v))


func _float_str(v: float) -> String:
	if is_nan(v):
		return "nan"
	if is_inf(v):
		return "inf" if v > 0 else "-inf"
	if v == floorf(v) and absf(v) < 1e16:
		return "%d.0" % int(v)
	var s := str(v)
	return s


func _str(v, depth := 0) -> String:
	if v is String:
		return v
	if v is PyObj:
		var m = _class_attr((v as PyObj).cls, "__str__")
		if not is_same(m, _missing):
			var r = call_value(m, [v], {})
			return r if r is String else _str(r)
		if (v as PyObj).cls.is_exc:
			return _exc_message(v)
	return _repr(v, depth)


func _repr(v, depth := 0) -> String:
	if depth > 12:
		return "..."
	if v == null:
		return "None"
	if v is bool:
		return "True" if v else "False"
	if v is int:
		return str(v)
	if v is float:
		return _float_str(v)
	if v is String:
		var q := "'" if not v.contains("'") or v.contains("\"") else "\""
		var s: String = v.replace("\\", "\\\\").replace("\n", "\\n").replace("\t", "\\t").replace("\r", "\\r")
		if q == "'":
			s = s.replace("'", "\\'")
		return q + s + q
	if v is Array:
		var parts := PackedStringArray()
		for x in v:
			parts.append(_repr(x, depth + 1))
		if v.is_read_only():
			return "(" + ", ".join(parts) + ("," if v.size() == 1 else "") + ")"
		return "[" + ", ".join(parts) + "]"
	if v is Dictionary:
		var parts := PackedStringArray()
		for k in v:
			parts.append(_repr(k, depth + 1) + ": " + _repr(v[k], depth + 1))
		return "{" + ", ".join(parts) + "}"
	if v is PyObj:
		var m = _class_attr((v as PyObj).cls, "__repr__")
		if not is_same(m, _missing):
			var r = call_value(m, [v], {})
			return r if r is String else _str(r)
		if (v as PyObj).cls.is_exc:
			return "%s(%s)" % [v.cls.name, ", ".join(Array(v.attrs.get("args", [])).map(func(x): return _repr(x)))]
		return "<%s object>" % v.cls.name
	if v is PyClass:
		return "<class '%s'>" % v.name
	if v is PyFunc:
		return "<function %s>" % v.name
	if v is PyBound:
		return "<bound method %s>" % _repr(v.fn)
	if v is PyBuiltin:
		return "<built-in function %s>" % v.name
	if v is PyModule:
		return "<module '%s'>" % v.name
	if v is PyRange:
		return "range(%d, %d%s)" % [v.start, v.stop, "" if v.step == 1 else ", %d" % v.step]
	return str(v)


## format(value, spec) with Python's mini-language: fill, align, sign, width, grouping, precision, type.
func format_value(v, spec: String) -> String:
	if spec == "":
		return _str(v)
	if v is PyObj:
		var m = _class_attr((v as PyObj).cls, "__format__")
		if not is_same(m, _missing):
			return _str(call_value(m, [v, spec], {}))
	var m := _fmt_re.search(spec)
	if m == null:
		_raise("ValueError", "Invalid format specifier '%s'" % spec)
		return ""
	var fill := m.get_string(1)
	var align := m.get_string(2)
	var sign := m.get_string(3)
	var zero := m.get_string(5) != ""
	var width := int(m.get_string(6)) if m.get_string(6) != "" else 0
	var group := m.get_string(7)
	var prec := int(m.get_string(8)) if m.get_string(8) != "" else -1
	var typ := m.get_string(9)
	var body := ""
	var neg := false
	if typ in ["f", "F", "%", "e", "E", "g", "G"] or (typ == "" and v is float and prec >= 0):
		if not _is_num(v):
			_raise("ValueError", "Unknown format code '%s' for object of type '%s'" % [typ, _type_name(v)])
			return ""
		var x := float(v)
		if typ == "%":
			x *= 100.0
		neg = x < 0.0
		x = absf(x)
		var p := 6 if prec < 0 else prec
		if typ == "e" or typ == "E":
			var ex := 0 if x == 0.0 else int(floor(log(x) / log(10.0)))
			var mant := x / pow(10.0, ex)
			if snappedf(mant, pow(10.0, -p)) >= 10.0:
				mant /= 10.0
				ex += 1
			body = ("%." + str(p) + "f") % mant + ("e" if typ == "e" else "E") + ("+" if ex >= 0 else "-") + "%02d" % absi(ex)
		elif typ == "g" or typ == "G" or typ == "":
			body = _general(x, maxi(p, 1))
		else:
			body = ("%." + str(p) + "f") % x
		if group != "":
			body = _group(body, group)
		if typ == "%":
			body += "%"
	elif typ in ["d", "n", "x", "X", "o", "b", "c"] or (typ == "" and (v is int or v is bool)):
		if not (v is int or v is bool):
			_raise("ValueError", "Unknown format code '%s' for object of type '%s'" % [typ, _type_name(v)])
			return ""
		var n := int(v)
		neg = n < 0
		n = absi(n)
		match typ:
			"x":
				body = "%x" % n
			"X":
				body = ("%x" % n).to_upper()
			"o":
				body = _to_base(n, 8)
			"b":
				body = _to_base(n, 2)
			"c":
				body = char(n)
			_:
				body = str(n)
				if group != "":
					body = _group(body, group)
	else:
		body = _str(v) if typ != "r" else _repr(v)
		if prec >= 0:
			body = body.left(prec)
	var sign_s := "-" if neg else ("+" if sign == "+" else (" " if sign == " " else ""))
	if zero and fill == "" and align == "":
		fill = "0"
		align = "="
	if fill == "":
		fill = " "
	if align == "":
		align = "<" if (v is String or typ == "s") else ">"
	var total := sign_s.length() + body.length()
	if total >= width:
		return sign_s + body
	var pad := width - total
	match align:
		"<":
			return sign_s + body + fill.repeat(pad)
		"^":
			return fill.repeat(pad / 2) + sign_s + body + fill.repeat(pad - pad / 2)
		"=":
			return sign_s + fill.repeat(pad) + body
	return fill.repeat(pad) + sign_s + body


## %g: p significant digits, trailing zeros dropped, exponent form for very big or small numbers.
static func _general(x: float, p: int) -> String:
	if x == 0.0:
		return "0"
	var ex := int(floor(log(x) / log(10.0)))
	if ex >= -4 and ex < p:
		var s := ("%." + str(maxi(p - 1 - ex, 0)) + "f") % x
		if s.contains("."):
			s = s.rstrip("0").trim_suffix(".")
		return s
	var mant := x / pow(10.0, ex)
	var ms := ("%." + str(maxi(p - 1, 0)) + "f") % mant
	if ms.contains("."):
		ms = ms.rstrip("0").trim_suffix(".")
	return ms + "e" + ("+" if ex >= 0 else "-") + "%02d" % absi(ex)


static func _group(s: String, sep: String) -> String:
	var int_part := s
	var rest := ""
	var dot := s.find(".")
	if dot >= 0:
		int_part = s.left(dot)
		rest = s.substr(dot)
	var out := ""
	var count := 0
	for i in range(int_part.length() - 1, -1, -1):
		out = int_part[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = sep + out
	return out + rest


static func _to_base(n: int, base: int) -> String:
	if n == 0:
		return "0"
	var s := ""
	while n > 0:
		s = str(n % base) + s
		n /= base
	return s


## "%s and %d" % (a, b)
func _percent(fmt: String, args) -> String:
	var vals: Array = args if args is Array else [args]
	var out := ""
	var i := 0
	var vi := 0
	var re := RegEx.create_from_string("^%([-+ 0#]*)(\\d+)?(?:\\.(\\d+))?([sdifrxXeEgGc%])")
	while i < fmt.length():
		var c := fmt[i]
		if c != "%":
			out += c
			i += 1
			continue
		var m := re.search(fmt.substr(i))
		if m == null:
			_raise("ValueError", "incomplete format")
			return ""
		var conv := m.get_string(4)
		i += m.get_string(0).length()
		if conv == "%":
			out += "%"
			continue
		if vi >= vals.size():
			_raise("TypeError", "not enough arguments for format string")
			return ""
		var v = vals[vi]
		vi += 1
		var flags := m.get_string(1)
		var spec := ""
		if flags.contains("-"):
			spec += "<"
		elif flags.contains("0"):
			spec += "0"
		if flags.contains("+"):
			spec = "+" + spec if spec != "0" else "+0"
		spec += m.get_string(2)
		if m.get_string(3) != "":
			spec += "." + m.get_string(3)
		match conv:
			"s":
				out += format_value(_str(v), spec)
			"r":
				out += format_value(_repr(v), spec)
			"d", "i":
				out += format_value(int(v) if _is_num(v) else v, spec + "d")
			"f", "e", "E", "g", "G", "x", "X", "c":
				out += format_value(v, spec + conv)
		if _exc != null:
			return ""
	if vi < vals.size() and args is Array:
		_raise("TypeError", "not all arguments converted during string formatting")
	return out


func _tuple(a: Array) -> Array:
	var t := a.duplicate()
	t.make_read_only()
	return t


# --- builtins ---------------------------------------------------------------------------------
func _bi(nm: String) -> PyBuiltin:
	var b := PyBuiltin.new()
	b.name = nm
	b.fn = _builtin.bind(nm)
	return b


func _argn(args: Array, lo: int, hi: int, nm: String) -> bool:
	if args.size() < lo or args.size() > hi:
		if lo == hi:
			_raise("TypeError", "%s() takes exactly %d argument%s (%d given)" % [nm, lo, "" if lo == 1 else "s", args.size()])
		else:
			_raise("TypeError", "%s() takes from %d to %d arguments (%d given)" % [nm, lo, hi, args.size()])
		return false
	return true


func _builtin(args: Array, kw: Dictionary, nm: String):
	match nm:
		"__noop__":
			return null
		"print":
			var parts := PackedStringArray()
			for a in args:
				parts.append(_str(a))
				if _exc != null:
					return null
			var line := String(kw.get("sep", " ")).join(parts) + String(kw.get("end", ""))
			_printed += 1
			if _printed <= MAX_PRINT and print_hook.is_valid():
				print_hook.call(line)
			elif _printed == MAX_PRINT + 1 and print_hook.is_valid():
				print_hook.call("… (more output skipped)")
			return null
		"len":
			if not _argn(args, 1, 1, nm):
				return null
			var v = args[0]
			if v is String:
				return v.length()
			if v is Array or v is Dictionary:
				return v.size()
			if v is PyRange:
				return v.size()
			if v is PyObj:
				var m = _class_attr((v as PyObj).cls, "__len__")
				if not is_same(m, _missing):
					return call_value(m, [v], {})
			return _raise("TypeError", "object of type '%s' has no len()" % _type_name(v))
		"range":
			if not _argn(args, 1, 3, nm):
				return null
			for a in args:
				if not (a is int or a is bool):
					return _raise("TypeError", "'%s' object cannot be interpreted as an integer" % _type_name(a))
			var r := PyRange.new()
			if args.size() == 1:
				r.stop = int(args[0])
			else:
				r.start = int(args[0])
				r.stop = int(args[1])
				if args.size() == 3:
					r.step = int(args[2])
					if r.step == 0:
						return _raise("ValueError", "range() arg 3 must not be zero")
			return r
		"int":
			if args.is_empty():
				return 0
			var v = args[0]
			var base := int(args[1]) if args.size() > 1 else int(kw.get("base", 10))
			if v is bool:
				return int(v)
			if v is int:
				return v
			if v is float:
				if is_nan(v) or is_inf(v):
					return _raise("ValueError", "cannot convert float %s to integer" % _float_str(v))
				return int(v)
			if v is String:
				var s: String = v.strip_edges().replace("_", "").to_lower()
				var neg := s.begins_with("-")
				s = s.trim_prefix("-").trim_prefix("+")
				if base == 16:
					s = s.trim_prefix("0x")
				elif base == 2:
					s = s.trim_prefix("0b")
				elif base == 8:
					s = s.trim_prefix("0o")
				var n := 0
				if s == "":
					return _raise("ValueError", "invalid literal for int() with base %d: %s" % [base, _repr(v)])
				for ch in s:
					var d := "0123456789abcdefghijklmnopqrstuvwxyz".find(ch)
					if d < 0 or d >= base:
						return _raise("ValueError", "invalid literal for int() with base %d: %s" % [base, _repr(v)])
					n = n * base + d
				return -n if neg else n
			if v is PyObj:
				var m = _class_attr((v as PyObj).cls, "__int__")
				if not is_same(m, _missing):
					return call_value(m, [v], {})
			return _raise("TypeError", "int() argument must be a string or a number, not '%s'" % _type_name(v))
		"float":
			if args.is_empty():
				return 0.0
			var v = args[0]
			if _is_num(v):
				return float(v)
			if v is String:
				var s: String = v.strip_edges().to_lower().replace("_", "")
				if s in ["inf", "+inf", "infinity"]:
					return INF
				if s in ["-inf", "-infinity"]:
					return -INF
				if s == "nan":
					return NAN
				if not s.is_valid_float():
					return _raise("ValueError", "could not convert string to float: %s" % _repr(v))
				return s.to_float()
			return _raise("TypeError", "float() argument must be a string or a number, not '%s'" % _type_name(v))
		"str":
			return _str(args[0]) if not args.is_empty() else ""
		"repr":
			return _repr(args[0]) if _argn(args, 1, 1, nm) else null
		"bool":
			return truthy(args[0]) if not args.is_empty() else false
		"list":
			if args.is_empty():
				return []
			return iterate(args[0])
		"tuple":
			if args.is_empty():
				return _tuple([])
			var items = iterate(args[0])
			return null if _exc != null else _tuple(items)
		"dict":
			var d := {}
			if not args.is_empty():
				var src = args[0]
				if src is Dictionary:
					d = src.duplicate()
				else:
					var items = iterate(src)
					if _exc != null:
						return null
					for pair in items:
						var kv = iterate(pair)
						if _exc != null:
							return null
						if kv.size() != 2:
							return _raise("ValueError", "dictionary update sequence element has length %d; 2 is required" % kv.size())
						if not _hashable(kv[0]):
							return null
						d[kv[0]] = kv[1]
			d.merge(kw, true)
			return d
		"abs":
			if not _argn(args, 1, 1, nm):
				return null
			if args[0] is int or args[0] is bool:
				return absi(int(args[0]))
			if args[0] is float:
				return absf(args[0])
			return _raise("TypeError", "bad operand type for abs(): '%s'" % _type_name(args[0]))
		"min", "max":
			var items = args
			if args.size() == 1:
				items = iterate(args[0])
				if _exc != null:
					return null
			if items.is_empty():
				if kw.has("default"):
					return kw.default
				return _raise("ValueError", "%s() arg is an empty sequence" % nm)
			var key = kw.get("key", null)
			var best = items[0]
			var best_k = call_value(key, [best], {}) if key != null else best
			for i in range(1, items.size()):
				var x = items[i]
				var xk = call_value(key, [x], {}) if key != null else x
				if _exc != null:
					return null
				var better := less(xk, best_k) if nm == "min" else less(best_k, xk)
				if _exc != null:
					return null
				if better:
					best = x
					best_k = xk
			return best
		"sum":
			var items = iterate(args[0]) if not args.is_empty() else []
			if _exc != null:
				return null
			var total = args[1] if args.size() > 1 else kw.get("start", 0)
			for x in items:
				total = binop("+", total, x)
				if _exc != null:
					return null
			return total
		"round":
			if not _argn(args, 1, 2, nm):
				return null
			var x = args[0]
			if not _is_num(x):
				return _raise("TypeError", "type %s doesn't define __round__ method" % _type_name(x))
			var nd = args[1] if args.size() > 1 else kw.get("ndigits", null)
			if nd == null:
				return _round_half_even(float(x))
			if x is int:
				return x
			var k := pow(10.0, float(nd))
			return float(_round_half_even(float(x) * k)) / k
		"sorted":
			var items = iterate(args[0]) if not args.is_empty() else []
			if _exc != null:
				return null
			return _sorted(items, kw.get("key", null), truthy(kw.get("reverse", false)))
		"reversed":
			if not _argn(args, 1, 1, nm):
				return null
			var items = iterate(args[0])
			if _exc != null:
				return null
			items.reverse()
			return items
		"enumerate":
			var items = iterate(args[0]) if not args.is_empty() else []
			if _exc != null:
				return null
			var start := int(args[1]) if args.size() > 1 else int(kw.get("start", 0))
			var out := []
			for i in items.size():
				out.append(_tuple([start + i, items[i]]))
			return out
		"zip":
			var lists := []
			var n := MAX_ITEMS
			for a in args:
				var items = iterate(a)
				if _exc != null:
					return null
				lists.append(items)
				n = mini(n, items.size())
			if lists.is_empty():
				return []
			var out := []
			for i in n:
				var row := []
				for l in lists:
					row.append(l[i])
				out.append(_tuple(row))
			return out
		"map":
			if args.size() < 2:
				return _raise("TypeError", "map() must have at least two arguments.")
			var lists := []
			var n := MAX_ITEMS
			for k in range(1, args.size()):
				var items = iterate(args[k])
				if _exc != null:
					return null
				lists.append(items)
				n = mini(n, items.size())
			var out := []
			for i in n:
				var row := []
				for l in lists:
					row.append(l[i])
				out.append(call_value(args[0], row, {}))
				if _exc != null:
					return null
			return out
		"filter":
			if not _argn(args, 2, 2, nm):
				return null
			var items = iterate(args[1])
			if _exc != null:
				return null
			var out := []
			for x in items:
				var ok = truthy(x) if args[0] == null else truthy(call_value(args[0], [x], {}))
				if _exc != null:
					return null
				if ok:
					out.append(x)
			return out
		"any", "all":
			var items = iterate(args[0]) if not args.is_empty() else []
			if _exc != null:
				return null
			for x in items:
				var t := truthy(x)
				if nm == "any" and t:
					return true
				if nm == "all" and not t:
					return false
			return nm == "all"
		"isinstance":
			if not _argn(args, 2, 2, nm):
				return null
			return _isinstance(args[0], args[1])
		"issubclass":
			if not _argn(args, 2, 2, nm):
				return null
			if args[0] is PyClass and args[1] is PyClass:
				return (args[0] as PyClass).mro.has(args[1])
			return false
		"hasattr":
			if not _argn(args, 2, 2, nm):
				return null
			getattr_(args[0], String(args[1]))
			if _exc != null:
				_exc = null
				return false
			return true
		"getattr":
			if not _argn(args, 2, 3, nm):
				return null
			var v = getattr_(args[0], String(args[1]))
			if _exc != null and args.size() == 3 and _exc.cls == _exc_classes.AttributeError:
				_exc = null
				return args[2]
			return v
		"setattr":
			if not _argn(args, 3, 3, nm):
				return null
			setattr_(args[0], String(args[1]), args[2])
			return null
		"callable":
			var v = args[0]
			return v is PyFunc or v is PyBound or v is PyBuiltin or v is PyClass or (v is PyObj and not is_same(_class_attr(v.cls, "__call__"), _missing))
		"type":
			if not _argn(args, 1, 1, nm):
				return null
			var v = args[0]
			if v is PyObj:
				return v.cls
			var tn := _type_name(v)
			if builtins.has(tn):
				return builtins[tn]
			return tn
		"chr":
			return char(int(args[0])) if _argn(args, 1, 1, nm) else null
		"ord":
			if not _argn(args, 1, 1, nm):
				return null
			if not (args[0] is String) or args[0].length() != 1:
				return _raise("TypeError", "ord() expected a character")
			return args[0].unicode_at(0)
		"divmod":
			if not _argn(args, 2, 2, nm):
				return null
			var q = binop("//", args[0], args[1])
			if _exc != null:
				return null
			return _tuple([q, binop("%", args[0], args[1])])
		"pow":
			if not _argn(args, 2, 3, nm):
				return null
			var r = binop("**", args[0], args[1])
			if args.size() == 3 and _exc == null:
				r = binop("%", r, args[2])
			return r
		"hex":
			return ("-" if int(args[0]) < 0 else "") + "0x" + "%x" % absi(int(args[0]))
		"bin":
			return ("-" if int(args[0]) < 0 else "") + "0b" + _to_base(absi(int(args[0])), 2)
		"oct":
			return ("-" if int(args[0]) < 0 else "") + "0o" + _to_base(absi(int(args[0])), 8)
		"format":
			if not _argn(args, 1, 2, nm):
				return null
			return format_value(args[0], String(args[1]) if args.size() > 1 else "")
		"super":
			var s := PySuper.new()
			if args.size() == 2:
				s.cls = args[0]
				s.obj = args[1]
				return s
			if _frame == null or _frame.fn == null or _frame.fn.owner == null or _frame.fn.params.is_empty():
				return _raise("RuntimeError", "super(): no arguments")
			s.cls = _frame.fn.owner
			s.obj = _frame.locals.get(String(_frame.fn.params[0][0]))
			return s
		"iter":
			return iterate(args[0]) if _argn(args, 1, 1, nm) else null
		"next":
			if not _argn(args, 1, 2, nm):
				return null
			var v = args[0]
			if v is Array and not v.is_read_only():
				if v.is_empty():
					if args.size() == 2:
						return args[1]
					return _raise("StopIteration", "")
				return v.pop_front()
			if v is PyObj:
				var m = _class_attr((v as PyObj).cls, "__next__")
				if not is_same(m, _missing):
					return call_value(m, [v], {})
			return _raise("TypeError", "'%s' object is not an iterator" % _type_name(v))
		"id":
			var v = args[0]
			if v is Object:
				return v.get_instance_id()
			return hash(v)
		"hash":
			var v = args[0]
			if not _hashable(v):
				return null
			return hash(v)
	return _raise("NameError", "name '%s' is not defined" % nm)


func _round_half_even(x: float) -> int:
	var f := floorf(x)
	var d := x - f
	if d > 0.5:
		return int(f) + 1
	if d < 0.5:
		return int(f)
	return int(f) if int(f) % 2 == 0 else int(f) + 1


func _isinstance(v, t) -> bool:
	if t is Array:
		for x in t:
			if _isinstance(v, x):
				return true
		return false
	if t is PyClass:
		if t == _object_cls:
			return true
		return v is PyObj and (v as PyObj).cls.mro.has(t)
	if t is PyBuiltin:
		match String(t.name):
			"int":
				return v is int or v is bool
			"float":
				return v is float
			"str":
				return v is String
			"bool":
				return v is bool
			"list":
				return v is Array and not v.is_read_only()
			"tuple":
				return v is Array and v.is_read_only()
			"dict":
				return v is Dictionary
	return false


## A stable merge sort with Python's comparisons (a key function may raise).
func _sorted(items: Array, key, reverse: bool) -> Array:
	var keys := []
	for x in items:
		keys.append(call_value(key, [x], {}) if key != null else x)
		if _exc != null:
			return []
	var idx := range(items.size())
	idx = _merge(idx, keys, reverse)
	var out := []
	for i in idx:
		out.append(items[i])
	return out


func _merge(idx: Array, keys: Array, reverse: bool) -> Array:
	if idx.size() <= 1 or _exc != null:
		return idx
	var mid := idx.size() / 2
	var a := _merge(idx.slice(0, mid), keys, reverse)
	var b := _merge(idx.slice(mid), keys, reverse)
	var out := []
	var i := 0
	var j := 0
	while i < a.size() and j < b.size():
		if not _tick():
			return idx
		# take from b only when strictly before a: equal keys keep their order
		var b_first := less(keys[a[i]], keys[b[j]]) if reverse else less(keys[b[j]], keys[a[i]])
		if _exc != null:
			return idx
		if b_first:
			out.append(b[j])
			j += 1
		else:
			out.append(a[i])
			i += 1
	out.append_array(a.slice(i))
	out.append_array(b.slice(j))
	return out


# --- methods of str, list, tuple and dict ----------------------------------------------------
func _method(args: Array, kw: Dictionary, obj, nm: String):
	if obj is String:
		return _str_method(obj, nm, args, kw)
	if obj is Array:
		return _list_method(obj, nm, args, kw)
	return _dict_method(obj, nm, args, kw)


func _str_method(s: String, nm: String, args: Array, kw: Dictionary):
	match nm:
		"upper":
			return s.to_upper()
		"lower":
			return s.to_lower()
		"strip":
			return s.strip_edges() if args.is_empty() or args[0] == null else _strip_chars(s, String(args[0]), true, true)
		"lstrip":
			return s.strip_edges(true, false) if args.is_empty() or args[0] == null else _strip_chars(s, String(args[0]), true, false)
		"rstrip":
			return s.strip_edges(false, true) if args.is_empty() or args[0] == null else _strip_chars(s, String(args[0]), false, true)
		"split":
			var sep = args[0] if not args.is_empty() else kw.get("sep", null)
			var maxsplit := int(args[1]) if args.size() > 1 else int(kw.get("maxsplit", -1))
			if sep == null:
				var parts := []
				for p in s.strip_edges().split(" ", false):
					for q in String(p).split("\t", false):
						for r in String(q).split("\n", false):
							parts.append(r)
				if maxsplit >= 0 and parts.size() > maxsplit + 1:
					var head := parts.slice(0, maxsplit)
					head.append(" ".join(PackedStringArray(parts.slice(maxsplit))))
					return head
				return parts
			if String(sep) == "":
				return _raise("ValueError", "empty separator")
			return Array(s.split(String(sep), true, maxi(maxsplit, 0)))
		"join":
			var items = iterate(args[0])
			if _exc != null:
				return null
			var parts := PackedStringArray()
			for x in items:
				if not (x is String):
					return _raise("TypeError", "sequence item: expected str instance, %s found" % _type_name(x))
				parts.append(x)
			return s.join(parts)
		"replace":
			if args.size() > 2:
				var out := s
				var n := int(args[2])
				var res := ""
				var count := 0
				while count < n:
					var i := out.find(String(args[0]))
					if i < 0:
						break
					res += out.left(i) + String(args[1])
					out = out.substr(i + String(args[0]).length())
					count += 1
				return res + out
			return s.replace(String(args[0]), String(args[1]))
		"startswith", "endswith":
			var pre = args[0]
			var opts: Array = pre if pre is Array else [pre]
			for o in opts:
				if (s.begins_with(String(o)) if nm == "startswith" else s.ends_with(String(o))):
					return true
			return false
		"find":
			return s.find(String(args[0]), int(args[1]) if args.size() > 1 else 0)
		"rfind":
			return s.rfind(String(args[0]))
		"index":
			var i := s.find(String(args[0]))
			if i < 0:
				return _raise("ValueError", "substring not found")
			return i
		"count":
			return s.count(String(args[0]))
		"format":
			return _str_format(s, args, kw)
		"title":
			var out := ""
			var up := true
			for c in s:
				out += c.to_upper() if up else c.to_lower()
				up = not (c.to_lower() != c.to_upper())
			return out
		"capitalize":
			return s.left(1).to_upper() + s.substr(1).to_lower()
		"isdigit":
			return s != "" and s.is_valid_int() and not s.begins_with("-") and not s.begins_with("+")
		"isalpha":
			if s == "":
				return false
			for c in s:
				if c.to_lower() == c.to_upper():
					return false
			return true
		"isalnum":
			if s == "":
				return false
			for c in s:
				if c.to_lower() == c.to_upper() and not (c >= "0" and c <= "9"):
					return false
			return true
		"isspace":
			return s != "" and s.strip_edges() == ""
		"isupper":
			return s.to_upper() == s and s.to_lower() != s
		"islower":
			return s.to_lower() == s and s.to_upper() != s
		"zfill":
			var w := int(args[0])
			if s.begins_with("-") or s.begins_with("+"):
				return s.left(1) + s.substr(1).lpad(w - 1, "0")
			return s.lpad(w, "0")
		"ljust":
			return s.rpad(int(args[0]), String(args[1]) if args.size() > 1 else " ")
		"rjust":
			return s.lpad(int(args[0]), String(args[1]) if args.size() > 1 else " ")
		"center":
			var w := int(args[0])
			var fill := String(args[1]) if args.size() > 1 else " "
			var pad := maxi(w - s.length(), 0)
			return fill.repeat(pad - pad / 2) + s + fill.repeat(pad / 2)
		"splitlines":
			var t := s.replace("\r\n", "\n")
			if t.ends_with("\n"):
				t = t.left(-1)
			return [] if s == "" else Array(t.split("\n"))
		"partition":
			var sep := String(args[0])
			var i := s.find(sep)
			if i < 0:
				return _tuple([s, "", ""])
			return _tuple([s.left(i), sep, s.substr(i + sep.length())])
	return null


func _strip_chars(s: String, chars: String, left: bool, right: bool) -> String:
	var a := 0
	var b := s.length()
	if left:
		while a < b and chars.contains(s[a]):
			a += 1
	if right:
		while b > a and chars.contains(s[b - 1]):
			b -= 1
	return s.substr(a, b - a)


## "{} and {name:.2f}".format(a, name=b)
func _str_format(s: String, args: Array, kw: Dictionary) -> String:
	var out := ""
	var i := 0
	var auto := 0
	while i < s.length():
		var c := s[i]
		if c == "{":
			if i + 1 < s.length() and s[i + 1] == "{":
				out += "{"
				i += 2
				continue
			var j := s.find("}", i)
			if j < 0:
				_raise("ValueError", "Single '{' encountered in format string")
				return ""
			var field := s.substr(i + 1, j - i - 1)
			var spec := ""
			var k := field.find(":")
			if k >= 0:
				spec = field.substr(k + 1)
				field = field.left(k)
			var conv := ""
			if field.ends_with("!r") or field.ends_with("!s"):
				conv = field.right(1)
				field = field.left(field.length() - 2)
			var v = null
			var head := field.get_slice(".", 0).get_slice("[", 0)
			if head == "":
				if auto >= args.size():
					_raise("IndexError", "Replacement index %d out of range" % auto)
					return ""
				v = args[auto]
				auto += 1
			elif head.is_valid_int():
				if int(head) >= args.size():
					_raise("IndexError", "Replacement index %s out of range" % head)
					return ""
				v = args[int(head)]
			else:
				if not kw.has(head):
					_raise("KeyError", _repr(head))
					return ""
				v = kw[head]
			var rest := field.substr(head.length())
			while rest != "" and _exc == null:
				if rest.begins_with("."):
					var nm := rest.substr(1).get_slice(".", 0).get_slice("[", 0)
					v = getattr_(v, nm)
					rest = rest.substr(1 + nm.length())
				elif rest.begins_with("["):
					var e := rest.find("]")
					var key := rest.substr(1, e - 1)
					v = getitem(v, int(key) if key.is_valid_int() else key)
					rest = rest.substr(e + 1)
				else:
					break
			if _exc != null:
				return ""
			if conv == "r":
				v = _repr(v)
			out += format_value(v, spec)
			i = j + 1
			continue
		if c == "}" and i + 1 < s.length() and s[i + 1] == "}":
			i += 1
		out += c
		i += 1
	return out


func _list_method(a: Array, nm: String, args: Array, kw: Dictionary):
	match nm:
		"append":
			if not _argn(args, 1, 1, nm):
				return null
			if a.size() >= MAX_ITEMS:
				return _raise("MemoryError", "list too long")
			a.append(args[0])
		"extend":
			_inplace("+", a, args[0])
		"insert":
			if not _argn(args, 2, 2, nm):
				return null
			var i := int(args[0])
			if i < 0:
				i = maxi(i + a.size(), 0)
			a.insert(mini(i, a.size()), args[1])
		"pop":
			if a.is_empty():
				return _raise("IndexError", "pop from empty list")
			var i := a.size() - 1 if args.is_empty() else _index(args[0], a.size())
			if _exc != null:
				return null
			var v = a[i]
			a.remove_at(i)
			return v
		"remove":
			for i in a.size():
				if equal(a[i], args[0]):
					a.remove_at(i)
					return null
			return _raise("ValueError", "list.remove(x): x not in list")
		"index":
			for i in a.size():
				if equal(a[i], args[0]):
					return i
			return _raise("ValueError", "%s is not in list" % _repr(args[0]))
		"count":
			var n := 0
			for x in a:
				if equal(x, args[0]):
					n += 1
			return n
		"sort":
			var sorted_items := _sorted(a, kw.get("key", null), truthy(kw.get("reverse", false)))
			if _exc != null:
				return null
			a.clear()
			a.append_array(sorted_items)
		"reverse":
			a.reverse()
		"copy":
			return a.duplicate()
		"clear":
			a.clear()
	return null


func _dict_method(d: Dictionary, nm: String, args: Array, kw: Dictionary):
	match nm:
		"get":
			if args.is_empty():
				return _raise("TypeError", "get expected at least 1 argument, got 0")
			if d.has(args[0]):
				return d[args[0]]
			return args[1] if args.size() > 1 else null
		"keys":
			return d.keys()
		"values":
			return d.values()
		"items":
			var out := []
			for k in d:
				out.append(_tuple([k, d[k]]))
			return out
		"pop":
			if d.has(args[0]):
				var v = d[args[0]]
				d.erase(args[0])
				return v
			if args.size() > 1:
				return args[1]
			return _raise("KeyError", _repr(args[0]))
		"popitem":
			if d.is_empty():
				return _raise("KeyError", "popitem(): dictionary is empty")
			var k = d.keys().back()
			var v = d[k]
			d.erase(k)
			return _tuple([k, v])
		"setdefault":
			if not d.has(args[0]):
				if not _hashable(args[0]):
					return null
				d[args[0]] = args[1] if args.size() > 1 else null
			return d[args[0]]
		"update":
			if not args.is_empty():
				var other = _builtin([args[0]], {}, "dict")
				if _exc != null:
					return null
				d.merge(other, true)
			d.merge(kw, true)
		"copy":
			return d.duplicate()
		"clear":
			d.clear()
	return null


# --- math and random --------------------------------------------------------------------------
func _native(mname: String, names: Array, fn: Callable) -> PyModule:
	var m := PyModule.new()
	m.name = mname
	m.frozen = true
	for nm in names:
		var b := PyBuiltin.new()
		b.name = nm
		b.fn = fn.bind(nm)
		m.attrs[nm] = b
	return m


func _math_module() -> PyModule:
	var m := _native("math", ["sqrt", "sin", "cos", "tan", "asin", "acos", "atan", "atan2", "floor", "ceil", "fabs",
		"hypot", "radians", "degrees", "log", "log10", "log2", "exp", "pow", "isfinite", "isnan", "isinf", "trunc",
		"fmod", "copysign", "dist", "lerp", "clamp"], _math_fn)
	m.attrs["pi"] = PI
	m.attrs["e"] = exp(1.0)
	m.attrs["tau"] = TAU
	m.attrs["inf"] = INF
	m.attrs["nan"] = NAN
	return m


func _num_args(args: Array, n: int, nm: String) -> bool:
	if args.size() < n:
		_raise("TypeError", "%s() takes %d argument%s (%d given)" % [nm, n, "" if n == 1 else "s", args.size()])
		return false
	for i in n:
		if not _is_num(args[i]):
			_raise("TypeError", "must be real number, not %s" % _type_name(args[i]))
			return false
	return true


func _math_fn(args: Array, _kw: Dictionary, nm: String):
	var need := 2 if nm in ["atan2", "hypot", "pow", "fmod", "copysign"] else (3 if nm in ["lerp", "clamp"] else 1)
	if nm == "dist":
		var a = iterate(args[0]) if args.size() > 1 else null
		var b = iterate(args[1]) if args.size() > 1 else null
		if _exc != null or a == null or a.size() != b.size():
			return _raise("ValueError", "both points must have the same number of dimensions")
		var s := 0.0
		for i in a.size():
			s += pow(float(a[i]) - float(b[i]), 2.0)
		return sqrt(s)
	if nm == "log" and args.size() == 2:
		need = 2
	if not _num_args(args, need, nm):
		return null
	var x := float(args[0])
	match nm:
		"sqrt":
			if x < 0.0:
				return _raise("ValueError", "math domain error")
			return sqrt(x)
		"sin":
			return sin(x)
		"cos":
			return cos(x)
		"tan":
			return tan(x)
		"asin", "acos":
			if x < -1.0 or x > 1.0:
				return _raise("ValueError", "math domain error")
			return asin(x) if nm == "asin" else acos(x)
		"atan":
			return atan(x)
		"atan2":
			return atan2(x, float(args[1]))
		"floor":
			return int(floor(x))
		"ceil":
			return int(ceil(x))
		"trunc":
			return int(x)
		"fabs":
			return absf(x)
		"hypot":
			return sqrt(x * x + float(args[1]) * float(args[1]))
		"radians":
			return deg_to_rad(x)
		"degrees":
			return rad_to_deg(x)
		"log", "log10", "log2":
			if x <= 0.0:
				return _raise("ValueError", "math domain error")
			if nm == "log10":
				return log(x) / log(10.0)
			if nm == "log2":
				return log(x) / log(2.0)
			if args.size() == 2:
				return log(x) / log(float(args[1]))
			return log(x)
		"exp":
			return exp(x)
		"pow":
			return pow(x, float(args[1]))
		"isfinite":
			return not (is_inf(x) or is_nan(x))
		"isnan":
			return is_nan(x)
		"isinf":
			return is_inf(x)
		"fmod":
			if float(args[1]) == 0.0:
				return _raise("ValueError", "math domain error")
			return fmod(x, float(args[1]))
		"copysign":
			return absf(x) * (-1.0 if float(args[1]) < 0.0 else 1.0)
		"lerp":
			return lerpf(x, float(args[1]), float(args[2]))
		"clamp":
			return clampf(x, float(args[1]), float(args[2]))
	return null


func _random_module() -> PyModule:
	return _native("random", ["random", "randint", "uniform", "choice", "shuffle", "randrange", "seed", "sample"], _random_fn)


func _random_fn(args: Array, _kw: Dictionary, nm: String):
	match nm:
		"random":
			return rng.randf()
		"randint":
			if not _num_args(args, 2, nm):
				return null
			if int(args[0]) > int(args[1]):
				return _raise("ValueError", "empty range for randint()")
			return rng.randi_range(int(args[0]), int(args[1]))
		"uniform":
			if not _num_args(args, 2, nm):
				return null
			return rng.randf_range(float(args[0]), float(args[1]))
		"randrange":
			var r = _builtin(args, {}, "range")
			if _exc != null:
				return null
			var n: int = r.size()
			if n <= 0:
				return _raise("ValueError", "empty range for randrange()")
			return r.start + rng.randi_range(0, n - 1) * r.step
		"choice":
			var items = iterate(args[0]) if not args.is_empty() else []
			if _exc != null:
				return null
			if items.is_empty():
				return _raise("IndexError", "Cannot choose from an empty sequence")
			return items[rng.randi_range(0, items.size() - 1)]
		"shuffle":
			var a = args[0] if not args.is_empty() else null
			if not (a is Array) or a.is_read_only():
				return _raise("TypeError", "shuffle() needs a list")
			for i in range(a.size() - 1, 0, -1):
				var j := rng.randi_range(0, i)
				var t = a[i]
				a[i] = a[j]
				a[j] = t
			return null
		"sample":
			var items = iterate(args[0]) if not args.is_empty() else []
			if _exc != null:
				return null
			var k := int(args[1]) if args.size() > 1 else 0
			if k > items.size() or k < 0:
				return _raise("ValueError", "Sample larger than population or is negative")
			var pool: Array = items.duplicate()
			var out := []
			for i in k:
				out.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
			return out
		"seed":
			rng.seed = hash(args[0]) if not args.is_empty() else int(Time.get_ticks_usec())
			return null
	return null
