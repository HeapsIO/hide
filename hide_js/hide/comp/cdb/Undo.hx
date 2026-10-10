package hide.comp.cdb;

/**
	What a change of the data modifies : the smaller, the cheaper its undo.
**/
enum UndoScope {
	/** anything : a copy of the whole data **/
	All;
	/** a root sheet : a copy of its lines (with their sub lists), separators and props **/
	Sheet( s : cdb.Sheet );
	/** a root sheet : the order of its lines, the lines inserted or removed, its separators, but not the content of its lines **/
	Lines( s : cdb.Sheet );
	/** a line of a root sheet (with its sub lists) **/
	Line( s : cdb.Sheet, obj : Dynamic );
}

private enum ChangeKind {
	KAll;
	KSheet;
	KLines;
	KLine;
}

private class Change {
	public var kind : ChangeKind;
	public var sheet : String;
	// open : KLine the line, KLines the lines before the change
	public var obj : Dynamic;
	// KLine : the position of the line, the same before and after the change
	public var index : Int;
	// KAll, KSheet, KLine : a JSON copy ; KLines : each line as its position in the other array, or its JSON
	public var before : Dynamic;
	public var after : Dynamic;
	public var sepBefore : String;
	public var sepAfter : String;
	public var open = true;
	public function new(kind, sheet) {
		this.kind = kind;
		this.sheet = sheet;
	}
}

private typedef Group = {
	var changes : Array<Change>;
	var state : Editor.UndoState;
	var sheetAfter : String;
	var separatorsAfter : Map<String,Bool>;
	var merge : String;
	var size : Float;
}

/**
	The undo of the changes of the data of an editor. A change of a line keeps the line before and after,
	a change of the order of lines keeps their positions, the other changes of a sheet keep a copy of the sheet ;
	only the changes of structure keep a copy of the whole data.
	The successive changes of the same cell are a single undo.
**/
class Undo {

	static inline var MAX = 300;
	static inline var MAX_ALL = 40;
	static inline var MAX_BYTES = 400 << 20;

	var editor : Editor;
	var group : Group;
	// the groups of the undo history of the editor, by id
	var groups : Map<Int, Group> = new Map();
	// the last copy of the whole data : a new copy with the same content shares its memory
	var lastCopy : String;

	public function new( editor ) {
		this.editor = editor;
	}

	public function clear() {
		groups = new Map();
		lastCopy = null;
	}

	public function begin( state : Editor.UndoState, ?merge : String ) {
		group = { changes : [], state : state, sheetAfter : null, separatorsAfter : null, merge : merge, size : 0 };
	}

	/**
		Starts keeping a change, unless an open change of the group already covers it.
	**/
	public function add( scope : UndoScope ) {
		if( group == null ) return;
		var kind, sheet : cdb.Sheet = null, obj : Dynamic = null;
		switch( scope ) {
		case null, All: kind = KAll;
		case Sheet(s): kind = KSheet; sheet = s;
		case Lines(s): kind = KLines; sheet = s;
		case Line(s, o): kind = KLine; sheet = s; obj = o;
		}
		// the editor of an object (not of the database), the lines of prefabs : the whole data
		if( kind != KAll && (editor.cdbTable == null || sheet == null || sheet.parent != null || sheet.props.dataFiles != null) )
			kind = KAll;
		var name = sheet == null ? null : sheet.name;
		for( c in group.changes )
			if( c.open && covers(c, kind, name, obj) )
				return;

		var c = new Change(kind, name);
		// a change of the positions of lines ends the changes of lines of its sheet (and the ones it covers) :
		// the positions of their lines are kept now
		if( kind != KLine )
			for( c2 in group.changes )
				if( c2.open && (covers(c, c2.kind, c2.sheet, c2.obj) || (c2.kind == KLine && c2.sheet == name)) )
					close(c2);
		switch( kind ) {
		case KAll:
			c.before = copyAll();
		case KSheet:
			c.before = copySheet(sheet);
		case KLines:
			c.obj = getLines(sheet).copy();
			c.sepBefore = haxe.Json.stringify(@:privateAccess sheet.sheet.separators);
		case KLine:
			c.obj = obj;
			c.before = haxe.Json.stringify(obj);
		}
		group.changes.push(c);
	}

	static function covers( c : Change, kind : ChangeKind, sheet : String, obj : Dynamic ) {
		return switch( c.kind ) {
		case KAll: true;
		case KSheet: kind != KAll && c.sheet == sheet;
		case KLines: kind == KLines && c.sheet == sheet;
		case KLine: kind == KLine && c.sheet == sheet && c.obj == obj;
		}
	}

	function getSheet( name : String ) : cdb.Sheet {
		return editor.base.getSheet(name);
	}

	// the data can change out of the groups (normalized indexes, formulas) : always copied
	function copyAll() : String {
		var copy : String = editor.api.copy();
		if( lastCopy != null && lastCopy == copy )
			return lastCopy;
		return lastCopy = copy;
	}

	static function getLines( s : cdb.Sheet ) : Array<Dynamic> {
		return @:privateAccess s.sheet.lines;
	}

	static function copySheet( s : cdb.Sheet ) : String {
		var d = @:privateAccess s.sheet;
		return haxe.Json.stringify({ lines : d.lines, separators : d.separators, props : d.props });
	}

	function close( c : Change ) {
		c.open = false;
		switch( c.kind ) {
		case KAll:
			c.after = copyAll();
		case KSheet:
			c.after = copySheet(getSheet(c.sheet));
		case KLines:
			var s = getSheet(c.sheet);
			var before : Array<Dynamic> = c.obj;
			var after = getLines(s);
			c.before = linesSpec(before, after);
			c.after = linesSpec(after, before);
			c.sepAfter = haxe.Json.stringify(@:privateAccess s.sheet.separators);
		case KLine:
			c.index = getLines(getSheet(c.sheet)).indexOf(c.obj);
			c.after = haxe.Json.stringify(c.obj);
		}
		c.obj = null;
	}

	/** the lines of an array, as their positions in another array (or their JSON when they are not in it) **/
	static function linesSpec( lines : Array<Dynamic>, other : Array<Dynamic> ) : Array<Dynamic> {
		var pos = new js.lib.Map<Dynamic, Int>();
		for( i in 0...other.length ) pos.set(other[i], i);
		return [for( o in lines ) {
			var i = pos.get(o);
			i == null ? ({ json : haxe.Json.stringify(o) } : Dynamic) : (i : Dynamic);
		}];
	}

	static function sameSpec( a : Array<Dynamic>, b : Array<Dynamic> ) {
		if( a.length != b.length ) return false;
		for( i in 0...a.length )
			if( !Std.isOfType(a[i], Int) || a[i] != i ) return false;
		return true;
	}

	function isEmpty( c : Change ) {
		return switch( c.kind ) {
		case KLines: sameSpec(c.before, c.after) && sameSpec(c.after, c.before) && c.sepBefore == c.sepAfter;
		case KLine: c.index < 0 || c.before == c.after;
		default: c.before == c.after;
		}
	}

	/**
		Ends the group of changes, returns false if nothing changed.
	**/
	public function end() : Bool {
		var g = group;
		group = null;
		if( g == null ) return false;
		for( c in g.changes )
			if( c.open ) close(c);
		g.changes = [for( c in g.changes ) if( !isEmpty(c) ) c];
		if( g.changes.length == 0 )
			return false;
		g.sheetAfter = editor.getCurrentSheet();
		g.separatorsAfter = editor.separatorsState.copy();
		for( c in g.changes )
			g.size += size(c);
		push(g);
		return true;
	}

	/**
		Ends the group of changes and restores the data as it was before them.
	**/
	public function cancel() {
		var g = group;
		group = null;
		if( g == null ) return;
		for( c in g.changes )
			if( c.open ) close(c);
		g.changes = [for( c in g.changes ) if( !isEmpty(c) ) c];
		if( g.changes.length > 0 )
			apply(g, true);
	}

	function push( g : Group ) {
		var undo = editor.undo;
		// the successive changes of a same cell are one change
		var last = groups.get(undo.currentID);
		if( g.merge != null && last != null && last.merge == g.merge && @:privateAccess undo.redoElts.length == 0
			&& g.changes.length == 1 && last.changes.length == 1 ) {
			var c = g.changes[0], prev = last.changes[0];
			if( c.kind == KLine && prev.kind == KLine && c.sheet == prev.sheet && c.index == prev.index ) {
				prev.after = c.after;
				last.size = size(prev);
				last.sheetAfter = g.sheetAfter;
				last.separatorsAfter = g.separatorsAfter;
				return;
			}
		}
		undo.change(Custom(function(isUndo) apply(g, isUndo)));
		groups.set(undo.currentID, g);
		prune();
	}

	// the history keeps MAX groups, MAX_ALL copies of the whole data, MAX_BYTES of copies
	function prune() {
		var elts : Array<{ id : Int }> = @:privateAccess editor.undo.undoElts;
		var redos : Array<{ id : Int }> = @:privateAccess editor.undo.redoElts;
		var count = 0, all = 0, bytes = 0.;
		var newerBefore : String = null;
		var i = elts.length - 1;
		while( i >= 0 ) {
			var g = groups.get(elts[i].id);
			if( g != null ) {
				count++;
				bytes += g.size;
				var before : String = null;
				for( c in g.changes )
					if( c.kind == KAll ) {
						all++;
						// the copy after a change is the one before the next : counted once
						if( newerBefore != null && js.Syntax.strictEq(c.after, newerBefore) ) bytes -= c.after.length * 2;
						if( before == null ) before = c.before;
					}
				newerBefore = before;
				if( count > MAX || all > MAX_ALL || (bytes > MAX_BYTES && i < elts.length - 1) ) {
					elts.splice(0, i + 1);
					break;
				}
			}
			i--;
		}
		var live = new Map();
		for( e in elts ) live.set(e.id, true);
		for( e in redos ) live.set(e.id, true);
		for( id in [for( id in groups.keys() ) id] )
			if( !live.exists(id) ) groups.remove(id);
	}

	static function size( c : Change ) : Float {
		inline function str( s : String ) return s == null ? 0 : s.length * 2;
		return switch( c.kind ) {
		case KLines:
			var n = str(c.sepBefore) + str(c.sepAfter);
			for( spec in [(c.before : Array<Dynamic>), (c.after : Array<Dynamic>)] )
				for( e in spec )
					n += Std.isOfType(e, Int) ? 8 : str(e.json);
			n;
		default: str(c.before) + str(c.after);
		}
	}

	function apply( g : Group, isUndo : Bool ) {
		var reload = false;
		var changes = g.changes.copy();
		if( isUndo ) changes.reverse();
		for( c in changes ) {
			var v : Dynamic = isUndo ? c.before : c.after;
			switch( c.kind ) {
			case KAll:
				editor.api.load(v);
				lastCopy = v;
				reload = true;
			case KSheet:
				var d = @:privateAccess getSheet(c.sheet).sheet;
				var o : Dynamic = haxe.Json.parse(v);
				d.lines = o.lines;
				d.separators = o.separators;
				d.props = o.props;
			case KLines:
				var s = getSheet(c.sheet);
				var lines = getLines(s);
				var cur = lines.copy();
				lines.splice(0, lines.length);
				for( e in (v : Array<Dynamic>) )
					lines.push(Std.isOfType(e, Int) ? cur[e] : haxe.Json.parse(e.json));
				@:privateAccess s.sheet.separators = haxe.Json.parse(isUndo ? c.sepBefore : c.sepAfter);
			case KLine:
				getLines(getSheet(c.sheet))[c.index] = haxe.Json.parse(v);
			}
		}
		@:privateAccess editor.onUndoApplied(isUndo ? g.state.sheet : g.sheetAfter, isUndo ? g.state.separatorsState : g.separatorsAfter, g.state, reload);
	}
}
