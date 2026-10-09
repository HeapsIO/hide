package hrt.ui;

#if hui

typedef VisibleEntry = {
	lineId: Int,
};

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

	var visibleList : Array<VisibleEntry> = [];
	var cellSizes: Array<Int> = [];
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

	static var SRC =
		<hui-cdb-table>
			<hui-table-line(this) id="headerLine"/>
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

		// pooled lines have the previous sheet's columns
		list.clear();
		linePool.resize(0);

		if (sheet == null)
			return;

		computeCellSizes();
		buildHeader();
		refreshVisible();
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
		var cell = getCell(cursorLine, cursorCol);
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

	function getLine(lineId: Int) : HuiTableLine {
		return cast list.tryGetElement(visibleList[lineId]);
	}

	function getCell(lineId: Int, col: Int) : HuiTableCell {
		return getLine(lineId)?.getCell(col);
	}

	function getCellFromObjectPath(path: cdb.Sheet.ObjectPath) : Null<HuiTableCell> {
		if (path.sheets[0] != sheet)
			return null;
		for (i => c in sheet.columns)
			if (c.name == path.cols[1])
				return getCell(path.indexes[0], i);
		return null;
	}

	function updateCursor() {
		var cell = cursorCol != -1 && cursorLine != -1 ? getCell(cursorLine, cursorCol) : null;
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
				var line = getLine(lineId);
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

		computeCellSizes();

		headerLine.resizeCells(cellSizes);
	}

	override function sync(ctx: h2d.RenderContext) {
		super.sync(ctx);
		// after the list sync, so the cells have been laid out
		updateCursor();
		updateRects();
	}

	function refreshItem(item: VisibleEntry, line: HuiTableLine) {
		var lineData = sheet.lines[item.lineId];
		if (line.lineId != item.lineId || line.lineData != lineData)
			line.setLine(item.lineId, lineData);
		line.resizeCells(cellSizes);
	}

	function generateLine(entry: VisibleEntry) : HuiElement {
		var lineData = sheet.lines[entry.lineId];
		var line = linePool.pop();

		if (line == null) {
			line = new HuiTableLine(this);
			line.pool = linePool;
		}
		line.setLine(entry.lineId, lineData);
		line.resizeCells(cellSizes);

		line.onPush = (e) -> {
			if (e.button == hxd.Key.MOUSE_RIGHT) {
				uiBase.contextMenu([
					{
						label: "Delete",
						click: () -> {
							getView().undo.run(actionDeleteLine(entry.lineId), true);
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

	function setDataAction(path: cdb.Sheet.ObjectPath, newData: Dynamic) : hrt.tools.Undo.Action {
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
			getCellFromObjectPath(path)?.refreshData();
			refreshVisible();
		}
	}

	function getCellObjectPath(lineId: Int, column: cdb.Data.Column) : cdb.Sheet.ObjectPath {
		var lineData = sheet.lines[lineId];
		var path = new cdb.Sheet.ObjectPath();
		// TODO : handle subtables
		path.push(lineData, lineId, sheet, null);
		path.push(Reflect.field(lineData, column.name), -1, sheet, column.name);
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
					actions.push(setDataAction(getCellObjectPath(lineId, column), getDefault(column)));
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

		headerLine.resizeCells(cellSizes);
	}

	function computeCellSizes() {
		cellSizes.resize(0);
		var total = 0;
		cellSizes.push(20);
		total += 20;
		for (column in sheet.columns) {
			var size = 100;
			cellSizes.push(size);
			total += size;
		}

		var prop = innerWidth / total;
		for (i => _ in cellSizes) {
			cellSizes[i] = hxd.Math.floor(cellSizes[i] * prop);
		}
	}

	function refreshVisible() {
		// reuse the entries, they are the list keys of the displayed lines
		visibleList.resize(sheet != null ? sheet.lines.length : 0);
		for (i in 0...visibleList.length) {
			if (visibleList[i] == null)
				visibleList[i] = {lineId: i};
			visibleList[i].lineId = i;
		}

		// drops the keep lines of the removed entries
		list.setItems(visibleList);
	}


}

@:access(hrt.ui.HuiTableCell)
@:access(hrt.ui.HuiCdbTable)
class HuiTableLine extends HuiElement {
	var table: HuiCdbTable;
	var pool: Array<HuiTableLine>;
	var lineData: Dynamic;
	var lineId: Int;
	var lineNoCell: HuiTableCellText;
	var subEditor: HuiElement;

	static var SRC =
		<hui-table-line>
			<hui-element id="cells"/>
		</hui-table-line>

	public function new(table: HuiCdbTable, ?parent) {
		super(parent);
		initComponent();
		this.table = table;
		lineNoCell = new HuiTableCellText(null, cells);
		lineNoCell.readOnly = true;

		if (table.sheet == null)
			return;

		for (column in table.sheet.columns) {
			switch (column.type) {
				case TId, TString:
					new HuiTableCellText(column, cells);
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

	function openSubEditor(cell: HuiTableCell) {
		if (subEditor != null)
			closeSubEditor();
		subEditor = cell.getEditor();
		if (subEditor != null)
			addChild(subEditor);
	}

	function closeSubEditor() {
		onSubEditorClosed();
		subEditor?.remove();
		subEditor = null;
	}

	dynamic function onSubEditorClosed() {}

	function getVisibleEntry() : VisibleEntry {
		return table.visibleList[lineId];
	}

	function getCell(col: Int) : HuiTableCell {
		// skip line number cell
		return cast cells.childElements[col + 1];
	}

	public function resizeCells(sizes: Array<Int>) {
		for (i => element in cells.childElements) {
			element.setWidth(sizes[i]);
		}
	}

	public function setLine(lineId: Int, lineData: Dynamic) {
		this.lineId = lineId;
		this.lineData = lineData;
		refreshData();
	}

	function refreshData() {
		lineNoCell.text.text = Std.string(lineId + 1);
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

	function getObjectPath() : cdb.Sheet.ObjectPath {
		return line.table.getCellObjectPath(line.lineId, column);
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

	function hasEditor() : Bool {
		return false;
	}

	function getEditor() : HuiElement {
		return null;
	}

	function openEditor() {
		line.openSubEditor(this);
	}

	function edit() {
		editing = true;
		dom.addClass("edit");
		// keep the line while scrolled out, so the edit isn't lost
		line.table.list.setKeepLine(line.getVisibleEntry(), true);
	}

	function commit() {
		finishEdit();
	}

	function finishEdit() {
		editing = false;
		dom.removeClass("edit");
		line.table.list.setKeepLine(line.getVisibleEntry(), false);
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