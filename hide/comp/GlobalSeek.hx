package hide.comp;
using hide.tools.Extensions;

enum SeekMode {
    Sheets;
    LocalIds;
    GlobalIds;
}

class GlobalSeek extends Modal {
    var cdbTable: hide.view.CdbTable;

    // Seeking files is not supported yet
    public function new(?parent, cdbTable, mode: SeekMode, ?currentSheet: cdb.Sheet) {
        super(parent);
        this.cdbTable = cdbTable;
        element.addClass("global-seek");
		var sheets = cdbTable.getSheets();
        var choices : Array<hide.comp.Dropdown.Choice> = [];
        if (mode == Sheets) {
            for( s in sheets ) {
                choices.push({
                    id : s.name,
                    ico : null,
                    text : s.name,
                });
            }
        } else {
            function addSheet(s: cdb.Sheet) {
                for (i in 0...s.all.length) {
                    var l = s.all[i];
                    var id = Reflect.field(l, s.idCol.name);
                    if (l.id != null) {
                        choices.push({
                            id: '#${s.name}:$id',
                            ico: s.name,
                            text: l.disp,
                        });
                    }
                }
            }
            if (currentSheet != null && currentSheet.idCol != null) {
                addSheet(currentSheet);
            }
            if (mode == GlobalIds) {
                for( s in sheets ) {
                    if (s.idCol != null && (currentSheet == null || currentSheet.name != s.name)) {
                        addSheet(s);
                    }
                }
            }
        }

        var d = new Dropdown(content, choices, null, function(c) {
            if (c.ico == null)
                return null;
            return new Element('<p class="option-context">${c.ico}</p>');
        });

        d.onSelect = function(val) {
            for( s in sheets ) {
                if( s.name == val ) {
                    cdbTable.goto2(s, []);
                    return;
                }
            }
            if (StringTools.startsWith(val, "#") && currentSheet != null) {
                var parts = val.substr(1).split(":");
                var sname = parts[0];
                var id = parts[1];
                var s = sheets.find(s -> s.name == sname);
                cdbTable.goto2(s, [Id(s.idCol.name, id)]);
            }
        }
        d.onClose = close;
        modalClick = (_) -> close();
    }
}
