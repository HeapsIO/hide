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
	var ?categories : Array<String>;
}

typedef EditorSheetProps = {
	var ?categories : Array<String>;
}

@:allow(hide.comp.cdb)
class Editor extends Component {

	var base : cdb.Database;
	var currentSheet : cdb.Sheet;
	var existsCache : Map<String,{ t : Float, r : Bool }> = new Map();
	var tables : Array<Table> = [];
	var searchBox : Element;
	var searchHidden : Bool = true;
	var displayMode : Table.DisplayMode;
	var clipboard : {
		text : String,
		data : Array<{}>,
		schema : Array<cdb.Data.Column>,
	};
	var changesDepth : Int = 0;
	var currentFilters : Array<String> = [];
	var api : EditorApi;
	var undoState : Array<UndoState> = [];
	var currentValue : Any;
	var cdbTable : hide.view.CdbTable;
	public var view : cdb.DiffFile.ConfigView;
	public var config : hide.Config;
	public var cursor : Cursor;
	public var keys : hide.ui.Keys;
	public var undo : hide.ui.UndoHistory;
	public var cursorStates : Array<UndoState> = [];
	public var cursorIndex : Int = 0;
	public var formulas : Formulas;

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
			if( cell != null && cell.isTextInput() && !e.ctrlKey && !cell.blockEdit())
				cell.edit();
		});
		element.contextmenu(function(e) e.preventDefault());

		if( cdbTable == null ) {
			element.mousedown(onMouseDown);
			keys = new hide.ui.Keys(element);
		} else {
			cdbTable.element.off("mousedown", onMouseDown);
			cdbTable.element.mousedown(onMouseDown);
			keys = cdbTable.keys;
		}

		keys.clear();
		keys.addListener(onKey);
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
		keys.register("cdb.moveBack", () -> cursorJump(true));
		keys.register("cdb.moveAhead", () -> cursorJump(false));
		keys.register("cdb.insertLine", function() { insertLine(cursor.table,cursor.y); cursor.move(0,1,false,false); });
		keys.register("duplicate", function() { duplicateLine(cursor.table,cursor.y); cursor.move(0,1,false,false); });
		for( k in ["cdb.editCell","rename"] )
			keys.register(k, function() {
				var c = cursor.getCell();
				if( c != null && !c.blockEdit()) c.edit();
			});
		keys.register("cdb.closeList", function() {
			var c = cursor.getCell();
			var sub = Std.downcast(c == null ? cursor.table : c.table, SubTable);
			if( sub != null ) {
				sub.cell.elementHtml.click();
				return;
			}
			if( cursor.select != null ) {
				cursor.select = null;
				cursor.update();
			}
		});
		keys.register("cdb.", () -> gotoReference(cursor.getCell()));
		keys.register("cdb.globalSeek", () -> new GlobalSeek(cdbTable.element, cdbTable));

		base = sheet.base;
		if( cursor == null )
			cursor = new Cursor(this);
		else if ( !tables.contains(cursor.table) )
			cursor.set();
		if( displayMode == null ) displayMode = Table;
		DataFiles.load();
		if( currentValue == null ) currentValue = api.copy();
		refresh();
	}

	function onMouseDown( e : js.jquery.Event ) {
		switch ( e.which ) {
		case 4:
			cursorJump(true);
			return false;
		case 5:
			cursorJump(false);
			return false;
		}
		return true;
	}

	function onKey( e : js.jquery.Event ) {
		if( e.altKey )
			return false;
		switch( e.keyCode ) {
		case K.LEFT:
			cursor.move( -1, 0, e.shiftKey, e.ctrlKey);
			return true;
		case K.RIGHT:
			cursor.move( 1, 0, e.shiftKey, e.ctrlKey);
			return true;
		case K.UP:
			cursor.move( 0, -1, e.shiftKey, e.ctrlKey);
			return true;
		case K.DOWN:
			cursor.move( 0, 1, e.shiftKey, e.ctrlKey);
			return true;
		case K.TAB:
			cursor.move( e.shiftKey ? -1 : 1, 0, false, false, true);
			return true;
		case K.PGUP:
			cursor.move(0, -10, e.shiftKey, e.ctrlKey);
			return true;
		case K.PGDOWN:
			cursor.move(0, 10, e.shiftKey, e.ctrlKey);
			return true;
		case K.SPACE:
			e.preventDefault(); // prevent scroll
		case K.ESCAPE:
			if( currentFilters.length > 0 ) {
				searchFilter([]);
				// Auto expand separators if they were hidden
				// Also : Very cursed code
				var line = cursor.getLine();
				if (line != null) {
					var sep = line.element.prevAll(".separator").first();
					while (sep.length > 0) {
						trace(sep.get(0).classList);
						if (sep.hasClass("sep-hidden")) {
							sep.find("a").click();
						}
						if (Std.parseInt(sep.attr("level")) > 0) {
							sep = sep.prevAll(".separator").first();
						}
						else {
							break;
						}
					}
				}
			}

			searchBox.hide();
			refresh();
		}
		return false;
	}

	public function updateFilter() {
		searchFilter(currentFilters);
	}

	public function setFilter( f : String ) {
		if( searchBox != null ) {
			if( f == null )
				searchBox.hide();
			else {
				searchBox.show();
				searchBox.find("input").val(f);
			}
		}
		if ( f == null )
			searchFilter([]);
		else
			searchFilter([f]);
	}

	function searchFilter( filters : Array<String> ) {
		while( filters.indexOf("") >= 0 )
			filters.remove("");
		while( filters.indexOf(null) >= 0 )
			filters.remove(null);

		function matches(haysack: String, needle: String) {
			return needle.split(" ").all(f -> haysack.indexOf(f) >= 0);
		}

		function removeAccents(str: String) {
			var t = untyped str.toLowerCase().normalize('NFD');
			return ~/[\u0300-\u036f]/g.map(t, (r) -> "");
		}
		for( i in 0...filters.length )
			filters[i] = removeAccents(filters[i]);

		var all = element.find("table.cdb-sheet > tbody > tr").not(".head");
		if( config.get("cdb.filterIgnoreSublist") )
			all = element.find("> table.cdb-sheet > tbody > tr").not(".head");
		var seps = all.filter(".separator");
		var lines = all.not(".separator");
		all.removeClass("filtered");
		if( filters.length > 0 ) {
			if (searchHidden) {
				var currentTable = tables.filter((t) -> t.sheet == currentSheet)[0];
				for (l in currentTable.lines) {
					if (l.element.hasClass("hidden"))
						l.create();
				}
			}

			for( t in lines ) {
				var content = removeAccents(t.textContent);
				if( !filters.any(f -> matches(content, f)) )
					t.classList.add("filtered");
			}
			for( t in lines ) {
				var l = new Element(t);
				var parent: Element = l.data("parent-tr");
				if( parent != null ) {
					var f = parent.hasClass("filtered") && l.hasClass("filtered");
					l.toggleClass("filtered", f);
					parent.toggleClass("filtered", f);
				}
			}
			all = all.not(".filtered");
			if (!searchHidden)
				all = all.not(".hidden");
			for( s in seps.elements() ) {
				var idx = all.index(s);
				if( idx == all.length - 1 || new Element(all.get(idx+1)).hasClass("separator") ) {
					s.addClass("filtered");
				}
			}
		}
		currentFilters = filters;
		cursor.update();
	}

	function onCopy() {
		var sel = cursor.getSelection();
		if( sel == null )
			return;
		var data = [];
		var isProps = (cursor.table.displayMode != Table);
		var schema;
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
			schema = [];
			var out = {};
			for( y in sel.y1...sel.y2+1 ) {
				var line = cursor.table.lines[y];
				var obj = line.obj;
				var c = line.columns[0];

				saveValue(out, obj, c);
				schema.push(c);
			}
			data.push(out);

		} else {
			for( y in sel.y1...sel.y2+1 ) {
				var obj = cursor.table.lines[y].obj;
				var out = {};
				for( x in sel.x1...sel.x2+1 ) {
					var c = cursor.table.columns[x];
					saveValue(out, obj, c);

				}
				data.push(out);
			}
			schema = [for( x in sel.x1...sel.x2+1 ) cursor.table.columns[x]];
		}
		clipboard = {
			data : data,
			text : Std.string([for( o in data ) cursor.table.sheet.objToString(o,true)]),
			schema : schema,
		};
		ide.setClipboard(clipboard.text);
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

	function onPaste() {
		var text = ide.getClipboard();
		var columns = cursor.table.columns;
		var sheet = cursor.table.sheet;
		var realSheet = cursor.table.getRealSheet();
		var allLines = cursor.table.lines;

		var fullRefresh = false;
		var toRefresh : Array<Cell> = [];

		var isProps = (cursor.table.displayMode != Table);
		var x1 = cursor.x;
		var y1 = cursor.y;
		var x2 = cursor.select == null ? x1 : cursor.select.x;
		var y2 = cursor.select == null ? y1 : cursor.select.y;
		if( x1 > x2 ) {
			var tmp = x1;
			x1 = x2;
			x2 = tmp;
		}
		if( y1 > y2 ) {
			var tmp = y1;
			y1 = y2;
			y2 = tmp;
		}

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
				default:
				}
				return null;
			}
			if( isProps ) {
				var line = cursor.getLine();
				toRefresh.push(cursor.getCell());
				var col = line.columns[x1];

				if( !cursor.table.canEditColumn(col.name) )
					return;

				var value = parseText(text, col.type);
				if( value == null )
					return;
				beginChanges();
				var obj = line.obj;
				formulas.removeFromValue(obj, col);
				if (col.type == TId)
					value = ensureUniqueId(value, cursor.table, col);
				Reflect.setField(obj, col.name, value);
			} else {
				beginChanges();
				for( x in x1...x2+1 ) {
					var col = columns[x];
					if( !cursor.table.canEditColumn(col.name) )
						continue;
					var lines = y1 == y2 ? [text] : text.split("\n");
					for( y in y1...y2+1 ) {
						var text = lines[y - y1];
						if( text == null ) text = lines[lines.length - 1];
						var value = parseText(text, col.type);
						if( value == null ) continue;
						var obj = sheet.lines[y];
						formulas.removeFromValue(obj, col);
						if (col.type == TId)
							value = ensureUniqueId(value, cursor.table, col);
						Reflect.setField(obj, col.name, value);
						toRefresh.push(allLines[y].cells[x]);
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
			if( f == null )
				v = base.getDefault(destCol, sheet);
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
			}
			if( v == null )
				Reflect.deleteField(destObj, destCol.name);
			else
				Reflect.setField(destObj, destCol.name, v);
		}

		var posX = x1 < 0 ? 0 : x1;
		var posY = y1 < 0 ? 0 : y1;
		var data = clipboard.data;
		if( data.length == 0 )
			return;

		if( isProps ) {
			var obj1 = data[0];
			var obj2 = cursor.getLine().obj;
			if( clipboard.schema.length == 1 ) {
				var line = cursor.getLine();
				var destCol = line.columns[posX];
				var clipSchema = clipboard.schema[0];
				if( clipSchema == null || destCol == null)
					return;
				if( !cursor.table.canEditColumn(destCol.name) )
					return;
				toRefresh.push(cursor.getCell());
				beginChanges();
				setValue(obj1, obj2, clipSchema, destCol);
			} else {
				beginChanges();
				for( c1 in clipboard.schema ) {
					var c2 = cursor.table.sheet.columns.find(c -> c.name == c1.name);
					if( c2 == null || !cursor.table.canEditColumn(c2.name))
						continue;
					if( !cursor.table.canInsert() && c2.opt && !Reflect.hasField(obj2, c2.name) )
						continue;
					setValue(obj1, obj2, c1, c2);
					fullRefresh = true;
				}
			}
		} else {
			beginChanges();
			if( data.length == 1 && y1 != y2 )
				data = [for( i in y1...y2+1 ) data[0]];
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

					if( !cursor.table.canEditColumn(c2.name) )
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
		var sel = cursor.getSelection();
		if( sel == null )
			return;
		var hasChanges = false;
		var sheet = cursor.table.sheet;
		var id = getCursorId(sheet, true);
		if( id != null && id.length > 0) {
			var refs = getReferences(id, sheet);
			if( refs.length > 0 ) {
				var message = refs.join("\n");
				if( !ide.confirm('$id is referenced elswhere. Are you sure you want to delete?\n$message') )
					return;
			}
		}
		beginChanges();
		if( cursor.x < 0 ) {
			// delete lines
			var y = sel.y2;
			if( !cursor.table.canInsert() ) {
				endChanges();
				return;
			}
			while( y >= sel.y1 ) {
				var line = cursor.table.lines[y];
				sheet.deleteLine(line.index);
				hasChanges = true;
				y--;
			}
			cursor.set(cursor.table, -1, sel.y1, null, false);
		} else {
			// delete cells
			for( y in sel.y1...sel.y2+1 ) {
				var line = cursor.table.lines[y];
				for( x in sel.x1...sel.x2+1 ) {
					var c = line.columns[x];
					if( !line.cells[x].canEdit() )
						continue;
					var old = Reflect.field(line.obj, c.name);
					var def = base.getDefault(c,false,sheet);
					if( old == def )
						continue;
					changeObject(line,c,def);
					hasChanges = true;
				}
			}
		}
		endChanges();
		if( hasChanges )
			refreshAll();
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
			pushCursorState();
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

	function save() {
		api.save();
	}


	function undoStatesEqual( s1 : UndoState, s2 : UndoState, cmpCursors = true ) {
		function cursorEqual(c1 : Cursor.CursorState, c2 : Cursor.CursorState) {
			if( c1 == c2 )
				return true;
			if( c1 == null || c2 == null )
				return false;
			return c1.sheet == c2.sheet && c1.x == c2.x && c1.y == c2.y;
		}
		function undoSheetEqual(s1 : UndoSheet, s2 : UndoSheet) {
			if( s1.parent == null && s2.parent == null )
				return s1.sheet == s2.sheet;
			if( s1.parent == null || s2.parent == null )
				return false;
			if ( s1.sheet != s2.sheet || s1.parent.column != s2.parent.column || s1.parent.line != s2.parent.line )
				return false;
			return undoSheetEqual(s1.parent.sheet, s2.parent.sheet);
		}
		if ( s1.sheet != s2.sheet )
			return false;
		if( s1.tables.length != s2.tables.length )
			return false;
		for( i in 0...s1.tables.length ) {
			if( !undoSheetEqual(s1.tables[i], s2.tables[i]) )
				return false;
		}
		if( !cmpCursors )
			return true;
		if( cursorEqual(s1.cursor, s2.cursor) )
			return true;
		if( s1.cursor == null || s2.cursor == null )
			return false;
		return s1.cursor.y == -1 && s2.cursor.y == -1;
	}

	public function pushCursorState() {
		if ( cursor == null )
			return;
		var state = getState();
		state.data = null;

		var stateBehind = (cursorStates.length <= 0) ? null : cursorStates[cursorIndex];
		if( stateBehind != null && undoStatesEqual(state, stateBehind) )
			return;
		var stateAhead = (cursorStates.length <= 0 || cursorIndex >= cursorStates.length - 1) ? null : cursorStates[cursorIndex + 1];
		if ( stateAhead != null && undoStatesEqual(state, stateAhead) ) {
			cursorIndex++;
			return;
		}

		if( cursorIndex < cursorStates.length - 1 && cursorIndex >= 0 ) {
			cursorStates.splice(cursorIndex + 1, cursorStates.length);
		}

		cursorStates.push(state);
		if( cursorIndex < cursorStates.length - 1 )
			cursorIndex++;
	}

	function cursorJump(back = true) {
		focus();

		if( (back && cursorIndex <= 0) || (!back && cursorIndex >= cursorStates.length - 1) )
			return;
		if( back && cursorIndex == cursorStates.length - 1)
			pushCursorState();

		if(back)
			cursorIndex--;
		else
			cursorIndex++;

		var state = cursorStates[cursorIndex];
		syncSheet(null, state.sheet);

		if( undoStatesEqual(state, getState(), false) ) {
			setState(state, true);
			if( cursor.table != null ) {
				for( t in tables ) {
					if( t.sheet.getPath() == cursor.table.sheet.getPath() )
						cursor.table = t;
				}
			}
		} else
			refresh(state);

		if( cdbTable != null )
			@:privateAccess cdbTable.syncTabs();
		haxe.Timer.delay(() -> cursor.update(), 1); // scroll
	}

	public static var inRefreshAll(default,null) : Bool;
	public static function refreshAll( eraseUndo = false ) {
		var editors : Array<Editor> = [for( e in new Element(".is-cdb-editor").elements() ) e.data("cdb")];
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
	public function getReferences(id: String, withCodePaths = true, sheet: cdb.Sheet) : Array<{str:String, ?goto:Void->Void}> {
		if( id == null )
			return [];

		function splitPath(rs: {s:Array<{s:cdb.Sheet, c:String, id:Null<String>}>, o:{path:Array<Dynamic>, indexes:Array<Int>}}) {
			var path = [];
			var coords = [];
			for( i in 0...rs.s.length ) {
				var s = rs.s[i];
				var oid = Reflect.field(rs.o.path[i], s.id);
				var idx = rs.o.indexes[i];
				if( oid == null || oid == "" )
					path.push(s.s.name.split("@").pop() + (idx < 0 ? "" : "[" + idx +"]"));
				else
					path.push(oid);
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

		var results = sheet.getReferencesFromId(id);
		var message = [];
		if( results != null ) {
			for( rs in results ) {
				var path = splitPath(rs);
				message.push({str: rs.s[0].s.name+"."+path.pathNames.join("."), goto: () -> openReference2(rs.s[0].s, path.pathParts)});
			}
		}
		if (withCodePaths) {
			var paths : Array<String> = this.config.get("haxe.classPath");
			if( paths != null ) {
				var spaces = "[ \\n\\t]";
				var prevChars = ",\\(:=\\?\\[";
				var postChars = ",\\):;\\?\\]&|";
				var regexp = new EReg('((case$spaces+)|[$prevChars])$spaces*$id$spaces*[$postChars]',"");
				var regall = new EReg("\\b"+id+"\\b", "");
				function lookupRec(p) {
					for( f in sys.FileSystem.readDirectory(p) ) {
						var fpath = p+"/"+f;
						if( sys.FileSystem.isDirectory(fpath) ) {
							lookupRec(fpath);
							continue;
						}
						if( StringTools.endsWith(f, ".hx") ) {
							var content = sys.io.File.getContent(fpath);
							if( content.indexOf(id) < 0 ) continue;
							for( line => str in content.split("\n") ) {
								if( regall.match(str) ) {
									if( !regexp.match(str) ) {
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
								}
							}
						}
					}
				}
				for( p in paths ) {
					var path = ide.getPath(p);
					if( sys.FileSystem.exists(path) && sys.FileSystem.isDirectory(path) )
						lookupRec(path);
				}
			}
			var paths : Array<String> = this.config.get("cdb.prefabsSearchPaths");
			var scriptStr = new EReg("\\b"+sheet.name.charAt(0).toUpperCase() + sheet.name.substr(1) + "\\." + id + "\\b","");

			if( paths != null ) {
				function lookupPrefabRec(path) {
					for( f in sys.FileSystem.readDirectory(path) ) {
						var fpath = path+"/"+f;
						if( sys.FileSystem.isDirectory(fpath) ) {
							lookupPrefabRec(fpath);
							continue;
						}
						var ext = f.split(".").pop();
						if( @:privateAccess hrt.prefab.Library.registeredExtensions.exists(ext) ) {
							var content = sys.io.File.getContent(fpath);
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
				}
				for( p in paths ) {
					var path = ide.getPath(p);
					if( sys.FileSystem.exists(path) && sys.FileSystem.isDirectory(path) )
						lookupPrefabRec(path);
				}
			}

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

	function openReference2(rootSheet : cdb.Sheet, path: Path) {
		ide.open("hide.view.CdbTable", {}, function(view) Std.downcast(view,hide.view.CdbTable).goto2(rootSheet,path));
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

		var filters: Array<String> = [];

		searchBox = new Element('<div><div class="input-col"><div class="input-cont"/></div></div>').addClass("searchBox").appendTo(element);
		var inputCont = searchBox.find(".input-cont");
		var inputCol = searchBox.find(".input-col");

		function addSearchInput() {
			var index = filters.length;
			filters.push("");
			new Element("<input type='text'>").appendTo(inputCont).keydown(function(e) {
				if( e.keyCode == 27 ) {
					searchBox.find("i.close-search").click();
					return;
				} else if( e.keyCode == 9 && index == filters.length - 1) {
					addSearchInput();
					return;
				}
			}).keyup(function(e) {
				filters[index] = e.getThis().val();
				searchFilter(filters.copy());
			});
			inputCol.find(".remove-btn").toggleClass("hidden", filters.length <= 1);
		}
		function removeSearchInput() {
			if( filters.length > 1 ) {
				var a = inputCont.find("input").last().remove();
				filters.pop();
				searchFilter(filters.copy());
				inputCol.find(".remove-btn").toggleClass("hidden", filters.length <= 1);
			}
		}

		var hideButton = new Element("<i>").addClass("fa fa-eye").appendTo(searchBox);
		hideButton.attr("title", "Search through hidden categories");

		hideButton.click(function(_) {
			searchHidden = !searchHidden;
			hideButton.toggleClass("fa-eye", searchHidden);
			hideButton.toggleClass("fa-eye-slash", !searchHidden);
			if (!searchHidden) {
				var hiddenSeps = element.find("table.cdb-sheet > tbody > tr").not(".head").filter(".separator").filter(".sep-hidden").find("a.toggle");
				hiddenSeps.click();
				hiddenSeps.click();
			}
			updateFilter();
		});

		new Element("<i>").addClass("close-search ico ico-times-circle").appendTo(searchBox).click(function(_) {
			searchFilter([]);
			searchBox.toggle();
			var c = cursor.save();
			focus();
			cursor.load(c);
			var hiddenSeps = element.find("table.cdb-sheet > tbody > tr").not(".head").filter(".separator").filter(".sep-hidden").find("a.toggle");
			hiddenSeps.click();
			hiddenSeps.click();
		});

		new Element("<i>").addClass("add-btn ico ico-plus").appendTo(inputCol).click(function(_) {
			addSearchInput();
		});
		new Element("<i>").addClass("remove-btn ico ico-minus").appendTo(inputCol).click(function(_) {
			removeSearchInput();
		});
		addSearchInput();

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

		if( currentFilters.length > 0 ) {
			updateFilter();
			searchBox.show();
			for( i in filters.length...currentFilters.length )
				addSearchInput();
			if( filters.length <= currentFilters.length ) {
				var inputs = inputCont.find("input");
				for( i in 0...inputs.length ) {
					var input: js.html.InputElement = cast inputs[i];
					input.value = currentFilters[i];
				}
			}
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

	public function newColumn( sheet : cdb.Sheet, ?index : Int, ?onDone : cdb.Data.Column -> Void, ?col ) {
		var modal = new hide.comp.cdb.ModalColumnForm(this, sheet, col, element);
		modal.setCallback(function() {
			var c = modal.getColumn(col);
			if (c == null)
				return;
			beginChanges(true);
			var err;
			if( col != null )
				err = base.updateColumn(sheet, col, c);
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
			for( t in tables )
				if( t.sheet == sheet )
					t.refresh();
			modal.closeModal();
		});
	}

	public function editColumn( sheet : cdb.Sheet, col : cdb.Data.Column ) {
		newColumn(sheet,col);
	}

	public function insertLine( table : Table, index = 0 ) {
		if( table == null || !table.canInsert() )
			return;
		if( table.displayMode == Properties ) {
			var ins = table.element.find("select.insertField");
			var options = [for( o in ins.find("option").elements() ) o.val()];
			ins.attr("size", options.length);
			options.shift();
			ins.focus();
			var index = 0;
			ins.val(options[0]);
			ins.off();
			ins.blur(function(_) table.refresh());
			ins.keydown(function(e) {
				switch( e.keyCode ) {
				case K.ESCAPE:
					element.focus();
				case K.UP if( index > 0 ):
					ins.val(options[--index]);
				case K.DOWN if( index < options.length - 1 ):
					ins.val(options[++index]);
				case K.ENTER:
					@:privateAccess table.insertProperty(ins.val());
				default:
				}
				e.stopPropagation();
				e.preventDefault();
			});
			return;
		}
		beginChanges();
		table.sheet.newLine(index);
		endChanges();
		table.refresh();
	}

	public function ensureUniqueId(originalId : String, table : Table, column : cdb.Data.Column) {
		var scope = table.getScope();
		var idWithScope : String = if(column.scope != null)  table.makeId(scope, column.scope, originalId) else originalId;

		if (isUniqueID(table.getRealSheet(), {}, idWithScope)) {
			return originalId;
		}
		return getNewUniqueId(originalId, table, column);
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

	public function duplicateLine( table : Table, index = 0 ) {
		if( !table.canInsert() || table.displayMode != Table )
			return;
		var srcObj = table.sheet.lines[index];
		beginChanges();
		var obj = table.sheet.newLine(index);
		for(colId => c in table.columns ) {
			var val = Reflect.field(srcObj, c.name);
			if( val != null ) {
				if( c.type != TId ) {
					// Deep copy
					Reflect.setField(obj, c.name, haxe.Json.parse(haxe.Json.stringify(val)));
				} else {
					// Increment the number at the end of the id if there is one

					var newId = getNewUniqueId(val, table, c);
					if (newId != null) {
						Reflect.setField(obj, c.name, newId);
					}
				}
			}
		}
		endChanges();
		table.refresh();
		table.getRealSheet().sync();
	}

	public function popupColumn( table : Table, col : cdb.Data.Column, ?cell : Cell ) {
		if( view != null )
			return;
		var sheet = table.getRealSheet();
		var indexColumn = sheet.columns.indexOf(col);
		var menu : Array<hide.comp.ContextMenu.ContextMenuItem> = [
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
					cursor.set(cursor.table, nextIndex, cursor.y);
				else if (cursor.x == nextIndex)
					cursor.set(cursor.table, nextIndex + 1, cursor.y);
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
					cursor.set(cursor.table, nextIndex, cursor.y);
				else if (cursor.x == nextIndex)
					cursor.set(cursor.table, nextIndex - 1, cursor.y);
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
			case TId | TString:
				menu.push({ label : "Sort", click: () -> table.sortBy(col), enabled : table.displayMode != AllProperties });
			default:
			}
		}

		if( col.type == TString && col.kind == Script )
			menu.insert(1,{ label : "Edit all", click : function() editScripts(table,col) });
		if( table.displayMode == Properties ) {
			menu.push({ label : "Delete All", click : function() {
				if( !ide.confirm("*** WARNING ***\nThis will delete the row for all properties !") )
					return;
				beginChanges(true);
				table.sheet.deleteColumn(col.name);
				endChanges();
				refresh();
			}});
		}
		new hide.comp.ContextMenu(menu);
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

	public function moveLine( line : Line, delta : Int, exact = false ) {
		if( !line.table.canInsert() )
			return;
		beginChanges();
		var prevIndex = line.index;

		var index : Null<Int> = null;
		var currIndex : Null<Int> = line.index;
		if (!exact) {
			var distance = (delta >= 0 ? delta : -1 * delta);
			for( _ in 0...distance ) {
				currIndex = line.table.sheet.moveLine( currIndex, delta );
				if( currIndex == null )
					break;
				else
					index = currIndex;
			}
		}
		else
			while (index != prevIndex + delta) {
				currIndex = line.table.sheet.moveLine( currIndex, delta );
				if( currIndex == null )
					break;
				else
					index = currIndex;
			}

		if( index != null ) {
			if (index != prevIndex) {
				if ( cursor.y == prevIndex ) cursor.set(cursor.table, cursor.x, index);
				else if ( cursor.y > prevIndex && cursor.y <= index) cursor.set(cursor.table, cursor.x, cursor.y - 1);
				else if ( cursor.y < prevIndex && cursor.y >= index) cursor.set(cursor.table, cursor.x, cursor.y + 1);
			}
			refresh();
		}
		endChanges();
	}

	function moveLines(lines : Array<Line>, delta : Int) {
		if( lines.length == 0 || !lines[0].table.canInsert() || delta == 0 )
			return;
		var selDiff: Null<Int> = cursor.select == null ? null : cursor.select.y - cursor.y;
		beginChanges();
		lines.sort((a, b) -> { return (a.index - b.index) * delta * -1; });
		for( l in lines ) {
			moveLine(l, delta);
		}
		if (selDiff != null && hxd.Math.iabs(selDiff) == lines.length - 1)
			cursor.set(cursor.table, cursor.x, cursor.y, {x: cursor.x, y: cursor.y + selDiff});
		endChanges();
	}

	public function popupLine( line : Line ) {
		if( !line.table.canInsert() )
			return;
		var sheet = line.table.sheet;
		var selection = cursor.getSelectedLines();
		var isSelectedLine = false;
		for( l in selection ) {
			if( l == line ) {
				isSelectedLine = true;
				break;
			}
		}
		var firstLine = isSelectedLine ? selection[0] : line;
		var lastLine = isSelectedLine ? selection[selection.length - 1] : line;

		var sepIndex = -1;
		for( i in 0...sheet.separators.length )
			if( sheet.separators[i].index == line.index ) {
				sepIndex = i;
				break;
			}

		var moveSubmenu : Array<hide.comp.ContextMenu.ContextMenuItem> = [];
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
			moveSubmenu.push({
				label : sep.title,
				enabled : true,
				click : isSelectedLine ? moveLines.bind(selection, delta) : moveLine.bind(usedLine, delta),
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

		var menu : Array<hide.comp.ContextMenu.ContextMenuItem> = [
			{
				label : "Move Up",
				enabled:  (firstLine.index > 0 || sepIndex >= 0),
				click : isSelectedLine ? moveLines.bind(selection, -1) : moveLine.bind(line, -1),
			},
			{
				label : "Move Down",
				enabled:  (lastLine.index < sheet.lines.length - 1),
				click : isSelectedLine ? moveLines.bind(selection, 1) : moveLine.bind(line, 1),
			},
			{ label : "Move to Group", enabled : moveSubmenu.length > 0, menu : moveSubmenu },
			{ label : "", isSeparator : true },
			{ label : "Insert", click : function() {
				insertLine(line.table,line.index);
				cursor.set(line.table, -1, line.index + 1);
				focus();
			}, keys : config.get("key.cdb.insertLine") },
			{ label : "Duplicate", click : function() {
				duplicateLine(line.table,line.index);
				cursor.set(line.table, -1, line.index + 1);
				focus();
			}, keys : config.get("key.duplicate") },
			{ label : "Delete", click : function() {
				var id = line.getId();
				if( id != null && id.length > 0) {
					var refs = getReferences(id, sheet);
					if( refs.length > 0 ) {
						var message = refs.join("\n");
						if( !ide.confirm('$id is referenced elswhere. Are you sure you want to delete?\n$message') )
							return;
					}
				}
				beginChanges();
				sheet.deleteLine(line.index);
				endChanges();
				refreshAll();
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
		new hide.comp.ContextMenu(menu);
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
		var menu : Array<ContextMenu.ContextMenuItem> = [{ label : "Set...", click : function() {
			var wstr = "";
			if(categories != null)
				wstr = categories.join(",");
			wstr = ide.ask("Set Categories (comma separated)", wstr);
			if(wstr == null)
				return;
			categories = [for(s in wstr.split(",")) { var t = StringTools.trim(s); if(t.length > 0) t; }];
			setFunc(categories.length > 0 ? categories : null);
			ide.initMenu();
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

	public function popupSheet( ?sheet : cdb.Sheet, ?onChange : Void -> Void ) {
		if( view != null )
			return;
		if( sheet == null ) sheet = this.currentSheet;
		if( onChange == null ) onChange = function() {}
		var index = base.sheets.indexOf(sheet);

		var content : Array<ContextMenu.ContextMenuItem> = [
			{ label : "Add Sheet", click : function() { beginChanges(); var db = ide.createDBSheet(index+1); endChanges(); if( db != null ) onChange(); } },
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

		];
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
						Reflect.deleteField(sheet.props,"dataFile");
						@:privateAccess sheet.sheet.lines = [];
					} else {
						sheet.props.dataFiles = txt;
						@:privateAccess sheet.sheet.lines = null;
						DataFiles.load();
					}
					endChanges();
					refresh();
				}
			});
		new ContextMenu(content);
	}

	public function close() {
		for( t in tables.copy() )
			t.dispose();
	}

	public function focus() {
		if( element.is(":focus") ) return;
		(element[0] : Dynamic).focus({ preventScroll : true });
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
