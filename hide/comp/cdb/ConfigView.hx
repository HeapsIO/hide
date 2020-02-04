package hide.comp.cdb;

typedef SheetView = {
	var insert : Bool;
	var ?show : Array<String>;
	var ?edit : Array<String>;
	var sub : haxe.DynamicAccess<SheetView>;
}

typedef ConfigView = haxe.DynamicAccess<SheetView>;