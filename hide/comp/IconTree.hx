package hide.comp;

typedef IconTreeItem<T> = {
	var value : T;
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
	@:optional var a_attr : Dynamic;
	@:optional @:noCompletion var id : String; // internal usage
	@:optional @:noCompletion var absKey : String; // internal usage
}

class IconTree<T:{}> extends Component {

	static var UID = 0;

	var waitRefresh = new Array<Void->Void>();
	var map : Map<String, IconTreeItem<T>> = new Map();
	var values : Map<String, T> = new Map();
	var revMapString : haxe.ds.StringMap<IconTreeItem<T>> = new haxe.ds.StringMap();
	var revMap : haxe.ds.ObjectMap<T, IconTreeItem<T>> = new haxe.ds.ObjectMap();
	public var allowRename : Bool;
	public var async : Bool = false;
	public var autoOpenNodes = true;
	public var filter(default,null) : String;

	public function new(?parent,?el) {
		super(parent,el);
		element.addClass("tree");
	}

	public dynamic function get( parent : Null<T> ) : Array<IconTreeItem<T>> {
		return [{ value : null, text : "get()", children : true }];
	}

	public dynamic function onClick( e : T, evt: Dynamic) : Void {
	}

	public dynamic function onDblClick( e : T ) : Bool {
		return false;
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

	public dynamic function applyStyle( e : T, element : Element ) {
	}

	function getValue( c : IconTreeItem<T> ) {
		if( c.value != null )
			return c.value;
		return values.get(c.id);
	}

	function getVal( id : String ) : T {
		var c = map.get(id);
		if( c == null ) return null; // id is loading ?
		return getValue(c);
	}

	function makeContent(parent:IconTreeItem<T>) {
		var content : Array<IconTreeItem<T>> = get(parent == null ? null : getValue(parent));
		for( c in content ) {
			var key = (parent == null ? "" : parent.absKey + "/") + c.text;
			if( c.absKey == null ) c.absKey = key;
			c.id = "titem__" + (UID++);
			map.set(c.id, c);
			if( Std.is(c.value, String) )
				revMapString.set(cast c.value, c);
			else {
				revMap.set(c.value, c);
				values.set(c.id, c.value);
				c.value = null;
			}
			if( c.state == null ) {
				var s = getDisplayState(key);
				if( s != null ) c.state = { opened : s } else c.state = {};
			}
			if( !async && c.children ) {
				c.state.loaded = true;
				c.children = cast makeContent(c);
			}
		}
		return content;
	}

	public function init() {
		var inInit = true;
		(element:Dynamic).jstree({
			core : {
				dblclick_toggle: false,
				animation: 50,
				themes: {
					name: "default-dark",
					dots: true,
					icons: true
            	},
				check_callback : function(operation, node, node_parent, value, extra) {
					if( operation == "edit" && allowRename )
						return true;
					if(!map.exists(node.id))  // Can happen on drag from foreign tree
						return false;
					if( operation == "rename_node" ) {
						if( node.text == value ) return true; // no change
						return onRename(getVal(node.id), value);
					}
					if( operation == "move_node" ) {
						if( extra.ref == null ) return true;
						return onAllowMove(getVal(node.id), getVal(extra.ref.id));
					}
					return false;
				},
				data : function(obj, callb) {
					if( !inInit && checkRemoved() )
						return;
					callb.call(this, makeContent(obj.parent == null ? null : map.get(obj.id)));
				}
			},
			plugins : [ "dnd", "changed" ],
		});
		element.on("click.jstree", function (event) {
			var node = new Element(event.target).closest("li");
			if(node == null || node.length == 0) return;
   			var v = getVal(node[0].id);
			if( v == null ) return;
			onClick(v, event);
		});
		element.on("dblclick.jstree", function (event) {
			// ignore dblclick on open/close arrow
			if( event.target.className.indexOf("jstree-ocl") >= 0 )
				return;

			var node = new Element(event.target).closest("li");
			if( node == null || node.length == 0 ) return;
   			var v = getVal(node[0].id);
			if(onDblClick(v))
				return;
			if( allowRename ) {
				// ignore rename on icon
				if( event.target.className.indexOf("jstree-icon") >= 0 )
					return;
				editNode(v);
				return;
			}
		});
		element.on("open_node.jstree", function(event, e) {
			var i = map.get(e.node.id);
			if( filter == null ) saveDisplayState(i.absKey, true);
			onToggle(getValue(i), true);
		});
		element.on("close_node.jstree", function(event,e) {
			var i = map.get(e.node.id);
			if( filter == null ) saveDisplayState(i.absKey, false);
			onToggle(getValue(i), false);
		});
		element.on("refresh.jstree", function(_) {
			var old = waitRefresh;
			waitRefresh = [];
			if( searchBox != null ) {
				element.append(searchBox);
				searchFilter(this.filter);
			}
			for( f in old ) f();
		});
		element.on("move_node.jstree", function(event, e) {
			onMove(getVal(e.node.id), e.parent == "#" ? null : getVal(e.parent), e.position);
		});
		element.on('ready.jstree', function () {
			/* var lis = element.find("li");
			for(li in lis) {
				var item = map.get(li.id);
				if(item != null)
					applyStyle(getValue(item), new Element(li));
			} */
		});
		element.on('changed.jstree', function (e, data) {
			var nodes: Array<Dynamic> = data.changed.deselected;
			for(id in nodes) {
				var item = getVal(id);
				var el = getElement(item);
				applyStyle(item, el);
			}
		});
		element.on("rename_node.jstree", function(e, data) {
			var item = getVal(data.node.id);
			var el = getElement(item);
			applyStyle(item, el);
		});
		element.on("after_open.jstree", function(event, data) {
			var lis = new Element(event.target).find("li");
			for(li in lis) {
				var item = map.get(li.id);
				if(item != null)
					applyStyle(getValue(item), new Element(li));
			}
		});
		element.keydown(function(e:js.jquery.Event) {
			if( e.keyCode == 27 ) closeFilter();
		});
		inInit = false;
	}

	function checkRemoved() {
		if( element == null || element[0].parentNode == null )
			return true;
		if( !js.Browser.document.contains(element[0]) ) {
			dispose();
			return true;
		}
		return false;
	}

	public function dispose() {
		(element:Dynamic).jstree("detroy");
		element.remove();
		for( f in Reflect.fields(this) )
			try Reflect.deleteField(this,f) catch(e:Dynamic) {}
	}

	function getRev( o : T ) {
		if( Std.is(o, String) )
			return revMapString.get(cast o);
		return revMap.get(o);
	}

	public function getElement(e : T) : Element {
		var v = getRev(e);
		if(v == null)
			return null;
		var el = (element:Dynamic).jstree('get_node', v.id, true);
		return el;
	}

	public function editNode( e : T ) {
		var n = getRev(e).id;
		(element:Dynamic).jstree('edit',n);
	}

	public function getCurrentOver() : Null<T> {
		var id = element.find(":focus").attr("id");
		if( id == null )
			return null;
		var i = map.get(id.substr(0, -7)); // remove _anchor
		return i == null ? null : getValue(i);
	}

	public function setSelection( objects : Array<T> ) {
		(element:Dynamic).jstree('deselect_all');
		var ids = [for( o in objects ) { var v = getRev(o); if( v != null ) v.id; }];
		(element:Dynamic).jstree('select_node', ids, false, !autoOpenNodes); // Don't auto-open parent
		if(autoOpenNodes)
		for(obj in objects)
			revealNode(obj);
	}

	public function refresh( ?onReady : Void -> Void ) {
		map = new Map();
		revMap = new haxe.ds.ObjectMap();
		revMapString = new haxe.ds.StringMap();
		values = new Map();
		if( onReady != null ) waitRefresh.push(onReady);
		(element:Dynamic).jstree('refresh',true);
	}

	public function getSelection() : Array<T> {
		var ids : Array<String> = (element:Dynamic).jstree('get_selected');
		return [for( id in ids ) getVal(id)];
	}

	public function collapseAll() {
		(element:Dynamic).jstree('close_all');
	}

	public function openNode(e: T) {
		var v = getRev(e);
		if(v == null) return;
		(element:Dynamic).jstree('_open_to', v.id);
	}

	public function revealNode(e : T) {
		openNode(e);
		var el = getElement(e);
		if(el != null)
			(el[0] : Dynamic).scrollIntoViewIfNeeded();
	}

	public function searchFilter( flt : String ) {
		this.filter = flt;
		if( filter == "" ) filter = null;
		if( filter != null ) {
			filter = filter.toLowerCase();
			// open all nodes that might contain data
			for( id => v in map )
				if( v.text.toLowerCase().indexOf(filter) >= 0 )
					(element:Dynamic).jstree('_open_to', id);
		}
		var lines = element.find(".jstree-node");
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

	var searchBox : Element;

	public function closeFilter() {
		if( searchBox != null ) {
			searchBox.remove();
			searchBox = null;
		}
		if( filter != null ) {
			searchFilter(null);
			var sel = getSelection();
			refresh(() -> setSelection(sel));
		}
	}

	public function openFilter() {
		if( async ) {
			async = false;
			refresh(openFilter);
			return;
		}
		if( searchBox == null ) {
			searchBox = new Element("<div>").addClass("searchBox").prependTo(element);
			new Element("<input type='text'>").appendTo(searchBox).keydown(function(e) {
				if( e.keyCode == 27 ) {
					searchBox.find("i").click();
					return;
				}
			}).keyup(function(e) {
				var elt = e.getThis();
				function filter() {
					if( searchBox == null ) return;
					var val = StringTools.trim(elt.val());
					if( val == "" ) val = null;
					if( val != this.filter ) searchFilter(val);
				}
				var val = elt.val();
				haxe.Timer.delay(filter, val.length == 1 ? 500 : 100);
			});
			new Element("<i>").addClass("fa fa-times-circle").appendTo(searchBox).click(function(_) {
				closeFilter();
			});
		}
		searchBox.show();
		searchBox.find("input").focus().select();
	}


}