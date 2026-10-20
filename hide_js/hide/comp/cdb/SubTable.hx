package hide.comp.cdb;

class SubTable extends Table {

	var insertedTR : Element;
	var slider : Element;
	public var cell : Cell;
	// null for simple variants and the empty-poly picker, so getRealSheet() stays stable across edits
	public var polyVal(default,null) : { col : cdb.Data.Column, obj : Dynamic };

	public function new(editor:Editor, cell:Cell) {
		this.editor = editor;
		this.cell = cell;
		parent = cell.table;

		var pe = cell.getPolyEdit();
		if( pe != null && pe.col.type.match(TList | TProperties | TPolymorph) )
			polyVal = pe;

		var sheet = makeSubSheet();
		var line = cell.line;
		if( line.subTable != null ) throw "assert";
		line.subTable = this;

		var etype = polyVal != null ? polyVal.col.type : cell.column.type;
		var mode : Table.DisplayMode = switch( etype ) {
			case TProperties, TPolymorph: Properties;
			default: Table;
		};

		insertedTR = new Element("<tr>").addClass((etype == TProperties || etype == TPolymorph) ? "props" : "list");
		var group;
		if( editor.displayMode == AllProperties && cell.table.parent == null ) {
			group = new Element("<td>").attr("colspan","2").appendTo(insertedTR);
		} else if( mode == Properties ) {
			if (parent.displayMode == Properties) {
				new Element("<td>")
					.appendTo(insertedTR)
					.toggleClass("sublist-pad-" + parent.nestedIndex);
			}

			if( parent.displayMode == Properties ) {
				var count = cell.columnIndex + 1;
				group = new Element("<td>").attr("colspan",""+(count+1)).appendTo(insertedTR);
				var remain = cell.table.columns.length - count;
				if( remain > 0 )
					new Element("<td>").attr("colspan", "" + remain).appendTo(insertedTR);
			} else {
				group = new Element("<td>").attr("colspan", "" + (cell.table.columns.length + 1)).addClass("under-cell").appendTo(insertedTR);
			}
		} else {
			new Element("<td>")
				.appendTo(insertedTR)
				.toggleClass("sublist-pad-" + parent.nestedIndex);
			group = new Element("<td>").attr("colspan",""+cell.table.columns.length).addClass("under-cell").appendTo(insertedTR);
		}
		slider = new Element("<div>").appendTo(group);
		slider.hide();
		var root = new Element("<table>");
		root.appendTo(slider);
		root.addClass("cdb-sub-sheet");

		insertedTR.data("parent-cell", cell);
		insertedTR.data("parent-tr", cell.line.element);

		// the line stays in the DOM while its sub table is open
		if( !line.row.attached )
			parent.render();
		insertedTR.insertAfter(cell.line.element);
		var lineElt = cell.line.element.get(0);
		lineElt.style.height = lineElt.getBoundingClientRect().height + "px";
		cell.elementHtml.textContent = "...";
		cell.elementHtml.classList.add("parent-sub-table");

		super(editor, sheet, root, mode);

		this.nestedIndex = parent.nestedIndex + 1;
	}

	function getTarget() : { parent : cdb.Sheet, col : cdb.Data.Column, obj : Dynamic } {
		if( polyVal != null )
			return { parent : cell.table.sheet.getSub(cell.column), col : polyVal.col, obj : polyVal.obj };
		return { parent : cell.table.sheet, col : cell.column, obj : cell.line.obj };
	}

	override function getRealSheet() {
		var t = getTarget();
		return t.parent.getSub(t.col);
	}

	override function refresh() {
		super.refresh();
		alignUnderCell();
		checkIntegrity();
	}

	function checkIntegrity() {
		var t = getTarget();
		var v = Reflect.field(t.obj, t.col.name);
		switch(t.col.type) {
			case TList:
				if (v != sheet.lines) {
					hide.Ide.inst.error("Editor integrity compromised, please refresh the editor and contact someone in the tool team");
				}
			case TProperties, TPolymorph:
				if (v != sheet.lines[0]) {
					hide.Ide.inst.error("Editor integrity compromised, please refresh the editor and contact someone in the tool team");
				}
			default:
		}
		var parSub = Std.downcast(parent, SubTable);
		if (parSub != null) {
			parSub.checkIntegrity();
		}
	}

	function makeSubSheet() {
		var t = getTarget();
		var c = t.col;
		var index = cell.line.index;
		var key = cell.table.sheet.getPath() + "@" + cell.column.name + ":" + index;
		var psheet = t.parent.getSub(c);
		var value : Dynamic = Reflect.field(t.obj, c.name);
		var lines = switch( c.type ) {
		case TList:
			if( value == null ) {
				value = [];
				Reflect.setField(t.obj, c.name, value);
				// do not save for now
			}
			value;
		case TProperties, TPolymorph:
			if( value == null ) {
				value = {};
				Reflect.setField(t.obj, c.name, value);
				// do not save for now
			}
			var lines = [for( f in psheet.columns ) value];
			if( lines.length == 0 ) lines.push(value);
			lines;
		default:
			throw "assert";
		}
		return new cdb.Sheet(editor.base,{
			columns : psheet.columns, // SHARE
			props : psheet.props, // SHARE
			name : psheet.name, // same
			lines : lines, // ref
			separators : [], // none
		},key, { sheet : t.parent, column : t.parent.columns.indexOf(c), line : index });
	}

	public function show( ?immediate ) {
		var duration = Editor.animDuration(100);
		if( immediate || duration == 0 ) {
			slider.show();
			revealInView();
		} else
			slider.slideDown(duration, revealInView);
		alignUnderCell();
	}

	function revealInView() {
		if( slider == null ) return;
		var scroll = editor.element.get(0);
		var view = scroll.getBoundingClientRect();
		var bottom = insertedTR.get(0).getBoundingClientRect().bottom;
		var lineTop = cell.line.element.get(0).getBoundingClientRect().top - (view.top + 30);
		var delta = Math.min(bottom + 4 - view.bottom, lineTop);
		if( delta > 0 )
			scroll.scrollTop += Math.ceil(delta);
	}

	function alignUnderCell() {
		var sub = this;
		while( sub != null ) {
			sub.alignSelf();
			sub = Std.downcast(sub.parent, SubTable);
		}
	}

	function alignSelf() {
		var group = slider?.parent();
		if( group == null || !group.hasClass("under-cell") ) return;
		var content = displayMode == Properties ? slider : element;
		content.css("margin-left", "0px");
		var groupRect = group.get(0).getBoundingClientRect();
		var x = cell.elementHtml.getBoundingClientRect().left - groupRect.left;
		content.css("margin-left", Math.round(Math.max(0, Math.min(x, groupRect.width - content.outerWidth()))) + "px");
	}

	override public function close() {
		if( cell.line.subTable == this ) cell.line.subTable = null;
		if( slider != null ) {
			var duration = Editor.animDuration(100);
			if( duration > 0 ) {
				slider.slideUp(duration, function() { slider = null; close(); });
				return;
			}
			slider = null;
		}
		cell.elementHtml.classList.remove("parent-sub-table");
		super.close();
	}

	public function immediateClose() {
		if( cell.line.subTable == this ) cell.line.subTable = null;
		cell.elementHtml.classList.remove("parent-sub-table");
		super.close();
	}

	override function dispose() {
		super.dispose();
		insertedTR.remove();
		if( cell.line.subTable == null )
			cell.line.element.get(0).style.height = "";
		cell.refresh();
		var parentSub = Std.downcast(parent, SubTable);
		if( parentSub != null )
			parentSub.alignUnderCell();
	}

	override function refreshLinesStatus() {
	}
}