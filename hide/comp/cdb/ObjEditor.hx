package hide.comp.cdb;

class ObjEditor extends Editor {

	public dynamic function onChange(propName : String) {}

	var obj : {};

	public function new( sheet : cdb.Sheet, props, obj : {}, ?parent : Element ) {
		this.displayMode = AllProperties;
		this.obj = obj;
		var api = {
			load : function(v:Any) {
				var obj2 = haxe.Json.parse((v:String));
				for( f in Reflect.fields(obj) )
					Reflect.deleteField(obj,f);
				for( f in Reflect.fields(obj2) )
					Reflect.setField(obj, f, Reflect.field(obj2,f));
			},
			copy : function() return (haxe.Json.stringify(obj) : Any),
			save : function() throw "assert",
		};
		super(props, api);
		sheet = makePseudoSheet(sheet);
		show(sheet, parent);
	}

	override function isUniqueID( sheet : cdb.Sheet, obj : {}, id : String ) {
        // we don't know yet how to make sure that our object view
        // is the same as the object in CDB indexed data
		return true;
	}

	override function syncSheet(?base:cdb.Database, ?name:String) {
		super.syncSheet(base, name);
		currentSheet = makePseudoSheet(currentSheet);
	}

	function makePseudoSheet( sheet : cdb.Sheet ) {
		var sheetData = Reflect.copy(@:privateAccess sheet.sheet);
		sheetData.linesData = null;
		sheetData.lines = [for( i in 0...sheetData.columns.length ) obj];
		return new cdb.Sheet(sheet.base, sheetData);
	}

	override function save() {
	}

	override function changeObject(line:Line, column:cdb.Data.Column, value:Dynamic) {
		super.changeObject(line, column, value);
		onChange(column.name);
	}

}