package hide.comp.cdb;

class ObjEditor extends Editor {

    public dynamic function onChange(propName : String) {}

    public function new( sheet : cdb.Sheet, props, obj : {}, ?parent : Element ) {
        var sheetData = Reflect.copy(@:privateAccess sheet.sheet);
        sheetData.lines = [for( i in 0...sheet.columns.length ) obj];
        var pseudoSheet = new cdb.Sheet(sheet.base, sheetData);
        this.displayMode = AllProperties;
        var api = {
            load : function(v:Any) {
                var obj2 = haxe.Json.parse((v:String));
                for( f in Reflect.fields(obj) )
                    Reflect.deleteField(obj,f);
                for( f in Reflect.fields(obj2) )
                    Reflect.setField(obj, f, Reflect.field(obj2,f));
            },
            copy : function() return (haxe.Json.stringify(obj) : Any),
            save : function() {},
        };
        super(pseudoSheet, props, api, parent);
    }

	override function changeObject(line:Line, column:cdb.Data.Column, value:Dynamic) {
        super.changeObject(line, column, value);
        onChange(column.name);
    }

}