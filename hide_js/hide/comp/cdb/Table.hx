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

	// the rows of the main table are virtual : only the ones in the view are in the DOM
	var virtual = false;
	var tbody : Element;
	var rows : Array<Row> = [];
	var attached : Array<Row> = [];
	var materialized : Array<Line> = [];
	var spacers : Array<js.html.Element> = [];
	var rowsLock = 0;
	var rowsDirty = false;
	var renderPending = false;
	var lineHeight = 24.;
	var sepHeight = 26.;
	var bodyObserver : hide.comp.ResizeObserver;
	// the sheet path, kept : the sheet is no longer valid once the database is reloaded (undo)
	var heightsKey : String;

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
		renderPending = false;
		#if js
		if( resizeObserver != null ) resizeObserver.disconnect();
		if( bodyObserver != null ) bodyObserver.disconnect();
		#end
	}

	public function refresh() {
		// emptied, the table loses the scroll position : it is restored once the rows are back
		var scroll = virtual ? editor.element.get(0) : null;
		var scrollTop = scroll?.scrollTop;
		saveHeights();
		element.empty();
		rows = [];
		attached = [];
		spacers = [];
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
		if( scroll != null && virtual )
			restoreScroll(scrollTop);
	}

	/**
		Keeps the measured heights of the rows (by index) for the next table of the same sheet, so that it is laid out like this one.
	**/
	function saveHeights() {
		if( !virtual || lines == null || separators == null ) return;
		editor.rowHeights.set(heightsKey, {
			lines : [for( l in lines ) l.row.height],
			seps : [for( s in separators ) s.row.height],
			line : lineHeight,
			sep : sepHeight,
		});
	}

	function loadHeights() {
		heightsKey = sheet.getPath();
		var h = editor.rowHeights.get(heightsKey);
		if( h == null ) return;
		lineHeight = h.line;
		sepHeight = h.sep;
		for( i => l in lines )
			if( i < h.lines.length ) l.row.height = h.lines[i];
		for( i => s in separators )
			if( i < h.seps.length ) s.row.height = h.seps[i];
	}

	public function restoreScroll( scrollTop : Int ) {
		#if js
		var scroll = editor.element.get(0);
		if( scroll.scrollTop == scrollTop ) return;
		scroll.scrollTop = scrollTop;
		render();
		#end
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

		// the cells of the lines are created when they are displayed, see render()
		lines = [for( index in 0...sheet.lines.length ) new Line(this, columns, index, J("<tr>"))];
		materialized = [];

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

		tbody = J("<tbody>");

		var sepIndex = -1;
		var sepNext = sheet.separators[++sepIndex];
		separators = [];
		for( i in 0...lines.length ) {
			// Create the separator of this index if there is one
			while( sepNext != null && sepNext.index == i ) {
				var sep = new Separator(this, sepNext);

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
				sepNext = sheet.separators[++sepIndex];
			}

			lines[i].separator = separators[separators.length - 1];
		}
		#if js
		virtual = sheet.parent == null;
		#end
		if( virtual ) loadHeights();
		editor.formulas.validateBatch(() -> for( l in lines ) l.updateStatus());

		refreshLinesStatus();

		lockRows(function() {
			for (s in separators)
				s.refresh(false);
		});

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
			resizeObserver = new hide.comp.ResizeObserver((_,_) -> {
				setupTableElement();
				scheduleRender();
			});
			resizeObserver.observe(editor.element.parent().get(0));

			// a sub table opened or closed, an image loaded... : the rows around the view change
			if( bodyObserver != null )
				bodyObserver.disconnect();
			bodyObserver = new hide.comp.ResizeObserver((_,_) -> scheduleRender());
			bodyObserver.observe(tbody.get(0));
		}
		#end

		refreshRows();
	}

	function createLineHead( line : Line ) {
		var l = line.element;
		var head = J("<td>").addClass("start").text("" + line.index);
		l.prepend(head);
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
	}

	function onLineCreated( line : Line ) {
		materialized.push(line);
		// created out of the view (copy, paste...) : its cells are removed by the next render
		if( !line.row.attached )
			scheduleRender();
	}

	/**
		Rebuilds the list of the displayed rows (lines and separators) after a change of filter or of group state, then renders them.
	**/
	public function refreshRows() {
		if( lines == null || separators == null || displayMode != Table )
			return;
		if( rowsLock > 0 ) {
			rowsDirty = true;
			return;
		}
		for( r in rows )
			r.index = -1;
		rows = [];
		var sepIndex = 0;
		for( l in lines ) {
			while( sepIndex < separators.length && separators[sepIndex].data.index == l.index ) {
				var s = separators[sepIndex++];
				if( s.isDisplayed() ) {
					s.row.index = rows.length;
					rows.push(s.row);
				}
			}
			l.displayed = !l.filtered && (l.separator == null || l.separator.getLinesVisiblity()) && !l.isForbidden();
			if( l.displayed ) {
				l.row.index = rows.length;
				rows.push(l.row);
			}
		}
		render();
	}

	/**
		Groups the changes of displayed rows made by `f` into a single refreshRows().
	**/
	public function lockRows( f : Void -> Void ) {
		rowsLock++;
		f();
		rowsLock--;
		if( rowsLock == 0 && rowsDirty ) {
			rowsDirty = false;
			refreshRows();
		}
	}

	public function scheduleRender() {
		#if js
		if( renderPending || !virtual ) return;
		renderPending = true;
		js.Browser.window.requestAnimationFrame((_) -> if( renderPending ) render());
		#end
	}

	inline function rowHeight( r : Row ) {
		return r.height >= 0 ? r.height : r.line != null ? lineHeight : sepHeight;
	}

	// the rows which stay in the DOM out of the view
	function isPinned( r : Row ) {
		var l = r.line;
		if( l == null ) return false;
		if( l.subTable != null ) return true;
		for( c in l.cells )
			if( c.inEdit ) return true;
		return false;
	}

	/**
		Puts in the DOM the rows which are in the view (with a margin around it) and the pinned rows (an open sub table,
		a cell in edition) ; the other rows are replaced by spacers of the same height.
		A table which is not virtual has all its rows in the DOM.
	**/
	public function render() {
		renderPending = false;
		if( rows == null || tbody == null ) return;
		#if js
		var body = tbody.get(0);
		var scroll = editor.element.get(0);
		// out of the document, the rows can not be measured : the body observer renders them once it is in
		if( virtual && !body.isConnected ) return;
		var attachedNew = false;

		// the view stays on the row at its top, at the same distance : the heights of the rows above it can change
		// (measured, or a new estimate for the rows never shown)
		var viewH = scroll.clientHeight;
		var bodyTop = 0.;
		var anchor : Row = null;
		var anchorOffset = 0.;
		if( virtual ) {
			bodyTop = body.getBoundingClientRect().top - scroll.getBoundingClientRect().top + scroll.scrollTop;
			var viewTop = scroll.scrollTop - bodyTop;
			var y = 0.;
			for( r in rows ) {
				var h = rowHeight(r);
				if( y + h > viewTop ) {
					anchor = r;
					anchorOffset = viewTop - y;
					break;
				}
				y += h;
			}
		}

		for( pass in 0...4 ) {
			var top = Math.NEGATIVE_INFINITY, bottom = Math.POSITIVE_INFINITY;
			if( virtual ) {
				top = anchor == null ? scroll.scrollTop - bodyTop : getRowY(anchor) + anchorOffset;
				bottom = top + viewH;
				var margin = Math.max(viewH * 0.5, 300);
				top -= margin;
				bottom += margin;
			}

			// the rows to show
			var want = [];
			var y = 0.;
			var first = -1;
			for( r in rows ) {
				var h = rowHeight(r);
				var w = y + h > top && y < bottom;
				if( w && first < 0 ) first = r.index;
				want.push(w || isPinned(r));
				y += h;
			}
			// the group of the first row stays, so that its title sticks at the top of the view
			var i = first - 1;
			while( i >= 0 ) {
				if( rows[i].sep != null ) {
					want[i] = true;
					break;
				}
				i--;
			}

			// remove the rows which are no longer shown
			for( r in attached.copy() )
				if( r.index < 0 || !want[r.index] )
					detachRow(r);
			for( s in spacers )
				if( s.parentNode != null ) s.parentNode.removeChild(s);
			for( l in materialized.copy() )
				if( !l.row.attached )
					l.removeCells();

			// insert the rows in order, and the spacers between them
			var cur = body.firstChild;
			var gap = 0.;
			var spacerCount = 0;
			var shown : Array<Row> = [];
			for( r in rows ) {
				if( !want[r.index] ) {
					gap += rowHeight(r);
					continue;
				}
				if( gap > 0 ) {
					body.insertBefore(getSpacer(spacerCount++, gap), cur);
					shown.push(null);
					gap = 0;
				}
				var e = r.getElement();
				if( !r.attached ) {
					r.attached = true;
					attached.push(r);
					attachedNew = true;
					if( r.line != null ) r.line.create();
					body.insertBefore(e, cur);
				} else if( e != cur ) {
					// the elements inserted after the row (sub table...) move with it
					var extra = [];
					var n = e.nextSibling;
					while( n != null && !isRowElement(n) ) {
						extra.push(n);
						n = n.nextSibling;
					}
					body.insertBefore(e, cur);
					for( x in extra ) body.insertBefore(x, cur);
				} else {
					cur = e.nextSibling;
					while( cur != null && !isRowElement(cur) )
						cur = cur.nextSibling;
				}
				shown.push(r);
			}
			if( gap > 0 ) {
				body.insertBefore(getSpacer(spacerCount++, gap), cur);
				shown.push(null);
			}

			if( !virtual ) break;

			// measure the rows : their heights give the heights of the spacers
			var changed = false;
			var spacerIndex = 0;
			var tops = [for( r in shown ) r == null ? spacers[spacerIndex++].offsetTop : r.getElement().offsetTop];
			var end = body.offsetTop + body.offsetHeight;
			for( k => r in shown ) {
				if( r == null ) continue;
				var h = (k + 1 < tops.length ? tops[k + 1] : end) - tops[k];
				if( h <= 0 || Math.abs(h - r.height) <= 0.5 ) continue;
				changed = true;
				r.height = h;
				if( r.sep != null )
					sepHeight = h;
			}
			if( !changed ) break;

			// the lines which were never shown have the average height of the measured ones
			var sum = 0., count = 0;
			for( r in rows )
				if( r.line != null && r.height >= 0 && r.line.subTable == null ) {
					sum += r.height;
					count++;
				}
			if( count > 0 )
				lineHeight = sum / count;
		}

		if( anchor != null ) {
			var want = bodyTop + getRowY(anchor) + anchorOffset;
			if( Math.abs(scroll.scrollTop - want) >= 1 )
				scroll.scrollTop = Math.round(want);
		}
		if( attachedNew && editor.cursor.table != null )
			editor.cursor.update(false);
		#end
	}

	function detachRow( r : Row ) {
		attached.remove(r);
		if( r.line != null ) {
			r.line.unrender();
			return;
		}
		var e = r.getElement();
		if( e.parentNode != null ) e.parentNode.removeChild(e);
		r.attached = false;
	}

	static function isRowElement( n : js.html.Node ) {
		return (n : Dynamic).__cdbRow == true || (n : Dynamic).__cdbSpacer == true;
	}

	function getSpacer( index : Int, height : Float ) {
		var s = spacers[index];
		if( s == null ) {
			s = js.Browser.document.createTableRowElement();
			(s : Dynamic).__cdbSpacer = true;
			s.className = "cdb-spacer";
			var td = js.Browser.document.createTableCellElement();
			td.colSpan = columns.length + 1;
			s.appendChild(td);
			spacers[index] = s;
		}
		(cast s.firstChild : js.html.Element).style.height = height + "px";
		return s;
	}

	// the position of a displayed row in the body of the table
	function getRowY( row : Row ) {
		var y = 0.;
		for( r in rows ) {
			if( r == row ) break;
			y += rowHeight(r);
		}
		return y;
	}

	// the position of a displayed row in the content of the scroll
	function getRowTop( row : Row ) {
		var scroll = editor.element.get(0);
		return tbody.get(0).getBoundingClientRect().top - scroll.getBoundingClientRect().top + scroll.scrollTop + getRowY(row);
	}

	/**
		Scrolls the view to a line of the table which is out of the DOM, and renders it.
	**/
	public function revealRow( line : Line ) {
		#if js
		if( !virtual || line.row.index < 0 || line.row.attached ) return;
		var scroll = editor.element.get(0);
		scroll.scrollTop = Std.int(getRowTop(line.row) - scroll.clientHeight * 0.5);
		render();
		// the row is measured now : center it
		if( line.row.attached ) {
			var r = line.element.get(0).getBoundingClientRect();
			var v = scroll.getBoundingClientRect();
			scroll.scrollTop += Std.int((r.top + r.height * 0.5) - (v.top + v.height * 0.5));
			render();
		}
		#end
	}

	/**
		The first line in the view, and the distance from its top to the top of the view : the position of the view
		which does not depend on the heights of the rows above.
	**/
	public function getViewLine() : { line : Int, offset : Float } {
		#if js
		if( !virtual ) return null;
		var viewTop = editor.element.get(0).getBoundingClientRect().top;
		var best : Row = null;
		var bestTop = 0.;
		for( r in attached ) {
			if( r.line == null || r.index < 0 ) continue;
			var b = r.getElement().getBoundingClientRect();
			if( b.bottom > viewTop && (best == null || b.top < bestTop) ) {
				best = r;
				bestTop = b.top;
			}
		}
		return best == null ? null : { line : best.line.index, offset : viewTop - bestTop };
		#else
		return null;
		#end
	}

	public function scrollToLine( index : Int, offset : Float ) {
		#if js
		var l = lines[index];
		if( !virtual || l == null || l.row.index < 0 ) return;
		var scroll = editor.element.get(0);
		scroll.scrollTop = Std.int(getRowTop(l.row) + offset);
		render();
		#end
	}

	/**
		The index of the displayed line which is `delta` displayed lines away from `index`, the first displayed line when there
		are not enough before it. When there are not enough after it, the last displayed line if `clamp` is set, -1 otherwise.
	**/
	public function moveDisplayed( index : Int, delta : Int, clamp = false ) : Int {
		var step = delta < 0 ? -1 : 1;
		var n = delta < 0 ? -delta : delta;
		var i = index;
		var found = index;
		while( n > 0 ) {
			i += step;
			if( i < 0 || i >= lines.length ) break;
			if( lines[i].displayed ) {
				found = i;
				n--;
			}
		}
		if( n > 0 && step > 0 && !clamp )
			return -1;
		return found;
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
			// polymorph variant unfold: contribute its object frame so scoped ids resolve correctly
			if( p.polyVal != null )
				scope.unshift({ s : line.table.getRealSheet().getSub(p.cell.column), obj : p.polyVal.obj });
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

			if( c.type.match(TList | TProperties | TPolymorph) ) isLarge = true;

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
				e.stopPropagation();
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
		@:privateAccess editor.cdbTable.warningCountEl.text(warningCount);
		@:privateAccess editor.cdbTable.errorCountEl.text(errorCount);
		@:privateAccess editor.cdbTable.regularCountEl.text(lines.length - (errorCount + warningCount));
	}
}
@:allow(hide.comp.cdb)
class Row {
	public var line(default, null) : Line;
	public var sep(default, null) : Separator;
	// position in the displayed rows of the table, -1 if not displayed
	public var index = -1;
	// measured height, -1 if not measured yet
	public var height = -1.;
	public var attached = false;

	public function new( line, sep ) {
		this.line = line;
		this.sep = sep;
		(getElement() : Dynamic).__cdbRow = true;
	}

	public inline function getElement() : js.html.Element {
		return (line != null ? line.element : sep.element).get(0);
	}
}
