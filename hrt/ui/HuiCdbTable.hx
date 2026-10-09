package hrt.ui;

#if hui

import cdb.Sheet.ObjectPath;

/** A displayed line of the table **/
typedef VirtualLine = {path: ObjectPath};

typedef SheetEntry = {path: ObjectPath, lines: Array<VirtualLine>, cellSizes: Array<Int>};

@:structInit
class HuiTableSelectionRect {
	public var x: Int;
	public var y: Int;
	public var h: Int;
	public var w: Int;
}

@:access(hrt.ui.HuiTableLine)
@:access(hrt.ui.HuiTableCellText)
@:access(hrt.ui.HuiBackground)
@:access(hrt.ui.HuiTableCell)
class HuiCdbTable extends HuiElement {
	var sheet: cdb.Sheet;

	var visibleList : Array<VirtualLine> = [];
	/**
		Visible sheets, their lines and their cell sizes, by parent line. The root sheet uses null and is always present.
		Keys match by reference : use the lines returned by getSheetLines, not an equivalent copy.
	**/
	var openSheets: Map<VirtualLine, SheetEntry> = [];
	var linePool: Array<HuiTableLine> = [];
	var selectionRects: Array<HuiTableSelectionRect> = [];
	var selectionRectsElements: Array<HuiCdbSelection> = [];
	var cursorCol = 0;
	var cursorLine = 0;
	var cursorElement: HuiCdbCursor;

	static var upCmd = new HuiCommands.HuiCommand("Cursor Up", {key: hxd.Key.UP});
	static var downCmd = new HuiCommands.HuiCommand("Cursor Down", {key: hxd.Key.DOWN});
	static var leftCmd = new HuiCommands.HuiCommand("Cursor Left", {key: hxd.Key.LEFT});
	static var rightCmd = new HuiCommands.HuiCommand("Cursor Right", {key: hxd.Key.RIGHT});
	static var selectUpCmd = new HuiCommands.HuiCommand("Select Up", {shift: true, key: hxd.Key.UP});
	static var selectDownCmd = new HuiCommands.HuiCommand("Select Down", {shift: true, key: hxd.Key.DOWN});
	static var selectLeftCmd = new HuiCommands.HuiCommand("Select Left", {shift: true, key: hxd.Key.LEFT});
	static var selectRightCmd = new HuiCommands.HuiCommand("Select Right", {shift: true, key: hxd.Key.RIGHT});
	static var editCmd = new HuiCommands.HuiCommand("Edit", {key: hxd.Key.ENTER});

	/** Left margin of the lines per sub sheet depth **/
	static final DEPTH_MARGIN = 8;

	static var SRC =
		<hui-cdb-table>
			<hui-table-line(this, null) id="headerLine"/>
			<hui-virtual-list id="list"/>
		</hui-cdb-table>

	public function new(sheet: cdb.Sheet, ?parent) {
		super(parent);
		initComponent();
		list.setItems(visibleList);
		list.generateItem = cast generateLine;
		list.refreshItem = cast refreshItem;

		cursorElement = new HuiCdbCursor(this);
		updateCursor();

		openSheet(sheet);
		onAfterReflow = afterReflow;

		registerCommand(HuiCommands.delete, ElementAndChildren, clearSelectedCells);
		registerCommand(upCmd, ElementAndChildren, moveCursor.bind(-1, 0));
		registerCommand(downCmd, ElementAndChildren, moveCursor.bind(1, 0));
		registerCommand(leftCmd, ElementAndChildren, moveCursor.bind(0, -1));
		registerCommand(rightCmd, ElementAndChildren, moveCursor.bind(0, 1));
		registerCommand(selectUpCmd, ElementAndChildren, moveSelectionCorner.bind(-1, 0));
		registerCommand(selectDownCmd, ElementAndChildren, moveSelectionCorner.bind(1, 0));
		registerCommand(selectLeftCmd, ElementAndChildren, moveSelectionCorner.bind(0, -1));
		registerCommand(selectRightCmd, ElementAndChildren, moveSelectionCorner.bind(0, 1));
		registerCommand(editCmd, ElementAndChildren, editCursorCell);
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
		// entries hold the previous sheet
		visibleList.resize(0);
		openSheets.clear();
		openSubSheet(null, sheetPath);

		if (sheet == null)
			return;

		buildHeader();
	}

	public function setCursor(col: Int, line: Int) {
		cursorCol = col;
		cursorLine = line;
		list.scrollToIndex(line);
		updateCursor();
	}

	function moveCursor(dLine: Int, dCol: Int) {
		selectionRects.resize(0);
		setCursor(hxd.Math.iclamp(cursorCol + dCol, 0, sheet.columns.length - 1), hxd.Math.iclamp(cursorLine + dLine, 0, sheet.lines.length - 1));
	}

	/** Move the corner opposite to the cursor of the last selection rect **/
	function moveSelectionCorner(dLine: Int, dCol: Int) {
		var r = selectionRects[selectionRects.length - 1];
		if (r == null || (cursorCol != r.x && cursorCol != r.x + r.w - 1) || (cursorLine != r.y && cursorLine != r.y + r.h - 1)) {
			r = {x: cursorCol, y: cursorLine, w: 1, h: 1};
			selectionRects.push(r);
		}
		var col = hxd.Math.iclamp((cursorCol == r.x ? r.x + r.w - 1 : r.x) + dCol, 0, sheet.columns.length - 1);
		var line = hxd.Math.iclamp((cursorLine == r.y ? r.y + r.h - 1 : r.y) + dLine, 0, sheet.lines.length - 1);
		r.x = hxd.Math.imin(cursorCol, col);
		r.y = hxd.Math.imin(cursorLine, line);
		r.w = hxd.Math.iabs(col - cursorCol) + 1;
		r.h = hxd.Math.iabs(line - cursorLine) + 1;
		list.scrollToIndex(line);
	}

	function editCursorCell() {
		var cell = getCell(visibleList[cursorLine], cursorCol);
		if (cell != null && !cell.readOnly && !cell.editing)
			cell.edit();
	}

	function rectSelectTo(line: Int, col: Int) {
		// replace the rect anchored on the cursor
		for (r in selectionRects.copy()) {
			var onCol = cursorCol == r.x || cursorCol == r.x + r.w - 1;
			var onLine = cursorLine == r.y || cursorLine == r.y + r.h - 1;
			if (onCol && onLine)
				selectionRects.remove(r);
		}

		selectionRects.push({
			x: hxd.Math.imin(cursorCol, col),
			y: hxd.Math.imin(cursorLine, line),
			w: hxd.Math.iabs(col - cursorCol) + 1,
			h: hxd.Math.iabs(line - cursorLine) + 1,
		});
	}

	/** `vline` must be the instance from visibleList, list items match by reference **/
	function getLine(vline: VirtualLine) : HuiTableLine {
		return cast list.tryGetElement(vline);
	}

	function getCell(vline: VirtualLine, col: Int) : HuiTableCell {
		return getLine(vline)?.getCell(col);
	}

	/** The line instance from openSheets matching the line path `path`, null if its sheet isn't open **/
	function getLiveLine(path: ObjectPath) : Null<VirtualLine> {
		var live : VirtualLine = null;
		for (i in 0...path.path.length) {
			var entry = openSheets.get(live);
			live = entry?.lines[path.indexes[i]];
			if (live == null || live.path.cols[i] != path.cols[i])
				return null;
		}
		return live;
	}

	function updateCursor() {
		var cell = cursorCol != -1 && cursorLine != -1 ? getCell(visibleList[cursorLine], cursorCol) : null;
		cursorElement.visible = cell != null;
		if (cell == null)
			return;

		surroundCells(cursorElement, cell, cell);
	}

	function updateRects() {
		while (selectionRectsElements.length < selectionRects.length)
			selectionRectsElements.push(new HuiCdbSelection(this));
		while (selectionRectsElements.length > selectionRects.length)
			selectionRectsElements.pop().remove();

		for (i => r in selectionRects) {
			var element = selectionRectsElements[i];

			// only the displayed lines of the rect
			var first : HuiTableLine = null;
			var last : HuiTableLine = null;
			for (lineId in r.y...r.y + r.h) {
				var line = getLine(visibleList[lineId]);
				if (line == null)
					continue;
				if (first == null)
					first = line;
				last = line;
			}

			element.visible = first != null;
			if (first != null)
				surroundCells(element, first.getCell(r.x), last.getCell(r.x + r.w - 1));
		}
	}

	// place element around the cells from topLeft to bottomRight, outset by its outline thickness (top, right, bottom, left)
	function surroundCells(element: HuiElement, topLeft: HuiTableCell, bottomRight: HuiTableCell) {
		var t = element.huiBg._outlineThickness;

		var min = globalToLocal(topLeft.localToGlobal());
		var max = globalToLocal(bottomRight.localToGlobal(new h2d.col.Point(bottomRight.calculatedWidth, bottomRight.calculatedHeight)));
		element.x = min.x - t.w;
		element.y = min.y - t.x;
		element.setWidth(Std.int(max.x - min.x + t.w + t.y));
		element.setHeight(Std.int(max.y - min.y + t.x + t.z));
	}

	function afterReflow() {
		if (sheet == null)
			return;

		for (entry in openSheets)
			computeCellSizes(entry);

		headerLine.resizeCells();
	}

	override function sync(ctx: h2d.RenderContext) {
		super.sync(ctx);
		// after the list sync, so the cells have been laid out
		updateCursor();
		updateRects();
	}

	function refreshItem(item: VirtualLine, line: HuiTableLine) {
		if (line.lineId != getLineId(item.path) || line.lineData != item.path.obj)
			line.setLine(item);
		line.resizeCells();
	}

	function generateLine(entry: VirtualLine) : HuiElement {
		// pooled lines have the cells of their sheet
		var sheet = entry.path.sheets[entry.path.sheets.length - 1];
		var line = Lambda.find(linePool, (l) -> l.vline.path.sheets[l.vline.path.sheets.length - 1] == sheet);
		linePool.remove(line);

		if (line == null) {
			line = new HuiTableLine(this, entry);
			line.pool = linePool;
		}
		line.setLine(entry);
		line.resizeCells();

		line.onPush = (e) -> {
			if (e.button == hxd.Key.MOUSE_RIGHT) {
				uiBase.contextMenu([
					{
						label: "Delete",
						click: () -> {
							getView().undo.run(actionDeleteLine(getLineId(entry.path)), true);
						}
					}
				]);
			}
		};
		return line;
	}

	function actionDeleteLine(lineId: Int) : hrt.tools.Undo.Action {
		var data = sheet.lines[lineId];
		return (isUndo) -> {
			if (!isUndo) {
				sheet.deleteLine(lineId);
			} else {
				var newLine = sheet.newLine(lineId-1);
				for (f in Reflect.fields(data)) {
					Reflect.setField(newLine, f, Reflect.field(data, f));
				}
			}
			refreshVisible();
		}
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

	static inline function getLineId(path: ObjectPath) : Int {
		return path.indexes[path.indexes.length - 1];
	}

	function getCellObjectPath(linePath: ObjectPath, column: cdb.Data.Column) : ObjectPath {
		var path = linePath.copy();
		path.push(Reflect.field(linePath.obj, column.name), -1, linePath.sheets[linePath.sheets.length - 1], column.name);
		return path;
	}

	function clearSelectedCells() {
		var rects : Array<HuiTableSelectionRect> = selectionRects;
		if (rects.length == 0) {
			if (cursorCol < 0 || cursorLine < 0)
				return;
			rects = [{x: cursorCol, y: cursorLine, w: 1, h: 1}];
		}

		var actions = [];
		for (r in rects)
			for (lineId in r.y...r.y + r.h)
				for (col in r.x...r.x + r.w) {
					var column = sheet.columns[col];
					actions.push(setDataAction(getCellObjectPath(visibleList[lineId].path, column), getDefault(column)));
				}
		getView().undo.run(hrt.tools.Undo.actionFromActions(actions), true);
	}

	/** Value of a new or cleared cell. Null for optional columns **/
	function getDefault(column: cdb.Data.Column) : Dynamic {
		return sheet.base.getDefault(column, false, sheet);
	}

	function buildHeader() {
		headerLine.cells.removeChildElements();
		headerLine.cells.addChild(headerLine.lineNoCell);

		if (sheet == null)
			return;

		for (column in sheet.columns) {
			var cell = new HuiTableCellText(column, headerLine.cells);
			cell.text.text = column.name;
			cell.readOnly = true;
		}

		headerLine.resizeCells();
	}

	function computeCellSizes(entry: SheetEntry) {
		var cellSizes = entry.cellSizes;
		cellSizes.resize(0);
		var sheet = getTableSheet(entry.path);
		if (sheet == null)
			return;
		var total = 0;
		cellSizes.push(20);
		total += 20;
		for (column in sheet.columns) {
			var size = 100;
			cellSizes.push(size);
			total += size;
		}

		// lines have the same depth as their lines array
		var prop = (innerWidth - DEPTH_MARGIN * (entry.path.path.length - 1)) / total;
		for (i => _ in cellSizes) {
			cellSizes[i] = hxd.Math.floor(cellSizes[i] * prop);
		}
	}

	/** `vline` must be the instance returned by getSheetLines, openSheets keys match by reference **/
	function openSubSheet(vline: VirtualLine, tablePath: ObjectPath) {
		var entry : SheetEntry = {path: tablePath, lines: [], cellSizes: []};
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
			openSheets.remove(vline);
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

		vlines.resize(lines.length);
		for (i => l in lines) {
			if (vlines[i] == null) {
				var p = path.copy();
				// the line replaces the lines array level
				p.pop();
				p.push(l, i, s, col);
				vlines[i] = {path: p};
				continue;
			}
			// only the last level differs between the lines of a sheet
			var p = vlines[i].path;
			p.path[p.path.length - 1] = l;
			p.indexes[p.indexes.length - 1] = i;
		}
		return vlines;
	}

	function refreshVisible() {
		visibleList.resize(0);
		// opened sub sheets are displayed right after their parent line
		function pushLines(vline: VirtualLine) {
			for (l in getSheetLines(vline)) {
				visibleList.push(l);
				if (openSheets.exists(l))
					pushLines(l);
			}
		}
		pushLines(null);

		// drops the keep lines of the removed entries
		list.setItems(visibleList);
	}


}

@:access(hrt.ui.HuiTableCell)
@:access(hrt.ui.HuiCdbTable)
class HuiTableLine extends HuiElement {
	var table: HuiCdbTable;
	var vline: VirtualLine;
	/** Key of the sheet holding the line in table.openSheets **/
	var parentLine: VirtualLine;
	var pool: Array<HuiTableLine>;
	var lineData: Dynamic;
	var lineId: Int;
	var lineNoCell: HuiTableCellText;

	static var SRC =
		<hui-table-line>
			<hui-element id="cells"/>
		</hui-table-line>

	public function new(table: HuiCdbTable, vline: VirtualLine, ?parent) {
		super(parent);
		initComponent();
		this.table = table;
		this.vline = vline;
		lineNoCell = new HuiTableCellText(null, cells);
		lineNoCell.readOnly = true;

		if (vline == null)
			return;

		var path = vline.path;
		for (column in path.sheets[path.sheets.length - 1].columns) {
			switch (column.type) {
				case TId, TString:
					new HuiTableCellText(column, cells);
				case TList:
					new HuiTableCellList(column, cells);
				default:
					var cell = new HuiTableCellText(column, cells);
					cell.readOnly = true;
			}
		}
	}

	override function onAdd() {
		super.onAdd();
		pool?.remove(this);
	}

	override function onRemove() {
		super.onRemove();
		pool?.push(this);
	}

	function getCell(col: Int) : HuiTableCell {
		// skip line number cell
		return cast cells.childElements[col + 1];
	}

	/** Uses the cell sizes of the sheet holding the line **/
	public function resizeCells() {
		var sizes = table.openSheets.get(parentLine).cellSizes;
		for (i => element in cells.childElements) {
			element.setWidth(sizes[i]);
		}
	}

	public function setLine(vline: VirtualLine) {
		this.vline = vline;
		var p = vline.path.copy();
		p.pop();
		parentLine = table.getLiveLine(p);
		lineId = HuiCdbTable.getLineId(vline.path);
		lineData = vline.path.obj;
		refreshData();
	}

	function refreshData() {
		lineNoCell.text.text = Std.string(lineId + 1);
		dom.setAttribute("margin-left", VInt(HuiCdbTable.DEPTH_MARGIN * (vline.path.path.length - 1)));
		for (element in cells.childElements) {
			(cast element : HuiTableCell).refreshData();
		}
	}
}

@:access(hrt.ui.HuiTableLine)
@:access(hrt.ui.HuiCdbTable)
class HuiTableCell extends HuiElement {
	var column: cdb.Data.Column;
	var readOnly = false;
	var editing = false;
	var line(get, never): HuiTableLine;

	public function new(column: cdb.Data.Column, ?parent) {
		super(parent);
		initComponent();
		this.column = column;

		propagateEvents = true;
		onPush = onCellPush;
		onDoubleClick = onCellDoubleClick;
		onKeyDown = (e) -> onCellKeyDown(e);
	}

	inline function get_line() return (cast parent.parent : HuiTableLine);

	/*
		Cells fill the height of the tallest cell of their line (fill-height + auto-size-height). This requires
		overflow expand : during the first layout pass, auto-size constrains each cell to the height of the previous
		cells (starting at 0), and overflow hidden would use that constraint as a max size, collapsing the line.
		With expand however, content wider than the column grows the cell, so we clamp the width after the layout and
		clip the content in drawRec, like overflow hidden does.
	*/
	override function reflow() {
		super.reflow();
		if (maxWidth == null || calculatedWidth <= maxWidth)
			return;
		calculatedWidth = maxWidth;
		// sized by h2d.Flow.reflow before the clamp. The mask doesn't clip interactives
		if (interactive != null)
			interactive.width = calculatedWidth;
		if (background != null)
			background.width = calculatedWidth;
	}

	override function drawRec(ctx: h2d.RenderContext) {
		// the mask uses the absolute position, refresh it like h2d.Flow does for overflow hidden
		if (posChanged) {
			calcAbsPos();
			for (c in children)
				c.posChanged = true;
			posChanged = false;
		}
		h2d.Mask.maskWith(ctx, this, flowCeil(calculatedWidth), flowCeil(calculatedHeight));
		super.drawRec(ctx);
		h2d.Mask.unmask(ctx);
	}

	function getObjectPath() : ObjectPath {
		return line.table.getCellObjectPath(line.vline.path, column);
	}

	function onCellPush(e: hxd.Event) {
		// ignore line number and header cells
		if (column == null || line.lineData == null)
			return;
		var col = line.cells.childElements.indexOf(this) - 1;
		if (hxd.Key.isDown(hxd.Key.SHIFT))
			line.table.rectSelectTo(line.lineId, col);
		else {
			line.table.selectionRects.resize(0);
			line.table.setCursor(col, line.lineId);
		}
	}

	function onCellDoubleClick(e: hxd.Event) {
		if (readOnly)
			return;
		edit();
	}

	/** Returns true if the key was handled **/
	function onCellKeyDown(e: hxd.Event) : Bool {
		if (!editing)
			return false;
		if (hxd.Key.isDown(hxd.Key.SHIFT) || hxd.Key.isDown(hxd.Key.CTRL) || hxd.Key.isDown(hxd.Key.ALT))
			return false;
		if (e.keyCode != hxd.Key.ENTER && e.keyCode != hxd.Key.TAB)
			return false;
		commit();
		return true;
	}

	function edit() {
		editing = true;
		dom.addClass("edit");
		// keep the line while scrolled out, so the edit isn't lost
		line.table.list.setKeepLine(line.vline, true);
	}

	function commit() {
		finishEdit();
	}

	function finishEdit() {
		editing = false;
		dom.removeClass("edit");
		line.table.list.setKeepLine(line.vline, false);
	}

	function refreshData() {}
}

@:access(hrt.ui.HuiTableLine)
@:access(hrt.ui.HuiCdbTable)
class HuiTableCellText extends HuiTableCell {
	static var SRC =
		<hui-table-cell-text>
			<hui-text id="text"/>
			<hui-text-input id="input"/>
		</hui-table-cell-text>

	public function new(column: cdb.Data.Column, ?parent) {
		super(column, parent);
		initComponent();
		input.onFocusLost = (e) -> finishEdit();
		// the input has focus while editing, so the cell doesn't receive its keys
		input.onKeyDown = (e) -> input.preventDefault = onCellKeyDown(e);
	}

	override function edit() {
		super.edit();
		input.text = text.text;
		input.focus();
		var len = input.getTextLength();
		input.cursorIndex = len;
		input.selectionRange = {start: 0, length: len};
	}

	override function commit() {
		getView().undo.run(line.table.setDataAction(getObjectPath(), input.text), true);
		super.commit();
	}

	override function refreshData() {
		if (column == null)
			return;
		var dataText : Dynamic = Reflect.getProperty(line.lineData, column.name);
		if (dataText is String) {
			text.text = dataText;
		} else {
			if (!readOnly)
				throw "Can't use CellText for non string data that are not read only";
			text.text = haxe.Json.stringify(dataText);
		}
	}
}

@:access(hrt.ui.HuiTableLine)
@:access(hrt.ui.HuiCdbTable)
class HuiTableCellList extends HuiTableCell {
	static var SRC =
		<hui-table-cell-list>
			<hui-text id="text"/>
		</hui-table-cell-list>

	public function new(column: cdb.Data.Column, ?parent) {
		super(column, parent);
		initComponent();
	}

	override function edit() {
		if (editing) {
			finishEdit();
			return;
		}
		super.edit();
		line.table.openSubSheet(line.vline, getObjectPath());
	}

	override function finishEdit() {
		super.finishEdit();
		line.table.closeSubSheet(line.vline);
	}

	override function refreshData() {
		var lines : Array<Dynamic> = Reflect.field(line.lineData, column.name);
		text.text = "[" + (lines?.length ?? 0) + "]";
	}
}

class HuiCdbSelection extends HuiElement {
	static var SRC =
		<hui-cdb-selection>
		</hui-cdb-selection>

	public function new(?parent) {
		super(parent);
		initComponent();
	}
}

class HuiCdbCursor extends HuiElement {
	static var SRC =
		<hui-cdb-cursor>
		</hui-cdb-cursor>

	public function new(?parent) {
		super(parent);
		initComponent();
	}
}

#end