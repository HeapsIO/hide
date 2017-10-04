package hide.comp;

typedef IconTreeItem<T> = {
	var data : T;
	var text : String;
	@:optional var children : Bool;
	@:optional var icon : String;
	@:optional var state : {
		@:optional var opened : Bool;
		@:optional var selected : Bool;
		@:optional var disabled : Bool;
	};
	@:optional private var id : String; // internal usage
	@:optional private var absKey : String; // internal usage
}

class IconTree<T:{}> extends Component {

	static var UID = 0;

	var waitRefresh = new Array<Void->Void>();
	var map : Map<String, IconTreeItem<T>> = new Map();
	var revMapString : haxe.ds.StringMap<IconTreeItem<T>> = new haxe.ds.StringMap();
	var revMap : haxe.ds.ObjectMap<T, IconTreeItem<T>> = new haxe.ds.ObjectMap();

	public var onMenu : Void -> Void;

	public dynamic function get( parent : Null<T> ) : Array<IconTreeItem<T>> {
		return [{ data : null, text : "get()", children : true }];
	}

	public dynamic function onClick( e : T ) : Void {
	}

	public dynamic function onDblClick( e : T ) : Void {
	}

	public dynamic function onToggle( e : T, isOpen : Bool ) : Void {
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
					var parent = obj.parent == null ? null : map.get(obj.id);
					var content : Array<IconTreeItem<T>> = get(parent == null ? null : parent.data);
					for( c in content ) {
						var key = (parent == null ? "" : parent.absKey + "/") + c.text;
						if( c.absKey == null ) c.absKey = key;
						c.id = "titem$" + (UID++);
						map.set(c.id, c);
						if( Std.is(c.data, String) )
							revMapString.set(cast c.data, c);
						else
							revMap.set(c.data, c);
						if( c.state == null ) {
							var s = getDisplayState(key);
							if( s != null ) c.state = { opened : s };
						}
					}
					callb.call(this,content);
				}
			},
			plugins : [ "wholerow" ],
		});
		root.on("click.jstree", function (event) {
			var node = new Element(event.target).closest("li");
   			var i = map.get(node[0].id);
			onClick(i.data);
		});
		root.on("dblclick.jstree", function (event) {
			var node = new Element(event.target).closest("li");
   			var i = map.get(node[0].id);
			onDblClick(i.data);
		});
		root.on("open_node.jstree", function(event, e) {
			var i = map.get(e.node.id);
			saveDisplayState(i.absKey, true);
			onToggle(i.data, true);
		});
		root.on("close_node.jstree", function(event,e) {
			var i = map.get(e.node.id);
			saveDisplayState(i.absKey, false);
			onToggle(i.data, false);
		});
		root.on("refresh.jstree", function(_) {
			var old = waitRefresh;
			waitRefresh = [];
			for( f in old ) f();
		});
	}

	function getRev( o : T ) {
		if( Std.is(o, String) )
			return revMapString.get(cast o);
		return revMap.get(o);
	}

	public function getCurrentOver() : Null<T> {
		var id = root.find(":focus").attr("id");
		if( id == null )
			return null;
		var i = map.get(id.substr(0, -7)); // remove _anchor
		return i == null ? null : i.data;
	}

	public function setSelection( objects : Array<T> ) {
		(untyped root.jstree)('deselect_all');
		var ids = [for( o in objects ) { var v = getRev(o); if( v != null ) v.id; }];
		(untyped root.jstree)('select_node',ids);
	}

	public function refresh( ?onReady : Void -> Void ) {
		if( onReady != null ) waitRefresh.push(onReady);
		(untyped root.jstree)('refresh',true);
	}

	public function getSelection() : Array<T> {
		var ids : Array<String> = (untyped root.jstree)('get_selected');
		return [for( id in ids ) map.get(id).data];
	}

}