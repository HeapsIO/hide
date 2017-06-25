package golden;

typedef Config = {
	@:optional var settings: {
		@:optional var hasHeaders : Bool;
		@:optional var constrainDragToContainer : Bool;
		@:optional var reorderEnabled : Bool;
		@:optional var selectionEnabled : Bool;
		@:optional var popoutWholeStack : Bool;
		@:optional var blockedPopoutsThrowError : Bool;
		@:optional var closePopoutsOnUnload : Bool;
		@:optional var showPopoutIcon : Bool;
		@:optional var showMaximiseIcon : Bool;
		@:optional var showCloseIcon : Bool;
	};
	@:optional var dimensions: {
		@:optional var borderWidth: Int;
		@:optional var minItemHeight : Int;
		@:optional var minItemWidth : Int;
		@:optional var headerHeight : Int;
		@:optional var dragProxyWidth : Int;
		@:optional var dragProxyHeight : Int;
	};
	@:optional var labels: {
		@:optional var close: String;
		@:optional var maximise: String;
		@:optional var minimise: String;
		@:optional var popout: String;
	};
	@:optional var content: Array<ItemConfig>;
};

@:enum abstract ItemType(String) {
	var Row = "row";
	var Column = "column";
	var Stack = "stack";
	var Component = "component";
}

typedef ItemConfig = {
	var type: ItemType;
	@:optional var componentName : String;
	@:optional var componentState : Dynamic;
	@:optional var content : Array<ItemConfig>;
	@:optional var id : String;
	@:optional var width : Int;
	@:optional var height: Int;
	@:optional var isClosable : Bool;
	@:optional var title : String;
	@:optional var activeItemIndex : Int;
}
