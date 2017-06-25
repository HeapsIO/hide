package golden;

@:native("GoldenLayout")
extern class Layout {


	var root : ContentItem;
	var selectedItem : ContentItem;

	function new( config : Config ) : Void;
	function init() : Void;

	function registerComponent( name : String, callb : Container -> Dynamic -> Void ) : Void;

}