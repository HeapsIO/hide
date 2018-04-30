package hide.comp.cdb;

class ObjEditor extends Editor {

    public function new( root : Element, sheet : cdb.Sheet, obj : {} ) {
        var sheetData = Reflect.copy(@:privateAccess sheet.sheet);
        sheetData.lines = [obj];
        var pseudoSheet = new cdb.Sheet(sheet.base, sheetData);
        this.displayMode = Properties;
        super(root, pseudoSheet);
    }

}