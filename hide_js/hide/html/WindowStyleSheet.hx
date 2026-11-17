package hide.html;

/**
	Css text with one `CSSStyleSheet` per window : a constructed sheet only applies to the documents of the window that created it.
**/
class WindowStyleSheet {
	var css : String;
	var sheets : Array<{win : js.html.Window, sheet : js.html.CSSStyleSheet}> = [];

	public function new(css : String) {
		this.css = css;
	}

	public function get(win : js.html.Window) : js.html.CSSStyleSheet {
		for (s in sheets)
			if (s.win == win)
				return s.sheet;

		sheets = [for (s in sheets) if (!s.win.closed) s];
		var sheet : js.html.CSSStyleSheet = js.Syntax.code("new {0}.CSSStyleSheet()", win);
		sheet.replaceSync(css);
		sheets.push({win: win, sheet: sheet});
		return sheet;
	}

	public function update(css : String) {
		this.css = css;
		for (s in sheets)
			if (!s.win.closed)
				s.sheet.replaceSync(css);
	}
}
