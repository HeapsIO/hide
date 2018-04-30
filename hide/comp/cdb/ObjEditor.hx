package hide.comp.cdb;

class ObjEditor extends Editor {

    public function new( root : Element, sheet : cdb.Sheet, obj : {} ) {
        var sheetData = Reflect.copy(@:privateAccess sheet.sheet);
        sheetData.lines = [for( i in 0...sheet.columns.length ) obj];
        var pseudoSheet = new cdb.Sheet(sheet.base, sheetData);
        this.displayMode = AllProperties;
        super(root, pseudoSheet);
    }

}