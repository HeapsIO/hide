package golden;

extern class ContentItem {

	var type : Config.ItemType;
	var parent : ContentItem;
	var contentItems : Array<ContentItem>;
	var element : js.jquery.JQuery;
	var childElementContainer : Container;
	var config : Config.ItemConfig;
	var header : Header;
	var id : String;

	var __view : Dynamic;

	public function addChild( config : Config.ItemConfig, ?index : Int ) : Void;
	public function on( type : String, callb : Event<ContentItem> -> Void ) : Void;
	public function off( type : String ) : Void;
	public function replaceChild( c : ContentItem, config : Config.ItemConfig ) : Void;
	public function getItemsByFilter( f : ContentItem -> Bool ) : Array<ContentItem>;
	public function getActiveContentItem() : ContentItem;
	public function setActiveContentItem( item : ContentItem ) : Void;
	public function getItemsById(id : String) : Array<ContentItem>;
	public function remove() : Void ;
}