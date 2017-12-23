package hide.comp;
import js.jquery.Helper.*;

private typedef Cursor = {
	s : cdb.Sheet,
	x : Int,
	y : Int,
	?select : { x : Int, y : Int },
	?onchange : Void -> Void,
}

@:allow(hide.comp.CdbCell)
class CdbTable extends Component {

	var base : cdb.Database;
	var sheet : cdb.Sheet;
	var cursor : Cursor;
	var existsCache : Map<String,{ t : Float, r : Bool }> = new Map();

	public function new(root, sheet) {
		super(root);
		this.sheet = sheet;
		base = sheet.base;
		cursor = {
			s : null,
			x : 0,
			y : 0,
		};
		refresh();
	}

	function refresh() {

		root.html('');
		root.addClass('cdb');

		if( sheet.columns.length == 0 ) {
			J("<a>Add a column</a>").appendTo(root).click(function(_) {
				newColumn(sheet);
			});
			return;
		}

		var content = J("<table>");
		content.addClass("cdb-sheet");
		fillTable(content, sheet);
		content.appendTo(root);
	}

	function fillTable( content : Element, sheet : cdb.Sheet ) {

		content.attr("sheet", sheet.getPath());

		var cols = J("<tr>").addClass("head");
		J("<th>").addClass("start").appendTo(cols);
		var lines = [for( i in 0...sheet.lines.length ) {
			var l = J("<tr>");
			l.data("index", i);
			var head = J("<td>").addClass("start").text("" + i);
			l.mousedown(function(e) {
				if( e.which == 3 ) {
					head.click();
					//haxe.Timer.delay(popupLine.bind(sheet,i),1);
					e.preventDefault();
					return;
				}
			}).click(function(e) {
				if( e.shiftKey && cursor.s == sheet && cursor.x < 0 ) {
					cursor.select = { x : -1, y : i };
					updateCursor();
				} else
					setCursor(sheet, -1, i);
			});
			head.appendTo(l);
			l;
		}];


		var colCount = sheet.columns.length;
		var todo = [];
		var inTodo = false;
		for( cindex in 0...sheet.columns.length ) {
			var c = sheet.columns[cindex];
			var col = J("<th>");
			col.text(c.name);
			col.addClass( "t_"+c.type.getName().substr(1).toLowerCase() );
			if( sheet.props.displayColumn == c.name )
				col.addClass("display");
			col.mousedown(function(e) {
				if( e.which == 3 ) {
					//haxe.Timer.delay(popupColumn.bind(sheet,c),1);
					e.preventDefault();
					return;
				}
			});
			col.dblclick(function(_) {
				newColumn(sheet, c);
			});
			cols.append(col);

			for( index in 0...sheet.lines.length ) {
				var v = J("<td>").addClass("c");
				var l = lines[index];
				v.appendTo(l);
				new CdbCell(v, this, c, sheet.lines[index]);
			}
		}

		if( sheet.lines.length == 0 ) {
			var l = J('<tr><td colspan="${sheet.columns.length + 1}"><a href="javascript:_.insertLine()">Insert Line</a></td></tr>');
			l.find("a").click(function(_) setCursor(sheet));
			lines.push(l);
		}

		content.empty();
		content.append(cols);

		var snext = 0;
		for( i in 0...lines.length ) {
			while( sheet.separators[snext] == i ) {
				var sep = J("<tr>").addClass("separator").append('<td colspan="${colCount+1}">').appendTo(content);
				var content = sep.find("td");
				var title = if( sheet.props.separatorTitles != null ) sheet.props.separatorTitles[snext] else null;
				if( title != null ) content.text(title);
				var pos = snext;
				sep.dblclick(function(e) {
					content.empty();
					J("<input>").appendTo(content).focus().val(title == null ? "" : title).blur(function(_) {
						/*title = JTHIS.val();
						JTHIS.remove();
						content.text(title);
						var titles = sheet.props.separatorTitles;
						if( titles == null ) titles = [];
						while( titles.length < pos )
							titles.push(null);
						titles[pos] = title == "" ? null : title;
						while( titles[titles.length - 1] == null && titles.length > 0 )
							titles.pop();
						if( titles.length == 0 ) titles = null;
						sheet.props.separatorTitles = titles;
						save();*/
					}).keypress(function(e) {
						e.stopPropagation();
					}).keydown(function(e) {
						if( e.keyCode == 13 ) { JTHIS.blur(); e.preventDefault(); } else if( e.keyCode == 27 ) content.text(title);
						e.stopPropagation();
					});
				});
				snext++;
			}
			content.append(lines[i]);
		}

		inTodo = true;
		for( t in todo ) t();
		inTodo = false;
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

	function setCursor( ?s, ?x=0, ?y=0, ?sel, update = true ) {
		cursor.s = s;
		cursor.x = x;
		cursor.y = y;
		cursor.select = sel;
		var ch = cursor.onchange;
		if( ch != null ) {
			cursor.onchange = null;
			ch();
		}
		if( update ) updateCursor();
	}

	function getLine( sheet : cdb.Sheet, index : Int ) {
		return J("table[sheet='"+sheet.getPath()+"'] > tbody > tr").not(".head,.separator,.list").eq(index);
	}

	function updateCursor() {
		J(".selected").removeClass("selected");
		J(".cursor").removeClass("cursor");
		J(".cursorLine").removeClass("cursorLine");
		if( cursor.s == null )
			return;
		if( cursor.y < 0 ) {
			cursor.y = 0;
			cursor.select = null;
		}
		if( cursor.y >= cursor.s.lines.length ) {
			cursor.y = cursor.s.lines.length - 1;
			cursor.select = null;
		}
		var max = cursor.s.props.isProps ? 1 : cursor.s.columns.length;
		if( cursor.x >= max ) {
			cursor.x = max - 1;
			cursor.select = null;
		}
		var l = getLine(cursor.s, cursor.y);
		if( cursor.x < 0 ) {
			l.addClass("selected");
			if( cursor.select != null ) {
				var y = cursor.y;
				while( cursor.select.y != y ) {
					if( cursor.select.y > y ) y++ else y--;
					getLine(cursor.s, y).addClass("selected");
				}
			}
		} else {
			l.find("td.c").eq(cursor.x).addClass("cursor").closest("tr").addClass("cursorLine");
			if( cursor.select != null ) {
				var s = getSelection();
				for( y in s.y1...s.y2 + 1 )
					getLine(cursor.s, y).find("td.c").slice(s.x1, s.x2+1).addClass("selected");
			}
		}
		var e = l[0];
		if( e != null ) untyped e.scrollIntoViewIfNeeded();
	}

	function getSelection() {
		if( cursor.s == null )
			return null;
		var x1 = if( cursor.x < 0 ) 0 else cursor.x;
		var x2 = if( cursor.x < 0 ) cursor.s.columns.length-1 else if( cursor.select != null ) cursor.select.x else x1;
		var y1 = cursor.y;
		var y2 = if( cursor.select != null ) cursor.select.y else y1;
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

	function updateClasses(v:Element, c:cdb.Data.Column, val:Dynamic) {
		switch( c.type ) {
		case TBool :
			v.removeClass("true, false").addClass( val==true ? "true" : "false" );
		case TInt, TFloat :
			v.removeClass("zero");
			if( val==0 )
				v.addClass("zero");
		default:
		}
	}

	function newColumn( sheet : cdb.Sheet, ?after ) {
	}

	public dynamic function save() {
	}

}