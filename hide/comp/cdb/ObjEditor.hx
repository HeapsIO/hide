package hide.comp.cdb;

class ObjEditor extends Editor {

	public var fileView : hide.view.FileView;

	var obj : {};
	var structureWasChanged = false;
	var fileReference : String;

	public function new( sheet : cdb.Sheet, props, obj : {}, fileReference, ?parent : Element ) {
		this.displayMode = AllProperties;
		this.obj = obj;
		this.fileReference = fileReference;

		// track changes in columns and props (structure changes made within local editor)
		function makeStructSign() {
			var sheets = [for( s in sheet.base.sheets ) Reflect.copy(@:privateAccess s.sheet)];
			for( s in sheets ) {
				s.separators = null;
				s.lines = null;
				s.linesData = null;
			}
			return ide.makeSignature(haxe.Serializer.run(sheets)).substr(0,16);
		}

		var api = {
			load : function(v:Any) {
				var obj2 = haxe.Json.parse((v:String).substr(16));
				for( f in Reflect.fields(obj) )
					Reflect.deleteField(obj,f);
				for( f in Reflect.fields(obj2) )
					Reflect.setField(obj, f, Reflect.field(obj2,f));
			},
			copy : function() return ((makeStructSign() + haxe.Json.stringify(obj)) : Any),
			save : function() {
				// allow save in case structure was changed
				ide.saveDatabase();
			}
		};
		super(props, api);
		sheet = makePseudoSheet(sheet);
		show(sheet, parent);
	}

	override function beginChanges( ?structure ) {
		if( structure && fileView != null ) {
			/*
				We are about to change structure, but our prefab will not see its data changed...
				Let's save first our file and reload it in DataFiles so the changes gets applied to it
			*/
			if( fileView.modified ) {
				fileView.save();
				@:privateAccess DataFiles.reload();
			}
			structureWasChanged = true;
		}
		super.beginChanges(structure);
	}

	override function endChanges() {
		super.endChanges();
		if( structureWasChanged && changesDepth == 0 ) {
			structureWasChanged = false;
			// force reload if was changed on disk because of structural change
			@:privateAccess if( fileView.currentSign == null || fileView.currentSign != fileView.makeSign() ) {
				fileView.modified = false;
				fileView.onFileChanged(false);
			}
		}
	}

	override function show(sheet:cdb.Sheet, ?parent:Element) {
		super.show(sheet, parent);
		element.addClass("cdb-obj-editor");
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
		sheetData.separators = [0];
		sheetData.props = { separatorTitles: [fileReference] };
		var s = new cdb.Sheet(sheet.base, sheetData);
		s.realSheet = sheet;
		return s;
	}

	override function changeObject(line:Line, column:cdb.Data.Column, value:Dynamic) {
		super.changeObject(line, column, value);
		onChange(column.name);
	}

	public dynamic function onChange(propName : String) {}

}