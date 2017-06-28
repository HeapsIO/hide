package hide;

enum HTypeDef {
	TId;
	TInt;
	TBool;
	TFloat;
	TString;
	TAlias( name : String, t : HType );
	TArray( t : HType );
	TEither( values : Array<String> );
	TFlags( values : Array<String> );
	TFile;
	TTile;
	TDynamic;
	TStruct( fields : Array<{ name : String, t : HType }> );
	TEnum( constructors : Array<{ name : String, args : Array<{ name : String, t : HType }> }> );
}

enum HTypeProp {
	PNull; // can be null
	PIsColor; // TInt only
}

typedef HType = {
	var def : HTypeDef;
	@:optional var props : haxe.EnumFlags<HTypeProp>;
}
