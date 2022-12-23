package hide.prefab2;

typedef HideProps = {
	var icon : String;
	var name : String;
	var ?isGround : Bool;
	var ?fileSource : Array<String>;
	@:optional dynamic function allowChildren( cl : Class<hrt.prefab2.Prefab> ) : Bool;
	@:optional dynamic function allowParent( p : hrt.prefab2.Prefab ) : Bool;
	@:optional dynamic function onChildUpdate( p : hrt.prefab2.Prefab ) : Void;
	@:optional dynamic function onChildListChanged() : Void;
	@:optional dynamic function onResourceRenamed( map : (oldPath : String) -> String ) : Void;
	@:optional dynamic function hideChildren( p : hrt.prefab2.Prefab ) : Bool;
}
