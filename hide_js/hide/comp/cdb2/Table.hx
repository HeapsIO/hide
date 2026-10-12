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

/** Port of hrt.ui.HuiCdbTable, read only **/
@:access(hide.comp.cdb2.TableLine)
@:access(hide.comp.cdb2.TableCell)
class Table {
	public var element(default, null) : js.html.Element;
	var sheet: cdb.Sheet;
	var headerLine : TableLine;
	var list : hide.comp.VirtualList<VirtualLine>;

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

	public function new(sheet: cdb.Sheet) {
		element = js.Browser.document.createElement("cdb-table2");
		headerLine = new TableLine(this, null);
		element.appendChild(headerLine.element);
		list = new hide.comp.VirtualList(element);
		list.setItems(visibleList);
		list.generateItem = generateLine;
		list.refreshItem = refreshItem;
		list.onItemRemoved = onLineRemoved;

		openSheet(sheet);
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
		return line.element;
	}

	function onLineRemoved(entry: VirtualLine) {
		var line = shownLines.get(entry);
		shownLines.delete(entry);
		if (entry.kind == Line)
			linePool.push(line);
	}

	function buildHeader() {
		headerLine.element.textContent = "";
		headerLine.cells = [];
		headerLine.element.appendChild(headerLine.lineNoCell.element);
		headerLine.cells.push(headerLine.lineNoCell);

		if (sheet == null)
			return;

		for (column in sheet.columns)
			new TableCellText(headerLine, column).element.textContent = column.name;

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

		if (vline == null || vline.kind == Header)
			element.classList.add("header");

		if (vline == null)
			return;

		var path = vline.path;
		for (column in path.sheets[path.sheets.length - 1].columns) {
			if (vline.kind == Header) {
				new TableCellText(this, column).element.textContent = column.name;
				continue;
			}
			switch (column.type) {
				case TList:
					new TableCellList(this, column);
				default:
					new TableCellText(this, column);
			}
		}
	}

	/** Uses the cell sizes of the sheet holding the line **/
	function resizeCells() {
		var columns = table.openSheets.get(vline?.parent).gridColumns;
		if (columns != gridColumns)
			element.style.gridTemplateColumns = gridColumns = columns;
	}

	function setLine(vline: VirtualLine) {
		this.vline = vline;
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
class TableCell {
	var line: TableLine;
	var column: cdb.Data.Column;
	var element: js.html.Element;

	public function new(line: TableLine, column: cdb.Data.Column) {
		this.line = line;
		this.column = column;
		element = js.Browser.document.createElement("cdb-cell");
		line.element.appendChild(element);
		line.cells.push(this);
	}

	function refreshData() {}
}

@:access(hide.comp.cdb2.TableLine)
class TableCellText extends TableCell {
	override function refreshData() {
		if (column == null)
			return;
		var data : Dynamic = Reflect.field(line.lineData, column.name);
		element.textContent = data is String ? data : haxe.Json.stringify(data);
	}
}

@:access(hide.comp.cdb2.TableLine)
class TableCellList extends TableCell {
	override function refreshData() {
		var lines : Array<Dynamic> = Reflect.field(line.lineData, column.name);
		element.textContent = "[" + (lines?.length ?? 0) + "]";
	}
}
