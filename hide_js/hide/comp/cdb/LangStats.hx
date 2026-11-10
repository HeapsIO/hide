package hide.comp.cdb;

/**
	A popup with the count of the lines of each sheet by status of their localizable texts, in all the translations (the worst one).
	The lines ignored by the localization export are not counted.
**/
class LangStats {

	public static function open() {
		var ide = Ide.inst;
		var langDir = ide.resourceDir + "/lang";
		var files = sys.FileSystem.exists(langDir) ? [for( f in sys.FileSystem.readDirectory(langDir) ) if( StringTools.startsWith(f, "export_") && StringTools.endsWith(f, ".xml") ) langDir + "/" + f] : [];
		if( files.length == 0 ) {
			ide.quickError("No translation found in " + langDir);
			return;
		}
		var langs = [for( f in files ) Editor.loadLang(f)];

		function row( name : String, counts : Array<Int>, cl = "" ) {
			// the worst status with lines
			var badge = counts[3] > 0 ? '<span class="loc-outdated">NEED SEND</span>'
				: counts[2] > 0 ? '<span class="loc-pending">PENDING</span>'
				: counts[1] > 0 ? '<span class="loc-ok">OK</span>'
				: "";
			return '<tr class="$cl" data-sheet="${StringTools.htmlEscape(name, true)}"><td>${StringTools.htmlEscape(name)}</td><td class="status">$badge</td>' + [for( c in counts ) '<td>$c</td>'].join("") + "</tr>";
		}

		var rows = "";
		var all = [0, 0, 0, 0];
		for( s in ide.database.sheets ) {
			if( s.props.hide )
				continue;

			var counts = [0, 0, 0, 0];
			for( i => obj in s.lines )
				Editor.visitLangLines(langs, { sheet : s, obj : obj, index : i }, st -> {
					counts[0]++;
					counts[(st : Int) + 1]++;
				});
			if( counts[0] == 0 )
				continue;
			for( i => c in counts )
				all[i] += c;
			rows += row(s.name, counts);
		}

		var modal = new hide.comp.Modal.Modal2(new Element("body"), "Localisation Stats", "cdb-lang-stats");
		modal.content.get(0).innerHTML = '<table class="cdb-lang-stats">'
			+ "<tr><th>Sheet</th><th>Status</th><th>Total</th><th>Up To Date</th><th>Pending</th><th>Need Send</th></tr>"
			+ row("All", all, "all")
			+ rows
			+ "</table>";

		// opens the sheet of the row, filtered by the status of the column
		modal.content.get(0).onclick = function( e : js.html.MouseEvent ) {
			var td : js.html.TableCellElement = cast (cast e.target : js.html.Element).closest("td");
			if( td == null || td.parentElement.classList.contains("all") )
				return;
			var sheet = ide.database.getSheet(td.parentElement.dataset.sheet);
			var filter : Null<Editor.LangFilter> =switch( td.cellIndex ) {
				case 1:
					var badge = td.firstElementChild;
					badge == null ? null : badge.classList.contains("loc-outdated") ? NeedSend : badge.classList.contains("loc-pending") ? Pending : UpToDate;
				case 3: UpToDate;
				case 4: Pending;
				case 5: NeedSend;
				default: null;
			}
			modal.close();
			ide.open("hide.view.cdb.CdbTable", {}, null, v -> Std.downcast(v, hide.view.cdb.CdbTable).showLangStatus(sheet, filter));
		}
	}
}
