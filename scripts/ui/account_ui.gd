extends RefCounted
## Account dialogs of the multiplayer tab: sign in, register, and the account itself (change the
## nick, sign out, delete). An account is optional — without one a player is their friend code.
## Each dialog returns its root, so the screen can close it with Esc.

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const Account = preload("res://scripts/core/account.gd")

const HINT := Color(0.6, 0.85, 0.75)
const WIDTH := 560


# --- Pieces --------------------------------------------------------------------------------------
## A captioned input row. kind: "text" (a nick), "email" or "password".
static func field(v: VBoxContainer, caption: String, placeholder: String, kind := "text") -> LineEdit:
	var row := UiKit.hbox(12)
	var l := UiKit.label(caption, 16, HINT)
	l.custom_minimum_size = Vector2(120, 0)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.custom_minimum_size = Vector2(360, 46)
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.add_theme_font_size_override("font_size", 19)
	match kind:
		"email":
			e.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS
			e.max_length = 120
		"password":
			e.secret = true
			e.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_PASSWORD
			e.max_length = 128
		_:
			e.max_length = Account.NICK_MAX
	row.add_child(e)
	v.add_child(row)
	return e


## Enter moves on to the next field and presses `submit` on the last one.
static func chain(fields: Array, submit: Callable) -> void:
	for i in fields.size():
		var next: LineEdit = fields[i + 1] if i + 1 < fields.size() else null
		(fields[i] as LineEdit).text_submitted.connect(func(_t: String) -> void:
			if next != null:
				next.grab_focus()
			else:
				submit.call())


static func note(v: VBoxContainer, text: String, color := HINT, size := 14) -> Label:
	var l := UiKit.label(text, size, color, HORIZONTAL_ALIGNMENT_CENTER)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(WIDTH - 40, 0)
	v.add_child(l)
	return l


## A status line not yet in the dialog (added where it belongs).
static func status_label() -> Label:
	var l := UiKit.label("", 15, UiKit.RED, HORIZONTAL_ALIGNMENT_CENTER)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(WIDTH - 40, 0)
	return l


static func say(st: Label, text: String, good := false) -> void:
	st.text = text
	st.add_theme_color_override("font_color", UiKit.NEON if good else UiKit.RED)


## UiKit.modal with a solid panel: forms read better without the tab showing through.
static func dialog(parent: Node) -> Array:
	var m := UiKit.modal(parent, Vector2(WIDTH, 0))
	var v: VBoxContainer = m[1]
	(v.get_parent() as PanelContainer).add_theme_stylebox_override("panel", UiKit.sbox(Color(0.0, 0.045, 0.045, 0.97), Color(0.35, 0.85, 1.0, 0.55), 2, 8, 14))
	return m


static func _valid_mail(m: String) -> bool:
	var at := m.find("@")
	return at > 0 and m.find(".", at) > at + 1 and not m.ends_with(".") and not m.contains(" ")


# --- Sign in -------------------------------------------------------------------------------------
## done() runs after a successful sign-in; to_register() opens the registration instead.
static func login(parent: Node, done: Callable, to_register: Callable) -> Control:
	var m := dialog(parent)
	var root: Control = m[0]
	var v: VBoxContainer = m[1]
	v.add_child(UiKit.glow_label(GS.t("ВХОД В АККАУНТ"), 28, UiKit.CYAN))
	note(v, GS.t("Ваш ник, код и друзья будут с вами на любом устройстве."))
	var mail := field(v, GS.t("Почта"), "name@mail.com", "email")
	var pw := field(v, GS.t("Пароль"), "••••••", "password")
	var st := note(v, "", UiKit.RED, 15)
	var go := UiKit.button(GS.t("Войти"), func() -> void: pass)
	var submit := func() -> void:
		if go.disabled:
			return
		if not _valid_mail(mail.text.strip_edges()) or pw.text == "":
			say(st, GS.t("Введите почту и пароль"))
			return
		go.disabled = true
		say(st, GS.t("Входим…"), true)
		Net.login(mail.text, pw.text, func(ok: bool, text: String) -> void:
			if not is_instance_valid(root):
				return
			go.disabled = false
			if ok:
				root.queue_free()
				done.call()
			else:
				say(st, text))
	go.pressed.connect(submit)
	chain([mail, pw], submit)
	v.add_child(go)
	var row := UiKit.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var forgot := UiKit.button(GS.t("Забыли пароль?"), func() -> void: pass, 250, 16)
	forgot.pressed.connect(func() -> void:
		var addr := mail.text.strip_edges()
		if not _valid_mail(addr):
			say(st, GS.t("Введите почту — пришлём на неё ссылку для нового пароля"))
			mail.grab_focus()
			return
		forgot.disabled = true
		Net.reset_password(addr, func(ok: bool, text: String) -> void:
			if not is_instance_valid(root):
				return
			forgot.disabled = false
			say(st, GS.t("Если аккаунт с почтой %s есть, на неё пришло письмо со ссылкой для нового пароля.") % addr if ok else text, ok)))
	row.add_child(forgot)
	row.add_child(UiKit.button(GS.t("Регистрация"), func() -> void:
		root.queue_free()
		to_register.call(), 250, 16))
	v.add_child(row)
	v.add_child(UiKit.button(GS.t("Отмена"), func() -> void: root.queue_free(), 260, 18))
	mail.grab_focus.call_deferred()
	return root


# --- Register ------------------------------------------------------------------------------------
static func register(parent: Node, done: Callable, to_login: Callable) -> Control:
	var m := dialog(parent)
	var root: Control = m[0]
	var v: VBoxContainer = m[1]
	v.add_child(UiKit.glow_label(GS.t("РЕГИСТРАЦИЯ"), 28, UiKit.CYAN))
	note(v, GS.t("Аккаунт не обязателен — можно играть по коду. С аккаунтом друзья находят вас по нику, а код и друзья хранятся в облаке, на всех ваших устройствах."))
	var nick := field(v, GS.t("Ник"), GS.t("3–16 букв и цифр"))
	var mine := String(GS.settings.get("nick", "")).strip_edges()
	if Account.check_nick(mine) == "":
		nick.text = mine
	var mail := field(v, GS.t("Почта"), "name@mail.com", "email")
	var pw := field(v, GS.t("Пароль"), GS.t("не меньше 6 символов"), "password")
	var pw2 := field(v, GS.t("Ещё раз"), GS.t("повторите пароль"), "password")
	var n_friends := Net.device_friends().size()
	note(v, GS.t("Ваш код %s и друзья (%d) перейдут в аккаунт.") % [Net.fmt_code(Net.code()), n_friends], UiKit.NEON)
	var st := note(v, "", UiKit.RED, 15)
	var go := UiKit.button(GS.t("Создать аккаунт"), func() -> void: pass)
	var submit := func() -> void:
		if go.disabled:
			return
		var bad := Account.check_nick(nick.text)
		if bad != "":
			say(st, bad)
			nick.grab_focus()
			return
		if not _valid_mail(mail.text.strip_edges()):
			say(st, GS.t("Проверьте адрес почты"))
			mail.grab_focus()
			return
		if pw.text.length() < 6:
			say(st, GS.t("Пароль слишком простой — минимум 6 символов"))
			pw.grab_focus()
			return
		if pw.text != pw2.text:
			say(st, GS.t("Пароли не совпадают"))
			pw2.text = ""
			pw2.grab_focus()
			return
		go.disabled = true
		say(st, GS.t("Создаём аккаунт…"), true)
		Net.register(nick.text, mail.text, pw.text, func(ok: bool, text: String) -> void:
			if not is_instance_valid(root):
				return
			go.disabled = false
			if ok:
				root.queue_free()
				done.call()
			else:
				say(st, text))
	go.pressed.connect(submit)
	chain([nick, mail, pw, pw2], submit)
	v.add_child(go)
	v.add_child(UiKit.button(GS.t("Уже есть аккаунт? Войти"), func() -> void:
		root.queue_free()
		to_login.call(), 360, 16))
	v.add_child(UiKit.button(GS.t("Отмена"), func() -> void: root.queue_free(), 260, 18))
	(mail if nick.text != "" else nick).grab_focus.call_deferred()
	return root


# --- The account ---------------------------------------------------------------------------------
## done() runs when the account changed (new nick, signed out, deleted); track(root) is told about
## the deletion dialog that can open from here.
static func manage(parent: Node, done: Callable, track := Callable()) -> Control:
	var m := dialog(parent)
	var root: Control = m[0]
	var v: VBoxContainer = m[1]
	v.add_child(UiKit.glow_label(GS.t("АККАУНТ"), 28, UiKit.CYAN))
	var who := UiKit.glow_label(Net.nick(), 30, Color(0.85, 1.0, 0.95))
	v.add_child(who)
	note(v, "%s · %s" % [Net.account.email(), GS.t("код %s") % Net.fmt_code(Net.code())], Color(0.55, 0.8, 0.9), 15)
	note(v, GS.t("Друзья и код хранятся в аккаунте: войдите на телефоне или другом компьютере — всё будет там."))
	var row := UiKit.hbox(10)
	var nick := LineEdit.new()
	nick.text = Net.nick()
	nick.max_length = Account.NICK_MAX
	nick.custom_minimum_size = Vector2(300, 46)
	nick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nick.add_theme_font_size_override("font_size", 19)
	nick.select_all_on_focus = true
	row.add_child(nick)
	var st := status_label()
	var ren := UiKit.button(GS.t("Сменить ник"), func() -> void: pass, 200, 16)
	var rename := func() -> void:
		if ren.disabled or nick.text.strip_edges() == Net.nick():
			return
		ren.disabled = true
		say(st, GS.t("Сохраняем…"), true)
		Net.rename(nick.text, func(ok: bool, text: String) -> void:
			if not is_instance_valid(root):
				return
			ren.disabled = false
			if ok:
				who.text = Net.nick()
				say(st, GS.t("Ник изменён — друзья увидят «%s»") % Net.nick(), true)
				done.call()
			else:
				say(st, text))
	ren.pressed.connect(rename)
	nick.text_submitted.connect(func(_t: String) -> void: rename.call())
	row.add_child(ren)
	v.add_child(row)
	v.add_child(st)
	v.add_child(UiKit.button(GS.t("Выйти из аккаунта"), func() -> void:
		Net.logout()
		root.queue_free()
		done.call()))
	var del := UiKit.button(GS.t("Удалить аккаунт"), func() -> void: pass, 260, 16)
	del.add_theme_color_override("font_color", Color(1.0, 0.55, 0.5))
	del.pressed.connect(func() -> void:
		root.queue_free()
		var c := confirm_delete(parent, done)
		if track.is_valid():
			track.call(c))
	v.add_child(del)
	v.add_child(UiKit.button(GS.t("Закрыть"), func() -> void: root.queue_free(), 260, 18))
	return root


## Deleting is for good: the password once more, then the nick, the cloud friend list and the login go.
static func confirm_delete(parent: Node, done: Callable) -> Control:
	var m := dialog(parent)
	var root: Control = m[0]
	var v: VBoxContainer = m[1]
	(v.get_parent() as PanelContainer).add_theme_stylebox_override("panel", UiKit.sbox(Color(0.05, 0.02, 0.02, 0.97), Color(1.0, 0.35, 0.3, 0.6), 2, 8, 14))
	v.add_child(UiKit.glow_label(GS.t("УДАЛИТЬ АККАУНТ?"), 28, UiKit.RED))
	note(v, GS.t("Аккаунт %s будет удалён навсегда: ник, список друзей в облаке и вход. На этом устройстве останется его собственный код.") % Net.nick(), Color(1.0, 0.8, 0.75), 15)
	var pw := field(v, GS.t("Пароль"), GS.t("для подтверждения"), "password")
	var st := note(v, "", UiKit.RED, 15)
	var go := UiKit.button(GS.t("Удалить навсегда"), func() -> void: pass)
	go.add_theme_color_override("font_color", Color(1.0, 0.5, 0.45))
	var submit := func() -> void:
		if go.disabled or pw.text == "":
			return
		go.disabled = true
		say(st, GS.t("Удаляем…"), true)
		Net.delete_account(pw.text, func(ok: bool, text: String) -> void:
			if not is_instance_valid(root):
				return
			go.disabled = false
			if ok:
				root.queue_free()
				done.call()
			else:
				say(st, text))
	go.pressed.connect(submit)
	pw.text_submitted.connect(func(_t: String) -> void: submit.call())
	v.add_child(go)
	v.add_child(UiKit.button(GS.t("Отмена"), func() -> void: root.queue_free(), 260, 18))
	pw.grab_focus.call_deferred()
	return root
