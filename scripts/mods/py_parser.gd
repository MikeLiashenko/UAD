extends RefCounted
## Parser of the mods' Python (tokens from py_lexer.gd) into a tree of Arrays the interpreter
## (py_vm.gd) walks: every node is [kind, line, ...]. Statements: def / class (with decorators),
## if / elif / else, while, for, try / except / finally, raise, return, break, continue, pass,
## global, nonlocal, del, assert, import / from … import, assignments (chained, unpacking,
## augmented). Expressions: the whole operator table, lambda, conditional expressions, list / dict
## comprehensions, f-strings, slices, calls with keywords, *args and **kwargs.
## Not there: yield / generators, async, with, sets, decorators with arguments are fine.

const Lexer = preload("res://scripts/mods/py_lexer.gd")

enum {
	# expressions
	E_CONST, E_NAME, E_BIN, E_UNARY, E_NOT, E_BOOL, E_CMP, E_CALL, E_ATTR, E_SUB, E_SLICE,
	E_LIST, E_TUPLE, E_DICT, E_IFEXP, E_LAMBDA, E_COMP, E_FSTR, E_STAR,
	# statements
	S_EXPR, S_ASSIGN, S_AUG, S_IF, S_WHILE, S_FOR, S_DEF, S_CLASS, S_RETURN, S_BREAK, S_CONTINUE,
	S_PASS, S_GLOBAL, S_NONLOCAL, S_DEL, S_ASSERT, S_RAISE, S_TRY, S_IMPORT, S_FROM,
}

## Deepest nesting of expressions and blocks: the interpreter walks the tree recursively.
const MAX_DEPTH := 90

var _t: Array = []
var _p := 0
var _err := ""
var _err_line := 0
var _depth := 0


## {"body": Array of statements} or {"error": message, "line": n}.
static func parse(src: String) -> Dictionary:
	var lx := Lexer.tokenize(src)
	if lx.has("error"):
		return lx
	var p = new()
	p._t = lx.tokens
	var body: Array = p._file()
	if p._err != "":
		return {"error": p._err, "line": p._err_line}
	return {"body": body}


## One expression on its own (the inside of an f-string's braces).
static func parse_expr(src: String, line: int) -> Dictionary:
	var lx := Lexer.tokenize(src)
	if lx.has("error"):
		return {"error": lx.error, "line": line}
	var p = new()
	p._t = lx.tokens
	for t in p._t:
		t[2] = line
	var e = p._testlist()
	if p._err == "" and not (p._is(Lexer.NL) or p._is(Lexer.EOF)):
		p._fail("SyntaxError: f-string: invalid expression")
	if p._err != "":
		return {"error": p._err, "line": p._err_line}
	return {"expr": e}


# --- tokens -----------------------------------------------------------------------------------
func _peek() -> Array:
	return _t[mini(_p, _t.size() - 1)]


func _line() -> int:
	return int(_peek()[2])


func _is(kind: int, val = null) -> bool:
	var t := _peek()
	return int(t[0]) == kind and (val == null or t[1] == val)


func _op(val: String) -> bool:
	var t := _peek()
	return int(t[0]) == Lexer.OP and String(t[1]) == val


func _kw(word: String) -> bool:
	var t := _peek()
	return int(t[0]) == Lexer.NAME and String(t[1]) == word


func _next() -> Array:
	var t := _peek()
	if _p < _t.size() - 1:
		_p += 1
	return t


func _accept_op(val: String) -> bool:
	if _op(val):
		_next()
		return true
	return false


func _accept_kw(word: String) -> bool:
	if _kw(word):
		_next()
		return true
	return false


func _expect_op(val: String) -> void:
	if not _accept_op(val):
		_fail("SyntaxError: expected '%s'" % val)


func _fail(msg: String) -> void:
	if _err == "":
		_err = msg
		_err_line = _line()
	# stop the parse where it is
	_p = _t.size() - 1


func _name() -> String:
	var t := _peek()
	if int(t[0]) != Lexer.NAME or String(t[1]) in KEYWORDS:
		_fail("SyntaxError: invalid syntax")
		return ""
	_next()
	return String(t[1])


const KEYWORDS := ["False", "None", "True", "and", "as", "assert", "async", "await", "break", "class", "continue",
	"def", "del", "elif", "else", "except", "finally", "for", "from", "global", "if", "import", "in", "is",
	"lambda", "nonlocal", "not", "or", "pass", "raise", "return", "try", "while", "with", "yield"]


# --- statements -------------------------------------------------------------------------------
func _file() -> Array:
	var body := []
	while _err == "" and not _is(Lexer.EOF):
		if _is(Lexer.NL):
			_next()
			continue
		if _is(Lexer.INDENT):
			_fail("IndentationError: unexpected indent")
			break
		_statement(body)
	return body


func _block() -> Array:
	_expect_op(":")
	var body := []
	if _err != "":
		return body
	if not _is(Lexer.NL):
		_simple_line(body)
		return body
	_next()
	if not _is(Lexer.INDENT):
		_fail("IndentationError: expected an indented block")
		return body
	_next()
	_depth += 1
	if _depth > MAX_DEPTH:
		_fail("SyntaxError: too many nested blocks")
	while _err == "" and not _is(Lexer.DEDENT) and not _is(Lexer.EOF):
		if _is(Lexer.NL):
			_next()
			continue
		_statement(body)
	_depth -= 1
	if _is(Lexer.DEDENT):
		_next()
	return body


func _statement(body: Array) -> void:
	var line := _line()
	if _op("@"):
		var decos := []
		while _accept_op("@"):
			decos.append(_test())
			if not _is(Lexer.NL):
				_fail("SyntaxError: invalid syntax")
				return
			_next()
		if _kw("def"):
			var d := _def()
			d[5] = decos
			body.append(d)
		elif _kw("class"):
			var c := _class()
			c[5] = decos
			body.append(c)
		else:
			_fail("SyntaxError: a decorator must come before def or class")
		return
	if _kw("if"):
		body.append(_if())
	elif _kw("while"):
		_next()
		var cond = _namedexpr()
		var b := _block()
		var orelse := []
		if _accept_kw("else"):
			orelse = _block()
		body.append([S_WHILE, line, cond, b, orelse])
	elif _kw("for"):
		_next()
		var target = _target_list()
		if not _accept_kw("in"):
			_fail("SyntaxError: expected 'in'")
			return
		var it = _testlist()
		var b := _block()
		var orelse := []
		if _accept_kw("else"):
			orelse = _block()
		body.append([S_FOR, line, target, it, b, orelse])
	elif _kw("def"):
		body.append(_def())
	elif _kw("class"):
		body.append(_class())
	elif _kw("try"):
		body.append(_try())
	elif _kw("with") or _kw("async") or _kw("yield"):
		_fail("SyntaxError: '%s' is not supported in UAD mods" % String(_peek()[1]))
	else:
		_simple_line(body)


func _simple_line(body: Array) -> void:
	while true:
		_small(body)
		if _err != "":
			return
		if not _accept_op(";"):
			break
		if _is(Lexer.NL):
			break
	if _is(Lexer.NL):
		_next()
	elif not _is(Lexer.EOF) and not _is(Lexer.DEDENT):
		_fail("SyntaxError: invalid syntax")


func _small(body: Array) -> void:
	var line := _line()
	if _accept_kw("pass"):
		body.append([S_PASS, line])
	elif _accept_kw("break"):
		body.append([S_BREAK, line])
	elif _accept_kw("continue"):
		body.append([S_CONTINUE, line])
	elif _accept_kw("return"):
		var v = null
		if not _is(Lexer.NL) and not _op(";") and not _is(Lexer.EOF):
			v = _testlist()
		body.append([S_RETURN, line, v])
	elif _kw("global") or _kw("nonlocal"):
		var g := _kw("global")
		_next()
		var names := [_name()]
		while _accept_op(","):
			names.append(_name())
		body.append([S_GLOBAL if g else S_NONLOCAL, line, names])
	elif _accept_kw("del"):
		var ts := [_expr()]
		while _accept_op(","):
			ts.append(_expr())
		body.append([S_DEL, line, ts])
	elif _accept_kw("assert"):
		var test = _test()
		var msg = null
		if _accept_op(","):
			msg = _test()
		body.append([S_ASSERT, line, test, msg])
	elif _accept_kw("raise"):
		var exc = null
		if not _is(Lexer.NL) and not _op(";") and not _is(Lexer.EOF):
			exc = _test()
			if _accept_kw("from"):
				_test()
		body.append([S_RAISE, line, exc])
	elif _accept_kw("import"):
		var mods := []
		while true:
			var mname := _dotted()
			var alias := mname.get_slice(".", 0)
			if _accept_kw("as"):
				alias = _name()
			mods.append([mname, alias])
			if not _accept_op(","):
				break
		body.append([S_IMPORT, line, mods])
	elif _accept_kw("from"):
		var mname := _dotted()
		if not _accept_kw("import"):
			_fail("SyntaxError: expected 'import'")
			return
		var names := []
		if _accept_op("*"):
			names.append(["*", "*"])
		else:
			var paren := _accept_op("(")
			while true:
				var nm := _name()
				var alias := nm
				if _accept_kw("as"):
					alias = _name()
				names.append([nm, alias])
				if not _accept_op(","):
					break
				if paren and _op(")"):
					break
			if paren:
				_expect_op(")")
		body.append([S_FROM, line, mname, names])
	else:
		_expr_stmt(body)


func _dotted() -> String:
	var s := _name()
	while _accept_op("."):
		s += "." + _name()
	return s


const AUG_OPS := ["+=", "-=", "*=", "/=", "//=", "%=", "**=", "&=", "|=", "^=", ">>=", "<<="]


func _expr_stmt(body: Array) -> void:
	var line := _line()
	var first = _testlist_star()
	if _err != "":
		return
	var t := _peek()
	if int(t[0]) == Lexer.OP and String(t[1]) in AUG_OPS:
		_next()
		_check_target(first, true)
		var v = _testlist()
		body.append([S_AUG, line, first, String(t[1]).trim_suffix("="), v])
		return
	if _op(":"):
		# an annotation: "x: int = 3" — the type is read and forgotten
		_next()
		_test()
		if _accept_op("="):
			_check_target(first, false)
			body.append([S_ASSIGN, line, [first], _testlist()])
		return
	if _op("="):
		var targets := [first]
		var value = null
		while _accept_op("="):
			value = _testlist_star()
			targets.append(value)
		targets.pop_back()
		for tg in targets:
			_check_target(tg, false)
		body.append([S_ASSIGN, line, targets, value])
		return
	body.append([S_EXPR, line, first])


func _check_target(e, single: bool) -> void:
	if e == null:
		return
	var k := int(e[0])
	if k == E_NAME or k == E_ATTR or k == E_SUB:
		return
	if not single and (k == E_TUPLE or k == E_LIST):
		for x in e[2]:
			_check_target(x[2] if int(x[0]) == E_STAR else x, false)
		return
	_fail("SyntaxError: cannot assign to expression")


func _if() -> Array:
	var line := _line()
	_next() # if / elif
	var cond = _namedexpr()
	var b := _block()
	var orelse := []
	if _kw("elif"):
		orelse = [_if()]
	elif _accept_kw("else"):
		orelse = _block()
	return [S_IF, line, cond, b, orelse]


func _def() -> Array:
	var line := _line()
	_next()
	var fname := _name()
	_expect_op("(")
	var params := _params(")")
	_expect_op(")")
	if _accept_op("->"):
		_test()
	var b := _block()
	return [S_DEF, line, fname, params, b, [], locals_of(b, params)]


## [[name, default node or null, 0 plain / 1 *args / 2 **kwargs / 3 keyword-only], …]
func _params(close: String) -> Array:
	var params := []
	var seen := {}
	var kw_only := false
	while not _op(close) and _err == "":
		var kind := 3 if kw_only else 0
		if _accept_op("**"):
			kind = 2
		elif _accept_op("*"):
			kind = 1
			kw_only = true
			if _op(","):
				_next()
				continue # a bare *: the names after it are keyword-only
		var pname := _name()
		if seen.has(pname):
			_fail("SyntaxError: duplicate argument '%s' in function definition" % pname)
		seen[pname] = true
		if close == ")" and _accept_op(":"):
			_test()
		var dflt = null
		if (kind == 0 or kind == 3) and _accept_op("="):
			dflt = _test()
		params.append([pname, dflt, kind])
		if not _accept_op(","):
			break
	return params


func _class() -> Array:
	var line := _line()
	_next()
	var cname := _name()
	var bases := []
	if _accept_op("("):
		while not _op(")") and _err == "":
			bases.append(_test())
			if not _accept_op(","):
				break
		_expect_op(")")
	var b := _block()
	return [S_CLASS, line, cname, bases, b, []]


func _try() -> Array:
	var line := _line()
	_next()
	var b := _block()
	var handlers := []
	var orelse := []
	var fin := []
	while _kw("except"):
		_next()
		var typ = null
		var nm := ""
		if not _op(":"):
			typ = _test()
			if _accept_kw("as"):
				nm = _name()
		handlers.append([typ, nm, _block()])
	if _accept_kw("else"):
		orelse = _block()
	if _accept_kw("finally"):
		fin = _block()
	if handlers.is_empty() and fin.is_empty():
		_fail("SyntaxError: expected 'except' or 'finally' block")
	return [S_TRY, line, b, handlers, orelse, fin]


## The names a function body binds (its locals), minus those declared global / nonlocal.
static func locals_of(body: Array, params: Array) -> Dictionary:
	var names := {}
	var outer := {}
	for p in params:
		names[String(p[0])] = true
	_collect(body, names, outer)
	for k in outer:
		names.erase(k)
	return names


static func _collect(body: Array, names: Dictionary, outer: Dictionary) -> void:
	for s in body:
		match int(s[0]):
			S_ASSIGN:
				for tg in s[2]:
					_bind_target(tg, names)
			S_AUG:
				_bind_target(s[2], names)
			S_FOR:
				_bind_target(s[2], names)
				_collect(s[4], names, outer)
				_collect(s[5], names, outer)
			S_IF, S_WHILE:
				_collect(s[3], names, outer)
				_collect(s[4], names, outer)
			S_TRY:
				_collect(s[2], names, outer)
				for h in s[3]:
					if String(h[1]) != "":
						names[String(h[1])] = true
					_collect(h[2], names, outer)
				_collect(s[4], names, outer)
				_collect(s[5], names, outer)
			S_DEF, S_CLASS:
				names[String(s[2])] = true
			S_IMPORT:
				for m in s[2]:
					names[String(m[1])] = true
			S_FROM:
				for m in s[3]:
					if String(m[1]) != "*":
						names[String(m[1])] = true
			S_GLOBAL, S_NONLOCAL:
				for nm in s[2]:
					outer[String(nm)] = true
			S_DEL:
				for tg in s[2]:
					_bind_target(tg, names)


static func _bind_target(e, names: Dictionary) -> void:
	match int(e[0]):
		E_NAME:
			names[String(e[2])] = true
		E_TUPLE, E_LIST:
			for x in e[2]:
				_bind_target(x, names)
		E_STAR:
			_bind_target(e[2], names)


# --- expressions ------------------------------------------------------------------------------
func _enter() -> bool:
	_depth += 1
	if _depth > MAX_DEPTH:
		_fail("SyntaxError: expression too deeply nested")
		return false
	return true


## A comma list in a target position (for … in): a, b / (a, b) / a.
func _target_list() -> Array:
	var line := _line()
	var items := [_star_or(_expr)]
	if not _op(","):
		return items[0]
	while _accept_op(","):
		if _kw("in"):
			break
		items.append(_star_or(_expr))
	var tup: Array = [E_TUPLE, line, items]
	_check_target(tup, false)
	return tup


func _star_or(f: Callable):
	var line := _line()
	if _accept_op("*"):
		return [E_STAR, line, _expr()]
	return f.call()


func _testlist():
	var line := _line()
	var first = _test()
	if not _op(","):
		return first
	var items := [first]
	while _accept_op(","):
		if _ends_list():
			break
		items.append(_test())
	return [E_TUPLE, line, items]


func _testlist_star():
	var line := _line()
	var first = _star_or(_test)
	if not _op(",") and int(first[0]) != E_STAR:
		return first
	var items := [first]
	while _accept_op(","):
		if _ends_list():
			break
		items.append(_star_or(_test))
	return [E_TUPLE, line, items]


func _ends_list() -> bool:
	return _is(Lexer.NL) or _is(Lexer.EOF) or _op("=") or _op(")") or _op("]") or _op("}") or _op(";") or _op(":") \
		or (int(_peek()[0]) == Lexer.OP and String(_peek()[1]) in AUG_OPS)


func _namedexpr():
	var e = _test()
	if _op(":=") and e != null and int(e[0]) == E_NAME:
		var line := _line()
		_next()
		return [S_ASSIGN, line, [e], _test(), true]
	return e


func _test():
	if not _enter():
		return [E_CONST, _line(), null]
	var line := _line()
	var r
	if _kw("lambda"):
		_next()
		var params := _params(":")
		_expect_op(":")
		var body = _test()
		r = [E_LAMBDA, line, params, body, locals_of([], params)]
	else:
		r = _or()
		if _kw("if"):
			_next()
			var cond = _or()
			if not _accept_kw("else"):
				_fail("SyntaxError: expected 'else' after 'if' expression")
			var other = _test()
			r = [E_IFEXP, line, cond, r, other]
	_depth -= 1
	return r


func _or():
	var line := _line()
	var a = _and()
	if not _kw("or"):
		return a
	var vals := [a]
	while _accept_kw("or"):
		vals.append(_and())
	return [E_BOOL, line, false, vals]


func _and():
	var line := _line()
	var a = _not()
	if not _kw("and"):
		return a
	var vals := [a]
	while _accept_kw("and"):
		vals.append(_not())
	return [E_BOOL, line, true, vals]


func _not():
	var line := _line()
	if _accept_kw("not"):
		if not _enter():
			return null
		var r := [E_NOT, line, _not()]
		_depth -= 1
		return r
	return _comparison()


const CMP_OPS := ["<", ">", "==", ">=", "<=", "!="]


func _comparison():
	var line := _line()
	var a = _expr()
	var ops := []
	var rights := []
	while true:
		var t := _peek()
		if int(t[0]) == Lexer.OP and String(t[1]) in CMP_OPS:
			_next()
			ops.append(String(t[1]))
		elif _kw("in"):
			_next()
			ops.append("in")
		elif _kw("not") and _p + 1 < _t.size() and int(_t[_p + 1][0]) == Lexer.NAME and String(_t[_p + 1][1]) == "in":
			_next()
			_next()
			ops.append("not in")
		elif _kw("is"):
			_next()
			ops.append("is not" if _accept_kw("not") else "is")
		else:
			break
		rights.append(_expr())
	if ops.is_empty():
		return a
	return [E_CMP, line, a, ops, rights]


## Binary operators by precedence, lowest first.
const LEVELS := [["|"], ["^"], ["&"], ["<<", ">>"], ["+", "-"], ["*", "/", "//", "%", "@"]]


func _expr():
	return _bin(0)


func _bin(level: int):
	if level >= LEVELS.size():
		return _unary()
	var line := _line()
	var a = _bin(level + 1)
	while true:
		var t := _peek()
		if int(t[0]) == Lexer.OP and String(t[1]) in LEVELS[level]:
			_next()
			a = [E_BIN, line, String(t[1]), a, _bin(level + 1)]
		else:
			break
	return a


func _unary():
	var line := _line()
	var t := _peek()
	if int(t[0]) == Lexer.OP and String(t[1]) in ["-", "+", "~"]:
		_next()
		if not _enter():
			return null
		var operand = _unary()
		_depth -= 1
		# a negative number literal stays a constant
		if String(t[1]) == "-" and operand != null and int(operand[0]) == E_CONST and (operand[2] is int or operand[2] is float):
			return [E_CONST, line, -operand[2]]
		return [E_UNARY, line, String(t[1]), operand]
	return _power()


func _power():
	var line := _line()
	var a = _postfix()
	if _accept_op("**"):
		if not _enter():
			return null
		var b = _unary()
		_depth -= 1
		return [E_BIN, line, "**", a, b]
	return a


func _postfix():
	var e = _atom()
	while _err == "":
		var line := _line()
		if _accept_op("("):
			e = _call_args(e, line)
		elif _accept_op("["):
			var idx = _subscript()
			_expect_op("]")
			e = [E_SUB, line, e, idx]
		elif _accept_op("."):
			e = [E_ATTR, line, e, _name()]
		else:
			break
	return e


func _call_args(fn, line: int) -> Array:
	var args := []
	var kwn := []
	var kwv := []
	var star = null
	var dstar = null
	while not _op(")") and _err == "":
		if _accept_op("**"):
			dstar = _test()
		elif _accept_op("*"):
			star = _test()
		elif _is(Lexer.NAME) and _p + 1 < _t.size() and int(_t[_p + 1][0]) == Lexer.OP and String(_t[_p + 1][1]) == "=":
			kwn.append(_name())
			_next()
			kwv.append(_test())
		else:
			var a = _test()
			if _kw("for"):
				a = _comp_tail("gen", a, null, _line())
			elif not kwn.is_empty():
				_fail("SyntaxError: positional argument follows keyword argument")
			args.append(a)
		if not _accept_op(","):
			break
	_expect_op(")")
	return [E_CALL, line, fn, args, kwn, kwv, star, dstar]


func _subscript():
	var line := _line()
	var first = _slice_item()
	if _op(","):
		var items := [first]
		while _accept_op(","):
			if _op("]"):
				break
			items.append(_slice_item())
		return [E_TUPLE, line, items]
	return first


func _slice_item():
	var line := _line()
	var lo = null
	if not _op(":"):
		lo = _test()
		if not _op(":"):
			return lo
	_next()
	var hi = null
	var step = null
	if not _op("]") and not _op(":") and not _op(","):
		hi = _test()
	if _accept_op(":"):
		if not _op("]") and not _op(","):
			step = _test()
	return [E_SLICE, line, lo, hi, step]


func _atom():
	var t := _peek()
	var line := int(t[2])
	match int(t[0]):
		Lexer.NUM:
			_next()
			return [E_CONST, line, t[1]]
		Lexer.STR, Lexer.FSTR:
			# neighbouring literals are one string: "a" "b" == "ab"
			var parts := []
			var has_f := false
			while _is(Lexer.STR) or _is(Lexer.FSTR):
				var s := _next()
				if int(s[0]) == Lexer.FSTR:
					has_f = true
					parts.append_array(_fstring(String(s[1]), int(s[2])))
				else:
					parts.append(String(s[1]))
			if not has_f:
				return [E_CONST, line, "".join(PackedStringArray(parts))]
			return [E_FSTR, line, parts]
		Lexer.NAME:
			var w := String(t[1])
			if w == "None":
				_next()
				return [E_CONST, line, null]
			if w == "True":
				_next()
				return [E_CONST, line, true]
			if w == "False":
				_next()
				return [E_CONST, line, false]
			if w in KEYWORDS:
				_fail("SyntaxError: invalid syntax")
				return [E_CONST, line, null]
			_next()
			return [E_NAME, line, w]
		Lexer.OP:
			var o := String(t[1])
			if o == "(":
				_next()
				if _accept_op(")"):
					return [E_TUPLE, line, []]
				var first = _star_or(_namedexpr)
				if _kw("for"):
					var g := _comp_tail("gen", first, null, line)
					_expect_op(")")
					return g
				if _op(","):
					var items := [first]
					while _accept_op(","):
						if _op(")"):
							break
						items.append(_star_or(_test))
					_expect_op(")")
					return [E_TUPLE, line, items]
				_expect_op(")")
				return first
			if o == "[":
				_next()
				var items := []
				if _accept_op("]"):
					return [E_LIST, line, items]
				var first = _star_or(_namedexpr)
				if _kw("for"):
					var c := _comp_tail("list", first, null, line)
					_expect_op("]")
					return c
				items.append(first)
				while _accept_op(","):
					if _op("]"):
						break
					items.append(_star_or(_test))
				_expect_op("]")
				return [E_LIST, line, items]
			if o == "{":
				_next()
				var keys := []
				var vals := []
				if _accept_op("}"):
					return [E_DICT, line, keys, vals]
				if _accept_op("**"):
					keys.append(null)
					vals.append(_expr())
				else:
					var k = _test()
					if not _accept_op(":"):
						_fail("SyntaxError: sets are not supported in UAD mods — use a list or a dict")
						return [E_CONST, line, null]
					var v = _test()
					if _kw("for"):
						var c := _comp_tail("dict", k, v, line)
						_expect_op("}")
						return c
					keys.append(k)
					vals.append(v)
				while _accept_op(","):
					if _op("}"):
						break
					if _accept_op("**"):
						keys.append(null)
						vals.append(_expr())
						continue
					keys.append(_test())
					_expect_op(":")
					vals.append(_test())
				_expect_op("}")
				return [E_DICT, line, keys, vals]
			if o == "...":
				_next()
				return [E_CONST, line, null]
	if int(t[0]) == Lexer.NL or int(t[0]) == Lexer.EOF:
		_fail("SyntaxError: invalid syntax (unexpected end of line)")
	elif int(t[0]) == Lexer.INDENT:
		_fail("IndentationError: unexpected indent")
	else:
		_fail("SyntaxError: invalid syntax")
	return [E_CONST, line, null]


## "… for x in xs if c for y in ys" after the element: [E_COMP, line, kind, elt, value, gens].
func _comp_tail(kind: String, elt, val, line: int) -> Array:
	var gens := []
	while _accept_kw("for"):
		var target = _target_list()
		if not _accept_kw("in"):
			_fail("SyntaxError: expected 'in'")
			break
		var it = _or()
		var ifs := []
		while _accept_kw("if"):
			ifs.append(_or())
		gens.append([target, it, ifs])
	return [E_COMP, line, kind, elt, val, gens]


## The pieces of an f-string: plain text and [expression, conversion ("" / "r" / "s"), format spec].
func _fstring(s: String, line: int) -> Array:
	var parts := []
	var lit := ""
	var i := 0
	var n := s.length()
	while i < n:
		var c := s[i]
		if c == "{":
			if i + 1 < n and s[i + 1] == "{":
				lit += "{"
				i += 2
				continue
			var depth := 1
			var j := i + 1
			var quote := ""
			while j < n:
				var cj := s[j]
				if quote != "":
					if cj == quote:
						quote = ""
				elif cj == "'" or cj == "\"":
					quote = cj
				elif cj == "{" or cj == "[" or cj == "(":
					depth += 1
				elif cj == "}" or cj == "]" or cj == ")":
					depth -= 1
					if depth == 0:
						break
				j += 1
			if j >= n:
				_fail("SyntaxError: f-string: expecting '}'")
				return parts
			var inner := s.substr(i + 1, j - i - 1)
			var spec := ""
			var conv := ""
			# the format spec starts at the last ":" outside brackets and strings
			var k := _spec_colon(inner)
			if k >= 0:
				spec = inner.substr(k + 1)
				inner = inner.substr(0, k)
			if inner.ends_with("!r") or inner.ends_with("!s"):
				conv = inner.right(1)
				inner = inner.left(inner.length() - 2)
			var self_doc := inner.strip_edges().ends_with("=")
			if self_doc:
				inner = inner.strip_edges().trim_suffix("=")
				lit += inner + "="
				if conv == "":
					conv = "r"
			if lit != "":
				parts.append(lit)
				lit = ""
			var r := parse_expr(inner.strip_edges(), line)
			if r.has("error"):
				_fail(String(r.error))
				return parts
			parts.append([r.expr, conv, spec])
			i = j + 1
			continue
		if c == "}":
			if i + 1 < n and s[i + 1] == "}":
				i += 1
			lit += "}"
			i += 1
			continue
		lit += c
		i += 1
	if lit != "":
		parts.append(lit)
	return parts


static func _spec_colon(inner: String) -> int:
	var depth := 0
	var quote := ""
	for i in inner.length():
		var c := inner[i]
		if quote != "":
			if c == quote:
				quote = ""
		elif c == "'" or c == "\"":
			quote = c
		elif c == "[" or c == "(" or c == "{":
			depth += 1
		elif c == "]" or c == ")" or c == "}":
			depth -= 1
		elif c == ":" and depth == 0:
			if i + 1 < inner.length() and inner[i + 1] == "=":
				continue
			return i
		elif c == "!" and depth == 0 and i + 1 < inner.length() and inner[i + 1] == "=":
			continue
	return -1
