package hide.prefab;

typedef HideProps = {
	var icon : String;
	var name : String;
	@:optional var fileSource : Array<String>;
	@:optional dynamic function allowChildren( type : String ) : Bool;
	@:optional dynamic function allowParent( p : Prefab ) : Bool;
	@:optional dynamic function onChildUpdate( p : Prefab ) : Void;
	@:optional dynamic function onChildRemoved( p : Prefab ) : Void;
	@:optional dynamic function onResourceRenamed( map : (oldPath : String) -> String ) : Void;
}
