package hide.comp.cdb;
import js.jquery.Helper.*;

enum DisplayMode {
	Table;
	Properties;
	AllProperties;
}

private typedef SepTree = { sep : cdb.Data.Separator, index : Int, subs : Array<SepTree>, parent : SepTree };

class Table extends Component {

	public var editor : Editor;
	public var parent : Table;
	public var sheet : cdb.Sheet;
	public var lines : Array<Line>;
	public var displayMode(default,null) : DisplayMode;

	public var columns : Array<cdb.Data.Column>;
	public var view : cdb.DiffFile.SheetView;

	public var nestedIndex : Int = 0;

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
		switch( displayMode ) {
		case Table:
			refreshTable();
		case Properties, AllProperties:
			refreshProperties();
		}
	}

	function setupTableElement() {
		cloneTableHead();
		@:privateAccess {
			var elt = editor.element.parent();
			var scrollbarWidth = elt.parent().width() - elt.width();
			element.width(@:privateAccess editor.cdbTable.contentWidth - scrollbarWidth); // prevent to reflow all cdb-view
		}
	}

	function cloneTableHead() {
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

			var txt = elt[0].innerHTML;
			elt.empty();
			J("<span>" + txt + "</span>").appendTo(elt);

			clone.append(elt);
		}

		J('.cdb').prepend(clone);
	}

	function updateDrag() {
		var scrollHeight = js.Browser.document.body.scrollHeight;
		if (ide.mouseY > scrollHeight*0.8) {
			var scroll = element.get()[0].parentElement.parentElement;
			scroll.scrollTop += 15 + Std.int((ide.mouseY - scrollHeight*0.8)/(scrollHeight - scrollHeight*0.8)*30);
		}
		if (ide.mouseY < scrollHeight*0.2) {
			var scroll = element.get()[0].parentElement.parentElement;
			scroll.scrollTop -= 15 + Std.int((scrollHeight*0.2 - ide.mouseY)/(scrollHeight*0.2)*30);
		}
	}

	function refreshTable() {
		var cols = J("<thead>").addClass("head");
		var start = J("<th>").addClass("start").appendTo(cols);
		if (!Std.isOfType(this, SubTable) && sheet.props.dataFiles == null) {
			start.mousedown(function(e) {
				if( e.which == 3 ) {
					editor.popupSheet(false, sheet);
					e.preventDefault();
					return;
				}
			});
		}
		lines = [for( index in 0...sheet.lines.length ) {
			var l = J("<tr>");
			var head = J("<td>").addClass("start").text("" + index);
			head.appendTo(l);
			var line = new Line(this, columns, index, l);
			head.mousedown(function(e) {
				if( e.which == 3 ) {
					editor.popupLine(line);
					e.preventDefault();
					return;
				}
			});
			l.click(function(e) {
				if( e.which == 3 ) {
					e.preventDefault();
					return;
				}
				editor.cursor.clickLine(line, e.shiftKey);
			});
			var headEl = head.get()[0];
			headEl.draggable = true;
			headEl.ondragstart = function(e:js.html.DragEvent) {
				if (editor.cursor.getCell() != null && editor.cursor.getCell().inEdit) {
					e.preventDefault();
					return;
				}
				ide.registerUpdate(updateDrag);
				e.dataTransfer.effectAllowed = "move";
			}
			headEl.ondrag = function(e:js.html.DragEvent) {
				if (hxd.Key.isDown(hxd.Key.ESCAPE)) {
					e.dataTransfer.dropEffect = "none";
					e.preventDefault();
				}
			}
			headEl.ondragend = function(e:js.html.DragEvent) {
				ide.unregisterUpdate(updateDrag);
				if (e.dataTransfer.dropEffect == "none") return false;
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
				if (pickedLine != null) {
					editor.moveLine(line, pickedLine.index - line.index, true);
					return true;
				}

				return false;
			}
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

			if( c.documentation != null ) {
				col.attr("title", c.documentation);
				new Element('<i style="margin-left: 5px" class="ico ico-book"/>').appendTo(col);
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
				new Element('<i style="margin-right: 5px" class="ico $ico"/>').prependTo(col);
			}
			if( sheet.props.displayColumn == c.name )
				col.addClass("display");
			col.mousedown(function(e) {
				if( e.which == 3 ) {
					editor.popupColumn(this, c);
					e.preventDefault();
					return;
				}
			});
			col.dblclick(function(_) {
				if( editor.view == null ) editor.editColumn(getRealSheet(), c);
			});
			cols.append(col);
		}

		element.append(cols);

		var tbody = J("<tbody>");

		var groupClass : String = null;
		var sepIndex = -1, sepNext = sheet.separators[++sepIndex], hidden = false;
		for( i in 0...lines.length+1 ) {
			while( sepNext != null && sepNext.index == i ) {
				var sep = makeSeparator(sepIndex, colCount);
				sep.element.appendTo(tbody);
				if( sep.hidden != null ) hidden = sep.hidden;
				if( sepNext.title != null )
					groupClass = "group-"+StringTools.replace(sepNext.title.toLowerCase(), " ", "-");
				sepNext = sheet.separators[++sepIndex];
			}
			if( i == lines.length ) break;
			var line = lines[i];
			if( hidden )
				line.hide();
			else
				line.create();
			if( groupClass != null )
				line.element.addClass(groupClass);
			tbody.append(line.element);
		}
		element.append(tbody);

		if( colCount == 0 ) {
			var l = J('<tr><td><input type="button" value="Add a column"/></td></tr>').find("input").click(function(_) {
				editor.newColumn(sheet);
			});
			element.append(l);
		} else if( sheet.lines.length == 0 && canInsert() ) {
			var l = J('<tr><td colspan="${columns.length + 1}"><input type="button" value="Insert Line"/></td></tr>');
			l.find("input").click(function(_) {
				editor.insertLine(this);
				editor.cursor.set(this);
			});
			element.append(l);
		}

		if( sheet.parent == null ) {
			cols.ready(setupTableElement);
			cols.on("resize", setupTableElement);
		}
	}

	function makeSeparatorTree( ?root ) {
		var curLevel = 0;
		var cur : SepTree = { sep : null, index : -1, subs : [], parent : null };
		var stack = [];
		var select = cur;
		for( index => s in sheet.separators ) {
			var lv = s.level;
			if( lv == null ) lv = 0;
			if( lv < curLevel ) {
				for( i in lv...curLevel )
					cur = stack.pop();
			}
			var next = { sep : s, index : index, subs : [], parent : cur };
			if( s == root ) select = next;
			if( lv > curLevel ) {
				stack.push(cur);
				cur = cur.subs[cur.subs.length - 1];
			}
			cur.subs.push(next);
			curLevel = lv;
		}
		return select;
	}

	function isSepHidden(index) {
		return getDisplayState("sep/"+sheet.separators[index].title) == false;
	}

	public function expandLine(line: Int) {
		var sepIndex = -1;
		for( i in 0...sheet.separators.length ) {
			if( sheet.separators[i].index > line )
				break;
			sepIndex = i;
		}
		if( sepIndex < 0 )
			return;
		var subs = element.find("tr.separator");
		var t = makeSeparatorTree(sheet.separators[sepIndex]);
		while( t.parent != null ) {
			if( isSepHidden(t.index) )
				new Element(subs[t.index]).find("a.toggle").click();
			t = t.parent;
		}
	}

	function makeSeparator( sindex : Int, colCount : Int ) : { element : Element, hidden : Null<Bool> } {
		var sep = J("<tr>").addClass("separator").attr("sindex", sindex).append('<td colspan="${colCount+1}"><a href="#" class="toggle"></a><span></span></td>');
		var content = sep.find("span");
		var toggle = sep.find("a");
		var sepInfo = sheet.separators[sindex];
		var title = sepInfo.title;
		if( title != null )
			sep.addClass(StringTools.replace('separator-$title'.toLowerCase(), " ", "-"));

		var curLevel = sepInfo.level;
		if( curLevel == null ) curLevel = 0;

		function getLines( ?filter ) {
			var snext = 0, sref = -1, scur = -1;
			var out = [];
			for( i in 0...lines.length ) {
				while( true ) {
					var sep = sheet.separators[snext];
					if( sep == null || sep.index != i ) break;
					if( sep.title != null ) {
						scur = snext;
						if( sep.level == null || sep.level <= curLevel )
							sref = snext;
					}
					snext++;
				}
				if( sref == sindex && (filter == null || scur == filter) )
					out.push(lines[i]);
			}
			return out;
		}

		var hidden : Bool;
		var syncLevel : Int = -1;
		function sync() {
			hidden = title == null ? null : isSepHidden(sindex);
			toggle.css({ display : title == null ? "none" : "" });
			toggle.text(hidden ? "🡆" : "🡇");
			content.text(title == null ? "" : title+(hidden ? " ("+getLines().length+")" : ""));
			sep.toggleClass("sep-hidden", hidden == true);
			if( syncLevel != sepInfo.level ) {
				sep.removeClass("seplevel-"+(syncLevel == null ? 0 : syncLevel));
				syncLevel = sepInfo.level;
				sep.addClass('seplevel-'+(syncLevel == null ? 0 : syncLevel));
			}
			sep.attr("level", syncLevel == null ? 0 : sepInfo.level);
		}

		sep.contextmenu(function(e) {

			var parents = [];
			var minLevel = -1;
			for( i in 0...sindex ) {
				var sep = sheet.separators[sindex - 1 - i];
				var level = sep.level == null ? 0 : sep.level;
				if( minLevel < 0 || level < minLevel ) {
					parents.unshift(sep);
					minLevel = level;
				}
			}
			parents.unshift(null);

			var hasChildren = makeSeparatorTree(sepInfo).subs.length > 0;

			function expand(show) {
				var subs = element.find("tr.separator");
				function showRec(t:SepTree) {
					if( !show ) {
						for( s in t.subs )
							showRec(s);
					}
					if( isSepHidden(t.index) == show )
						new Element(subs[t.index]).find("a.toggle").click();
					if( show ) {
						for( s in t.subs )
							showRec(s);
					}
				}
				showRec(makeSeparatorTree(sepInfo));
			}

			var opts : Array<hide.comp.ContextMenu.ContextMenuItem> = [

				{ label : "Expand", click : function() expand(true) },
				{ label : "Collapse", click : function() expand(false) },
				{
					label : "Parent",
					enabled : parents.length > 0,
					menu : [for( s in parents ) {
						var level = s == null ? 0 : s.level == null ? 1 : s.level + 1;
						{
							label : s == null ? "(None)" : [for( i in 0...level ) ""].join("  ")+s.title,
							checked : s == null ? sepInfo.level == null : sepInfo.level == level,
							click : function() {
								editor.beginChanges();
								var delta = level - (sepInfo.level == null ? 0 : sepInfo.level);
								function deltaRec( t : SepTree ) {
									var level = t.sep.level;
									if( level == null ) level = 0;
									level += delta;
									t.sep.level = level == 0 ? js.Lib.undefined : level;
									for( s in t.subs )
										deltaRec(s);
								}
								deltaRec(makeSeparatorTree(sepInfo));
								editor.endChanges();
								refresh();
							},
						}
					}]
				},
				{ label : "", isSeparator : true },
				{ label : "Expand All", click : function() {
					element.find("tr.separator.sep-hidden a.toggle").click();
				}},
				{ label : "Collapse All", click : function() {
					element.find("tr.separator").not(".sep-hidden").find("a.toggle").click();

				}},
				{ label : "Collapse Others", click : function() {
					element.find("tr.separator").not(".sep-hidden").not(sep).find("a.toggle").click();
					if (sep.hasClass("sep-hidden"))
						sep.find("a.toggle").click();
				}},
				{ label : "", isSeparator : true },
				{ label : "Remove", enabled : !sheet.props.hide, click : function() {
					editor.beginChanges();
					sheet.separators.splice(sindex, 1);
					editor.endChanges();
					editor.refresh();
				}}
			];
			if( sepInfo.path != null )
				opts.unshift({
					label : "Open",
					click : function() {
						ide.openFile(sepInfo.path);
					},
				});
			new hide.comp.ContextMenu(opts);
		});

		sep.dblclick(function(e) {
			if( !canInsert() ) return;
			content.empty();
			J("<input>").appendTo(content).focus().val(title == null ? "" : title).blur(function(_) {
				title = JTHIS.val();
				JTHIS.remove();
				if( title == "" ) title = null;
				editor.beginChanges();
				var sep = sheet.separators[sindex];
				var prevTitle = sep.title;
				sep.title = title == null ? js.Lib.undefined : title;
				if( prevTitle != null ) {
					if( title == null ) {
						if( sep.level == null ) sep.level = 0;
						sep.level++;
					}
				} else if( title != null && sep.level > 0 ) {
					sep.level--;
					if( sep.level == 0 ) sep.level = js.Lib.undefined;
				}
				editor.endChanges();
				sync();
				var l = getLines();
				if( l.length > 0 ) {
					if( l[0].cells.length > 0 )
						l[0].cells[0].focus();
				}
			}).keypress(function(e) {
				e.stopPropagation();
			}).keydown(function(e) {
				if( e.keyCode == 13 ) { JTHIS.blur(); e.preventDefault(); } else if( e.keyCode == 27 ) content.text(title);
				e.stopPropagation();
			});
		});

		sync();
		var level = curLevel - 1;
		while( level >= 0 ) {
			for( i in 0...sindex ) {
				var s = sheet.separators[sindex - 1 - i];
				if( s.title != null && (s.level == null || s.level == level) ) {
					if( isSepHidden(sindex - 1 - i) ) {
						sep[0].style.display = "none";
						hidden = true;
					}
					break;
				}
			}
			level--;
		}
		toggle.dblclick(function(e) e.stopPropagation());
		toggle.click(function(e) {
			hidden = !hidden;
			saveDisplayState("sep/"+title, !hidden);
			sync();

			for( l in getLines( hidden ? null : sindex ) ) {
				l.hide();
				if( !hidden ) {
					l.create();
				}
			}

			var subs = element.find("tr.separator");
			function toggleRec( t : SepTree ) {
				var sid = sheet.separators.indexOf(t.sep);
				subs[sid].style.display = hidden ? "none" : "";
				if( !hidden ) {
					if( isSepHidden(sid) ) return;
					for( l in getLines(sid) )
						l.create();
				}
				for( s in t.subs )
					toggleRec(s);
			}
			for( s in makeSeparatorTree(sepInfo).subs )
				toggleRec(s);

			editor.updateFilter();
		});
		return { hidden : hidden, element : sep };
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

			if( c.documentation != null ) {
				th.attr("title", c.documentation);
				new Element('<i style="margin-left: 5px" class="ico ico-book"/>').appendTo(th);
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
				new Element('<i style="margin-right: 5px" class="ico $ico"/>').prependTo(th);
			}

			var line = new Line(this, [c], lines.length, l);
			var cell = new Cell(td[0], line, c);
			lines.push(line);

			th.mousedown(function(e) {
				if( e.which == 3 ) {
					editor.popupColumn(this, c, cell);
					editor.cursor.clickCell(cell, false);
					e.preventDefault();
					return;
				}
			});
		}

		if( isLarge )
			element.parent().addClass("cdb-large");

		// add/edit properties
		var end = new Element("<tr>").appendTo(element);
		end = new Element("<td>").attr("colspan", "2").appendTo(end);
		var sel = new Element("<select class='insertField'>").appendTo(end);
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
			var v = sel.val();
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
		editor.cursor.set(sub);
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

}