package golden;

@:native("GoldenLayout")
extern class Layout {


	var root : ContentItem;
	var selectedItem : ContentItem;
	var isInitialised : Bool;
	var config : Config;

	function new( config : Config ) : Void;
	function init() : Void;
	function destroy() : Void;

	function registerComponent( name : String, callb : Container -> Dynamic -> Void ) : Void;
	function on( event : String, f : Void -> Void ) : Void;

	function toConfig() : Config;

}