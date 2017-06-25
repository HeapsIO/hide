package golden;

extern class ContentItem {

	var parent : ContentItem;
	var contentItems : Array<ContentItem>;

	public function addChild( config : Config.ItemConfig ) : Void;

}