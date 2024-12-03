package golden;

@:native("GoldenLayout")
extern class Layout {


	var root : ContentItem;
	var selectedItem : ContentItem;
	var isInitialised : Bool;
	var config : Config;

	function new( config : Config, parent : js.html.Element = null ) : Void;
	function init() : Void;
	function destroy() : Void;
	function updateSize(width: Int = null, height: Int = null) : Void;

	function registerComponent( name : String, callb : Container -> Dynamic -> Void ) : Void;
	function on( event : String, f : Void -> Void ) : Void;

	function toConfig() : Config;

}