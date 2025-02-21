package hide.comp.cdb;

typedef Selection = {
	var x1 : Int;
	var y1 : Int;
	var x2 : Int;
	var y2 : Int;
	var ?origin : { x: Int, y: Int };
}

typedef CursorState = {
	var sheet : String;
	var x : Int;
	var y : Int;
	var selection : Array<Selection>;
}

class Cursor {
	var editor : Editor;
	public var table : Table;
	public var x : Int;
	public var y : Int;
	public var selection : Array<Selection>;

	public function new(editor) {
		this.editor = editor;
		set();
	}


	public function set( ?t : Table, ?x : Int = 0, ?y : Int = 0, ?sel : Array<Selection>, update : Bool = true ) {
		if( t != null ) {
			for( t2 in editor.tables )
				if( t.sheet.getPath() == t2.sheet.getPath() ) {
					t = t2;
					break;
				}
		}

		this.table = t;
		this.x = x;
		this.y = y;
		this.selection = sel;
		if( update ) this.update();
	}

	public function setDefault(line, column) {
		set(editor.tables[0], column, line);
	}

	public function move( dx : Int, dy : Int, shift : Bool, ctrl : Bool, alt : Bool, ?overflow : Bool = false ) {
		if( table == null )
			table = editor.tables[0];

		// Allow user to move lines while moving cursor and holding alt
		if( alt ) {
			if( dy != 0 ) {
				if( table == null )
					return;
				var lines = [];
				for (c in getSelectedCells())
					if (!lines.contains(c.line))
						lines.push(c.line);
				editor.moveLines(lines, dy);
			}
			update();
			return;
		}

		// enter/leave subtable
		if( dx == 0 && !shift && !ctrl && !alt) {
			var c = getCell();
			if( c != null && dy == 1 && c.line.subTable != null && c.line.subTable.cell == c ) {
				set(c.line.subTable);
				return;
			}
			var st = Std.downcast(table, SubTable);
			if( c != null && dy == -1 && st != null && c.line.index == 0 ) {
				set(st.parent, st.cell.columnIndex, st.cell.line.index);
				return;
			}
		}

		// take care of current filter
		var line = getLine();
		if( line != null && dy != 0 ) {
			var allLines = line.element.parent().children("tr").not(".separator");
			var lines = allLines.not(".filtered").not(".hidden");
			var index = lines.index(line.element);
			var targetLine = lines.get(hxd.Math.imax(index + dy,0));
			if( targetLine == null || targetLine == line.element.get(0) ) return;
			dy = allLines.index(new Element(targetLine)) - allLines.index(line.element);
		}

		// Allow area selection while moving cursor with arrows and holding shift
		if (shift) {
			if (selection != null && selection[selection.length - 1].origin != null) {
				var prev = selection[selection.length - 1];
				selection = [ { x1: Std.int(hxd.Math.min(prev.origin.x, x + dx)), y1: Std.int(hxd.Math.min(prev.origin.y, y + dy)),
					x2: Std.int(hxd.Math.max(prev.origin.x, x + dx)), y2: Std.int(hxd.Math.max(prev.origin.y, y + dy)),
					origin: prev.origin }];
			}
			else {
				addElementToSelection(line.table, line, x + dx, y + dy, true, false);
				selection[selection.length -1].origin = { x: x, y: y };
			}
		}
		else
			addElementToSelection(line.table, line, x + dx, y + dy);

		var minX = table.displayMode == Table ? -1 : 0;
		var maxX = table.columns.length;
		var maxY = table.lines.length;
		if( dx < 0 ) {
			x += dx;
			if( x < minX ) {
				if (overflow && y > 0) {
					x = maxX - 1;
					dy--;
				} else
					x = minX;
			}
		}
		if( dy < 0 ) {
			y += dy;
			if( y < 0 ) y = 0;
		}
		if( dx > 0 ) {
			x += dx;
			if( x >= maxX ) {
				if (overflow && y < maxY - 1) {
					x = minX;
					dy++;
				} else
					x = maxX - 1;
			}
		}
		if( dy > 0 ) {
			y += dy;
			if( y >= maxY ) y = maxY - 1;
		}
		update();
	}

	public function update() {
		hide();

		var line = getLine();
		if( table == null || line == null ) return;

		// Update cursor visual
		var cursorEl = x < 0 ? line.element.find(".start").get(0) : line.cells[x]?.elementHtml;
		if (cursorEl != null)
			cursorEl.classList.add("cursorView");

		// Update selection visual
		if (selection != null) {
			for (sel in selection) {
				var selectedCells = getCellsFromSelection(sel);
				if (selectedCells != null) {
					for (c in selectedCells) {
						if (c == null) continue;
						var cellX = c.columnIndex;
						var cellY = c.line.index;
						var el = c.elementHtml;
						el.classList.add("selected");
						if (cellY == sel.y1)
							el.classList.add("top");
						if (cellX == sel.x1)
							el.classList.add("left");
						if (cellX == sel.x2)
							el.classList.add("right");
						if (cellY == sel.y2)
							el.classList.add("bot");
					}
				}

				var selectedLines = getLinesFromSelection(sel);
				if (selectedLines != null) {
					for (l in selectedLines) {
						var el = l.element;
						el.addClass("selected");
						if (l.index == sel.y1)
							el.addClass("top");
						if (l.index == sel.y2)
							el.addClass("bot");
					}
				}
			}
		}

		var e = line.element.get(0);
		if( e != null ) untyped e.scrollIntoViewIfNeeded();
	}


	public function setState(state : CursorState, ?table : Table) {
		if( state == null )
			set(table);
		else
			set(table, state.x, state.y, state.selection);
	}

	public function getState() : CursorState {
		return table == null ? null : {
			sheet : table.sheet.getPath(),
			x : x,
			y : y,
			selection : selection?.copy()
		};
	}


	public function save() {
		if( table == null ) return null;
		return { sheet : table.sheet, x : x, y : y, selection : selection };
	}

	public function load( s ) {
		if( s == null )
			return false;
		var table = null;
		for( t in editor.tables )
			if( t.sheet == s.sheet ) {
				table = t;
				break;
			}
		if( table == null )
			return false;
		set(table, s.x, s.y, s.selection);
		return true;
	}

	public function hide() {
		var elt = editor.element;
		elt.find(".selected").removeClass("selected");
		elt.find(".cursorView").removeClass("cursorView");
		elt.find(".top").removeClass("top");
		elt.find(".left").removeClass("left");
		elt.find(".right").removeClass("right");
		elt.find(".bot").removeClass("bot");
	}


	// Get selected area with line in it. Otherwise return null
	public function getSelectedAreaIncludingLine(line : Line) {
		if (selection == null)
			return null;
		for (s in selection) {
			if (line.index >= s.y1 && line.index <= s.y2)
				return s;
		}

		return null;
	}

	// Get selected area with cell in it. Otherwise return null
	public function getSelectedAreaIncludingCell(cell : Cell) {
		if (selection == null)
			return null;
		for (s in selection) {
			if (cell.line.index >= s.y1 && cell.line.index <= s.y2 &&
				cell.columnIndex >= s.x1 && cell.columnIndex <= s.x2)
				return s;
		}

		return null;
	}

	public function getLinesFromSelection(sel : Selection) {
		if (sel == null || sel.x1 >= 0)
			return null;
		return [for( iy in sel.y1...(sel.y2 + 1) ) table.lines[iy]];
	}

	public function getCellsFromSelection(sel : Selection) {
		if (sel == null || sel.y1 >= table.lines.length || sel.y2 >= table.lines.length)
			return null;

		var cells = [];
		if (sel.x1 == -1) {
			for (y in sel.y1...(sel.y2 + 1)) {
				for (x in 0...(table.lines[y].cells.length)) {
					cells.push(table.lines[y].cells[x]);
				}
			}
		}
		else {
			for (y in sel.y1...(sel.y2 + 1)) {
				for (x in sel.x1...(sel.x2 + 1)) {
					cells.push(table.lines[y].cells[x]);
				}
			}
		}

		return cells;
	}

	public function getSelectedLines() {
		var lines = [];
		if (selection == null)
			return lines;

		for (s in selection) {
			var tmp = getLinesFromSelection(s);
			if (tmp == null)
				continue;

			lines = lines.concat(tmp);
		}

		return lines;
	}

	public function getSelectedCells() {
		var cells = [];
		if (selection == null)
			return cells;

		for (s in selection) {
			var tmp = getCellsFromSelection(s);
			if (tmp == null)
				continue;

			cells = cells.concat(tmp);
		}

		return cells;
	}

	public function getLine() {
		if( table == null ) return null;
		return table.lines[y];
	}

	public function getCell() {
		var line = getLine();
		if( line == null ) return null;
		return line.cells[x];
	}


	public function clickLine( line : Line, shiftKey = false, ctrlKey = false ) {
		addElementToSelection(line.table, line, -1, line.index, shiftKey, ctrlKey);
		set(line.table, -1, line.index, this.selection);
	}

	public function clickCell( cell : Cell, shiftKey = false, ctrlKey = false ) {
		var xIndex = cell.table.displayMode == Table ? cell.columnIndex : 0;
		addElementToSelection(cell.table, cell.line, xIndex, cell.line.index, shiftKey, ctrlKey);
		set(cell.table, xIndex, cell.line.index, this.selection);
	}

	public function addElementToSelection(table: Table, line: Line, xIndex : Int, yIndex: Int, shift: Bool = false, ctrl: Bool = false) {
		var p1 = new h3d.Vector(x, y, 0);
		var p2 = new h3d.Vector(xIndex, yIndex, 0);
		if (shift && this.table == table) {
			var prev = selection != null && selection.length >= 1 ? selection[selection.length - 1] : null;
			if (prev != null && prev.origin != null)
				p1 = new h3d.Vector(prev.origin.x, prev.origin.y, 0);
			selection = [];
			selection.push({ x1: Std.int(hxd.Math.min(p1.x, p2.x)), x2: Std.int(hxd.Math.max(p1.x, p2.x)),
				 y1: Std.int(hxd.Math.min(p1.y, p2.y)), y2: Std.int(hxd.Math.max(p1.y, p2.y)),
				origin: prev != null && prev.origin != null ? prev.origin : {x: x, y: y} });
		}
		else if(ctrl) {
			if (selection == null) {
				selection = [];
				selection.push({ x1: x, x2: x, y1: y, y2: y });
			}
			selection.push({ x1: xIndex, x2: xIndex, y1: yIndex, y2: yIndex });
		}
		else {
			selection = [{ x1: xIndex, x2: xIndex, y1: yIndex, y2: yIndex }];
		}

		updateSelection();
		table.showSeparator(line);
		update();
	}

	// Ensure each cell in selection is here only once
	public function updateSelection() {
		// Is s1 containing s2
		function isContaining(s1 : Selection, s2: Selection) {
			return s2.x1 >= s1.x1 && s2.x1 <= s1.x2 && s2.y1 >= s1.y1 && s2.y1 <= s1.y2 &&
			s2.x2 >= s1.x1 && s2.x2 <= s1.x2 && s2.y2 >= s1.y1 && s2.y2 <= s1.y2;
		}

		var idx = selection.length;
		while(idx-- > 0) {
			var s = selection[idx];
			var idx2 = selection.length;
			while(idx2-- > 0) {
				var s2 = selection[idx2];
				if (s2 == s) continue;
				if (isContaining(s, s2))
					selection.remove(s2);
			}

		}
	}
}
