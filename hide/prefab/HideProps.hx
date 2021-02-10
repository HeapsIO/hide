package hide.prefab;

typedef HideProps = {
	var icon : String;
	var name : String;
	@:optional var hideChildren : Bool;
	@:optional var fileSource : Array<String>;
	@:optional dynamic function allowChildren( type : String ) : Bool;
	@:optional dynamic function allowParent( p : hrt.prefab.Prefab ) : Bool;
	@:optional dynamic function onChildUpdate( p : hrt.prefab.Prefab ) : Void;
	@:optional dynamic function onChildListChanged() : Void;
	@:optional dynamic function onResourceRenamed( map : (oldPath : String) -> String ) : Void;
}
