package hide.comp.cdb;
import hide.ui.QueryHelper.*;

enum DisplayMode {
	Table;
	Properties;
	AllProperties;
}

class Table extends Component {

	public var editor : Editor;
	public var parent : Table;
	public var sheet : cdb.Sheet;
	public var lines : Array<Line>;
	public var displayMode(default,null) : DisplayMode;

	public var columns : Array<cdb.Data.Column>;
	public var view : cdb.DiffFile.SheetView;

	var separators : Array<Separator>;
	var previewDrop : Element;

	public var nestedIndex : Int = 0;

	var resizeObserver : hide.comp.ResizeObserver;
	var currentDragIndex = -1;

	public var errorCount = 0;
	public var errors = new Map<Line, Bool>();
	public var warningCount = 0;
	public var warnings = new Map<Line, Bool>();

	static final reorderLineKey = "x-cdb.reorder";

	public function new(editor, sheet, root, mode) {
		super(null,root);
		this.displayMode = mode;
		this.editor = editor;
		this.sheet = sheet;
		saveDisplayKey = "cdb/"+sheet.name;

		@:privateAccess for( t in editor.tables )
			if( t.sheet.path == sheet.path )
				trace("Dup CDB table!");

		@:privateAccess editor.tables.push(this);
		root.addClass("cdb-sheet");
		root.addClass("s_" + sheet.name.split("@").join("_"));
		if( editor.view != null ) {
			var cname = parent == null ? null : sheet.parent.sheet.columns[sheet.parent.column].name;
			if( parent == null )
				view = editor.view.get(sheet.name);
			else if( parent.view.sub != null )
				view = parent.view.sub.get(cname);
			if( view == null ) {
				if( parent != null && parent.canEditColumn(cname) )
					view = { insert : true, edit : [for( c in sheet.columns ) c.name], sub : {} };
				else
					view = { insert : false, edit : [], sub : {} };
			}
		}
		refresh();

		previewDrop = new Element('<div class="cdb-preview-drag"><div>');
		previewDrop.appendTo(root);
		previewDrop.hide();
	}

	public function setCursor() {
		editor.cursor.set(this);
	}

	public function getRealSheet() {
		return sheet.realSheet;
	}

	public function canInsert() {
		if( sheet.props.dataFiles != null ) return false;
		return view == null || view.insert;
	}

	public function canEditColumn( name : String ) {
		return view == null || (view.edit != null && view.edit.indexOf(name) >= 0);
	}

	public function close() {
		// Close eventual cdb type edition before closing table
		var children = element.children().find(".cdb-type-string");
		if (children.length > 0)
			children.first().trigger("click");

		for( t in @:privateAccess editor.tables.copy() )
			if( t.parent == this )
				t.close();
		element.remove();
		dispose();
	}

	public function dispose() {
		editor.tables.remove(this);
	}

	public function refresh() {
		element.empty();
		columns = view == null || view.show == null ? sheet.columns : [for( c in sheet.columns ) if( view.show.indexOf(c.name) >= 0 ) c];
		if( !editor.showGUIDs ) {
			var cols = null;
			for( c in columns )
				if( c.type == TGuid && !c.opt ) {
					if( cols == null ) cols = columns.copy();
					cols.remove(c);
				}
			if( cols != null ) columns = cols;
		}
		switch( displayMode ) {
		case Table:
			refreshTable();
		case Properties, AllProperties:
			refreshProperties();
		}
	}

	function setupTableElement() {
		cloneTableHead();
	}

	function cloneTableHead() {
		#if js
		var target = element.find('thead').first().find('.head');
		if (target.length == 0)
			return;
		var target_children = target.children();

		J(".floating-thead").remove();

		var clone = J("<div>").addClass("floating-thead");

		for (i in 0...target_children.length) {
			var targetElt = target_children.eq(i);
			var elt = targetElt.clone(true); // clone with events
			elt.width(targetElt.width());
			elt.css("max-width", targetElt.width());

			var txt = elt.get(0).innerHTML;
			elt.empty();
			J("<span>" + txt + "</span>").appendTo(elt);

			clone.append(elt);
		}

		J('.cdb').prepend(clone);
		#end
	}

	function updateDragScroll() {
		#if js
		var scroll = element?.get(0)?.parentElement?.parentElement;
		if (scroll == null)
			return;
		var box = scroll.getBoundingClientRect();
		var percentHeight = (ide.mouseY - box.top) / box.height;

		var scrollAmount = 0.0;
		if (percentHeight < 0.2) {
			scrollAmount = percentHeight / 0.2 - 1.0;
		}
		else if (percentHeight > 0.8) {
			scrollAmount = (percentHeight - 0.8) / 0.2;
		}
		scrollAmount = hxd.Math.clamp(scrollAmount, -1.0, 1.0);
		scroll.scrollTop += hxd.Math.round(scrollAmount * 30);
		#end
	}

	function addIcons(c: cdb.Data.Column, el: hide.Element) {
		if( c.documentation != null ) {
			el.attr("title", c.documentation);
			new Element('<i style="margin-left: 5px" class="ico ico-book"/>').appendTo(el);
		}
		if( c.shared ) {
			new Element('<i style="margin-left: 5px" class="ico ico-share-alt" title="Shared column"/>').appendTo(el);
			el.addClass("shared");
		}
		if( c.structRef != null ) {
			new Element('<i style="margin-left: 5px" class="ico ico-reply" title="Referencing ${c.structRef}"/>').appendTo(el);
			el.addClass("struct-ref");
		}
		if( c.type == TString ) {
			var ico = switch(c.kind) {
				case Localizable:
					"ico-globe";
				case Script:
					"ico-code";
				default:
					"ico-text-width";
			}
			new Element('<i style="margin-right: 5px" class="ico $ico"/>').prependTo(el);
		}
	}


	function refreshTable() {
		errorCount = 0;
		errors = new Map<Line, Bool>();
		warningCount = 0;
		warnings = new Map<Line, Bool>();

		var cols = J("<thead>").addClass("head");
		var start = J("<th>").addClass("start").appendTo(cols);
		if (!Std.isOfType(this, SubTable) && sheet.props.dataFiles == null) {
			start.contextmenu(function(e) {
				editor.popupSheet(false, sheet);
				e.preventDefault();
				return;
			});
		}
		lines = [for( index in 0...sheet.lines.length ) {
			var l = J("<tr>");
			var head = J("<td>").addClass("start").text("" + index);
			head.appendTo(l);
			var line = new Line(this, columns, index, l);
			head.contextmenu(function(e) {
				editor.popupLine(line);
				e.preventDefault();
				return;
			});
			l.click(function(e) {
				if( e.which == 3 ) {
					e.preventDefault();
					return;
				}
				editor.cursor.clickLine(line, e.shiftKey, e.ctrlKey);
			});
			#if js

			var headEl = head.get(0);
			headEl.draggable = true;
			headEl.ondragstart = function(e:js.html.DragEvent) {
				if (editor.cursor.getCell() != null && editor.cursor.getCell().inEdit) {
					e.preventDefault();
					return;
				}
				ide.registerUpdate(updateDragScroll);
				currentDragIndex = line.index;
				e.dataTransfer.setData(reorderLineKey, Std.string(line.index));
				e.dataTransfer.effectAllowed = "move";
				e.dataTransfer.setDragImage(l.get(0), 0, 0);
				previewDrop.show();
			}

			headEl.ondrag = function(e:js.html.DragEvent) {
				if (hxd.Key.isDown(hxd.Key.ESCAPE)) {
					e.dataTransfer.dropEffect = "none";
					e.preventDefault();
				}

				var pickedLine = getPickedLine(e);
				if (pickedLine != null) {
					var lineEl = editor.getLine(line.table.sheet, pickedLine.index).element;
					previewDrop.css("top",'${lineEl.position().top}px');
				}
			}

			var dragOver = function(e:js.html.DragEvent) {
				if (!e.dataTransfer.types.contains(reorderLineKey)) {
					return;
				}

				if (currentDragIndex < 0)
					return;

				ide.mouseX = e.clientX;
				ide.mouseY = e.clientY;

				e.preventDefault();
				e.stopPropagation();

				previewDrop.css("top",'${line.index > currentDragIndex ? l.position().top + l.height() : l.position().top}px');
			}

			var lineEl = l.get(0);
			lineEl.ondragover = dragOver;
			lineEl.ondragenter = dragOver;

			lineEl.ondrop = function(e:js.html.DragEvent) {
				if (currentDragIndex < 0)
					return;

				if (!e.dataTransfer.types.contains(reorderLineKey)) {
					return;
				}
				e.preventDefault();
				e.stopPropagation();

				var selection = editor.cursor.getSelectedAreaIncludingLine(line.table.lines[currentDragIndex]);
				if (selection != null) {
					moveLinesTo(editor.cursor.getLinesFromSelection(selection), line.index);
					return;
				}

				line.table.moveLinesTo([line.table.lines[currentDragIndex]], line.index);
			}

			headEl.ondragend = function(e:js.html.DragEvent) {
				ide.unregisterUpdate(updateDragScroll);
				previewDrop.hide();
				currentDragIndex = -1;
			}
			#end
			line;
		}];

		var colCount = columns.length;

		for( c in columns ) {
			var editProps = Editor.getColumnProps(c);
			var col = J("<th>");
			col.text(c.name);
			col.addClass( "t_"+c.type.getName().substr(1).toLowerCase() );
			col.addClass( "n_" + c.name );
			col.attr("title", c.name);
			col.toggleClass("hidden", !editor.isColumnVisible(c));
			col.toggleClass("cat", editProps.categories != null);
			if(editProps.categories != null)
				for(c in editProps.categories)
					col.addClass("cat-" + c);

			addIcons(c, col);
			if( sheet.props.displayColumn == c.name )
				col.addClass("display");
			col.contextmenu(function(e) {
				editor.popupColumn(this, c);
				e.preventDefault();
				return;
			});
			col.dblclick(function(_) {
				if( editor.view == null ) editor.editColumn(getRealSheet(), c);
			});
			cols.append(col);
		}

		element.append(cols);

		var tbody = J("<tbody>");

		var sepIndex = -1;
		var sepNext = sheet.separators[++sepIndex];
		separators = [];
		for( i in 0...lines.length ) {
			// Create the separator of this index if there is one
			while( sepNext != null && sepNext.index == i ) {
				var sep = new Separator(tbody, this, sepNext);

				// Create children relation between separators
				var prevSep = separators[separators.length - 1];
				if (prevSep != null) {
					var prevLevel = prevSep.data.level == null ? 0 : prevSep.data.level;
					var curLevel = sep.data.level == null ? 0 : sep.data.level;
					if (prevLevel < curLevel) {
						prevSep.subs.push(sep);
						sep.parent = prevSep;
					}
					else if (prevLevel == curLevel) {
						prevSep?.parent?.subs?.push(sep);
						sep.parent = prevSep?.parent;
					}
					else {
						var parent = prevSep;
						var level = prevLevel;
						while (parent != null && level >= curLevel) {
							parent = parent.parent;
							level = parent?.data?.level;
							if (level == null)
								level = 0;
						}

						parent?.subs?.push(sep);
						sep.parent = parent;
					}
				}

				separators.push(sep);
				sep.element.appendTo(tbody);
				sepNext = sheet.separators[++sepIndex];
			}

			// Create lines
			var parentSep = separators.length > 0 ? separators[separators.length - 1] : null;
			var line = lines[i];
			line.create();
			if (parentSep != null && !parentSep.getLinesVisiblity())
				line.hide();
			tbody.append(line.element);
		}

		refreshLinesStatus();

		for (s in separators)
			s.refresh(false);

		element.append(tbody);

		if( colCount == 0 ) {
			var l = J('<tr><td><input type="button" value="Add a column"/></td></tr>').find("input").click(function(_) {
				editor.newColumn(sheet);
			});
			element.append(l);
		} else if( sheet.lines.length == 0 && canInsert() ) {
			var l = J('<tr><td colspan="${columns.length + 1}"><input class="default-cursor" type="button" value="Insert Line"/></td></tr>');
			l.find("input").click(function(_) {
				insertLine();
				editor.cursor.set(this);
			});
			l.find("input").keydown(function(e) {
				if (e.keyCode != 13) return;
				insertLine();
				editor.cursor.set(this);
			});
			element.append(l);
		}

		#if js
		if( sheet.parent == null ) {
			cols.ready(setupTableElement);

			if (resizeObserver != null) {
				resizeObserver.disconnect();
			}
			resizeObserver = new hide.comp.ResizeObserver((_,_) -> setupTableElement());
			resizeObserver.observe(editor.element.parent().get(0));
		}
		#end
	}

	function getPickedLine(e : js.html.DragEvent) {
		var pickedEl = js.Browser.document.elementFromPoint(e.clientX, e.clientY);
		var pickedLine = null;
		var parentEl = pickedEl;
		while (parentEl != null) {
			if (lines.filter((otherLine) -> otherLine.element.get()[0] == parentEl).length > 0) {
				pickedLine = lines.filter((otherLine) -> otherLine.element.get()[0] == parentEl)[0];
				break;
			}
			parentEl = parentEl.parentElement;
		}

		return pickedLine;
	}

	public function revealLine(line: Int) {
		if (this.separators == null) return;
		var lastSeparator = -1;
		for (sIdx in 0...this.separators.length) {
			if (this.separators[sIdx].data.index > line) {
				break;
			}
			lastSeparator = sIdx;
		}
		if (lastSeparator >=0 ) {
			this.separators[lastSeparator].reveal();
		}
	}

	public function getScope() : Array<{ s : cdb.Sheet, obj : Dynamic }> {
		var scope = [];
		var table = this;
		while( true ) {
			var p = Std.downcast(table, SubTable);
			if( p == null ) break;
			var line = p.cell.line;
			scope.unshift({ s : line.table.getRealSheet(), obj : line.obj });
			table = table.parent;
		}
		return scope;
	}

	public function makeId(scopes : Array<{ s : cdb.Sheet, obj : Dynamic }>, scope : Int, id : String) : String {
		var ids = [];
		if( id != null ) ids.push(id);
		var pos = scopes.length;
		var scope : Null<Int> = scope;
		while( true ) {
			pos -= scope;
			if( pos < 0 ) {
				scopes = getScope();
				pos += scopes.length;
			}
			var s = scopes[pos];
			var pid = Reflect.field(s.obj, s.s.idCol.name);
			if( pid == null ) return "";
			ids.unshift(pid);
			scope = s.s.idCol.scope;
			if( scope == null ) break;
		}
		return ids.join(":");
	}

	public function shouldDisplayProp(props: Dynamic, c:cdb.Data.Column) {
		return !( c.opt && props != null && !Reflect.hasField(props,c.name) && displayMode != AllProperties );
	}

	function refreshProperties() {
		lines = [];

		var available = [];
		var props = sheet.lines[0];
		var isLarge = false;
		for( c in columns ) {

			if( c.type.match(TList | TProperties) ) isLarge = true;

			if(!shouldDisplayProp(props, c)) {
				available.push(c);
				continue;
			}

			var v = Reflect.field(props, c.name);
			var l = new Element("<tr>").appendTo(element);
			var th = new Element("<th>").text(c.name).appendTo(l);
			var td = new Element("<td>").addClass("c").appendTo(l);

			addIcons(c, th);
			var line = new Line(this, [c], lines.length, l);
			var cell = new Cell(td.get(0), line, c);
			lines.push(line);

			th.contextmenu(function(e) {
				editor.popupColumn(this, c, cell);
				editor.cursor.clickCell(cell, false, false);
				e.preventDefault();
			});
		}

		if( isLarge )
			element.parent().addClass("cdb-large");

		// add/edit properties
		var end = new Element("<tr>").appendTo(element);
		end = new Element("<td>").attr("colspan", "2").appendTo(end);
		var sel = new Element("<select class='insertField default-cursor'>").appendTo(end);
		new Element("<option>").attr("value", "").text("--- Choose ---").appendTo(sel);
		var canInsert = false;
		available.sort((c1, c2) -> (c1.name > c2.name ? 1 : -1));
		for( c in available )
			if( canEditColumn(c.name) ) {
				var opt = J("<option>").attr("value",c.name).text(c.name).appendTo(sel);
				if( c.documentation != null ) opt.attr("title", c.documentation);
				canInsert = true;
			}
		if( editor.view == null )
			J("<option>").attr("value","$new").text("New property...").appendTo(sel);
		else if( !canInsert )
			end.remove();
		sel.change(function(e) {
			var v = Element.getVal(sel);
			if( v == "" )
				return;
			sel.val("");
			editor.element.focus();
			if( v == "$new" ) {
				editor.newColumn(sheet, null, function(c) {
					if( c.opt ) insertProperty(c.name);
				});
				return;
			}
			insertProperty(v);
		});
	}

	function insertProperty( p : String ) {
		var props = sheet.lines[0];
		for( c in sheet.columns )
			if( c.name == p ) {
				var val = editor.base.getDefault(c, true, sheet);
				editor.beginChanges();
				Reflect.setField(props, c.name, val);
				editor.endChanges();
				refresh();
				for( l in lines )
					if( l.cells[0].column == c ) {
						l.cells[0].focus();
						break;
					}
				return true;
			}
		return false;
	}

	public function sortBy(col: cdb.Data.Column) {
		editor.beginChanges();
		var group : Array<Dynamic> = [];
		var startIndex = 0;
		function sort() {
			group.sort(function(a, b) {
				var val1 = Reflect.field(a, col.name);
				var val2 = Reflect.field(b, col.name);
				return Reflect.compare(val1, val2);
			});
			for(i in 0...group.length)
				sheet.lines[startIndex + i] = group[i];
		}
		var sepIndex = 0;
		for(i in 0...lines.length) {
			var isSeparator = false;
			while( sepIndex < sheet.separators.length ) {
				var sep = sheet.separators[sepIndex];
				if( sep.index > i ) break;
				if( sep.index == i ) isSeparator = true;
				sepIndex++;
			}
			if( isSeparator ) {
				sort();
				group = [];
				startIndex = i;
			}
			group.push(lines[i].obj);
		}
		sort();

		editor.endChanges();
		refresh();
	}

	public function toggleList( cell : Cell, ?immediate : Bool, ?make : Void -> SubTable ) {
		var line = cell.line;
		var cur = line.subTable;
		if( cur != null ) {
			cur.close();
			if( cur.cell == cell ) return; // toggle
		}
		var sub = make == null ? new SubTable(editor, cell) : make();
		sub.show(immediate);
		sub.setCursor();
	}

	public function refreshList( cell : Cell, ?make : Void -> SubTable ) {
		var line = cell.line;
		var cur = line.subTable;
		if( cur != null ) {
			cur.immediateClose();
			var sub = make == null ? new SubTable(editor, cell) : make();
			sub.show(true);
		}
	}

	function toString() {
		return "Table#"+sheet.name;
	}


	public function insertLine(index : Int = 0) {
		if( !canInsert() )
			return;
		if( displayMode == Properties ) {
			var ins = element.find("select.insertField");
			var options = [for( o in ins.find("option").elements() ) Element.getVal(o)];
			ins.attr("size", options.length);
			options.shift();
			ins.focus();
			var index = 0;
			ins.val(options[0]);
			ins.off();
			ins.blur(function(_) refresh());
			ins.keydown(function(e) {
				switch (e.keyCode) {
					case hxd.Key.ESCAPE:
						element.focus();
					case hxd.Key.UP if( index > 0 ):
						ins.val(options[--index]);
					case hxd.Key.DOWN if( index < options.length - 1 ):
						ins.val(options[++index]);
					case hxd.Key.ENTER:
						insertProperty(Element.getVal(ins));
					default:
				}
				e.stopPropagation();
				e.preventDefault();
			});
			return;
		}
		editor.beginChanges();
		sheet.newLine(index);
		editor.endChanges();
		refresh();
	}

	public function moveLines(lines : Array<Line>, delta : Int) {
		if( !canInsert() )
			return;

		var start = lines[0].index + 1;
		var end = start + delta;
		if (delta < 0) {
			var tmp = start;
			start = end - 1;
			end = tmp - 1;
		}
		var toUpdate : Array<Line> = [for (lIdx in start...end) this.lines[lIdx]];

		editor.beginChanges();
		lines.sort((a, b) -> { return (a.index - b.index) * delta * -1; });

		var range = { min: 100000, max: 0 };
		var distance = Std.int(hxd.Math.abs(delta));
		var newIdx = 0;
		for (l in lines ) {
			newIdx = l.index;
			for( _ in 0...distance ) {
				newIdx = sheet.moveLine(newIdx, delta);
				if( newIdx == null )
					break;
			}

			if (range.min > newIdx) range.min = newIdx;
			if (range.max < newIdx) range.max = newIdx;
		}

		editor.endChanges();

		// Update parent subtable line index to prevent weird behaviors while trying to reopen previous subtable
		// after editor refresh
		for (t in editor.tables) {
			var st = Std.downcast(t, SubTable);
			if (st == null)
				continue;

			if (toUpdate.contains(st.cell.line)) {
				var offset = lines.length;
				if (delta > 0)
					offset *= -1;
				st.sheet.parent.line += offset;
			}
		}

		// Set cursor and selection on moved lines
		editor.cursor.set(this, editor.cursor.x, range.min, [{ x1: -1, y1: range.min, x2: -1, y2: range.max }]);
		var state = editor.getState();
		trace(state);
		editor.refresh();
	}

	public function moveLinesTo(lines : Array<Line>, targetIdx : Int) {
		var fromIdx = lines[0].index;
		for (l in lines)
			if (l.index < fromIdx)
				fromIdx = l.index;

		var movingUp = fromIdx > targetIdx;
		var sepCount = 0;
		for (s in separators) {
			if ((movingUp && s.data.index > targetIdx && s.data.index <= fromIdx) || (!movingUp && s.data.index <= targetIdx && s.data.index > fromIdx))
				sepCount++;
		}

		moveLines(lines, movingUp ? (targetIdx - fromIdx) - sepCount : (targetIdx - fromIdx) + sepCount);

		// Set cursor and selection on moved lines
		editor.cursor.set(this, editor.cursor.x, targetIdx, [{ x1: -1, y1: targetIdx, x2: -1, y2: targetIdx + (lines.length - 1) }]);
	}

	public function duplicateLine(index : Int = 0) {
		if( !canInsert() || displayMode != Table )
			return;
		var srcObj = sheet.lines[index];
		editor.beginChanges();
		var obj = sheet.newLine(index);
		for(colId => c in columns ) {
			var val = Reflect.field(srcObj, c.name);
			if( val != null ) {
				if( c.type != TId ) {
					// Deep copy
					Reflect.setField(obj, c.name, haxe.Json.parse(haxe.Json.stringify(val)));
				} else {
					// Increment the number at the end of the id if there is one
					var newId = editor.getNewUniqueId(val, this, c);
					if (newId != null) {
						Reflect.setField(obj, c.name, newId);
					}
				}
			}
		}
		editor.endChanges();
		refresh();
		getRealSheet().sync();
	}

	public function refreshLinesStatus() {
		if (editor.cdbTable == null)
			return;
		editor.cdbTable.element.find(".warning").find("p").text(warningCount);
		editor.cdbTable.element.find(".error").find("p").text(errorCount);
		editor.cdbTable.element.find(".regular").find("p").text(lines.length - (errorCount + warningCount));
	}
}