package hide.comp;

typedef IconTreeItem = {
	var id : String;
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

	var waitRefresh = new Array<Void->Void>();

	public dynamic function get( id : String ) : Array<IconTreeItem> {
		return [{ id : id+"0", text : "get()", children : true }];
	}

	public dynamic function onClick( id : String ) : Void {
	}

	public dynamic function onDblClick( id : String ) : Void {
	}

	public dynamic function onToggle( id : String, isOpen : Bool ) : Void {
	}

	public function init() {
		(untyped root.jstree)({
			core : {
				themes: {
					name: "default-dark",
					dots: true,
					icons: true
            	},
				data : function(obj, callb) {
					var parent = obj.parent == null ? null : obj.id;
					var content : Array<IconTreeItem> = get(parent);
					for( c in content )
						if( c.state == null ) {
							var s = getDisplayState((parent == null ? "" : parent + "/") + c.id);
							if( s ) c.state = { opened : true };
						}
					callb.call(this,content);
				}
			},
			plugins : [ "wholerow" ],
		});
		root.on("click.jstree", function (event) {
			var node = new Element(event.target).closest("li");
   			var data = node[0].id;
			onClick(data);
		});
		root.on("dblclick.jstree", function (event) {
			var node = new Element(event.target).closest("li");
   			var data = node[0].id;
			onDblClick(data);
		});
		root.on("open_node.jstree", function(event, e) {
			saveDisplayState(e.node.id, true);
			onToggle(e.node.id, true);
		});
		root.on("close_node.jstree", function(event,e) {
			saveDisplayState(e.node.id, false);
			onToggle(e.node.id, false);
		});
		root.on("refresh.jstree", function(_) {
			var old = waitRefresh;
			waitRefresh = [];
			for( f in old ) f();
		});
	}

	public function getCurrentOver() : Null<String> {
		var id = root.find(":focus").attr("id");
		if( id != null )
			id = id.substr(0, -7); // remove _anchor
		return id;
	}

	public function setSelection( ids : Array<String> ) {
		(untyped root.jstree)('deselect_all');
		(untyped root.jstree)('select_node',ids);
	}

	public function refresh( ?onReady : Void -> Void ) {
		if( onReady != null ) waitRefresh.push(onReady);
		(untyped root.jstree)('refresh',true);
	}

	public function getSelection() : Array<String> {
		return (untyped root.jstree)('get_selected');
	}

}