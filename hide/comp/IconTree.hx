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
		@:optional var loaded : Bool;
	};
	@:optional var li_attr : Dynamic;
	@:optional private var id : String; // internal usage
	@:optional private var absKey : String; // internal usage
}

class IconTree<T:{}> extends Component {

	static var UID = 0;

	var waitRefresh = new Array<Void->Void>();
	var map : Map<String, IconTreeItem<T>> = new Map();
	var revMapString : haxe.ds.StringMap<IconTreeItem<T>> = new haxe.ds.StringMap();
	var revMap : haxe.ds.ObjectMap<T, IconTreeItem<T>> = new haxe.ds.ObjectMap();
	public var allowRename : Bool;
	public var async : Bool = false;

	public dynamic function get( parent : Null<T> ) : Array<IconTreeItem<T>> {
		return [{ data : null, text : "get()", children : true }];
	}

	public dynamic function onClick( e : T ) : Void {
	}

	public dynamic function onDblClick( e : T ) : Void {
	}

	public dynamic function onToggle( e : T, isOpen : Bool ) : Void {
	}

	public dynamic function onRename( e : T, value : String ) : Bool {
		return false;
	}

	public dynamic function onAllowMove( e : T, to : T ) : Bool {
		return false;
	}

	public dynamic function onMove( e : T, to : T, index : Int ) {
	}

	function makeContent(parent:IconTreeItem<T>) {
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
				if( s != null ) c.state = { opened : s } else c.state = {};
			}
			if( !async ) {
				c.state.loaded = true;
				c.children = cast makeContent(c);
			}
		}
		return content;		
	}

	public function init() {
		(untyped root.jstree)({
			core : {
				themes: {
					name: "default-dark",
					dots: true,
					icons: true
            	},
				check_callback : function(operation, node, node_parent, value, extra) {
					if( operation == "edit" && allowRename )
						return true;
					if( operation == "rename_node" ) {
						if( node.text == value ) return true; // no change
						return onRename(map.get(node.id).data, value);
					}
					if( operation == "move_node" ) {
						if( extra.ref == null ) return true;
						return onAllowMove(map.get(node.id).data, map.get(extra.ref.id).data);
					}
					return false;
				},
				data : function(obj, callb) {
					callb.call(this, makeContent(obj.parent == null ? null : map.get(obj.id)));
				}
			},
			plugins : [ "wholerow", "dnd" ],
		});
		root.on("click.jstree", function (event) {
			var node = new Element(event.target).closest("li");
   			var i = map.get(node[0].id);
			onClick(i.data);
		});
		root.on("dblclick.jstree", function (event) {
			var node = new Element(event.target).closest("li");
   			var i = map.get(node[0].id);
			if( allowRename ) {
				editNode(i.data);
				return;
			}
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
		root.on("move_node.jstree", function(event, e) {
			onMove(map.get(e.node.id).data, e.parent == "#" ? null : map.get(e.parent).data, e.position);
		});
	}

	function getRev( o : T ) {
		if( Std.is(o, String) )
			return revMapString.get(cast o);
		return revMap.get(o);
	}

	public function getElement(e : T) : Element {
		var v = getRev(e);
		var el = (untyped root.jstree)('get_node', v.id, true);
		return el;
	}

	public function editNode( e : T ) {
		var n = getRev(e).id;
		(untyped root.jstree)('edit',n);
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
		if(objects.length > 0) {
			revealNode(objects[0]);
		}
	}

	public function refresh( ?onReady : Void -> Void ) {		
		if( onReady != null ) waitRefresh.push(onReady);
		(untyped root.jstree)('refresh',true);
	}

	public function getSelection() : Array<T> {
		var ids : Array<String> = (untyped root.jstree)('get_selected');
		return [for( id in ids ) map.get(id).data];
	}

	public function revealNode(e : T) {
		var v = getRev(e);
		(untyped root.jstree)('_open_to', v.id).focus();
		var el = (untyped root.jstree)('get_node', v.id, true)[0];
		el.scrollIntoViewIfNeeded();
	}

	public function searchFilter( filter : String ) {
		if( filter == "" ) filter = null;
		if( filter != null ) filter = filter.toLowerCase();

		var lines = root.find(".jstree-node");
		lines.removeClass("filtered");
		if( filter != null ) {
			for( t in lines ) {
				if( t.textContent.toLowerCase().indexOf(filter) < 0 )
					t.classList.add("filtered");
			}
			while( lines.length > 0 ) {
				lines = lines.filter(".list").not(".filtered").prev();
				lines.removeClass("filtered");
			}
		}
	}
}