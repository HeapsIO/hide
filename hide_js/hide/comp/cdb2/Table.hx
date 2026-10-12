package hide.comp.cdb2;

import cdb.Sheet.ObjectPath;

enum VirtualLineKind {
	Line;
	Header;
	TableEnd;
}

/** A displayed line of the table **/
typedef VirtualLine = {
	path: ObjectPath,
	kind: VirtualLineKind,
	/** Key of the sheet holding the line in openSheets **/
	parent: VirtualLine,
};

/** `gridColumns` is the grid-template-columns of the lines of the sheet **/
typedef SheetEntry = {path: ObjectPath, lines: Array<VirtualLine>, gridColumns: String};

/** Port of hrt.ui.HuiCdbTable **/
@:access(hide.comp.cdb2.TableLine)
@:access(hide.comp.cdb2.TableCell)
class Table {
	public var element(default, null) : js.html.Element;
	var sheet: cdb.Sheet;
	var headerLine : TableLine;
	var list : hide.comp.VirtualList<VirtualLine>;
	var keys : hide.ui.Keys;
	var undo : hide.ui.UndoHistory;
	/** Path of the cell under the cursor **/
	var cursor: ObjectPath;
	/** Cell displaying the cursor **/
	var cursorCell: TableCell;

	var visibleList : Array<VirtualLine> = [];
	/**
		Visible sheets, their lines and their columns, by parent line. The root sheet uses null and is always present.
		Keys match by reference : use the lines returned by getSheetLines, not an equivalent copy.
	**/
	var openSheets = new js.lib.Map<VirtualLine, SheetEntry>();
	/** Lines displayed by the list, by list item **/
	var shownLines = new js.lib.Map<VirtualLine, TableLine>();
	var linePool: Array<TableLine> = [];

	/** Left margin of the lines per sub sheet depth **/
	static final DEPTH_MARGIN = 8;

	public function new(sheet: cdb.Sheet, undo: hide.ui.UndoHistory) {
		this.undo = undo;
		element = js.Browser.document.createElement("cdb-table2");
		// focusable, so it receives its keys
		element.tabIndex = 0;
		headerLine = new TableLine(this, null);
		element.appendChild(headerLine.element);
		list = new hide.comp.VirtualList(element);
		list.setItems(visibleList);
		list.generateItem = generateLine;
		list.refreshItem = refreshItem;
		list.onItemRemoved = onLineRemoved;

		openSheet(sheet);

		keys = new hide.ui.Keys(new hide.Element(element));
		keys.addListener(onKey);
		keys.register("delete", clearCursorCell);
		keys.register("cdb.editCell", editCursorCell);
		keys.register("cdb.closeList", escapeCursorCell);
	}

	function onKey(e: hide.Element.Event) : Bool {
		if (e.ctrlKey || e.altKey || e.shiftKey)
			return false;
		switch (e.keyCode) {
			case hxd.Key.UP: moveCursor(-1, 0);
			case hxd.Key.DOWN: moveCursor(1, 0);
			case hxd.Key.LEFT: moveCursor(0, -1);
			case hxd.Key.RIGHT: moveCursor(0, 1);
			default: return false;
		}
		return true;
	}

	public function openSheet(sheet: cdb.Sheet) {
		this.sheet = sheet;
		// path to the lines array of the root sheet
		var sheetPath = new ObjectPath();
		if (sheet != null)
			sheetPath.push(sheet.lines, -1, sheet, null);

		// pooled lines have the previous sheet's columns
		list.clear();
		linePool.resize(0);
		shownLines.clear();
		// entries hold the previous sheet
		visibleList.resize(0);
		openSheets.clear();
		openSubSheet(null, sheetPath);

		if (sheet == null)
			return;

		buildHeader();
	}

	/** `path` is the path of a cell, as returned by getCellObjectPath **/
	public function setCursor(path: ObjectPath) {
		cursor = path;
		var line = getCursorLine();
		if (line != -1)
			list.scrollToIndex(line);
		updateCursor();
	}

	/** The line holding the cursor, null if its sheet isn't open **/
	function getCursorVLine() : Null<VirtualLine> {
		return cursor == null ? null : getLiveLine(cursor, cursor.path.length - 1);
	}

	/** Index in visibleList of the line holding the cursor, -1 if not displayed **/
	function getCursorLine() : Int {
		return visibleList.indexOf(getCursorVLine());
	}

	/** Index of the cursor column in the sheet of its line, -1 without cursor **/
	function getCursorCol() : Int {
		if (cursor == null)
			return -1;
		var last = cursor.path.length - 1;
		for (i => c in cursor.sheets[last].columns)
			if (c.name == cursor.cols[last])
				return i;
		return -1;
	}

	function moveCursor(dLine: Int, dCol: Int) {
		var vline = getCursorVLine() ?? visibleList[0];
		if (vline == null)
			return;
		var col = hxd.Math.imax(getCursorCol(), 0) + dCol;
		var entry = openSheets.get(vline.parent);
		var firstLine = (lines: Array<VirtualLine>) -> Lambda.find(lines, (l) -> l.kind == Line);

		var sub = openSheets.get(vline);
		var subFirst = sub != null ? firstLine(sub.lines) : null;
		if (dLine > 0 && subFirst != null && sub.path.cols[sub.path.cols.length - 1] == cursor?.cols[cursor.cols.length - 1]) {
			// enter the sub table opened by the cursor cell
			vline = subFirst;
			col = 0;
		} else if (dLine < 0 && vline.parent != null && firstLine(entry.lines) == vline) {
			// back to the list cell of the sub table
			setCursor(entry.path.copy());
			return;
		} else {
			// stay in the table, skip the lines without cells
			var lines = entry.lines;
			var next = lines.indexOf(vline) + dLine;
			while (dLine != 0 && next >= 0 && next < lines.length && lines[next].kind != Line)
				next += dLine;
			if (next >= 0 && next < lines.length)
				vline = lines[next];
		}

		var columns = vline.path.sheets[vline.path.sheets.length - 1].columns;
		col = hxd.Math.iclamp(col, 0, columns.length - 1);
		setCursor(getCellObjectPath(vline.path, columns[col]));
	}

	function editCursorCell() {
		var vline = getCursorVLine();
		var cell = vline != null ? getCell(vline, getCursorCol()) : null;
		// edit toggles the sub sheet of list cells
		if (cell == null || cell.readOnly || (cell.editing && !(cell is TableCellList)))
			return;
		cell.edit();

		// move to the first cell of the opened sub sheet
		if (!(cell is TableCellList) || !cell.editing)
			return;
		var first = Lambda.find(openSheets.get(vline).lines, (l) -> l.kind == Line);
		if (first != null)
			setCursor(getCellObjectPath(first.path, first.path.sheets[first.path.sheets.length - 1].columns[0]));
	}

	function escapeCursorCell() {
		var vline = getCursorVLine();
		var cell = vline != null ? getCell(vline, getCursorCol()) : null;
		cell?.onEscape();
	}

	/** `vline` must be the instance from visibleList, list items match by reference **/
	function getLine(vline: VirtualLine) : TableLine {
		return shownLines.get(vline);
	}

	function getCell(vline: VirtualLine, col: Int) : TableCell {
		return getLine(vline)?.getCell(col);
	}

	/** The line instance from openSheets matching the line path `path`, null if its sheet isn't open **/
	function getLiveLine(path: ObjectPath, ?depth: Int) : Null<VirtualLine> {
		var live : VirtualLine = null;
		// only the first `depth` levels of path, all by default
		for (i in 0...(depth ?? path.path.length)) {
			var entry = openSheets.get(live);
			// sub sheet lines start with their header
			var header = live == null ? 0 : 1;
			live = entry?.lines[path.indexes[i] + header];
			if (live == null || live.path.cols[i] != path.cols[i])
				return null;
		}
		return live;
	}

	/** Must be called when the cursor or the lines displayed by the list change **/
	function updateCursor() {
		var vline = getCursorVLine();
		var cell = vline != null ? getCell(vline, getCursorCol()) : null;
		// pooled lines may display another line
		cursorCell?.element.classList.remove("cursor");
		cursorCell = cell;
		cell?.element.classList.add("cursor");
	}

	function refreshItem(item: VirtualLine, element: js.html.Element) {
		shownLines.get(item)?.resizeCells();
	}

	function generateLine(entry: VirtualLine) : js.html.Element {
		if (entry.kind == TableEnd)
			return js.Browser.document.createElement("cdb-table-end");

		// pooled lines have the cells of their sheet, header lines are rebuilt each time
		var line = null;
		if (entry.kind == Line) {
			var sheet = entry.path.sheets[entry.path.sheets.length - 1];
			line = Lambda.find(linePool, (l) -> l.vline.path.sheets[l.vline.path.sheets.length - 1] == sheet);
			linePool.remove(line);
		}

		if (line == null)
			line = new TableLine(this, entry);
		line.setLine(entry);
		shownLines.set(entry, line);
		updateCursor();
		return line.element;
	}

	function onLineRemoved(entry: VirtualLine) {
		var line = shownLines.get(entry);
		shownLines.delete(entry);
		if (entry.kind == Line)
			linePool.push(line);
	}

	function setDataAction(path: ObjectPath, newData: Dynamic) : hrt.tools.Undo.Action {
		var oldData = path.obj;
		if (hrt.prefab.Diff.diff(oldData, newData) == Skip)
			return null;
		var last = path.path.length - 1;
		return (isUndo) -> {
			// fetch the parent of the last level from the database
			var parent : Dynamic = null;
			for (i in 0...last) {
				var v : Dynamic = i == 0 ? path.sheets[0].lines : Reflect.field(parent, path.cols[i]);
				parent = path.indexes[i] >= 0 ? v[path.indexes[i]] : v;
			}
			var value = isUndo ? oldData : newData;
			if (last == 0)
				path.sheets[0].lines[path.indexes[0]] = value;
			else if (path.indexes[last] >= 0)
				Reflect.field(parent, path.cols[last])[path.indexes[last]] = value;
			// cdb lines don't store empty optional fields
			else if (value == null)
				Reflect.deleteField(parent, path.cols[last]);
			else
				Reflect.setField(parent, path.cols[last], value);

			// refresh the cell of the line holding the last level, if displayed
			var linePath = path.copy();
			linePath.pop();
			var live = getLiveLine(linePath);
			if (live != null)
				for (i => c in path.sheets[last].columns)
					if (c.name == path.cols[last])
						getCell(live, i)?.refreshData();
		}
	}

	/** Applies `action` and adds it to the undo history, ignores null actions **/
	function runAction(action: hrt.tools.Undo.Action) {
		if (action == null)
			return;
		action(false);
		undo.change(Custom(action));
	}

	function getCellObjectPath(linePath: ObjectPath, column: cdb.Data.Column) : ObjectPath {
		var path = linePath.copy();
		path.push(Reflect.field(linePath.obj, column.name), -1, linePath.sheets[linePath.sheets.length - 1], column.name);
		return path;
	}

	function clearCursorCell() {
		var vline = getCursorVLine();
		if (vline == null)
			return;
		var column = vline.path.sheets[vline.path.sheets.length - 1].columns[getCursorCol()];
		// rebuilt from the line, the cursor holds the cell value of when it was set
		runAction(setDataAction(getCellObjectPath(vline.path, column), getDefault(column)));
	}

	/** Value of a new or cleared cell. Null for optional columns **/
	function getDefault(column: cdb.Data.Column) : Dynamic {
		return sheet.base.getDefault(column, false, sheet);
	}

	function buildHeader() {
		headerLine.element.textContent = "";
		headerLine.cells = [];
		headerLine.element.appendChild(headerLine.lineNoCell.element);
		headerLine.cells.push(headerLine.lineNoCell);

		if (sheet == null)
			return;

		for (column in sheet.columns) {
			var cell = new TableCellText(headerLine, column);
			cell.element.textContent = column.name;
			cell.readOnly = true;
		}

		headerLine.resizeCells();
	}

	function computeCellSizes(entry: SheetEntry) {
		var sheet = getTableSheet(entry.path);
		if (sheet == null)
			return;
		var cellSizes = [20];
		for (column in sheet.columns)
			cellSizes.push(100);

		// proportions of the line width, excluding the depth margin. Min 0 so the content doesn't widen the columns
		entry.gridColumns = [for (size in cellSizes) 'minmax(0, ${size}fr)'].join(" ");
	}

	/** `vline` must be the instance returned by getSheetLines, openSheets keys match by reference **/
	function openSubSheet(vline: VirtualLine, tablePath: ObjectPath) {
		var entry : SheetEntry = {path: tablePath, lines: [], gridColumns: null};
		computeCellSizes(entry);
		openSheets.set(vline, entry);
		refreshVisible();
	}

	/** Also closes the sheets opened under its lines **/
	function closeSubSheet(vline: VirtualLine) {
		function close(vline: VirtualLine) {
			var entry = openSheets.get(vline);
			if (entry == null)
				return;
			openSheets.delete(vline);
			for (l in entry.lines)
				close(l);
		}
		close(vline);
		refreshVisible();
	}

	/** The sheet of the lines array at the end of `tablePath`, null for an empty path **/
	function getTableSheet(tablePath: ObjectPath) : cdb.Sheet {
		// a sheet path ends with its lines array : the root sheet lines (no column) or a list column of the parent line
		var last = tablePath.path.length - 1;
		var s = tablePath.sheets[last];
		var col = tablePath.cols[last];
		if (col != null)
			s = s.getSub(Lambda.find(s.columns, (c) -> c.name == col));
		return s;
	}

	/**
		Lines of the sheet opened under `vline` (null for the root sheet).
		The lines are reused, they are the list keys of the displayed lines.
	**/
	function getSheetLines(vline: VirtualLine) : Array<VirtualLine> {
		var entry = openSheets.get(vline);
		if (entry == null)
			throw "Sheet not open";
		var path = entry.path;
		var vlines = entry.lines;
		var s = getTableSheet(path);
		var col = path.cols[path.cols.length - 1];
		var lines : Array<Dynamic> = path.obj ?? [];

		// sub sheets start with a header line and end with a table end line, the root header is outside of the list
		var header = vline == null ? 0 : 1;
		var tableEnd = header == 1 ? vlines.pop() : null;
		vlines.resize(lines.length + header);
		if (header == 1 && vlines[0] == null) {
			var p = path.copy();
			p.pop();
			p.push(null, -1, s, col);
			vlines[0] = {path: p, kind: Header, parent: vline};
		}
		for (i => l in lines) {
			if (vlines[i + header] == null) {
				var p = path.copy();
				// the line replaces the lines array level
				p.pop();
				p.push(l, i, s, col);
				vlines[i + header] = {path: p, kind: Line, parent: vline};
				continue;
			}
			// only the last level differs between the lines of a sheet
			var p = vlines[i + header].path;
			p.path[p.path.length - 1] = l;
			p.indexes[p.indexes.length - 1] = i;
		}
		if (header == 1)
			vlines.push(tableEnd ?? {path: path.copy(), kind: TableEnd, parent: vline});
		return vlines;
	}

	function refreshVisible() {
		visibleList.resize(0);
		// opened sub sheets are displayed right after their parent line
		function pushLines(vline: VirtualLine) {
			for (l in getSheetLines(vline)) {
				visibleList.push(l);
				if (openSheets.has(l))
					pushLines(l);
			}
		}
		pushLines(null);

		// drops the keep lines of the removed entries
		list.setItems(visibleList);
	}
}

@:access(hide.comp.cdb2.TableCell)
@:access(hide.comp.cdb2.Table)
class TableLine {
	var table: Table;
	var vline: VirtualLine;
	var element: js.html.Element;
	var cells: Array<TableCell> = [];
	var lineData(get, never): Dynamic;
	var lineNoCell: TableCellText;
	/** Grid columns applied to the line **/
	var gridColumns: String;

	public function new(table: Table, vline: VirtualLine) {
		this.table = table;
		this.vline = vline;
		element = js.Browser.document.createElement("cdb-line");
		lineNoCell = new TableCellText(this, null);
		lineNoCell.readOnly = true;

		if (vline == null || vline.kind == Header)
			element.classList.add("header");

		if (vline == null)
			return;

		var path = vline.path;
		for (column in path.sheets[path.sheets.length - 1].columns) {
			if (vline.kind == Header) {
				var cell = new TableCellText(this, column);
				cell.element.textContent = column.name;
				cell.readOnly = true;
				continue;
			}
			switch (column.type) {
				case TId, TString:
					new TableCellText(this, column);
				case TList:
					new TableCellList(this, column);
				default:
					new TableCellText(this, column).readOnly = true;
			}
		}
	}

	function getCell(col: Int) : TableCell {
		// skip line number cell
		return cells[col + 1];
	}

	/** Uses the cell sizes of the sheet holding the line **/
	function resizeCells() {
		var columns = table.openSheets.get(vline?.parent).gridColumns;
		if (columns != gridColumns)
			element.style.gridTemplateColumns = gridColumns = columns;
	}

	function setLine(vline: VirtualLine) {
		this.vline = vline;
		// edited lines are kept, but closing a sub sheet also removes the lines of the sheets opened under it
		for (cell in cells)
			cell.editing = false;
		refreshData();
		resizeCells();
	}

	inline function get_lineData() return vline.path.obj;

	function refreshData() {
		element.style.marginLeft = '${Table.DEPTH_MARGIN * (vline.path.path.length - 1)}px';
		// header cells have no data
		if (vline.kind != Line)
			return;
		lineNoCell.element.textContent = Std.string(vline.path.indexes[vline.path.indexes.length - 1] + 1);
		for (cell in cells) {
			cell.refreshData();
		}
	}
}

@:access(hide.comp.cdb2.TableLine)
@:access(hide.comp.cdb2.Table)
class TableCell {
	var line: TableLine;
	var column: cdb.Data.Column;
	var element: js.html.Element;
	var readOnly = false;
	var editing = false;

	public function new(line: TableLine, column: cdb.Data.Column) {
		this.line = line;
		this.column = column;
		element = js.Browser.document.createElement("cdb-cell");
		line.element.appendChild(element);
		line.cells.push(this);
		element.onpointerdown = onCellPush;
		element.ondblclick = onCellDoubleClick;
	}

	function getObjectPath() : ObjectPath {
		return line.table.getCellObjectPath(line.vline.path, column);
	}

	function onCellPush(e: js.html.PointerEvent) {
		// ignore line number and header cells
		if (column == null || line.vline?.kind != Line)
			return;
		line.table.setCursor(getObjectPath());
	}

	function onCellDoubleClick(e: js.html.MouseEvent) {
		if (readOnly)
			return;
		edit();
	}

	/** Escape pressed with the cell under the cursor **/
	function onEscape() {
		if (editing) {
			finishEdit();
			return;
		}
		// close the sub sheet holding the line from its list cell
		var parent = line.vline?.parent;
		if (parent == null)
			return;
		var path = line.table.openSheets.get(parent).path;
		var last = path.path.length - 1;
		for (i => c in path.sheets[last].columns)
			if (c.name == path.cols[last])
				line.table.getCell(parent, i)?.finishEdit();
		line.table.setCursor(path.copy());
	}

	function edit() {
		editing = true;
		// keep the line while scrolled out, so the edit isn't lost
		line.table.list.setKeepLine(line.vline, true);
	}

	function commit() {
		finishEdit();
	}

	function finishEdit() {
		editing = false;
		line.table.list.setKeepLine(line.vline, false);
	}

	function refreshData() {}
}

@:access(hide.comp.cdb2.TableLine)
@:access(hide.comp.cdb2.Table)
class TableCellText extends TableCell {
	var input: js.html.InputElement;

	override function edit() {
		super.edit();
		input = js.Browser.document.createInputElement();
		input.value = Reflect.field(line.lineData, column.name) ?? "";
		element.textContent = "";
		element.appendChild(input);
		input.onblur = (_) -> if (editing) finishEdit();
		// the view doesn't process the keys of a focused input
		input.onkeydown = onInputKeyDown;
		input.focus();
		input.select();
	}

	function onInputKeyDown(e: js.html.KeyboardEvent) {
		if (e.shiftKey || e.ctrlKey || e.altKey)
			return;
		switch (e.keyCode) {
			case hxd.Key.ENTER, hxd.Key.TAB: commit();
			case hxd.Key.ESCAPE: finishEdit();
			default: return;
		}
		// the table keys would process it once the table has the focus back
		e.preventDefault();
		e.stopPropagation();
	}

	override function commit() {
		line.table.runAction(line.table.setDataAction(getObjectPath(), input.value));
		super.commit();
	}

	override function finishEdit() {
		super.finishEdit();
		// back to the table keys, unless the focus moved elsewhere
		if (js.Browser.document.activeElement == input)
			line.table.element.focus();
		input = null;
		// replaces the input
		refreshData();
	}

	override function refreshData() {
		if (column == null || editing)
			return;
		var data : Dynamic = Reflect.field(line.lineData, column.name);
		element.textContent = data is String ? data : haxe.Json.stringify(data);
	}
}

@:access(hide.comp.cdb2.TableLine)
@:access(hide.comp.cdb2.Table)
class TableCellList extends TableCell {
	override function edit() {
		if (editing) {
			finishEdit();
			return;
		}
		super.edit();
		line.table.openSubSheet(line.vline, getObjectPath());
		refreshData();
	}

	override function finishEdit() {
		super.finishEdit();
		line.table.closeSubSheet(line.vline);
		refreshData();
	}

	override function refreshData() {
		if (editing) {
			element.textContent = "...";
			return;
		}
		var lines : Array<Dynamic> = Reflect.field(line.lineData, column.name);
		element.textContent = "[" + (lines?.length ?? 0) + "]";
	}
}
