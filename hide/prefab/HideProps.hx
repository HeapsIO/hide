package hide.prefab;

typedef HideProps = {
	var icon : String;
	var name : String;
	@:optional var fileSource : Array<String>;
	@:optional dynamic function allowChildren( type : String ) : Bool;
	@:optional dynamic function allowParent( p : Prefab ) : Bool;
	@:optional dynamic function onChildUpdate( p : Prefab ) : Void;
}
