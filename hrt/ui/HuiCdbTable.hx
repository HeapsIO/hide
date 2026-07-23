package hrt.ui;

#if hui

typedef VisibleEntry = {
	lineId: Int,
};

class HuiCdbTable extends HuiElement {
	var sheet: cdb.Sheet;

	var visibleList : Array<VisibleEntry> = [];
	var cellSizes: Array<Int> = [];

	static var SRC =
		<hui-cdb-table>
			<hui-table-line id="headerLine"/>
			<hui-virtual-list id="list"/>
		</hui-cdb-table>

	public function new(?parent) {
		super(parent);
		initComponent();
		list.setItems(visibleList);
		list.generateItem = cast generateLine;

		openSheet(try hide.Ide.inst.database.getSheet("main") ?? null catch(e) null);
		onAfterReflow = afterReflow;

	}

	public function openSheet(sheet: cdb.Sheet) {
		this.sheet = sheet;

		computeCellSizes();
		buildHeader();
		refreshVisible();
	}

	function afterReflow() {
		computeCellSizes();

		headerLine.resizeCells(cellSizes);
	}

	function generateLine(entry: VisibleEntry) : HuiElement {
		var lineData = sheet.lines[entry.lineId];
		var line = new HuiTableLine();

		var lineNoCell = new HuiTableCell(line);
		new HuiText(Std.string(entry.lineId + 1), lineNoCell);


		for (column in sheet.columns) {
			var cell = new HuiTableCell(line);
			var data = haxe.Json.stringify(Reflect.getProperty(lineData, column.name));
			new HuiText(data, cell);
		}
		line.resizeCells(cellSizes);

		line.onClick = (e) -> {
			uiBase.contextMenu([
				{
					label: "Delete",
					click: () -> {
						getView().undo.run(actionDeleteLine(entry.lineId), true);
					}
				}
			]);
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

		if (sheet == null)
			return;

		// line n°
		var cell = new HuiTableCell(headerLine);

		for (column in sheet.columns) {
			var cell = new HuiTableCell(headerLine);
			new HuiText(column.name, cell);
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
		trace(innerWidth);
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

class HuiTableLine extends HuiElement {
	public function resizeCells(sizes: Array<Int>) {
		for (i => element in childElements) {
			element.setWidth(sizes[i]);
		}
	}
}

class HuiTableCell extends HuiElement {

}

#end