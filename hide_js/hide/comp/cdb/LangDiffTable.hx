package hide.comp.cdb;

/**
	The differences between the original text of a localizable cell and the ones of its translation, read only.
**/
class LangDiffTable extends SubTable {

	override function makeSubSheet():cdb.Sheet {
		var sheet = cell.table.sheet;
		var index = cell.line.index;
		var key = sheet.getPath() + "@" + cell.column.name + ":" + index;
		this.lines = [];
		return new cdb.Sheet(editor.base, {
			columns : [cell.column],
			props : {},
			name : key,
			lines : [cell.line.obj],
			separators: [],
		}, key, { sheet : sheet, column : cell.columnIndex, line : index });
	}

	override function setCursor() {
	}

	override function refresh() {
		var texts = editor.lang.sheets.getOriginals(cell.line, cell.column, Reflect.field(cell.line.obj, cell.column.name));
		// the old file can have a source text without translation
		var status = editor.lang.sheets.getStatus(cell.line, cell.column, texts.current);
		var exported = status == Missing ? "" : texts.exported;

		// null without loaded .loc file
		var sentStatus = editor.lang.sheets.getSentStatus(cell.line, cell.column, texts.current);
		var sent = status == UpToDate ? texts.current : sentStatus == NotSent ? "" : texts.sent;

		var root : js.html.Element = element.get(0);
		root.classList.add("cdb-lang-diff");
		root.innerHTML = "<tr>"
			+ "<th title='The translated text'>Translation</th>"
			+ "<th title='Difference between the CDB source text when this text was translated and the one in CDB right now'>Source at Export vs CDB</th>"
			+ "<th title='Difference between the CDB source text when the text was sent for translation and the one in CDB right now'>Source when Sent vs CDB</th>"
			+ "</tr>";
		var tr = js.Browser.document.createTableRowElement();
		root.appendChild(tr);

		var translated = editor.lang.sheets.getTranslation(cell.line, cell.column);
		tr.insertCell().innerHTML = translated == null ? "<i>No Translation</i>" : StringTools.htmlEscape(translated);

		// statusClasses : the status classes of the cell shown as badges, dimmed without difference
		function addDiff( old : Null<String>, missing : String, statusClasses : Array<String> ) {
			var td = tr.insertCell();
			for( c in statusClasses )
				if( cell.elementHtml.classList.contains(c) )
					td.classList.add(c);
			td.style.setProperty("--loc-version", cell.elementHtml.style.getPropertyValue("--loc-version"));
			td.classList.toggle("no-diff", old == texts.current);

			function words( s : String ) return s == "" ? [] : s.split(" ");
			var html = old == null ? '<i>$missing</i>' : new hrt.prefab.Diff.DiffText(words(old), words(texts.current)).toHtml();
			td.innerHTML = '<span class="loc-badges"></span>' + html;
		}
		addDiff(exported, "Unknown", ["loc-missing", "loc-outdated", "loc-uptodate"]);
		addDiff(sent, "Load a .loc file to see the send status", status == UpToDate ? ["loc-uptodate"] : ["loc-notsent", "loc-sent", "loc-sentoutdated"]);

		lines = [new Line(this, [], 0, new Element(tr))];
		alignUnderCell();
	}
}
