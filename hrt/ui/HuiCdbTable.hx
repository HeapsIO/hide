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
class HuiCdbTable extends HuiElement {
	var sheet: cdb.Sheet;

	var visibleList : Array<VisibleEntry> = [];
	var cellSizes: Array<Int> = [];
	var linePool: Array<HuiTableLine> = [];
	var selectionRects: Array<HuiTableSelectionRect> = [];
	var cursorCol = -1;
	var cursorLine = -1;
	var cursorElement: HuiCdbCursor;

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
		updateCursor();
	}

	function getLine(lineId: Int) : HuiTableLine {
		return cast list.tryGetElement(visibleList[lineId]);
	}

	function getCell(lineId: Int, col: Int) : HuiTableCell {
		return getLine(lineId)?.getCell(col);
	}

	function updateCursor() {
		var cell = cursorCol != -1 && cursorLine != -1 ? getCell(cursorLine, cursorCol) : null;
		cursorElement.visible = cell != null;
		if (cell == null)
			return;

		var t = cursorElement.huiBg._outlineThickness;

		var pos = globalToLocal(cell.localToGlobal());
		cursorElement.x = pos.x - t.w;
		cursorElement.y = pos.y - t.x;
		cursorElement.setWidth(Std.int(cell.calculatedWidth + t.w + t.y));
		cursorElement.setHeight(Std.int(cell.calculatedHeight + t.x + t.z));
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
	}

	function refreshItem(item: VisibleEntry, line: HuiTableLine) {
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

		line.onClick = (e) -> {
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

	function buildHeader() {
		headerLine.removeChildElements();
		headerLine.addChild(headerLine.lineNoCell);

		if (sheet == null)
			return;

		for (column in sheet.columns) {
			var cell = new HuiTableCellText(column.name, headerLine);
			cell.text.text = column.name;
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
		visibleList.resize(0);

		if (sheet != null) {
			for (i in 0...sheet.lines.length) {
				visibleList.push({lineId: i});
			}
		}

		list.refresh();
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

	public function new(table: HuiCdbTable, ?parent) {
		super(parent);
		initComponent();
		this.table = table;
		lineNoCell = new HuiTableCellText(null, this);

		if (table.sheet == null)
			return;

		for (column in table.sheet.columns) {
			switch (column.type) {
				case TId, TString:
					new HuiTableCellText(column.name, this);
				default:
					var cell = new HuiTableCellText(column.name, this);
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
		return cast childElements[col + 1];
	}

	public function resizeCells(sizes: Array<Int>) {
		for (i => element in childElements) {
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
		for (element in childElements) {
			(cast element : HuiTableCell).refreshData();
		}
	}
}

@:access(hrt.ui.HuiTableLine)
class HuiTableCell extends HuiElement {
	var column: String;
	var readOnly = false;
	var line(get, never): HuiTableLine;

	public function new(column: String, ?parent) {
		super(parent);
		initComponent();
		this.column = column;

		propagateEvents = true;
		onClick = onCellClick;
	}

	inline function get_line() return (cast parent : HuiTableLine);

	function onCellClick(e: hxd.Event) {
		// ignore line number and header cells
		if (column == null || line.lineData == null)
			return;
		line.table.setCursor(line.childElements.indexOf(this) - 1, line.lineId);
	}

	function refreshData() {}
}

@:access(hrt.ui.HuiTableLine)
class HuiTableCellText extends HuiTableCell {
	static var SRC =
		<hui-table-cell-text>
			<hui-text id="text"/>
		</hui-table-cell-text>

	public function new(column: String, ?parent) {
		super(column, parent);
		initComponent();
	}

	override function refreshData() {
		if (column == null)
			return;
		text.text = haxe.Json.stringify(Reflect.getProperty(line.lineData, column));
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