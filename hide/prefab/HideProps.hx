package hide.prefab;

typedef HideProps = {
	var icon : String;
	var name : String;
	@:optional var fileSource : Array<String>;
	@:optional function allowChildren( type : String ) : Bool;
	@:optional function allowParent( p : Prefab ) : Bool;
}
