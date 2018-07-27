package hide.prefab;

enum PropType {
	PInt( ?min : Int, ?max : Int );
	PFloat( ?min : Float, ?max : Float );
	PVec( n : Int, ?min : Float, ?max : Float );
	PBool;
	PTexture;
	PChoice( choices : Array<String> );
	PFile( exts : Array<String> );
	PEnum( e : Enum<Dynamic>);
	PUnsupported( debug : String );
}

typedef PropDef = {
	name : String,
	t : PropType,
	?def: Dynamic,
	?disp: String
};
