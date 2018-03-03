package hide.comp.cdb;

class Cursor {

	var editor : Editor;
	public var sheet : cdb.Sheet;
	public var x : Int;
	public var y : Int;
	public var select : Null<{ x : Int, y : Int }>;
	public var onchange : Void -> Void;

	public function new(editor) {
		this.editor = editor;
	}

	public function set( ?s, ?x=0, ?y=0, ?sel, update = true ) {
		this.sheet = s;
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

	public function getLine() {
		if( sheet == null ) return null;
		return editor.getLine(sheet, y);
	}

	public function move( dx : Int, dy : Int, shift : Bool, ctrl : Bool ) {
		if( sheet == null )
			return;
		if( x == -1 && ctrl ) {
			if( dy != 0 )
				editor.moveLine(getLine(), dy);
			update();
			return;
		}
		if( dx < 0 && x >= 0 )
			x--;
		if( dy < 0 && y > 0 )
			y--;
		if( dx > 0 && x < sheet.columns.length - 1 )
			x++;
		if( dy > 0 && y < sheet.lines.length - 1 )
			y++;
		select = null;
		update();
	}

	public function update() {
		var root = editor.root;
		root.find(".selected").removeClass("selected");
		root.find(".cursor").removeClass("cursor");
		root.find(".cursorLine").removeClass("cursorLine");
		if( sheet == null )
			return;
		if( y < 0 ) {
			y = 0;
			select = null;
		}
		if( y >= sheet.lines.length ) {
			y = sheet.lines.length - 1;
			select = null;
		}
		var max = sheet.props.isProps ? 1 : sheet.columns.length;
		if( x >= max ) {
			x = max - 1;
			select = null;
		}
		var line = getLine();
		if( x < 0 ) {
			line.root.addClass("selected");
			if( select != null ) {
				var cy = y;
				while( select.y != cy ) {
					if( select.y > cy ) cy++ else cy--;
					editor.getLine(sheet, cy).root.addClass("selected");
				}
			}
		} else {
			line.cells[x].root.addClass("cursor").closest("tr").addClass("cursorLine");
			if( select != null ) {
				var s = getSelection();
				for( y in s.y1...s.y2 + 1 ) {
					var l = editor.getLine(sheet, y);
					for( x in s.x1...s.x2+1)
						l.cells[x].root.addClass("selected");
				}
			}
		}
		var e = line.root[0];
		if( e != null ) untyped e.scrollIntoViewIfNeeded();
	}

	function getSelection() {
		if( sheet == null )
			return null;
		var x1 = if( x < 0 ) 0 else x;
		var x2 = if( x < 0 ) sheet.columns.length-1 else if( select != null ) select.x else x1;
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
		if( shiftKey && this.sheet == sheet && x < 0 ) {
			select = { x : -1, y : line.index };
			update();
		} else
			set(sheet, -1, line.index);
	}

}
