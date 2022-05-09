package hide.comp;

class GlobalSeek extends Modal {
    var cdbTable: hide.view.CdbTable;

    // Seeking files is not supported yet
    public function new(?parent, cdbTable) {
        super(parent);
        this.cdbTable = cdbTable;
        element.addClass("global-seek");
		var sheets = cdbTable.getSheets();
        trace(sheets.length);
        var choices : Array<hide.comp.Dropdown.Choice> = [
            for( s in sheets ) {
                id : s.name,
                ico : null,
                text : s.name,
            }
        ];

        var d = new Dropdown(content, choices, null);

        d.onSelect = function(val) {
            for( s in sheets ) {
                if( s.name == val ) {
                    cdbTable.goto(s);
                    return;
                }
            }
        }
        d.onClose = close;
        modalClick = (_) -> close();
    }
}