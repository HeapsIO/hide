package hide.comp.cdb;

import hxd.Key in K;
using hide.tools.Extensions;

enum PathPart {
	Id(idCol:String, name:String, ?targetCol: String);
	Prop(name: String);
	Line(lineNo:Int, ?targetCol: String);
	Script(lineNo:Int);
}

typedef Path = Array<PathPart>;

enum Direction {
	Left;
	Right;
}
typedef UndoSheet = {
	var sheet : String;
	var parent : { sheet : UndoSheet, line : Int, column : Int };
}

typedef UndoState = {
	var data : Any;
	var sheet : String;
	var cursor : Cursor.CursorState;
	var tables : Array<UndoSheet>;
}

typedef EditorApi = {
	function load( data : Any ) : Void;
	function copy() : Any;
	function save() : Void;
}

typedef EditorColumnProps = {
	var ?formula : String;
	var ?ignoreExport : Bool;
	var ?copyPasteImmutable : Bool;
	var ?categories : Array<String>;
}

typedef EditorSheetProps = {
	var ?categories : Array<String>;
}

@:allow(hide.comp.cdb)
class Editor extends Component {
	static var COMPARISON_EXPR_CHARS = ["!=", ">=", "<=", "==", "<", ">"];

	var base : cdb.Database;
	var currentSheet : cdb.Sheet;
	var existsCache : Map<String,{ t : Float, r : Bool }> = new Map();
	var tables : Array<Table> = [];
	var pendingSearchRefresh : haxe.Timer = null;
	var displayMode : Table.DisplayMode;
	var clipboard : {
		text : String,
		data : Array<{}>,
		schema : Array<cdb.Data.Column>,
	};
	var changesDepth : Int = 0;
	var api : EditorApi;
	var undoState : Array<UndoState> = [];
	var currentValue : Any;
	var cdbTable : hide.view.CdbTable;

	var searchBox : Element;
	var searchHidden : Bool = true; // Search through hidden categories
	var searchExp : Bool = false; // Does filters are parsed by hscript parser
	var filters : Array<String> = [];

	public var view : cdb.DiffFile.ConfigView;
	public var config : hide.Config;
	public var cursor : Cursor;
	public var keys : hide.ui.Keys;
	public var undo : hide.ui.UndoHistory;
	public var formulas : Formulas;
	public var showGUIDs = false;

	public var gradientEditor: GradientEditor;

	public function new(config, api, ?cdbTable) {
		super(null,null);
		this.api = api;
		this.config = config;
		this.cdbTable = cdbTable;
		view = cast this.config.get("cdb.view");
		undo = new hide.ui.UndoHistory();
	}

	public function getCurrentSheet() {
		return currentSheet == null ? null : currentSheet.name;
	}

	public function show( sheet, ?parent : Element ) {
		if( element != null ) element.remove();
		element = new Element('<div>');
		if( parent != null )
			parent.append(element);
		currentSheet = sheet;
		element.attr("tabindex", 0);
		element.addClass("is-cdb-editor");
		element.data("cdb", this);
		element.on("blur", function(_) cursor.hide());
		element.on("keypress", function(e) {
			if( e.target.nodeName == "INPUT" )
				return;
			var cell = cursor.getCell();
			if( cell != null && cell.isTextInput() && !e.ctrlKey)
				cell.edit();
		});
		element.contextmenu(function(e) e.preventDefault());

		if( cdbTable == null ) {
			element.mousedown(onMouseDown);
			keys = new hide.ui.Keys(element);
		} else {
			cdbTable.element.off("mousedown" #if js, onMouseDown #end);
			cdbTable.element.mousedown(onMouseDown);
			keys = cdbTable.keys;
		}

		keys.clear();
		keys.addListener(onKey);
		keys.register("view.reopenLastClosedTab", function() ide.reopenLastClosedTab());
		keys.register("search", function() {
			searchBox.show();
			searchBox.find("input").val("").focus().select();
		});
		keys.register("copy", onCopy);
		keys.register("paste", onPaste);
		keys.register("delete", onDelete);
		keys.register("cdb.showReferences", () -> showReferences());
		keys.register("undo", function() undo.undo());
		keys.register("redo", function() undo.redo());
		keys.register("cdb.moveBack", () -> cursor.jump(true));
		keys.register("cdb.moveAhead", () -> cursor.jump(false));
		keys.register("cdb.insertLine", function() { cursor.table.insertLine(cursor.y); cursor.move(0,1,false,false,false); });
		keys.register("duplicate", function() { cursor.table.duplicateLine(cursor.y); cursor.move(0,1,false,false,false); });
		for( k in ["cdb.editCell","rename"] )
			keys.register(k, function() {
				var c = cursor.getCell();
				if( c != null) c.edit();
			});
		keys.register("cdb.closeList", function() {
			var c = cursor.getCell();
			var sub = Std.downcast(c == null ? cursor.table : c.table, SubTable);
			if (sub == null)
				sub = c.line.subTable != null && c.line.subTable.cell == c ? c.line.subTable : null;

			if( sub != null ) {
				sub.cell.elementHtml.click();
				return;
			}
			if( cursor.selection != null ) {
				cursor.selection = null;
				cursor.addElementToSelection(c.table, c.line, c.columnIndex, c.line.index);
				cursor.update();
			}
		});
		keys.register("cdb.gotoReference", () -> gotoReference(cursor.getCell()));
		keys.register("cdb.globalSeek", () -> new GlobalSeek(cdbTable.element, cdbTable, Sheets, currentSheet));
		keys.register("cdb.sheetSeekIds", () -> new GlobalSeek(cdbTable.element, cdbTable, LocalIds, currentSheet));
		keys.register("cdb.globalSeekIds", () -> new GlobalSeek(cdbTable.element, cdbTable, GlobalIds, currentSheet));

		base = sheet.base;
		if( cursor == null )
			cursor = new Cursor(this);
		// else if ( !tables.contains(cursor.table) ) //TODO(lv): needed ?
		// 	cursor.set();
		if( displayMode == null ) displayMode = Table;
		DataFiles.load();
		if( currentValue == null ) currentValue = api.copy();
		refresh();
	}

	function onMouseDown( e : hide.Element.Event ) {
		switch ( e.which ) {
		case 4:
			cursor.jump(true);
			return false;
		case 5:
			cursor.jump(false);
			return false;
		}
		return true;
	}

	function onKey( e : hide.Element.Event ) {
		var isRepeat: Bool = untyped e.originalEvent.repeat;
		switch( e.keyCode ) {
		case K.LEFT:
			if (e.altKey) {
				cursor.jump(true);
				return true;
			}
			cursor.move( -1, 0, e.shiftKey, e.ctrlKey, e.altKey);
			return true;
		case K.RIGHT:
			if (e.altKey) {
				cursor.jump(false);
				return true;
			}
			cursor.move( 1, 0, e.shiftKey, e.ctrlKey, e.altKey);
			return true;
		case K.UP:
			cursor.move( 0, -1, e.shiftKey, e.ctrlKey, e.altKey);
			return true;
		case K.DOWN:
			cursor.move( 0, 1, e.shiftKey, e.ctrlKey, e.altKey);
			return true;
		case K.TAB:
			cursor.move( e.shiftKey ? -1 : 1, 0, false, false, true);
			return true;
		case K.PGUP:
			var scrollView = element.parent(".hide-scroll");
			var stickyElHeight = scrollView.find(".separator").height();
			if (Math.isNaN(stickyElHeight))
				stickyElHeight = scrollView.find("thead").outerHeight();
			else
				stickyElHeight += scrollView.find("thead").outerHeight();

			var lines = scrollView.find("tbody").find(".start");
			var idx = lines.length - 1;
			while (idx >= 0) {
				var b = lines[idx].getBoundingClientRect();
				if (b.top <= stickyElHeight)
					break;
				idx--;
			}

			cursor.setDefault(cursor.table, cursor.x, idx);
			lines.get(idx).scrollIntoView({ block: js.html.ScrollLogicalPosition.END });

			// Handle sticky elements
			scrollView.scrollTop(scrollView.scrollTop() + scrollView.parent().siblings(".tabs-header").outerHeight());

			return true;
		case K.PGDOWN:
			var scrollView = element.parent(".hide-scroll");
			var height = scrollView.outerHeight() - (scrollView.find("thead").outerHeight() + scrollView.parent().siblings(".tabs-header").outerHeight());
			var lines = scrollView.find("tbody").find(".start");
			var idx = 0;
			for (el in lines) {
				var b = el.getBoundingClientRect();
				if (b.top >= height)
					break;
				idx++;
			}

			if (idx > lines.length - 1)
				idx = lines.length - 1;
			lines.get(idx).scrollIntoView(true);
			cursor.setDefault(cursor.table, cursor.x, idx);

			// Handle sticky elements
			var sepHeight = scrollView.find(".separator").height();
			if (Math.isNaN(sepHeight))
				sepHeight = 0;
			scrollView.scrollTop(scrollView.scrollTop() - (scrollView.find("thead").height() + sepHeight));

			return true;
		case K.SPACE:
			e.preventDefault(); // prevent scroll
		case K.ESCAPE:
			var c = cursor.getCell();
			var sub = Std.downcast(c == null ? cursor.table : c.table, SubTable); // Prevent closing search filter befor closing list
			if (sub == null && !isRepeat && searchBox != null && searchBox.is(":visible")) {
				searchBox.find(".close-search").click();
				return true;
			}
		}
		return false;
	}

	public dynamic function onScriptCtrlS() {
	}


	public function updateFilters() {
		if (filters.length > 0)
			searchFilter(filters, false);
	}

	function searchFilter( newFilters : Array<String>, updateCursor : Bool = true ) {
		function removeAccents(str: String) {
			var t = untyped str.toLowerCase().normalize('NFD');
			return ~/[\u0300-\u036f]/g.map(t, (r) -> "");
		}

		// Clean new filters
		var idx = newFilters.length;
		while (idx >= 0) {
			if (newFilters[idx] == null || newFilters[idx] == "")
				newFilters.remove(newFilters[idx]);

			idx--;
		}

		filters = newFilters;

		var table = tables.filter((t) -> t.sheet == currentSheet)[0];
		if (filters.length <= 0) @:privateAccess {
			if (table.lines != null) {
				for (l in table.lines)
					l.element.removeClass("filtered");
			}
			if (table.separators != null) {
				for (s in table.separators) {
					s.filtered = false;
					s.refresh(false);
				}
			}
			searchBox.find("#results").text('No results');
			return;
		}

		var isFiltered : (line: Dynamic) -> Bool;
		if (searchExp) {
			var parser = new hscript.Parser();
			parser.allowMetadata = true;
			parser.allowTypes = true;
			parser.allowJSON = true;

			var sheetNames = new Map();
				for( s in this.base.sheets )
					sheetNames.set(Formulas.getTypeName(s), s);

			function replaceRec( e : hscript.Expr ) {
				switch( e.e ) {
				case EField({ e : EIdent(s) }, name) if( sheetNames.exists(s) ):
					if( sheetNames.get(s).idCol != null )
						e.e = EConst(CString(name)); // replace for faster eval
				default:
					hscript.Tools.iter(e, replaceRec);
				}
			}

			var interp = new hscript.Interp();
			this.formulas.evaluateAll(this.currentSheet.realSheet);

			isFiltered = function(line: Dynamic) {
				@:privateAccess interp.resetVariables();
				@:privateAccess interp.initOps();

				interp.variables.set("Math", Math);

				// Need deep copy here, not ideal but works
				var cloned = haxe.Json.parse(haxe.Json.stringify(table.sheet.lines[line.index]));
				for (f in Reflect.fields(cloned)) {
					var c = table.columns[0];
					for (col in table.columns) {
						if (col.name == f) {
							c = col;
							break;
						}
					}

					switch(c.type) {
						case cdb.Data.ColumnType.TEnum(e):
							interp.variables.set(f, e[Reflect.getProperty(cloned, f)]);
						default:
							interp.variables.set(f, Reflect.getProperty(cloned, f));
					}
				}

				// Check if the current line is filtered or not
				for (f in filters) {
					var expr = try parser.parseString(f) catch( e : Dynamic ) { return true; }
					replaceRec(expr);

					var res = try interp.execute(expr) catch( e : hscript.Expr.Error ) { return true; } // Catch errors that can be thrown if search input text is not interpretabled
					if (res)
						return false;
				}

				return true;
			}
		}
		else {
			isFiltered = function(line: hide.comp.cdb.Line) {
				var content = removeAccents(line.element.get(0).textContent);
				for (f in filters)
					if (content.indexOf(removeAccents(f)) >= 0)
						return false;

				return true;
			}
		}

		// Create hidden lines to ensure they are take into account while searching
		if (searchHidden) {
			for (l in table.lines) {
				if (l.element.hasClass("hidden"))
					l.create();
			}
		}

		for (s in @:privateAccess table.separators)
			@:privateAccess s.filtered = true;

		var results = 0;
		for (l in table.lines) {
			var filtered = isFiltered(l);
			l.element.toggleClass("filtered", filtered);
			if (!filtered) {
				results++;
				var seps = Separator.getParentSeparators(l.index, @:privateAccess table.separators);
				for (s in seps)
					@:privateAccess s.filtered = false;
			}
		}

		for (s in @:privateAccess table.separators)
			s.refresh(false);

		// Force show lines that are not filtered (even if their parent sep is collapsed)
		for (l in table.lines) {
			if (l.element.hasClass("hidden") && !l.element.hasClass("filtered"))
				l.create();
		}

		searchBox.find("#results").text(results > 0 ? '$results Results' : 'No results');

		if (updateCursor)
			cursor.update();
	}


	function stringToCol(str : String) : Null<Int> {
		str = str.toUpperCase();
		var hexChars = "0123456789ABCDEF";
		if( str.charAt(0) == "#" )
			str = str.substr(1, str.length);
		for( i in new haxe.iterators.StringIterator(str) ) {
			if( hexChars.indexOf(String.fromCharCode(i)) == -1 )
				return null;
		}
		var color = Std.parseInt("0x"+str);
		if( str.length == 6 )
			return color;
		else if( str.length == 3 ) {
			var r = color >> 8;
			var g = (color & 0xF0) >> 4;
			var b = color & 0xF;
			r |= r << 4;
			g |= g << 4;
			b |= b << 4;
			color = (r << 16) | (g << 8) | b;
			return color;
		}
		return null;
	}

	/* Change the id of a cell, propagating the changes to all the references in the database
	*/
	function changeID(obj : Dynamic, newValue : Dynamic, column : cdb.Data.Column, table : Table) {
		if (column.type != TId)
			throw "Target column is not an ID";
		var value = Reflect.getProperty(obj, column.name);
		var prevValue = value;
		var realSheet = table.getRealSheet();
		var isLocal = realSheet.idCol.scope != null;
		var parentID = isLocal ? table.makeId([],realSheet.idCol.scope,null) : null;
		// most likely our obj, unless there was a #DUP
		var prevObj = value != null ? realSheet.index.get(isLocal ? parentID+":"+value : value) : null;
		// have we already an obj mapped to the same id ?
		var prevTarget = realSheet.index.get(isLocal ? parentID+":"+newValue : newValue);

		{
			beginChanges();
			if( prevObj == null || prevObj.obj == obj ) {
				// remap
				var m = new Map();
				m.set(value, newValue);
				if( isLocal ) {
					var scope = table.getScope();
					var parent = scope[scope.length - realSheet.idCol.scope];
					base.updateLocalRefs(realSheet, m, parent.obj, parent.s);
				} else
					base.updateRefs(realSheet, m);
			}
			Reflect.setField(obj, column.name, newValue);
			endChanges();
			refreshRefs();

			// Refresh display of all ids in the column manually
			var colId = table.sheet.columns.indexOf(column);
			for (l in table.lines) {
				if (l.cells[colId] != null)
					l.cells[colId].refresh(false);
			}
		}

		if( prevTarget != null || (prevObj != null && (prevObj.obj != obj || (table.sheet.index != null && table.sheet.index.get(prevValue) != null))) )
			table.refresh();
	}

	function onCopy() {
		if( cursor.selection == null )
			return;
		var data = [];
		var isProps = (cursor.table.displayMode != Table);
		var schema = [];
		function saveValue(out, obj, c) {
			var form = @:privateAccess formulas.getFormulaNameFromValue(obj, c);
			if( form != null ) {
				Reflect.setField(out, c.name+"__f", form);
				return;
			}

			var v = Reflect.field(obj, c.name);
			if( v != null )
				Reflect.setField(out, c.name, v);
		}
		if( isProps ) {
			var out = {};
			for (sel in cursor.selection) {
				for( y in sel.y1...sel.y2+1 ) {
					var line = cursor.table.lines[y];
					var obj = line.obj;
					var c = line.columns[0];

					saveValue(out, obj, c);
					schema.push(c);
				}
				data.push(out);
			}
		} else {
			for (sel in cursor.selection) {
				for( y in sel.y1...sel.y2+1 ) {
					var obj = cursor.table.lines[y].obj;
					var out = {};
					var start = sel.x1;
					var end = sel.x2 + 1;
					if (start < 0) {
						start = 0;
						end = cursor.table.columns.length;
					}

					for( x in start...end ) {
						var c = cursor.table.columns[x];
						saveValue(out, obj, c);
						schema.pushUnique(c);
					}
					data.push(out);
				}
			}
		}

		// In case we only have one value, just copy the cell value
		if (data.length == 1 && Reflect.fields(data[0]).length == 1) {
			var colName = Reflect.fields(data[0])[0];
			var col = cursor.table.columns.find((c) -> c.name == colName);
			if (col == null)
				throw "unknown column";

			// if we are a property or a list, fallback to the default case
			if (col.type != TProperties && col.type != TList) {
				var escape = switch(col.type) {
					case TGradient, TCurve:
						true;
					default:
						false;
				};

				var str = cursor.table.sheet.colToString(col, Reflect.field(data[0], colName), escape);

				clipboard = {
					data : data,
					text : str,
					schema : schema,
				};

				ide.setClipboard(str);
				return;
			}
		}
		// copy many values at once
		clipboard = {
			data : data,
			text : Std.string([for( o in data ) cursor.table.sheet.objToString(o,true)]),
			schema : schema,
		};
		ide.setClipboard(clipboard.text);
	}

	function onPaste() {
		var text = ide.getClipboard();

		if (this.cursor.table == null)
			return;

		var targetCells = cursor.getSelectedCells();

		var columns = cursor.table.columns;
		var sheet = cursor.table.sheet;
		var realSheet = cursor.table.getRealSheet();
		var allLines = cursor.table.lines;

		var fullRefresh = false;
		var toRefresh : Array<Cell> = [];

		var isProps = (cursor.table.displayMode != Table);
		if( clipboard == null || text != clipboard.text ) {
			if( cursor.x < 0 || cursor.y < 0 ) return;
			function parseText(text, type : cdb.Data.ColumnType) : Dynamic {
				switch( type ) {
				case TId:
					if( ~/^[A-Za-z0-9_]+$/.match(text) )
						return text;
				case TString:
					return text;
				case TFile:
					return ide.makeRelative(text);
				case TInt:
					text = text.split(",").join("").split(" ").join("");
					return Std.parseInt(text);
				case TFloat:
					text = text.split(",").join("").split(" ").join("");
					var value = Std.parseFloat(text);
					if( Math.isNaN(value) )
						return null;
					return value;
				case TColor:
					return stringToCol(text);
				case TGradient:
					try {
						var json = haxe.Json.parse(text);
						var grad : cdb.Types.Gradient = {colors: [], positions: []};
						if (Reflect.hasField(json, "stops")) {
							for (i => stop in (json.stops: Array<Dynamic>)) {
								grad.data.colors[i] = stop.color;
								grad.data.positions[i] = stop.position;
							}
						}
						else if (Reflect.hasField(json, "colors") && Reflect.hasField(json, "positions")) {
							grad.data.colors = json.colors;
							grad.data.positions = json.positions;
						}

						return grad;
					} catch (_) {
						return null;
					}
				default:
				}
				return null;
			}

			if( isProps ) {
				var line = cursor.getLine();
				toRefresh.push(cursor.getCell());
				var col = line.columns[cursor.x];
				var p = Editor.getColumnProps(col);

				if( !cursor.table.canEditColumn(col.name) || p.copyPasteImmutable)
					return;

				var value = parseText(text, col.type);
				if( value == null )
					return;
				beginChanges();
				var obj = line.obj;
				formulas.removeFromValue(obj, col);
				Reflect.setField(obj, col.name, value);
			} else {
				beginChanges();
				var col = columns[cursor.x];
				var p = Editor.getColumnProps(col);
				if( cursor.table.canEditColumn(col.name) && !p.copyPasteImmutable) {
					var lines = cursor.y == cursor.y ? [text] : text.split("\n");
					var text = lines[0];
					if( text == null ) text = lines[lines.length - 1];
					var value = parseText(text, col.type);
					if( value != null ) {
						var obj = sheet.lines[cursor.y];
						formulas.removeFromValue(obj, col);
						Reflect.setField(obj, col.name, value);
						toRefresh.push(allLines[cursor.y].cells[cursor.x]);
					}
				}
			}
			formulas.evaluateAll(realSheet);
			endChanges();
			realSheet.sync();
			for( c in toRefresh ) {
				c.refresh(true);
			}
			refreshRefs();
			return;
		}

		function setValue(cliObj, destObj, clipSchema : cdb.Data.Column, destCol : cdb.Data.Column) {
			var form = Reflect.field(cliObj, clipSchema.name+"__f");

			if( form != null && destCol.type.equals(clipSchema.type) ) {
				formulas.setForValue(destObj, sheet, destCol, form);
				return;
			}

			var f = base.getConvFunction(clipSchema.type, destCol.type);
			var v : Dynamic = Reflect.field(cliObj, clipSchema.name);
			if (f == null) {
				switch ([clipSchema.type, destCol.type]) {
					case [TId, TRef(destSheet)]:
						if (v != null)
							v = haxe.Json.parse(haxe.Json.stringify(v));

						if (!doesSheetContainsId(base.getSheet(destSheet), v))
							v = base.getDefault(destCol, sheet);
					case [TRef(_), TId]:
					// do nothing
					default:
						v = base.getDefault(destCol, sheet);
				}
			}
			else {
				// make a deep copy to erase references
				if( v != null ) v = haxe.Json.parse(haxe.Json.stringify(v));
				if( f.f != null )
					v = f.f(v);
			}
			if( v == null && !destCol.opt )
				v = base.getDefault(destCol, sheet);

			if (destCol.type == TId) {
				v = ensureUniqueId(v, cursor.table, destCol);
				if (v != null) {
					changeID(destObj, v, destCol, cursor.table);
				}
				return;
			}
			if( v == null )
				Reflect.deleteField(destObj, destCol.name);
			else
				Reflect.setField(destObj, destCol.name, v);
		}

		var posX = cursor.x < 0 ? 0 : cursor.x;
		var posY = cursor.y < 0 ? 0 : cursor.y;
		var data = clipboard.data;
		if( data.length == 0 )
			return;

		if( isProps ) {
			var obj1 = data[0];
			var obj2 = cursor.getLine().obj;
			if( clipboard.schema.length == 1 ) {
				var clipSchema = clipboard.schema[0];
				if (clipSchema == null) return;
				beginChanges();
				for (c in targetCells) {
					var col = c.column;
					if (!c.table.canEditColumn(col.name) || Editor.getColumnProps(col).copyPasteImmutable || clipSchema.kind != col.kind)
						continue;

					toRefresh.push(c);
					setValue(obj1, obj2, clipSchema, col);
				}
			} else {
				beginChanges();
				for( c1 in clipboard.schema ) {
					var c2 = cursor.table.sheet.columns.find(c -> c.name == c1.name);
					var p = Editor.getColumnProps(c2);
					if( c2 == null || !cursor.table.canEditColumn(c2.name) || p.copyPasteImmutable)
						continue;
					if( !cursor.table.canInsert() && c2.opt && !Reflect.hasField(obj2, c2.name) )
						continue;
					setValue(obj1, obj2, c1, c2);
					fullRefresh = true;
				}
			}
		} else {
			beginChanges();

			if( data.length == 1 && cursor.y != cursor.y )
				data = [data[0]];
			for( obj1 in data ) {
				if( posY == sheet.lines.length ) {
					if( !cursor.table.canInsert() ) break;
					sheet.newLine();
					fullRefresh = true;
				}
				var obj2 = sheet.lines[posY];
				for( cid in 0...clipboard.schema.length ) {
					var c1 = clipboard.schema[cid];
					var c2 = columns[cid + posX];
					if( c2 == null ) continue;
					var p = Editor.getColumnProps(c2);

					if( !cursor.table.canEditColumn(c2.name) || p.copyPasteImmutable)
						continue;

					setValue(obj1, obj2, c1, c2);

					if( c2.type == TList || c2.type == TProperties )
						fullRefresh = true;
					if( !fullRefresh )
						toRefresh.push(allLines[posY].cells[cid + posX]);
				}
				posY++;
			}
		}
		formulas.evaluateAll(realSheet);
		endChanges();
		realSheet.sync();
		if( fullRefresh )
			refreshAll();
		else {
			for( c in toRefresh ) {
				c.refresh(true);
			}
			refreshRefs();
		}
	}

	function onDelete() {
		if( cursor.selection == null )
			return;

		beginChanges();
		cursor.selection.sort((el1, el2) -> { return el1.y1 == el2.y1 ? 0 : el1.y1 < el2.y1 ? 1 : -1; });
		for (s in cursor.selection)
			delete(s.x1, s.x2, s.y1, s.y2);
		endChanges();
	}

	function delete(x1 : Int, x2 : Int, y1 : Int, y2 : Int) {
		var modifiedTables = [];
		var sheet = cursor.table.sheet;

		if (cursor.getCell() == null || cursor.getCell().column.type == TId) {
			var id = getCursorId(sheet, true);
			if(id != null && id.length > 0) {
				var refs = getReferences(id, sheet);
				if( refs.length > 0 ) {
					var message = [for (r in refs) r.str].join("\n");
					if( !ide.confirm('$id is referenced elswhere. Are you sure you want to delete?\n$message') )
						return;
				}
			}
		}

		beginChanges();
		if( cursor.x < 0 ) {
			// delete lines
			var y = y2;
			if( !cursor.table.canInsert() ) {
				endChanges();
				return;
			}

			while( y >= y1 ) {
				var line = cursor.table.lines[y];
				if(!cursor.table.lines[y].element.hasClass("filtered")) {
					sheet.deleteLine(line.index);
					cursor.table.refreshCellValue();
					modifiedTables.pushUnique(cursor.table);
				}
				y--;
			}

			cursor.set(cursor.table, -1, y1, null, true, true, false);
		}
		else {
			// delete cells
			for( y in y1...y2+1 ) {
				var line = cursor.table.lines[y];
				if (line.element.hasClass("filtered"))
					continue;
				for( x in x1...x2+1 ) {
					var c = line.columns[x];
					if( !line.cells[x].canEdit() )
						continue;
					var old = Reflect.field(line.obj, c.name);
					var def = base.getDefault(c,false,sheet);
					if( old == def )
						continue;
					changeObject(line,c,def);
					cursor.table.refreshCellValue();
					modifiedTables.pushUnique(cursor.table);
				}
			}
		}

		endChanges();
		refreshAll();
		updateFilters();
	}

	public function changeObject( line : Line, column : cdb.Data.Column, value : Dynamic ) {
		beginChanges();
		var prev = Reflect.field(line.obj, column.name);
		if( value == null ) {
			formulas.setForValue(line.obj, line.table.sheet, column, null);
		} else {
			Reflect.setField(line.obj, column.name, value);
			formulas.removeFromValue(line.obj, column);
		}
		line.table.getRealSheet().updateValue(column, line.index, prev);
		line.evaluate(); // propagate
		endChanges();
	}

	/**
		Call before modifying the database, allow to group several changes together.
		Allow recursion, only last endChanges() will trigger db save and undo point creation.
	**/
	public function beginChanges( ?structure : Bool ) {
		if( changesDepth == 0 )
			undoState.unshift(getState());
		changesDepth++;
	}

	function getState() : UndoState {
		return {
			data : currentValue,
			sheet : getCurrentSheet(),
			cursor : cursor.getState(),
			tables : [for( i in 1...tables.length ) {
				function makeParent(t:Table) : UndoSheet {
					var tp = t.parent;
					return { sheet : t.sheet.name, parent : tp == null ? null : {
						sheet : makeParent(tp),
						line : t.sheet.parent.line,
						column : tp.columns.indexOf(tp.sheet.columns[t.sheet.parent.column]),
					} };
				}
				makeParent(tables[i]);
			}],
		};
	}

	function setState( state : UndoState, doFocus : Bool ) {
		var cur = state.cursor;
		for( t in state.tables ) {
			function openRec(s:UndoSheet) : Table {
				if( s.parent != null ) {
					var t = openRec(s.parent.sheet);
					if( t != null && s.parent.line < t.lines.length ) {
						var cell = t.lines[s.parent.line].cells[t.displayMode == Properties || t.displayMode == AllProperties ? 0 : s.parent.column];
						if (cell == null)
							return null;
						if( cell.line.subTable == null && (cell.column.type == TList || cell.column.type == TProperties) )
							cell.open(true);
						return cell.line.subTable;
					}
				} else {
					for( tp in tables )
						if( tp.sheet.name == s.sheet )
							return tp;
				}
				return null;
			}
			openRec(t);
		}

		if( cur != null ) {
			var table = null;
			for( t in tables ) {
				if( t.sheet.getPath() == cur.sheet ) {
					table = t;
					break;
				}
			}
			if( table != null && doFocus )
				focus();
			cursor.setState(cur, table);
		} else
			cursor.set();
	}

	/**
		Call when changes are done, after endChanges.
	**/
	public function endChanges() {
		changesDepth--;
		if( changesDepth != 0 ) return;

		var newValue = api.copy();
		if( newValue == currentValue )
			return;
		var state = undoState[0];
		var newSheet = getCurrentSheet();
		currentValue = newValue;
		save();
		undo.change(Custom(function(undo) {
			var currentSheet;
			if( undo ) {
				undoState.shift();
				currentValue = state.data;
				currentSheet = state.sheet;
			} else {
				undoState.unshift(state);
				currentValue = newValue;
				currentSheet = newSheet;
			}
			api.load(currentValue);
			DataFiles.save(true); // save reloaded data
			element.removeClass("is-cdb-editor");
			refreshAll();
			element.addClass("is-cdb-editor");
			syncSheet(currentSheet);
			refresh(state);
			save();
		}));
	}

	static var runningHooks = false;
	static var queuedCommand: Void -> Void = null;
	function save() {
		api.save();

		function hookEnd() {
			runningHooks = false;
			if (queuedCommand != null) {
				var a = queuedCommand;
				queuedCommand = null;
				a();
			}
		}
		var hooks: Array<{cmd: String, sheets: Array<String>}> = this.config.get("cdb.onChangeHooks");
		if( hooks != null ) {
			var s = getCurrentSheet();
			var commands = [for (h in hooks) if (h.sheets.has(s)) h.cmd];
			function runRec(i: Int) {
				runningHooks = true;
				ide.runCommand(commands[i], (e) -> {
					if (e != null) {
						ide.quickError('Hook error:\n$e');
						hookEnd();
					} else {
						if (i < commands.length - 1) {
							runRec(i + 1);
						} else  {
							hookEnd();
						}
					}
				});
			}
			if (!commands.isEmpty()) {
				if (runningHooks) {
					queuedCommand = () -> runRec(0);
				} else {
					runRec(0);
				}
			}
		}
	}

	public static var inRefreshAll(default,null) : Bool;
	public static function refreshAll( eraseUndo = false, loadDataFiles = true) {
		var editors : Array<Editor> = [for( e in new Element(".is-cdb-editor").elements() ) e.data("cdb")];
		if (loadDataFiles)
			DataFiles.load();
		inRefreshAll = true;
		for( e in editors ) {
			e.syncSheet(Ide.inst.database);
			e.refresh();
			// prevent undo over input changes
			if( eraseUndo ) {
				e.currentValue = e.api.copy();
				e.undo.clear();
				e.undoState = [];
			}
		}
		inRefreshAll = false;
	}

	public function getCursorId(?sheet, ?childOnly = false): String {
		var id: String = null;
		if( sheet == null )
			sheet = cursor.table.sheet;
		var cell = cursor.getCell();
		switch (cell == null ? null : cell.column.type) {
			case TRef(sname):
				id = cell.value;
			case TId:
				id = cell.value;
			default:
				if (!childOnly || cursor.x < 0) {
					for( c in sheet.columns ) {
						switch( c.type ) {
						case TId:
							id = Reflect.field(sheet.lines[cursor.y], c.name);
							break;
						default:
						}
					}
				}
		}
		return id;
	}

	public static function splitPath(rs: {s:Array<{s:cdb.Sheet, c:String, id:Null<String>}>, o:{path:Array<Dynamic>, indexes:Array<Int>}}) {
		var path = [];
		var coords = [];
		for( i in 0...rs.s.length ) {
			var s = rs.s[i];
			var oid = Reflect.field(rs.o.path[i], s.id);
			var idx = rs.o.indexes[i];
			if( oid == null || oid == "" )
				path.push(s.s.name.split("@").pop() + (idx < 0 ? "" : "[" + idx +"]"));
			else {
				path.push(oid);
			}
			if (i == rs.s.length - 1 && s.c != "" && s.c != null) {
				path.push(s.c);
			}
		}
		var coords = [];
		var curIdx = 0;
		while(curIdx < rs.o.indexes.length) {
			var sheet = rs.s[curIdx];
			var isSheet = !sheet.s.props.isProps;
			if (isSheet) {
				var oid = Reflect.field(rs.o.path[curIdx], sheet.id);
				var next = sheet.c;
				if (oid != null) {
					coords.push(Id(sheet.id, oid, next));
				}
				else {
					coords.push(Line(rs.o.indexes[curIdx], next));
				}
			}
			else {
				coords.push(Prop(rs.s[curIdx].c));
			}

			curIdx += 1;
		}

		return {pathNames: path, pathParts: coords};
	}

	public function getReferences(id: String, withCodePaths = true, returnAtFirstRef = false, sheet: cdb.Sheet, ?codeFileCache: Array<{path: String, data:String}>, ?prefabFileCache: Array<{path: String, data:String}>) : Array<{str:String, ?goto:Void->Void}> {
		#if hl
		return [];
		#else
		if( id == null )
			return [];

		var results = sheet.getReferencesFromId(id);
		var message = new Array<{str:String, ?goto:Void->Void}>();
		if( results != null ) {
			for( rs in results ) {
				var path = splitPath(rs);
				message.push({str: rs.s[0].s.name+"."+path.pathNames.join("."), goto: () -> openReference2(rs.s[0].s, path.pathParts)});
				if (returnAtFirstRef) return message;
			}
		}
		if (withCodePaths) {
			var paths : Array<String> = this.config.get("haxe.classPath");
			if( paths != null ) {


				if (codeFileCache == null) {
					codeFileCache = [];
				}

				if (codeFileCache.length == 0) {
					function lookupRec(p) {
						for( f in sys.FileSystem.readDirectory(p) ) {
							var fpath = p+"/"+f;
							if( sys.FileSystem.isDirectory(fpath) ) {
								lookupRec(fpath);
								if (returnAtFirstRef && message.length > 0) return;
								continue;
							}
							if( StringTools.endsWith(f, ".hx") ) {
								codeFileCache.push({path: fpath, data: sys.io.File.getContent(fpath)});
							}
						}
					}

					for( p in paths ) {
						var path = ide.getPath(p);
						if( sys.FileSystem.exists(path) && sys.FileSystem.isDirectory(path) )
							lookupRec(path);
					}

					var formulasPath = ide.getPath("formulas.hx");
					if (sys.FileSystem.exists(formulasPath)) {
						codeFileCache.push({path: formulasPath, data: sys.io.File.getContent(formulasPath)});
					}
				}

				var spaces = "[ \\n\\t]";
				var prevChars = ",\\(:=\\?\\[|";
				var postChars = ",\\):;\\?\\]&|";
				var regexp = new EReg('((case$spaces+)|[$prevChars])$spaces*$id$spaces*[$postChars]*.*',"");
				var regall = new EReg("\\b"+id+"\\b", "");

				var tableName = sheet.name;
				var first = tableName.substr(0,1);
				var caseInsentive = '[${first.toLowerCase()}${first.toUpperCase()}]${tableName.substr(1)}';
				var regResolve = new EReg('${caseInsentive}\\.resolve\\(\\s*"$id"\\s*\\)', "");

				for (file in codeFileCache) {

					var fpath = file.path;
					var content = file.data;
					if( content.indexOf(id) < 0 ) continue;
					for( line => str in content.split("\n") ) {
						if( regall.match(str) ) {
							if( !regexp.match(str) && !regResolve.match(str) ) {
								var str2 = str.split(id+".").join("").split("."+id).join("").split(id+"(").join("").split(id+"<").join("");
								if( regall.match(str2) ) trace("Skip "+str);
								continue;
							}
							var path = ide.makeRelative(fpath);
							var fn = function () {
								var ext = @:privateAccess hide.view.FileTree.getExtension(path);

								ide.open(ext.component, { path : path }, function (v) {
									var scr : hide.view.Script = cast v;

									function checkSetPos() {
										var s = @:privateAccess scr.script;
										if (s != null) {
											var e = @:privateAccess s.editor;
											e.setPosition({column:0, lineNumber: line+1});
											haxe.Timer.delay(() ->e.revealLineInCenter(line+1), 1);
											return;
										}

										// needed because the editor can be created after our
										// function is called (if the tab was created but never opened,
										// likely because hide was closed and reopened)
										// see : View.rebuild()
										haxe.Timer.delay(checkSetPos, 200);
									}

									checkSetPos();
								});
							}
							message.push({str: path+":"+(line+1), goto: fn});
							if (returnAtFirstRef) return message;
						}
					}
				}
			}
			var paths : Array<String> = this.config.get("cdb.prefabsSearchPaths");
			var scriptStr = new EReg("\\b"+sheet.name.charAt(0).toUpperCase() + sheet.name.substr(1) + "\\." + id + "\\b","");

			if( paths != null ) {

				if (prefabFileCache == null)
					prefabFileCache = [];

				if (prefabFileCache.length == 0) {
					function lookupPrefabRec(path) {
						for( f in sys.FileSystem.readDirectory(path) ) {
							var fpath = path+"/"+f;
							if( sys.FileSystem.isDirectory(fpath) ) {
								lookupPrefabRec(fpath);
								continue;
							}
							var ext = f.split(".").pop();
							if( @:privateAccess hrt.prefab.Prefab.extensionRegistry.exists(ext) ) {
								prefabFileCache.push({path: fpath, data: sys.io.File.getContent(fpath)});
							}
						}
					}
					for( p in paths ) {
						var path = ide.getPath(p);
						if( sys.FileSystem.exists(path) && sys.FileSystem.isDirectory(path) )
							lookupPrefabRec(path);
					}
				}

				for (file in prefabFileCache) {
					var fpath = file.path;
					var content = file.data;
					if( !scriptStr.match(content) ) continue;
					for( line => str in content.split("\n") ) {
						if( scriptStr.match(str) ) {
							var path = ide.makeRelative(fpath);
							var fn = function () {
								ide.openFile(path, function (v) {
									var scr : hide.view.Script = cast v;
									haxe.Timer.delay(function() {
										@:privateAccess scr.script.editor.setPosition({column:0, lineNumber: line+1});
										haxe.Timer.delay(() ->@:privateAccess scr.script.editor.revealLineInCenter(line+1), 1);
									}, 1);
								});
							}
							message.push({str: path+":"+(line+1), goto: fn});
						}
					}
				}
			}

			// Script references
			{

				var results = [];
				for( s in sheet.base.sheets ) {
					for( cid => c in s.columns )
						switch( c.type ) {
						case TString:
							if (c.kind == cdb.Data.ColumnKind.Script) {
								var sheets = [];
								var p = { s : s, c : c.name, id : null };
								while( true ) {
									for( c in p.s.columns )
										switch( c.type ) {
										case TId: p.id = c.name; break;
										default:
										}
									sheets.unshift(p);
									var p2 = p.s.getParent();
									if( p2 == null ) break;
									p = { s : p2.s, c : p2.c, id : null };
								}
								var objs = s.getObjects();
								var i = 0;
								for( sheetline => o in objs ) {
									i += 1;
									var obj = o.path[o.path.length - 1];
									var content = Reflect.field(obj, c.name);
									if( !scriptStr.match(content) ) continue;
									for( line => str in content.split("\n") ) {
										if( scriptStr.match(str) )
										{
											var res = splitPath({s: sheets, o: o});
											res.pathParts.push(Script(line));
											message.push({str: sheets[0].s.name+"."+res.pathNames.join(".") + "." + c.name + ":" + Std.string(line + 1), goto: () -> openReference2(sheets[0].s, res.pathParts)});
											if (returnAtFirstRef) return message;
										}
									}
								}
							}

						/*case TRef(sname) if( sname == sheet.sheet.name ):
							var sheets = [];
							var p = { s : s, c : c.name, id : null };
							while( true ) {
								for( c in p.s.columns )
									switch( c.type ) {
									case TId: p.id = c.name; break;
									default:
									}
								sheets.unshift(p);
								var p2 = p.s.getParent();
								if( p2 == null ) break;
								p = { s : p2.s, c : p2.c, id : null };
							}
							for( o in s.getObjects() ) {
								var obj = o.path[o.path.length - 1];
								if( Reflect.field(obj, c.name) == id )
									results.push({ s : sheets, o : o });
							}*/
						default:
						}
				}
			}
		}
		return message;
		#end
	}

	public function findUnreferenced(col: cdb.Data.Column, table: Table) {
		var sheet = table.getRealSheet();

		var nonrefs = new Array<{str:String, ?goto:Void->Void}>();

		var codeFileCache = [];
		var prefabFileCache = [];
		for (o in sheet.lines) {
			var id = Reflect.getProperty(o, col.name);
			var refs = getReferences(id, true, true, sheet, codeFileCache, prefabFileCache);
			if (refs.length == 0) {
				nonrefs.push({str: id, goto: () -> openReference2(sheet, [Id(col.name, id)])});
			}
		}
		trace("codeFileCache: ", codeFileCache.length);
		trace("prefabFileCache: ", prefabFileCache.length);

		ide.open("hide.view.RefViewer", null, function(view) {
			var refViewer : hide.view.RefViewer = cast view;
			refViewer.showRefs(nonrefs, "Number of unreferenced ids");
		});
	}

	public function showReferences(?id: String, ?sheet: cdb.Sheet) {
		if( cursor.table == null ) return;
		if( sheet == null )
			sheet = cursor.table.sheet;
		if( id == null )
			id = getCursorId(sheet);
		var cell = cursor.getCell();
		if (cell != null) {
			switch (cell.column.type) {
				case TRef(sname):
					sheet = base.getSheet(sname);
				default:
			}
		}
		var refs = [];
		if( id != null )
			refs = getReferences(id, sheet);
		if( refs.length == 0 ) {
			ide.message("No reference found");
			return;
		}
		ide.open("hide.view.RefViewer", null, function(view) {
			var refViewer : hide.view.RefViewer = cast view;
			refViewer.showRefs(refs);
		});
	}

	function gotoReference( c : Cell ) {
		if( c == null || c.value == null ) return;
		switch( c.column.type ) {
		case TRef(s):
			var sd = base.getSheet(s);
			if( sd == null ) return;
			var k = sd.index.get(c.value);
			if( k == null ) return;
			var index = sd.lines.indexOf(k.obj);
			if( index >= 0 ) openReference(sd, index, 0);
		default:
		}
	}

	public static function openReference2(rootSheet : cdb.Sheet, path: Path) {
		hide.Ide.inst.open("hide.view.CdbTable", {}, null, function(view) Std.downcast(view,hide.view.CdbTable).goto2(rootSheet,path));
	}

	function openReference( s : cdb.Sheet, line : Int, column : Int, ?scriptLine: Int ) {
		ide.open("hide.view.CdbTable", {}, function(view) Std.downcast(view,hide.view.CdbTable).goto(s,line,column,scriptLine));
	}

	public function syncSheet( ?base, ?name ) {
		if( base == null ) base = this.base;
		this.base = base;
		if( name == null ) name = getCurrentSheet();
		// swap sheet if it was modified
		this.currentSheet = null;
		for( s in base.sheets )
			if( s.name == name ) {
				this.currentSheet = s;
				break;
			}
	}

	function isUniqueID( sheet : cdb.Sheet, obj : {}, id : String ) {
		var idx = base.getSheet(sheet.name).index;

		var uniq = idx.get(id);
		return uniq == null || uniq.obj == obj;
	}

	public function refreshRefs() {
		base.sync();

		for( t in tables ) {
			for( l in t.lines ) {
				for( c in l.cells ) {
					switch( c.column.type ){
					case TRef(_):
						c.refresh();
					case TString:
						if( c.column.kind == Script )
							c.refresh();
					default:
					}
				}
			}
		}
	}

	public function refresh( ?state : UndoState ) {
		if( state == null )
			state = getState();

		var hasFocus = element.find(":focus").length > 0;

		base.sync();

		element.empty();
		element.addClass('cdb');

		formulas = new Formulas(this);
		formulas.evaluateAll(currentSheet.realSheet);

		var content = new Element("<table>");
		tables = [];
		new Table(this, currentSheet, content, displayMode);
		content.appendTo(element);

		setState(state, hasFocus);

		if( cursor.table != null ) {
			for( t in tables )
				if( t.sheet.getPath() == cursor.table.sheet.getPath() )
					cursor.table = t;
			cursor.update();
		}

		// Setup for search bar
		searchBox = new Element('<div>
			<div class="buttons">
				<div class="btn add-btn ico ico-plus" title="Add filter"></div>
				<div class="btn remove-btn ico ico-minus" title="Remove filter"></div>
			</div>
			<div class="input-col">
				<div class="input-cont"/>
					<input type="text" class="search-bar-cdb"></input>
				</div>
			</div>
			<p id="results">No results</p>
			<div class="btn search-type fa fa-font" title="Change search type"></div>
			<div class="btn search-hidden fa fa-eye" title="Search through hidden categories"></div>
			<div class="btn close-search ico ico-close" title="Close (Escape)"></div>
		</div>').addClass("search-box").appendTo(element);
		searchBox.hide();

		function search(e: js.jquery.Event) {
			// Close search with escape
			if( e.keyCode == K.ESCAPE ) {
				searchBox.find(".close-search").click();
				return;
			}

			// Change to expresion mode if we detect an expression character in the search (qol)
			for (c in Editor.COMPARISON_EXPR_CHARS) {
				if (StringTools.contains(Element.getVal(e.getThis()), c) && !searchExp) {
					searchExp = true;
					var searchTypeBtn = searchBox.find(".search-type");
					searchTypeBtn.toggleClass("fa-superscript", searchExp);
					searchTypeBtn.toggleClass("fa-font", !searchExp);
					updateFilters();
					break;
				}
			}

			var index = e.getThis().parent().find('.search-bar-cdb').index(e.getThis());
			if (filters[index] == null)
				filters[index] = "";

			filters[index] = Element.getVal(e.getThis());

			// Slow table refresh protection
			if (currentSheet.lines.length > 300) {
				if (pendingSearchRefresh != null) {
					pendingSearchRefresh.stop();
				}
				pendingSearchRefresh = haxe.Timer.delay(function()
					{
						searchFilter(filters.copy());
						pendingSearchRefresh = null;
					}, 500);
			}
			else {
				searchFilter(filters.copy());
			}
		}

		var inputs = searchBox.find(".search-bar-cdb");
		inputs.attr("placeholder", "Find");
		inputs.keyup(search);

		var inputCont = searchBox.find(".input-cont");

		searchBox.find(".add-btn").click(function(_) {
			var newInput = new Element('<input type="text" class="search-bar-cdb"></input>');
			newInput.attr("placeholder", "Find");
			newInput.appendTo(searchBox.find(".input-cont"));
			newInput.css({"margin-top": "2px"});
			updateFilters();
			searchBox.find(".remove-btn").show();
		});

		searchBox.find(".remove-btn").hide();
		searchBox.find(".remove-btn").click(function(_) {
			var searchBars = inputCont.find(".search-bar-cdb");
			if( searchBars.length > 1 ) {
				searchBars.last().remove();
				filters.pop();
				searchFilter(filters.copy());

				if (filters.length <= 1)
					searchBox.find(".remove-btn").hide();
			}
		});

		searchBox.find(".close-search").click(function(_) {
			searchFilter([]);
			searchBox.find(".search-bar-cdb").not(':first').remove();
			searchBox.find(".expr-btn").not(':first').remove();
			filters.clear();
			if(searchBox.find(".expr-btn").hasClass("fa-superscript"))
				searchBox.find(".expr-btn").removeClass("fa-superscript").addClass("fa-font");
			searchBox.toggle();
			var c = cursor.save();
			focus();
			cursor.load(c);
			var hiddenSeps = element.find("table.cdb-sheet > tbody > tr").not(".head").filter(".separator").filter(".sep-hidden").find("a.toggle");
			hiddenSeps.click();
			cursor.scrollIntoView();
		});

		searchBox.find(".search-type").click(function(_) {
			searchExp = !searchExp;
			searchBox.find(".search-type").toggleClass("fa-superscript", searchExp);
			searchBox.find(".search-type").toggleClass("fa-font", !searchExp);
			updateFilters();
		});

		searchBox.find(".search-hidden").click(function(_) {
			searchHidden = !searchHidden;
			searchBox.find(".search-hidden").toggleClass("fa-eye", searchHidden);
			searchBox.find(".search-hidden").toggleClass("fa-eye-slash", !searchHidden);
			if (!searchHidden) {
				var hiddenSeps = element.find("table.cdb-sheet > tbody > tr").not(".head").filter(".separator").filter(".sep-hidden").find("a.toggle");
				hiddenSeps.click();
				hiddenSeps.click();
			}
			updateFilters();
		});

		// If there is still a search apply it
		if (filters.length > 0) {
			searchBox.show();

			for (f in filters)
				inputs.val(f);

			if (searchExp)
				searchBox.find(".search-type").click();

			if (!searchHidden)
				searchBox.find(".search-type").click();

			searchFilter(filters);
		}
	}

	function quickExists(path) {
		var c = existsCache.get(path);
		if( c == null ) {
			c = { t : -1e9, r : false };
			existsCache.set(path, c);
		}
		var t = haxe.Timer.stamp();
		if( c.t < t - 10 ) { // cache result for 10s
			c.r = sys.FileSystem.exists(path);
			c.t = t;
		}
		return c.r;
	}

	function getLine( sheet : cdb.Sheet, index : Int ) {
		for( t in tables )
			if( t.sheet == sheet )
				return t.lines[index];
		return null;
	}

	static public function getColumnProps( c : cdb.Data.Column ) {
		var pr : EditorColumnProps = c.editor;
		if( pr == null ) pr = {};
		return pr;
	}

	public function isColumnVisible( c : cdb.Data.Column ) {
		var props = getColumnProps(c);
		var cats = ide.projectConfig.dbCategories;
		return cats == null || props.categories == null || cats.filter(c -> props.categories.indexOf(c) >= 0).length > 0;
	}

	public function moveColumn(targetSheet: cdb.Sheet, origSheet: cdb.Sheet, col: cdb.Data.Column) : String {
		beginChanges(true);
		var err = targetSheet.addColumn(col);

		function createSubCols(targetSheet: cdb.Sheet, origSheet: cdb.Sheet, column: cdb.Data.Column) : String {
			// Check to see if the column contains other columns
			var subSheetPath = origSheet.getPath() + "@" + column.name;
			var subSheet = base.getSheet(subSheetPath);
			var subTargetPath = targetSheet.getPath() + "@" + column.name;
			var subTarget = base.getSheet(subTargetPath);
			if (subSheet != null) {
				if (subTarget == null)
					return 'original sheet $subSheetPath contains columns but target sheet $subTargetPath does not exist';

				for (c in subSheet.columns) {
					var err = subTarget.addColumn(c);
					if (err != null)
						return err;
					createSubCols(subTarget, subSheet, c);
				}
			}
			return null;
		}

		if (err == null) {
			var err = createSubCols(targetSheet, origSheet, col);
			if (err == null) {
				// Copy the data from the original column to the new one
				var commonSheet = origSheet;
				var commonPath = origSheet.getPath().split("@");
				while(true) {
					if (commonPath.length <= 0) {
						throw "missing parent table that is not props";
					}
					commonSheet = base.getSheet(commonPath.join("@"));

					if (!commonSheet.props.isProps)
						break;
					commonPath.pop();
				}

				var origPath = origSheet.getPath().split("@");
				origPath.splice(0, commonPath.length);
				origPath.push(col.name);
				var targetPath = targetSheet.getPath().split("@");
				targetPath.splice(0, commonPath.length);

				var lines = commonSheet.getLines();
				for (i => line in lines) {
					// read value from origPath
					var value : Dynamic = line;
					for (p in origPath) {
						value = Reflect.field(value, p);
						if (value == null)
							break;
					}

					if (value != null) {
						// Get or insert intermediates props value along targetPath
						var target : Dynamic = line;
						for (p in targetPath) {
							var newTarget = Reflect.field(target, p);
							if (newTarget == null) {
								newTarget = {};
								Reflect.setField(target, p, newTarget);
							}
							target = newTarget;
						}
						Reflect.setField(target, col.name, value);
					}
				}

				origSheet.deleteColumn(col.name);
			}
		}
		endChanges();
		return err;
	}

	public function newColumn( sheet : cdb.Sheet, ?index : Int, ?onDone : cdb.Data.Column -> Void, ?col ) {
		#if js
		var modal = new hide.comp.cdb.ModalColumnForm(this, sheet, col, element);
		modal.setCallback(function() {
			var c = modal.getColumn(col);
			if (c == null)
				return;
			beginChanges(true);
			var err;
			if( col != null ) {
				base.mapType(function(t) {
					return switch( t ) {
					case TRef(o) if( o.indexOf('${sheet.name}@${col.name}') >= 0 ):
						TRef(StringTools.replace(o, col.name, c.name));
					case TLayer(o) if( o.indexOf('${sheet.name}@${col.name}') >= 0 ):
						TLayer(StringTools.replace(o, col.name, c.name));
					default:
						t;
					}
				});
				var newPath = c.name;
				var back = newPath.split("/");
				var finalPart = back.pop();
				var path = finalPart.split(".");
				c.name = path.pop();
				err = base.updateColumn(sheet, col, c);
				if (path.length > 0 || back.length > 0) {
					function handleMoveTable() {
						var cdbPath = sheet.getPath().split("@");
						for(b in back) {
							if (b != "..") {
								return 'Invalid backwards move path "${back.join("/")}" (correct syntax : ../../columnName)';
							}
							if (cdbPath.length <= 0) {
								return 'Backwards path "${back.join("/")}" goes outside of base sheet';
							}
							var subSheet = base.getSheet(cdbPath.join("@"));
							if (!subSheet.props.isProps) {
								return 'Target path "${cdbPath.join(".")}" goes inside or outside another sheet';
							}
							cdbPath.pop();
						}

						for (p in path) {
							cdbPath.push(p);
							var subSheet = base.getSheet(cdbPath.join("@"));
							if (subSheet == null) {
								return 'Target sheet "${cdbPath.join(".")}" does not exist';
							}
							if (!subSheet.props.isProps) {
								return 'Target path "${cdbPath.join(".")}" goes inside or outside another sheet';
							}
						}

						var finalPath = cdbPath.join("@");
						var targetSheet = base.getSheet(finalPath);
						if (targetSheet != null) {
							if (ide.confirm('Move column to "$finalPath" ?')) {
								return moveColumn(targetSheet, sheet, c);
							}
							return 'Move canceled';
						}
						else {
							return 'Invalid move path "$newPath"';
						}
						return null;
					}

					err = handleMoveTable();
				}
			}
			else
				err = sheet.addColumn(c, index == null ? null : index + 1);
			endChanges();
			if (err != null) {
				modal.error(err);
				return;
			}
			// perform side effects before refresh
			if( onDone != null )
				onDone(c);
			// if first column or subtable, refresh all
			if( sheet.columns.length == 1 || sheet.name.indexOf("@") > 0 )
				refresh();
			else
				sheet.sync();
			for( t in tables )
				if( t.sheet == sheet )
					t.refresh();
			modal.closeModal();
		});
		#end
	}

	public function editColumn( sheet : cdb.Sheet, col : cdb.Data.Column ) {
		newColumn(sheet,col);
	}

	public function ensureUniqueId(originalId : String, table : Table, column : cdb.Data.Column) {
		var scope = table.getScope();
		var idWithScope : String = if(column.scope != null)  table.makeId(scope, column.scope, originalId) else originalId;

		if (isUniqueID(table.getRealSheet(), {}, idWithScope)) {
			return originalId;
		}
		return getNewUniqueId(originalId, table, column);
	}

	public function doesSheetContainsId(sheet:cdb.Sheet, id:String) {
		var idx = base.getSheet(sheet.name).index;

		var uniq = idx.get(id);
		return uniq != null;
	}

	public function getNewUniqueId(originalId : String, table : Table, column : cdb.Data.Column) {
		var str = originalId;
		var currentValue : Null<Int> = null;
		var strIdx : Int = 0;

		// Find the number at the end of the string
		while (strIdx < str.length) {
			var substr = str.substr(str.length-1-strIdx);
			var newValue = Std.parseInt(substr);
			if (newValue != null)
				currentValue = newValue;
			else {
				break;
			}
			strIdx += 1;
		}

		var scope = table.getScope();

        if (currentValue == null) {
            currentValue = 0;
            strIdx = 0;
        }


        var newId : String;
        var idWithScope : String;
        do {
            currentValue+=1;
            var valStr = Std.string(currentValue);

            // Pad with zeroes
            for (i in 0...strIdx - valStr.length) {
                valStr = "0" + valStr;
            }
            newId = str.substr(0, str.length-strIdx) + valStr;
            idWithScope = if(column.scope != null)  table.makeId(scope, column.scope, newId) else newId;
        }
        while (!isUniqueID(table.getRealSheet(), {}, idWithScope));

        return newId;
	}

	public function popupColumn( table : Table, col : cdb.Data.Column, ?cell : Cell ) {
		if( view != null )
			return;
		var sheet = table.getRealSheet();
		var indexColumn = sheet.columns.indexOf(col);
		var menu : Array<hide.comp.ContextMenu.MenuItem> = [
			{ label : "Edit", click : function () editColumn(sheet, col) },
			{
				label : "Add Column",
				click : function () newColumn(sheet, indexColumn),
				enabled : table.displayMode != AllProperties,
			},
			{ label : "", isSeparator: true },
			{ label : "Move Left", enabled:  (indexColumn > 0 &&
				nextVisibleColumnIndex(table, indexColumn, Left) > -1), click : function () {
				beginChanges();
				var nextIndex = nextVisibleColumnIndex(table, indexColumn, Left);
				sheet.columns.remove(col);
				sheet.columns.insert(nextIndex, col);
				if (cursor.x == indexColumn)
					cursor.setDefault(cursor.table, nextIndex, cursor.y);
				else if (cursor.x == nextIndex)
					cursor.setDefault(cursor.table, nextIndex + 1, cursor.y);
				endChanges();
				refresh();
			}},
			{ label : "Move Right", enabled: (indexColumn < sheet.columns.length - 1 &&
				nextVisibleColumnIndex(table, indexColumn, Right) < sheet.columns.length), click : function () {
				beginChanges();
				var nextIndex = nextVisibleColumnIndex(table, indexColumn, Right);
				sheet.columns.remove(col);
				sheet.columns.insert(nextIndex, col);
				if (cursor.x == indexColumn)
					cursor.setDefault(cursor.table, nextIndex, cursor.y);
				else if (cursor.x == nextIndex)
					cursor.setDefault(cursor.table, nextIndex - 1, cursor.y);
				endChanges();
				refresh();
			}},
			{ label: "", isSeparator: true },
			{
				label : "Delete",
				click : function () {
					if( table.displayMode == Properties ) {
						beginChanges();
						changeObject(cell.line, col, base.getDefault(col,sheet));
						cursor.table.refreshCellValue();
					} else {
						beginChanges(true);
						sheet.deleteColumn(col.name);
					}
					endChanges();
					refresh();
				},
				enabled : table.displayMode != AllProperties,
			},
		];

		if( table.parent == null ) {
			var props = table.sheet.props;
			switch( col.type ) {
			case TString, TRef(_):
				menu.push({ label : "Display Name", click : function() {
					beginChanges();
					props.displayColumn = (props.displayColumn == col.name ? null : col.name);
					endChanges();
					refresh();
				}, checked: props.displayColumn == col.name });
			case TTilePos:
				menu.push({ label : "Display Icon", click : function() {
					beginChanges();
					props.displayIcon = (props.displayIcon == col.name ? null : col.name);
					endChanges();
					refresh();
				}, checked: props.displayIcon == col.name });
			default:
			}

			var editProps = getColumnProps(col);
			menu.push({ label : "Categories", menu: categoriesMenu(editProps.categories, function(cats) {
				beginChanges();
				editProps.categories = cats;
				col.editor = editProps;
				endChanges();
				refresh();
			})});

			switch(col.type) {
			case TId | TString | TGuid:
				menu.push({ label : "Sort", click: () -> table.sortBy(col), enabled : table.displayMode != AllProperties });
			default:
			}

			var hasGUID = false;
			for( s in base.sheets )
				for( c in s.columns )
					if( c.type == TGuid ) {
						hasGUID = true;
						break;
					}
			if( hasGUID ) {
				menu.push({ label : "Display GUIDs", checked : showGUIDs, click : function() {
					showGUIDs = !showGUIDs;
					refresh();
				} });
			}
		}

		if( col.type == TString && col.kind == Script )
			menu.insert(1,{ label : "Edit all", click : function() editScripts(table,col) });
		if( table.displayMode == Properties ) {
			menu.push({ label : "Delete All", click : function() {
				if( !ide.confirm('*** WARNING ***\nThis will delete the row for all properties!\n${col.name}') )
					return;
				beginChanges(true);
				table.sheet.deleteColumn(col.name);
				cursor.table.refreshCellValue();
				endChanges();
				refresh();
			}});
		}
		hide.comp.ContextMenu.createFromPoint(ide.mouseX, ide.mouseY, menu);
	}

	function nextVisibleColumnIndex( table : Table, index : Int, dir : Direction){
		var next = index;
		do {
			next += (dir == Left ? -1 : 1);
		}
		while (next >= 0 && next <= table.columns.length - 1 && !isColumnVisible(table.columns[next]));
		return next;
	}

	function editScripts( table : Table, col : cdb.Data.Column ) {
		// TODO : create single edit-all script view allowing global search & replace
	}


	public function popupLine( line : Line ) {
		if( !line.table.canInsert() ) return;

		var sheet = line.table.sheet;
		var selectedLines = cursor.getSelectedLines();
		var isSelectedLine = selectedLines.contains(line);
		var firstLine = isSelectedLine ? selectedLines[0] : line;
		var lastLine = isSelectedLine ? selectedLines[selectedLines.length - 1] : line;

		var sepIndex = -1;
		for( i in 0...sheet.separators.length )
			if( sheet.separators[i].index == line.index ) {
				sepIndex = i;
				break;
			}

		var moveSubmenu : Array<hide.comp.ContextMenu.MenuItem> = [];
		for( sepIndex => sep in sheet.separators ) {
			if( sep.title == null )
				continue;

			function separatorCount( fromLine : Int ) {
				var count = 0;
				if( fromLine >= sep.index ) {
					for( i in (sepIndex + 1)...sheet.separators.length ) {
						if( sheet.separators[i].index > fromLine )
							break;
						count--;
					}
				} else {
					for( i in 0...(sepIndex + 1) ) {
						if( sheet.separators[i].index <= fromLine )
							continue;
						count++;
					}
				}
				return count;
			}

			var lastOfGroup = sepIndex == sheet.separators.length - 1 ? line.table.lines.length : sheet.separators[sepIndex + 1].index;
			var usedLine = firstLine;
			if( lastOfGroup > line.index ) {
				lastOfGroup--;
				usedLine = lastLine;
			}
			var delta = lastOfGroup - usedLine.index + separatorCount(usedLine.index);
			var linesToMove = isSelectedLine ? selectedLines : [usedLine];
			moveSubmenu.push({
				label : sep.title,
				enabled : true,
				click : () -> usedLine.table.moveLines(linesToMove, delta)
			});
		}

		var hasLocText = false;
		function checkRec(s:cdb.Sheet) {
			for( c in s.columns ) {
				switch( c.type ) {
				case TList, TProperties:
					var sub = s.getSub(c);
					checkRec(sub);
				case TString if( c.kind == Localizable ):
					hasLocText = true;
				default:
				}
			}
		}
		if( sheet.parent == null )
			checkRec(sheet);

		var menu : Array<hide.comp.ContextMenu.MenuItem> = [
			{
				label : "Move Up",
				enabled:  (firstLine.index > 0 || sepIndex >= 0),
				click : () -> line.table.moveLines(isSelectedLine ? [line] : selectedLines, -1),
			},
			{
				label : "Move Down",
				enabled:  (lastLine.index < sheet.lines.length - 1),
				click : () -> line.table.moveLines(isSelectedLine ? [line] : selectedLines, 1),
			},
			{ label : "Move to Group", enabled : moveSubmenu.length > 0, menu : moveSubmenu },
			{ label : "", isSeparator : true },
			{ label : "Insert", click : function() {
				line.table.insertLine(line.index);
				cursor.set(line.table, -1, line.index + 1);
				focus();
			}, keys : config.get("key.cdb.insertLine") },
			{ label : "Duplicate", click : function() {
				line.table.duplicateLine(line.index);
				cursor.set(line.table, -1, line.index + 1);
				focus();
			}, keys : config.get("key.duplicate") },
			{ label : "Delete", click : function() {
				beginChanges();
				cursor.selection.sort((el1, el2) -> { return el1.y1 == el2.y1 ? 0 : el1.y1 < el2.y1 ? 1 : -1; });
				for (s in cursor.selection)
					delete(s.x1, s.x2, s.y1, s.y2);
				endChanges();
			} },
			{ label : "Separator", enabled : !sheet.props.hide, checked : sepIndex >= 0, click : function() {
				beginChanges();
				if( sepIndex >= 0 ) {
					sheet.separators.splice(sepIndex, 1);
				} else {
					sepIndex = sheet.separators.length;
					var level = 1;
					for( i in 0...sheet.separators.length ) {
						if( sheet.separators[i].index > line.index ) {
							sepIndex = i;
							break;
						}
						var lv = sheet.separators[i].level;
						if( lv == null ) lv = 0;
						level = lv + 1;
					}
					sheet.separators.insert(sepIndex, { index : line.index, level : level });
				}
				endChanges();
				refresh();
			} }
		];
		if( hasLocText ) {
			menu.push({ label : "", isSeparator : true });
			menu.push({
				label : "Export Localized Texts",
				checked : !Reflect.hasField(line.obj,cdb.Lang.IGNORE_EXPORT_FIELD),
				click : function() {
					beginChanges();
					if( Reflect.hasField(line.obj,cdb.Lang.IGNORE_EXPORT_FIELD) )
						Reflect.deleteField(line.obj,cdb.Lang.IGNORE_EXPORT_FIELD);
					else
						Reflect.setField(line.obj,cdb.Lang.IGNORE_EXPORT_FIELD, true);
					endChanges();
					line.syncClasses();
				},
			});
		}
		hide.comp.ContextMenu.createFromPoint(ide.mouseX, ide.mouseY, menu);
	}

	function rename( sheet : cdb.Sheet, name : String ) {
		if( !base.r_ident.match(name) ) {
			ide.error("Invalid sheet name");
			return false;
		}
		var f = base.getSheet(name);
		if( f != null ) {
			if( f != sheet ) ide.error("Sheet name already in use");
			return false;
		}
		beginChanges();
		var old = sheet.name;
		sheet.rename(name);
		base.mapType(function(t) {
			return switch( t ) {
			case TRef(o) if( o == old ):
				TRef(name);
			case TLayer(o) if( o == old ):
				TLayer(name);
			default:
				t;
			}
		});

		for( s in base.sheets )
			if( StringTools.startsWith(s.name, old + "@") )
				s.rename(name + "@" + s.name.substr(old.length + 1));
		endChanges();
		DataFiles.save(true,[ sheet.name => old ]);
		return true;
	}

	function categoriesMenu(categories: Array<String>, setFunc : Array<String> -> Void) {
		var menu : Array<ContextMenu.MenuItem> = [{ label : "Set...", click : function() {
			var wstr = "";
			if(categories != null)
				wstr = categories.join(",");
			wstr = ide.ask("Set Categories (comma separated)", wstr);
			if(wstr == null)
				return;
			categories = [for(s in wstr.split(",")) { var t = StringTools.trim(s); if(t.length > 0) t; }];
			setFunc(categories.length > 0 ? categories : null);
			#if editor
			ide.initMenu();
			#end
		}}];

		for(name in getCategories(base)) {
			var has = categories != null && categories.indexOf(name) >= 0;
			menu.push({
				label: name, checked: has, stayOpen: true, click: function() {
					if(has)
						categories.remove(name);
					else {
						if(categories == null)
							categories = [];
						categories.push(name);
					}
					has = !has;
					setFunc(categories.length > 0 ? categories : null);
				}
			});
		}

		return menu;
	}

	public function createDBSheet( ?index : Int ) {
		var value = ide.ask("Sheet name");
		if( value == "" || value == null ) return null;
		var s = ide.database.createSheet(value, index);
		if( s == null ) {
			ide.error("Name already exists");
			return null;
		}
		ide.saveDatabase();
		refreshAll();
		return s;
	}

	public function popupSheet( withMacro = true, ?sheet : cdb.Sheet, ?onChange : Void -> Void ) {
		if( view != null )
			return;
		if( sheet == null ) sheet = this.currentSheet;
		if( onChange == null ) onChange = function() {}
		var index = base.sheets.indexOf(sheet);

		var content : Array<ContextMenu.MenuItem> = [];
		if (withMacro) {
			content = content.concat([
				{ label : "Add Sheet", click : function() { beginChanges(); var db = createDBSheet(index+1); endChanges(); if( db != null ) onChange(); } },
				{ label : "Move Left", click : function() { beginChanges(); base.moveSheet(sheet,-1); endChanges(); onChange(); } },
				{ label : "Move Right", click : function() { beginChanges(); base.moveSheet(sheet,1); endChanges(); onChange(); } },
				{ label : "Rename", click : function() {
					var name = ide.ask("New name", sheet.name);
					if( name == null || name == "" || name == sheet.name ) return;
					if( !rename(sheet, name) ) return;
					onChange();
				}},
				{ label : "Delete", click : function() {
					beginChanges();
					base.deleteSheet(sheet);
					endChanges();
					onChange();
				}},
				{ label : "Categories", menu: categoriesMenu(getSheetProps(sheet).categories, function(cats) {
					beginChanges();
					var props = getSheetProps(sheet);
					props.categories = cats;
					sheet.props.editor = props;
					endChanges();
					onChange();
				})},
				{ label : "", isSeparator: true },

			]);
		}
		if( sheet.props.dataFiles == null )
			content = content.concat([
				{ label : "Add Index", checked : sheet.props.hasIndex, click : function() {
					beginChanges();
					if( sheet.props.hasIndex ) {
						for( o in sheet.getLines() )
							Reflect.deleteField(o, "index");
						sheet.props.hasIndex = false;
					} else {
						for( c in sheet.columns )
							if( c.name == "index" ) {
								ide.error("Column 'index' already exists");
								return;
							}
						sheet.props.hasIndex = true;
					}
					endChanges();
				}},
				{ label : "Add Group", checked : sheet.props.hasGroup, click : function() {
					beginChanges();
					if( sheet.props.hasGroup ) {
						for( o in sheet.getLines() )
							Reflect.deleteField(o, "group");
						sheet.props.hasGroup = false;
					} else {
						for( c in sheet.columns )
							if( c.name == "group" ) {
								ide.error("Column 'group' already exists");
								return;
							}
						sheet.props.hasGroup = true;
					}
					endChanges();
				}},
			]);
		if( sheet.lines.length == 0 || sheet.props.dataFiles != null )
			content.push({
				label : "Data Files",
				checked : sheet.props.dataFiles != null,
				click : function() {
					var txt = ide.ask("Data Files Path", sheet.props.dataFiles);
					if( txt == null ) return;
					txt = StringTools.trim(txt);
					beginChanges();
					if( txt == "" ) {
						sheet.props.dataFiles = js.Lib.undefined;
						for( l in @:privateAccess sheet.sheet.lines )
							Reflect.deleteField(l, "$cdbtype");
						@:privateAccess sheet.sheet.linesData = js.Lib.undefined;
						@:privateAccess sheet.sheet.separators = [];
					} else {
						sheet.props.dataFiles = txt;
						@:privateAccess sheet.sheet.lines = null;
					}
					DataFiles.load();
					endChanges();
					refresh();
				}
			});
		ContextMenu.createFromPoint(ide.mouseX, ide.mouseY, content);
	}

	public function close() {
		for( t in tables.copy() )
			t.dispose();
	}

	public function focus() {
		#if js
		if( element.is(":focus") ) return;
		(element[0] : Dynamic).focus({ preventScroll : true });
		#end
	}

	static public function getSheetProps( s : cdb.Sheet ) {
		var pr : EditorSheetProps = s.props.editor;
		if( pr == null ) pr = {};
		return pr;
	}

	static public function getCategories(db: cdb.Database) : Array<String> {
		var names : Array<String> = [];
		for( s in db.sheets ) {
			var props = getSheetProps(s);
			if(props.categories != null) {
				for(n in props.categories) {
					if(names.indexOf(n) < 0)
						names.push(n);
				}
			}
			for(c in s.columns) {
				var cProps = getColumnProps(c);
				if(cProps.categories != null) {
					for(n in cProps.categories) {
						if(names.indexOf(n) < 0)
							names.push(n);
					}
				}
			}
		}
		names.sort((a, b) -> Reflect.compare(a, b));
		return names;
	}
}
