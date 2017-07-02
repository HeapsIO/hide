package golden;

extern class ContentItem {

	var parent : ContentItem;
	var contentItems : Array<ContentItem>;
	var element : Container;
	var childElementContainer : Container;

	public function addChild( config : Config.ItemConfig, ?index : Int ) : Void;
	public function on( type : String, callb : Event<ContentItem> -> Void ) : Void;
	public function off( type : String ) : Void;
}