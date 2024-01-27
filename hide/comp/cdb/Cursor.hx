package hide.comp.cdb;


typedef CursorState = {
	var sheet : String;
	var x : Int;
	var y : Int;
	var select : Null<{ x : Int, y : Int }>;
}

class Cursor {

	var editor : Editor;
	public var table : Table;
	public var x : Int;
	public var y : Int;
	public var select : Null<{ x : Int, y : Int }>;
	public var onchange : Void -> Void;

	public function new(editor) {
		this.editor = editor;
		set();
	}

	public function setState(state : CursorState, ?table : Table) {
		if( state == null )
			set(table);
		else
			set(table, state.x, state.y, state.select);
	}

	public function getState() : CursorState {
		return table == null ? null : {
			sheet : table.sheet.getPath(),
			x : x,
			y : y,
			select : Reflect.copy(select)
		};
	}

	public function set( ?t:Table, ?x=0, ?y=0, ?sel, update = true ) {
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
		this.select = sel;
		var ch = onchange;
		if( ch != null ) {
			onchange = null;
			ch();
		}
		if( update ) this.update();
	}

	public function setDefault(line, column) {
		set(editor.tables[0], column, line);
	}

	public function getLine() {
		if( table == null ) return null;
		return table.lines[y];
	}

	public function getSelectedLines() {
		if( table == null || x != -1 )
			return [];
		var selected = getSelection();
		return [for( iy in selected.y1...(selected.y2 + 1) ) table.lines[iy]];
	}

	public function getCell() {
		var line = getLine();
		if( line == null ) return null;
		return line.cells[x];
	}

	public function save() {
		if( table == null ) return null;
		return { sheet : table.sheet, x : x, y : y, select : select == null ? null : { x : select.x, y : select.y} };
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
		set(table, s.x, s.y, s.select);
		return true;
	}

	public function move( dx : Int, dy : Int, shift : Bool, ctrl : Bool, ?overflow = false ) {
		if( table == null )
			table = editor.tables[0];
		if( x == -1 && ctrl ) {
			if( dy != 0 ) {
				if( table == null )
					return;
				if( select == null )
					editor.moveLine(getLine(), dy);
				else
					editor.moveLines(getSelectedLines(), dy);
			}
			update();
			return;
		}

		// enter/leave subtable
		if( dx == 0 && !shift && !ctrl ) {
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

		if( !shift )
			select = null;
		else if( select == null )
			select = { x : x, y : y };
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

	public function hide() {
		var elt = editor.element;
		elt.find(".selected").removeClass("selected");
		elt.find(".cursorView").removeClass("cursorView");
		elt.find(".cursorLine").removeClass("cursorLine");
	}

	public function update() {
		var elt = editor.element;
		hide();
		if( table == null )
			return;
		if( y < 0 ) {
			y = 0;
			select = null;
		}
		if( y >= table.lines.length ) {
			y = table.lines.length - 1;
			select = null;
		}
		var max = table.sheet.props.isProps || table.columns == null ? 1 : table.columns.length;
		if( x >= max ) {
			x = max - 1;
			select = null;
		}
		var line = getLine();
		if( line == null )
			return;
		if( x < 0 ) {
			line.element.addClass("selected");
			if( select != null ) {
				var cy = y;
				while( select.y != cy ) {
					if( select.y > cy ) cy++ else cy--;
					table.lines[cy].element.addClass("selected");
				}
			}
		} else {
			var c = line.cells[x];
			if( c != null ){
				c.elementHtml.classList.add("cursorView");
				c.elementHtml.parentElement.classList.add("cursorLine");
			}
			if( select != null ) {
				var s = getSelection();
				for( y in s.y1...s.y2 + 1 ) {
					var l = table.lines[y];
					for( x in s.x1...s.x2+1)
						l.cells[x].elementHtml.classList.add("selected");
				}
			}
		}
		var e = line.element.get(0);
		if( e != null ) untyped e.scrollIntoViewIfNeeded();
	}

	public function getSelection() {
		if( table == null )
			return null;
		var x1 = if( x < 0 ) 0 else x;
		var x2 = if( x < 0 ) table.columns.length-1 else if( select != null ) select.x else x1;
		var y1 = y;
		var y2 = if( select != null ) select.y else y1;
		if( x2 < x1 ) {
			var tmp = x2;
			x2 = x1;
			x1 = tmp;
		}
		if( y2 < y1 ) {
			var tmp = y2;
			y2 = y1;
			y1 = tmp;
		}
		return { x1 : x1, x2 : x2, y1 : y1, y2 : y2 };
	}


	public function clickLine( line : Line, shiftKey = false ) {
		var sheet = line.table.sheet;
		if( shiftKey && this.table == line.table && x < 0 ) {
			select = { x : -1, y : line.index };
			update();
		} else {
			editor.pushCursorState();
			set(line.table, -1, line.index);
			line.table.showSeparator(line);
		}
	}

	public function clickCell( cell : Cell, shiftKey = false ) {
		var xIndex = cell.table.displayMode == Table ? cell.columnIndex : 0;
		if( shiftKey && table == cell.table ) {
			select = { x : xIndex, y : cell.line.index };
			update();
		} else {
			editor.pushCursorState();
			set(cell.table, xIndex, cell.line.index);
			cell.table.showSeparator(cell.line);
		}
	}

}
