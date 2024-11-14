package hide.view;

class CdbTable2 extends hide.ui.View<{}> {

    var streamTable: hide.comp.StreamTable;

	var base : cdb.Database;
	var currentSheet : cdb.Sheet;
    var root : Element;

    override function onDisplay() {
        // Allow exceptions to be displayed in the alert window
        haxe.Timer.delay(open, 10);
    }

    function open() {

        super.onDisplay();
		hide.comp.cdb.DataFiles.load();

        element.get(0).innerHTML = "";
        root = new Element("<div class='cdb2'></div>").appendTo(element);

        root.append(new Element("<p>Hello i'm a paragraph</p>"));
        streamTable = new hide.comp.StreamTable(root, null, root);
        currentSheet = getSheets()[4];
        base = currentSheet.base;

        streamTable.genTableHeader = (tr) -> {
            for (col in currentSheet.columns) {
                var th = hide.comp.StreamTable.createTableHeader(tr);
                th.innerText = col.name;
            }
        }

        streamTable.genTableRow = (index, tr) -> {
            var line = currentSheet.lines[index];
            for (col in currentSheet.columns) {
                var cell = tr.insertCell();
                cell.innerText = Reflect.getProperty(line, col.name);
            }
        }

        streamTable.getRowCounts = () -> {
            return currentSheet.lines.length;
        }

        streamTable.setTableColWidths([for (c in currentSheet.columns) "1fr"]);
        streamTable.refreshTable(15, 2000);
    }


    public function getSheets() {
		return [for( s in ide.database.sheets ) if( !s.props.hide) s];
	}

	static var _ = hide.ui.View.register(CdbTable2);
}