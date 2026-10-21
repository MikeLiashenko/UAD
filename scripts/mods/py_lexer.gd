extends RefCounted
## Tokens of the Python the mods are written in (scripts/mods/py_vm.gd runs it). The grammar is
## Python 3's own, line structure included: INDENT / DEDENT from the leading spaces, no line breaks
## inside brackets, a backslash at the end of a line continues it, # comments, f-strings.
## A token is [type, value, line]; an f-string's value is its raw text (the parser splits it).

enum { NAME, NUM, STR, FSTR, OP, NL, INDENT, DEDENT, EOF }

const OPS3 := ["**=", "//=", ">>=", "<<=", "..."]
const OPS2 := ["**", "//", "==", "!=", "<=", ">=", "+=", "-=", "*=", "/=", "%=", "->", "<<", ">>", "&=", "|=", "^=", ":="]
const OPS1 := "+-*/%<>=()[]{},:.;@&|^~"
## The longest source a mod file may have.
const MAX_SOURCE := 400000


## {"tokens": Array} or {"error": message, "line": n}.
static func tokenize(src: String) -> Dictionary:
	if src.length() > MAX_SOURCE:
		return {"error": "SyntaxError: the file is too long", "line": 1}
	var toks: Array = []
	var indents: Array = [0]
	var i := 0
	var n := src.length()
	var line := 1
	var depth := 0
	var bol := true
	while i < n:
		if bol and depth == 0:
			var col := 0
			var j := i
			while j < n and (src[j] == " " or src[j] == "\t"):
				col = (col / 4 + 1) * 4 if src[j] == "\t" else col + 1
				j += 1
			if j >= n:
				i = j
				break
			var c0 := src[j]
			if c0 == "\n" or c0 == "\r" or c0 == "#":
				# a blank or comment-only line has no say in the indentation
				while j < n and src[j] != "\n":
					j += 1
				i = j + 1
				line += 1
				continue
			if col > int(indents.back()):
				indents.append(col)
				toks.append([INDENT, null, line])
			else:
				while col < int(indents.back()):
					indents.pop_back()
					toks.append([DEDENT, null, line])
				if col != int(indents.back()):
					return {"error": "IndentationError: unindent does not match any outer indentation level", "line": line}
			i = j
			bol = false
		var c := src[i]
		if c == "\n":
			if depth == 0 and not toks.is_empty() and int(toks.back()[0]) != NL:
				toks.append([NL, null, line])
			bol = depth == 0 # inside brackets the next line has no indentation of its own
			line += 1
			i += 1
			continue
		if c == " " or c == "\t" or c == "\r" or c == "\f":
			i += 1
			continue
		if c == "#":
			while i < n and src[i] != "\n":
				i += 1
			continue
		if c == "\\":
			var k := i + 1
			if k < n and src[k] == "\r":
				k += 1
			if k < n and src[k] == "\n":
				i = k + 1
				line += 1
				continue
			return {"error": "SyntaxError: unexpected character after line continuation character", "line": line}
		if _is_digit(c) or (c == "." and i + 1 < n and _is_digit(src[i + 1])):
			var r := _number(src, i, line)
			if r.has("error"):
				return r
			toks.append([NUM, r.value, line])
			i = int(r.end)
			continue
		if _is_name_start(c):
			var j := i
			while j < n and _is_name_char(src[j]):
				j += 1
			var word := src.substr(i, j - i)
			var lw := word.to_lower()
			if j < n and (src[j] == "'" or src[j] == "\"") and lw in ["f", "r", "b", "rb", "br", "fr", "rf", "u"]:
				var s := _string(src, j, line, "r" in lw)
				if s.has("error"):
					return s
				toks.append([FSTR if "f" in lw else STR, s.value, line])
				line = int(s.line)
				i = int(s.end)
				continue
			toks.append([NAME, word, line])
			i = j
			continue
		if c == "'" or c == "\"":
			var s := _string(src, i, line, false)
			if s.has("error"):
				return s
			toks.append([STR, s.value, line])
			line = int(s.line)
			i = int(s.end)
			continue
		var op := ""
		if i + 3 <= n and src.substr(i, 3) in OPS3:
			op = src.substr(i, 3)
		elif i + 2 <= n and src.substr(i, 2) in OPS2:
			op = src.substr(i, 2)
		elif OPS1.contains(c):
			op = c
		if op == "":
			return {"error": "SyntaxError: invalid character '%s'" % c, "line": line}
		if op == "(" or op == "[" or op == "{":
			depth += 1
		elif op == ")" or op == "]" or op == "}":
			depth = maxi(depth - 1, 0)
		toks.append([OP, op, line])
		i += op.length()
	if not toks.is_empty() and int(toks.back()[0]) != NL:
		toks.append([NL, null, line])
	while indents.size() > 1:
		indents.pop_back()
		toks.append([DEDENT, null, line])
	toks.append([EOF, null, line])
	return {"tokens": toks}


static func _is_digit(c: String) -> bool:
	return c >= "0" and c <= "9"


static func _is_name_start(c: String) -> bool:
	return (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or c == "_" or c.unicode_at(0) > 127


static func _is_name_char(c: String) -> bool:
	return _is_name_start(c) or _is_digit(c)


static func _number(src: String, i: int, line: int) -> Dictionary:
	var n := src.length()
	var j := i
	if src[j] == "0" and j + 1 < n and src[j + 1].to_lower() in ["x", "o", "b"]:
		var base_c := src[j + 1].to_lower()
		j += 2
		var digits := ""
		while j < n and (_is_name_char(src[j])):
			if src[j] != "_":
				digits += src[j]
			j += 1
		var v := 0
		var base := 16 if base_c == "x" else (8 if base_c == "o" else 2)
		for ch in digits.to_lower():
			var d := "0123456789abcdef".find(ch)
			if d < 0 or d >= base:
				return {"error": "SyntaxError: invalid digit '%s' in number" % ch, "line": line}
			v = v * base + d
		return {"value": v, "end": j}
	var text := ""
	var is_float := false
	while j < n and (_is_digit(src[j]) or src[j] == "_"):
		if src[j] != "_":
			text += src[j]
		j += 1
	if j < n and src[j] == "." and not (j + 1 < n and src[j + 1] == "."):
		is_float = true
		text += "."
		j += 1
		while j < n and (_is_digit(src[j]) or src[j] == "_"):
			if src[j] != "_":
				text += src[j]
			j += 1
	if j < n and src[j].to_lower() == "e":
		var k := j + 1
		if k < n and (src[k] == "+" or src[k] == "-"):
			k += 1
		if k < n and _is_digit(src[k]):
			is_float = true
			text += "e" + src.substr(j + 1, k - j - 1)
			j = k
			while j < n and _is_digit(src[j]):
				text += src[j]
				j += 1
	if j < n and _is_name_start(src[j]):
		return {"error": "SyntaxError: invalid decimal literal", "line": line}
	if text.begins_with("."):
		text = "0" + text
	if is_float:
		return {"value": text.to_float(), "end": j}
	if text.length() > 18:
		return {"value": text.to_float(), "end": j}
	return {"value": text.to_int(), "end": j}


static func _string(src: String, i: int, line: int, raw: bool) -> Dictionary:
	var n := src.length()
	var q := src[i]
	var triple := i + 2 < n and src[i + 1] == q and src[i + 2] == q
	var j := i + (3 if triple else 1)
	var out := ""
	var start_line := line
	while true:
		if j >= n:
			return {"error": "SyntaxError: unterminated string literal", "line": start_line}
		var c := src[j]
		if triple:
			if c == q and j + 2 < n and src[j + 1] == q and src[j + 2] == q:
				j += 3
				break
		elif c == q:
			j += 1
			break
		if c == "\n":
			if not triple:
				return {"error": "SyntaxError: unterminated string literal", "line": start_line}
			line += 1
		if c == "\\" and j + 1 < n:
			var e := src[j + 1]
			if raw:
				out += c + e
				if e == "\n":
					line += 1
				j += 2
				continue
			j += 2
			match e:
				"n": out += "\n"
				"t": out += "\t"
				"r": out += "\r"
				"\\": out += "\\"
				"'": out += "'"
				"\"": out += "\""
				"\n": line += 1
				"x":
					out += char(src.substr(j, 2).hex_to_int())
					j += 2
				"u":
					out += char(src.substr(j, 4).hex_to_int())
					j += 4
				_:
					out += "\\" + e
			continue
		out += c
		j += 1
	return {"value": out, "end": j, "line": line}
