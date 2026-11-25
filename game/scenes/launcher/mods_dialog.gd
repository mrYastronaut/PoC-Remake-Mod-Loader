extends AcceptDialog
## Ventana de Mods del selector: ver, activar, ordenar, instalar desde .zip y quitar mods.
## Cada cambio se guarda y se aplica al momento (Assets.reindex + CardDB.load_db); las partidas
## empiezan siempre desde el selector, asi que no hay nada en marcha que romper.
## Estilo y estructura como cloud_dialog.gd. La logica vive en ModRegistry / ModInstaller.

const DialogTheme = preload("res://scenes/launcher/dialog_theme.gd")
const WRAP_WIDTH := 440.0
const GOLD := Color(1.0, 0.82, 0.3)
const GOLD_LIGHT := Color(1.0, 0.95, 0.7)
const OK_COLOR := Color(0.45, 0.85, 0.5)
const WARN_COLOR := Color(1.0, 0.7, 0.3)
const BAD_COLOR := Color(1.0, 0.45, 0.4)
const DIM_COLOR := Color(0.7, 0.66, 0.6)
const SVG_HEAD := "<svg xmlns='http://www.w3.org/2000/svg' width='24' height='24' viewBox='0 0 24 24' fill='none' stroke='#%s' stroke-width='2.4' stroke-linecap='round' stroke-linejoin='round'>"
const SVG_UP := "<polyline points='6 15 12 9 18 15'/></svg>"
const SVG_DOWN := "<polyline points='6 9 12 15 18 9'/></svg>"
const SVG_CHECKED := "<rect x='3' y='3' width='18' height='18' rx='4' fill='#3a2a0a'/><polyline points='7.5 12.5 10.5 15.5 16.5 8.5'/></svg>"
const SVG_UNCHECKED := "<rect x='3' y='3' width='18' height='18' rx='4'/></svg>"
const SVG_TRASH := "<polyline points='3 6 5 6 21 6'/><path d='M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6'/><path d='M10 11v6M14 11v6'/><path d='M9 6V4a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2'/></svg>"

const TEXT := {
	"s": {"skip_dependency": "Falta la dependencia (debe cargar antes): %s", "skip_engine": "Motor aún no soportado: %s", "invalid_detail": "mod.json tiene problemas:", "title": "Mods", "hint": "Los mods añaden cartas, imágenes y barajas sin tocar tus juegos. El orden importa: los últimos sobrescriben a los anteriores.",
		"none": "No hay mods instalados. Instala un .zip o copia la carpeta de un mod en la carpeta de mods.",
		"install": "Instalar .zip…", "folder": "Abrir carpeta", "close": "Cerrar", "active": "Activo", "disabled": "Desactivado",
		"invalid": "No válido", "skipped": "Omitido", "cards": "%d cartas", "up": "Subir", "down": "Bajar", "remove": "Quitar",
		"confirm_remove": "¿Quitar «%s»? Se borrará su carpeta.", "confirm_replace": "«%s» ya está instalado. ¿Reemplazarlo?",
		"installed": "Instalado «%s» (%d archivos). Márcalo para activarlo.", "install_failed": "No se pudo instalar: %s",
		"rejected": "%d archivos de mods se ignoraron (tablas protegidas o un juego que el mod no declara).",
		"scripts_allow": "Permitir mods que ejecutan código", "scripts_note": "Algunos mods incluyen scripts (código) para dar efectos a sus cartas. Un script tiene el mismo poder que el juego: actívalo solo con mods en los que confíes.", "scripts_off": "Hay mods con scripts que no funcionan hasta que permitas el código.",
		"card_errors": "Problemas con cartas:", "cards_total": "%d cartas de mods cargadas", "path": "Carpeta de mods: %s",
		"filter": "Mod (.zip)", "pick": "Elige un mod (.zip)",
		"e_open": "No se pudo abrir el archivo .zip.", "e_path": "El .zip contiene una ruta no permitida.", "e_no_manifest": "El .zip no contiene mod.json.",
		"e_many_manifests": "El .zip contiene más de un mod.json.", "e_manifest": "mod.json no es válido.", "e_too_many": "El .zip tiene demasiados archivos.",
		"e_too_big": "El .zip es demasiado grande.", "e_write": "No se pudo escribir en la carpeta de mods.", "e_cards": "cards.json no es válido.",
		"e_replace": "No se pudo reemplazar el mod."},
	"e": {"skip_dependency": "Missing dependency (it must load first): %s", "skip_engine": "Engine not supported yet: %s", "invalid_detail": "mod.json has problems:", "title": "Mods", "hint": "Mods add cards, art and decks without touching your games. Load order matters: later mods override earlier ones.",
		"none": "No mods installed. Install a .zip or copy a mod's folder into the mods folder.",
		"install": "Install .zip…", "folder": "Open folder", "close": "Close", "active": "Active", "disabled": "Disabled",
		"invalid": "Invalid", "skipped": "Skipped", "cards": "%d cards", "up": "Move up", "down": "Move down", "remove": "Remove",
		"confirm_remove": "Remove “%s”? Its folder will be deleted.", "confirm_replace": "“%s” is already installed. Replace it?",
		"installed": "Installed “%s” (%d files). Tick it to enable.", "install_failed": "Could not install: %s",
		"rejected": "%d mod files were ignored (protected tables or a game the mod doesn't declare).",
		"scripts_allow": "Allow mods that run code", "scripts_note": "Some mods ship scripts (code) that give their cards effects. A script can do anything the game can: turn this on only for mods you trust.", "scripts_off": "Some mods with scripts will not work until you allow code.",
		"card_errors": "Card problems:", "cards_total": "%d mod cards loaded", "path": "Mods folder: %s",
		"filter": "Mod (.zip)", "pick": "Choose a mod (.zip)",
		"e_open": "The .zip file could not be opened.", "e_path": "The .zip contains a disallowed path.", "e_no_manifest": "The .zip has no mod.json.",
		"e_many_manifests": "The .zip has more than one mod.json.", "e_manifest": "mod.json is not valid.", "e_too_many": "The .zip has too many files.",
		"e_too_big": "The .zip is too large.", "e_write": "Could not write to the mods folder.", "e_cards": "cards.json is not valid.",
		"e_replace": "Could not replace the mod."},
	"g": {"skip_dependency": "Abhängigkeit fehlt (muss zuerst geladen werden): %s", "skip_engine": "Engine noch nicht unterstützt: %s", "invalid_detail": "mod.json hat Probleme:", "title": "Mods", "hint": "Mods fügen Karten, Grafiken und Decks hinzu, ohne deine Spiele zu verändern. Die Reihenfolge zählt: spätere Mods überschreiben frühere.",
		"none": "Keine Mods installiert. Installiere eine .zip-Datei oder kopiere den Ordner eines Mods in den Mod-Ordner.",
		"install": ".zip installieren…", "folder": "Ordner öffnen", "close": "Schließen", "active": "Aktiv", "disabled": "Deaktiviert",
		"invalid": "Ungültig", "skipped": "Übersprungen", "cards": "%d Karten", "up": "Nach oben", "down": "Nach unten", "remove": "Entfernen",
		"confirm_remove": "„%s“ entfernen? Der Ordner wird gelöscht.", "confirm_replace": "„%s“ ist bereits installiert. Ersetzen?",
		"installed": "„%s“ installiert (%d Dateien). Hake es an, um es zu aktivieren.", "install_failed": "Installation fehlgeschlagen: %s",
		"rejected": "%d Mod-Dateien wurden ignoriert (geschützte Tabellen oder ein Spiel, das der Mod nicht angibt).",
		"scripts_allow": "Mods mit Code erlauben", "scripts_note": "Manche Mods enthalten Skripte (Code), die ihren Karten Effekte geben. Ein Skript kann alles, was das Spiel kann: Aktiviere dies nur für vertrauenswürdige Mods.", "scripts_off": "Mods mit Skripten funktionieren erst, wenn du Code erlaubst.",
		"card_errors": "Kartenprobleme:", "cards_total": "%d Mod-Karten geladen", "path": "Mod-Ordner: %s",
		"filter": "Mod (.zip)", "pick": "Mod wählen (.zip)",
		"e_open": "Die .zip-Datei konnte nicht geöffnet werden.", "e_path": "Die .zip enthält einen nicht erlaubten Pfad.", "e_no_manifest": "Die .zip enthält keine mod.json.",
		"e_many_manifests": "Die .zip enthält mehr als eine mod.json.", "e_manifest": "mod.json ist ungültig.", "e_too_many": "Die .zip enthält zu viele Dateien.",
		"e_too_big": "Die .zip ist zu groß.", "e_write": "Im Mod-Ordner konnte nicht geschrieben werden.", "e_cards": "cards.json ist ungültig.",
		"e_replace": "Der Mod konnte nicht ersetzt werden."},
	"f": {"skip_dependency": "Dépendance manquante (elle doit se charger avant) : %s", "skip_engine": "Moteur pas encore pris en charge : %s", "invalid_detail": "mod.json a des problèmes :", "title": "Mods", "hint": "Les mods ajoutent des cartes, des images et des decks sans toucher à tes jeux. L'ordre compte : les derniers écrasent les premiers.",
		"none": "Aucun mod installé. Installe un .zip ou copie le dossier d'un mod dans le dossier des mods.",
		"install": "Installer un .zip…", "folder": "Ouvrir le dossier", "close": "Fermer", "active": "Actif", "disabled": "Désactivé",
		"invalid": "Invalide", "skipped": "Ignoré", "cards": "%d cartes", "up": "Monter", "down": "Descendre", "remove": "Supprimer",
		"confirm_remove": "Supprimer « %s » ? Son dossier sera effacé.", "confirm_replace": "« %s » est déjà installé. Le remplacer ?",
		"installed": "« %s » installé (%d fichiers). Coche-le pour l'activer.", "install_failed": "Installation impossible : %s",
		"rejected": "%d fichiers de mods ont été ignorés (tables protégées ou jeu non déclaré par le mod).",
		"scripts_allow": "Autoriser les mods qui exécutent du code", "scripts_note": "Certains mods contiennent des scripts (du code) qui donnent des effets à leurs cartes. Un script peut faire tout ce que fait le jeu : n'active cette option que pour des mods de confiance.", "scripts_off": "Des mods avec scripts ne fonctionnent pas tant que tu n'autorises pas le code.",
		"card_errors": "Problèmes de cartes :", "cards_total": "%d cartes de mods chargées", "path": "Dossier des mods : %s",
		"filter": "Mod (.zip)", "pick": "Choisis un mod (.zip)",
		"e_open": "Impossible d'ouvrir le fichier .zip.", "e_path": "Le .zip contient un chemin interdit.", "e_no_manifest": "Le .zip ne contient pas de mod.json.",
		"e_many_manifests": "Le .zip contient plusieurs mod.json.", "e_manifest": "mod.json n'est pas valide.", "e_too_many": "Le .zip contient trop de fichiers.",
		"e_too_big": "Le .zip est trop volumineux.", "e_write": "Impossible d'écrire dans le dossier des mods.", "e_cards": "cards.json n'est pas valide.",
		"e_replace": "Impossible de remplacer le mod."},
	"i": {"skip_dependency": "Dipendenza mancante (deve caricarsi prima): %s", "skip_engine": "Motore non ancora supportato: %s", "invalid_detail": "mod.json ha dei problemi:", "title": "Mod", "hint": "I mod aggiungono carte, immagini e mazzi senza toccare i tuoi giochi. L'ordine conta: gli ultimi sovrascrivono i precedenti.",
		"none": "Nessun mod installato. Installa un .zip o copia la cartella di un mod nella cartella dei mod.",
		"install": "Installa .zip…", "folder": "Apri cartella", "close": "Chiudi", "active": "Attivo", "disabled": "Disattivato",
		"invalid": "Non valido", "skipped": "Saltato", "cards": "%d carte", "up": "Su", "down": "Giù", "remove": "Rimuovi",
		"confirm_remove": "Rimuovere «%s»? La sua cartella verrà eliminata.", "confirm_replace": "«%s» è già installato. Sostituirlo?",
		"installed": "«%s» installato (%d file). Spuntalo per attivarlo.", "install_failed": "Installazione non riuscita: %s",
		"rejected": "%d file dei mod sono stati ignorati (tabelle protette o un gioco che il mod non dichiara).",
		"scripts_allow": "Consenti mod che eseguono codice", "scripts_note": "Alcuni mod includono script (codice) che danno effetti alle loro carte. Uno script può fare tutto ciò che fa il gioco: attivalo solo per mod di cui ti fidi.", "scripts_off": "I mod con script non funzionano finché non consenti il codice.",
		"card_errors": "Problemi con le carte:", "cards_total": "%d carte dei mod caricate", "path": "Cartella dei mod: %s",
		"filter": "Mod (.zip)", "pick": "Scegli un mod (.zip)",
		"e_open": "Impossibile aprire il file .zip.", "e_path": "Lo .zip contiene un percorso non consentito.", "e_no_manifest": "Lo .zip non contiene mod.json.",
		"e_many_manifests": "Lo .zip contiene più di un mod.json.", "e_manifest": "mod.json non è valido.", "e_too_many": "Lo .zip contiene troppi file.",
		"e_too_big": "Lo .zip è troppo grande.", "e_write": "Impossibile scrivere nella cartella dei mod.", "e_cards": "cards.json non è valido.",
		"e_replace": "Impossibile sostituire il mod."},
	"j": {"skip_dependency": "依存MODがありません（先に読み込む必要があります）：%s", "skip_engine": "このエンジンにはまだ対応していません：%s", "invalid_detail": "mod.jsonに問題があります：", "title": "MOD", "hint": "MODは元のゲームを変更せずに、カード・画像・デッキを追加します。読み込み順が重要で、後のMODが前のMODを上書きします。",
		"none": "MODがインストールされていません。.zipをインストールするか、MODのフォルダーをMODフォルダーにコピーしてください。",
		"install": ".zipをインストール…", "folder": "フォルダーを開く", "close": "閉じる", "active": "有効", "disabled": "無効",
		"invalid": "無効なMOD", "skipped": "スキップ", "cards": "カード%d枚", "up": "上へ", "down": "下へ", "remove": "削除",
		"confirm_remove": "「%s」を削除しますか？ フォルダーも削除されます。", "confirm_replace": "「%s」はすでにインストールされています。置き換えますか？",
		"installed": "「%s」をインストールしました（%dファイル）。チェックを入れて有効にしてください。", "install_failed": "インストールできませんでした：%s",
		"rejected": "MODのファイル%d件を無視しました（保護されたテーブル、またはMODが宣言していないゲーム）。",
		"scripts_allow": "コードを実行するMODを許可", "scripts_note": "一部のMODはカードに効果を与えるスクリプト（コード）を含みます。スクリプトはゲームと同じ権限で動作するため、信頼できるMODにのみ有効にしてください。", "scripts_off": "スクリプト付きMODは、コードを許可するまで動作しません。",
		"card_errors": "カードの問題:", "cards_total": "MODカードを%d枚読み込みました", "path": "MODフォルダー：%s",
		"filter": "MOD (.zip)", "pick": "MOD（.zip）を選択",
		"e_open": ".zipファイルを開けませんでした。", "e_path": ".zipに許可されていないパスが含まれています。", "e_no_manifest": ".zipにmod.jsonがありません。",
		"e_many_manifests": ".zipにmod.jsonが複数あります。", "e_manifest": "mod.jsonが無効です。", "e_too_many": ".zipのファイル数が多すぎます。",
		"e_too_big": ".zipが大きすぎます。", "e_write": "MODフォルダーに書き込めませんでした。", "e_cards": "cards.jsonが無効です。",
		"e_replace": "MODを置き換えられませんでした。"},
}

static var _icons := {}

var _list := VBoxContainer.new()
var _scroll := ScrollContainer.new()
var _hint := Label.new()
var _status := Label.new()
var _notes := Label.new()
var _path := Label.new()
var _scripts_check := CheckBox.new()
var _scripts_note := Label.new()
var _install_button: Button
var _folder_button: Button
var _picker := FileDialog.new()
var _confirm := ConfirmationDialog.new()
var _pending := {}   # {"action": "remove" | "replace", "id", "zip"}


func _ready() -> void:
	min_size = Vector2i(560, 360)
	exclusive = true
	DialogTheme.apply(self)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Un Label con ajuste de linea sin ancho minimo calcula su alto como si cupiera una palabra
	# por linea e infla toda la ventana; con un ancho minimo el alto sale correcto.
	_hint.custom_minimum_size.x = WRAP_WIDTH
	_hint.add_theme_font_size_override("font_size", 15)
	_hint.add_theme_color_override("font_color", DIM_COLOR)
	column.add_child(_hint)
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.custom_minimum_size = Vector2(520, 150)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	_scroll.add_child(_list)
	column.add_child(_scroll)
	_style_check(_scripts_check)
	_scripts_check.toggled.connect(func(pressed: bool) -> void:
		ModScripts.set_allowed(_storage(), pressed)
		_refresh())
	column.add_child(_scripts_check)
	_scripts_note.add_theme_color_override("font_color", DIM_COLOR)
	for label: Label in [_scripts_note, _status, _notes, _path]:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = WRAP_WIDTH
		label.add_theme_font_size_override("font_size", 14)
		column.add_child(label)
	_path.add_theme_color_override("font_color", DIM_COLOR)
	add_child(column)
	_install_button = add_button("", false, "install")
	if not Paths.android_platform():
		_folder_button = add_button("", false, "folder")
	custom_action.connect(_action)
	about_to_popup.connect(_refresh)
	_picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_picker.access = FileDialog.ACCESS_FILESYSTEM
	_picker.use_native_dialog = true
	_picker.file_selected.connect(func(path: String) -> void: _install(path, false))
	add_child(_picker)
	DialogTheme.apply(_confirm, true)
	_confirm.confirmed.connect(_confirmed)
	add_child(_confirm)


## Abre la ventana ajustada a la pantalla visible (el selector puede ser de 800x600).
func open() -> void:
	# Un Window es su propio Viewport: la pantalla visible es la del padre (el selector).
	var host: Viewport = get_parent().get_viewport() if get_parent() != null else get_tree().root
	var screen := Vector2i(host.get_visible_rect().size)
	# El marco del dialogo añade la barra de titulo arriba y un margen abajo: se descuentan
	# para que el conjunto, y no solo el contenido, quede centrado y dentro de la pantalla.
	var top := DialogTheme.TITLE_HEIGHT + 6
	var bottom := 14
	var content := Vector2i(mini(740, screen.x - 60), mini(560, screen.y - top - bottom - 24))
	var origin := Vector2i((screen.x - content.x) / 2, (screen.y - content.y - top - bottom) / 2 + top)
	popup(Rect2i(origin, content))


func _t(key: String) -> String:
	return str((TEXT.get(Assets.lang, TEXT["e"]) as Dictionary).get(key, TEXT["e"].get(key, key)))


func _storage() -> String:
	return Paths.storage_dir


func _refresh() -> void:
	title = _t("title")
	get_ok_button().text = _t("close")
	_install_button.text = _t("install")
	if _folder_button != null:
		_folder_button.text = _t("folder")
	_picker.title = _t("pick")
	_picker.filters = PackedStringArray(["*.zip ; " + _t("filter")])
	_hint.text = _t("hint")
	_scripts_check.text = _t("scripts_allow")
	_scripts_check.set_pressed_no_signal(ModScripts.allowed(_storage()))
	_scripts_note.text = _t("scripts_note")
	_path.text = _t("path") % ProjectSettings.globalize_path(ModRegistry.mods_dir(_storage()))
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var rows := ModRegistry.rows(_storage())
	if rows.is_empty():
		var empty := Label.new()
		empty.text = _t("none")
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.custom_minimum_size.x = WRAP_WIDTH - 40.0
		empty.add_theme_color_override("font_color", DIM_COLOR)
		_list.add_child(empty)
	var enabled_rows := rows.filter(func(r): return r["enabled"])
	for row: Dictionary in rows:
		_list.add_child(_build_row(row, enabled_rows))
	_notes.text = _summary()
	_notes.add_theme_color_override("font_color", WARN_COLOR)


func _build_row(row: Dictionary, enabled_rows: Array) -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.07, 0.1, 0.85) if row["enabled"] else Color(0.05, 0.04, 0.05, 0.85)
	style.border_color = Color(GOLD, 0.3 if row["enabled"] else 0.12)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	panel.add_child(box)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	box.add_child(top)
	var check := CheckBox.new()
	check.text = "%s  v%s" % [row["name"], row["version"]] if row["version"] != "" else str(row["name"])
	check.button_pressed = row["enabled"]
	check.disabled = row["status"] == "invalid"
	check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	check.tooltip_text = str(row["description"])
	check.add_theme_font_size_override("font_size", 17)
	_style_check(check)
	check.toggled.connect(_toggled.bind(row["id"]))
	top.add_child(check)
	var position: int = enabled_rows.find(row)
	top.add_child(_icon_button("up", _t("up"), row["enabled"] and position > 0, _move.bind(row["id"], -1)))
	top.add_child(_icon_button("down", _t("down"), row["enabled"] and position >= 0 and position < enabled_rows.size() - 1, _move.bind(row["id"], 1)))
	top.add_child(_icon_button("trash", _t("remove"), true, _ask_remove.bind(row["id"], row["name"])))
	var meta := HBoxContainer.new()
	meta.add_theme_constant_override("separation", 14)
	var state := Label.new()
	state.text = _t(str(row["status"]))
	state.add_theme_font_size_override("font_size", 13)
	state.add_theme_color_override("font_color", {"active": OK_COLOR, "disabled": DIM_COLOR, "invalid": BAD_COLOR, "skipped": WARN_COLOR}[row["status"]])
	meta.add_child(state)
	var parts: Array = [" · ".join((row["games"] as Array).map(func(g): return str(g).to_upper()))]
	if int(row["cards"]) > 0:
		parts.append(_t("cards") % int(row["cards"]))
	if row["author"] != "":
		parts.append(str(row["author"]))
	var info := Label.new()
	info.text = "   ".join(parts)
	info.add_theme_font_size_override("font_size", 13)
	info.add_theme_color_override("font_color", DIM_COLOR)
	meta.add_child(info)
	box.add_child(meta)
	var detail_text := _reason(row)
	if detail_text != "":
		var detail := Label.new()
		detail.text = detail_text
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail.custom_minimum_size.x = WRAP_WIDTH - 60.0
		detail.add_theme_font_size_override("font_size", 13)
		detail.add_theme_color_override("font_color", BAD_COLOR if row["status"] == "invalid" else WARN_COLOR)
		box.add_child(detail)
	return panel


func _style_check(check: CheckBox) -> void:
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		check.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = GOLD
	focus.set_border_width_all(1)
	focus.set_corner_radius_all(6)
	check.add_theme_stylebox_override("focus", focus)
	check.add_theme_icon_override("checked", _icon("checked"))
	check.add_theme_icon_override("unchecked", _icon("unchecked"))
	check.add_theme_icon_override("checked_disabled", _icon("checked"))
	check.add_theme_icon_override("unchecked_disabled", _icon("unchecked_off"))
	check.add_theme_constant_override("h_separation", 10)


## Motivo traducido de por que un mod esta omitido o es invalido (el detalle tecnico va detras).
func _reason(row: Dictionary) -> String:
	if row["status"] == "invalid":
		return "%s %s" % [_t("invalid_detail"), row["detail"]]
	if row["status"] == "skipped":
		match row["reason_code"]:
			"dependency":
				return _t("skip_dependency") % row["reason_arg"]
			"engine":
				return _t("skip_engine") % row["reason_arg"]
		return str(row["detail"])
	return ""


func _icon_button(icon: String, tip: String, enabled: bool, callback: Callable) -> Button:
	var button := Button.new()
	button.icon = _icon(icon)
	button.tooltip_text = tip
	button.disabled = not enabled
	button.custom_minimum_size = Vector2(38, 34)
	button.pressed.connect(callback)
	return button


static func _icon(name: String) -> Texture2D:
	if not _icons.has(name):
		var body: String = {"up": SVG_UP, "down": SVG_DOWN, "trash": SVG_TRASH, "checked": SVG_CHECKED,
				"unchecked": SVG_UNCHECKED, "unchecked_off": SVG_UNCHECKED}[name]
		var color := GOLD if name in ["checked", "unchecked"] else (DIM_COLOR if name == "unchecked_off" else GOLD_LIGHT)
		var image := Image.new()
		image.load_svg_from_string((SVG_HEAD % color.to_html(false)) + body, 0.9 if name.begins_with("check") or name.begins_with("unchecked") else 0.8)
		_icons[name] = ImageTexture.create_from_image(image)
	return _icons[name]


func _summary() -> String:
	var lines := PackedStringArray()
	if not ModScripts.allowed(_storage()):
		for row: Dictionary in ModRegistry.rows(_storage()):
			if row["enabled"] and not (row["scripts"] as Array).is_empty():
				lines.append(_t("scripts_off"))
				break
	if not Assets.mod_rejected.is_empty():
		lines.append(_t("rejected") % Assets.mod_rejected.size())
	if not ModCards.last_errors.is_empty():
		lines.append(_t("card_errors"))
		for message in ModCards.last_errors.slice(0, 5):
			lines.append("  · " + str(message))
		if ModCards.last_errors.size() > 5:
			lines.append("  · …")
	return "\n".join(lines)


## Guarda, aplica al instante (indice de archivos + cartas) y repinta.
func _apply() -> void:
	Assets.reindex()
	CardDB.load_db()
	_refresh()
	if CardDB.mod_cards.size() > 0:
		_status.add_theme_color_override("font_color", OK_COLOR)
		_status.text = _t("cards_total") % CardDB.mod_cards.size()


func _toggled(pressed: bool, id: String) -> void:
	_status.text = ""
	if pressed:
		ModRegistry.enable(_storage(), id)
	else:
		ModRegistry.disable(_storage(), id)
	_apply()


func _move(id: String, delta: int) -> void:
	_status.text = ""
	ModRegistry.move(_storage(), id, delta)
	_apply()


func _ask_remove(id: String, mod_name: String) -> void:
	_pending = {"action": "remove", "id": id}
	_confirm.dialog_text = _t("confirm_remove") % mod_name
	_confirm.get_ok_button().text = _t("remove")
	_confirm.get_cancel_button().text = _t("close")
	_confirm.popup_centered()


func _action(action: StringName) -> void:
	match action:
		"install":
			_picker.popup_centered_ratio(0.7)
		"folder":
			var dir := ModRegistry.mods_dir(_storage())
			DirAccess.make_dir_recursive_absolute(dir)
			OS.shell_open(ProjectSettings.globalize_path(dir))


func _confirmed() -> void:
	var pending := _pending
	_pending = {}
	match pending.get("action", ""):
		"remove":
			ModRegistry.remove(_storage(), pending["id"])
			_status.text = ""
			_apply()
		"replace":
			_install(pending["zip"], true)


func _install(zip_path: String, replace: bool) -> void:
	var result := ModInstaller.install_zip(_storage(), zip_path, replace)
	if result["ok"]:
		_status.add_theme_color_override("font_color", OK_COLOR)
		_status.text = _t("installed") % [result["id"], result["files"]]
		_apply_after_install()
	elif result["exists"]:
		_pending = {"action": "replace", "zip": zip_path}
		_confirm.dialog_text = _t("confirm_replace") % result["id"]
		_confirm.get_ok_button().text = _t("install")
		_confirm.get_cancel_button().text = _t("close")
		_confirm.popup_centered()
	else:
		_status.add_theme_color_override("font_color", BAD_COLOR)
		_status.text = _t("install_failed") % ("%s (%s)" % [_t("e_" + str(result["code"])), result["error"]])


## Tras instalar no se activa solo: se repinta y se deja el mensaje de exito.
func _apply_after_install() -> void:
	var message := _status.text
	_refresh()
	_status.text = message
