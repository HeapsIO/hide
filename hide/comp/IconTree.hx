package hide.comp;

typedef IconTreeItem = {
	var id : Dynamic;
	var text : String;
	@:optional var children : Bool;
	@:optional var icon : String;
	@:optional var state : {
		@:optional var opened : Bool;
		@:optional var selected : Bool;
		@:optional var disabled : Bool;
	};
}

class IconTree extends Component {

	public var tree : Element;

	public dynamic function get( id : Dynamic ) : Array<IconTreeItem> {
		return [{ id : id+"0", text : "get()", children : true }];
	}

	public function init() {
		tree = (untyped root.jstree)({
			core : {
				themes: {
					name: "default-dark",
					dots: true,
					icons: true
            	},
				data : function(obj,callb) {
					callb.call(this,get(obj.parent == null ? null : obj.id));
				}
			}
		});
	}
	
}