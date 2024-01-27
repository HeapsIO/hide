package hide.ui;


typedef EntryDoc = {name: String, category: String};
typedef Entry = {doc: EntryDoc, cb: Void->Void};

class Keys {

	var keys = new Map<String,Entry>();
	var parent : Element.HTMLElement;
	var listeners = new Array<Element.Event -> Bool>();
	var disabledStack : Int = 0;

	public function pushDisable() {
		disabledStack ++;
	}

	public function popDisable() {
		disabledStack--;
		if (disabledStack < 0) {
			trace("Missmatched push/pop disable !!!!");
			disabledStack = 0;
		}
	}

	public function new( parent : Element ) {
		if( parent != null ) {
			this.parent = parent.get(0);
			parent.attr("haskeys","true");
			if( this.parent != null ) Reflect.setField(this.parent,"__keys",this);
		}
	}

	public function remove() {
		if( parent != null ) {
			Reflect.deleteField(parent,"__keys");
			parent.removeAttribute("haskeys");
		}
	}

	public function clear() {
		listeners = [];
		keys = [];
	}

	public function addListener( l ) {
		listeners.push(l);
	}

	public function processEvent( e : Element.Event, config : Config ) {
		if (disabledStack > 0)
			return false;
		var parts = [];
		if( e.altKey )
			parts.push("Alt");
		if( e.ctrlKey )
			parts.push("Ctrl");
		if( e.shiftKey )
			parts.push("Shift");
		if( e.keyCode == hxd.Key.ALT || e.keyCode == hxd.Key.SHIFT || e.keyCode == hxd.Key.CTRL ) {
			//
		} else {
			var name = hxd.Key.getKeyName(e.keyCode);
			if( name != null )
				parts.push(name);
			else if( e.key != "" )
				parts.push(e.key);
			else
				parts.push(""+e.keyCode);
		}

		var key = parts.join("-");
		if( triggerKey(e, key, config) ) {
			e.stopPropagation();
			e.preventDefault();
			return true;
		}

		return false;
	}

	public function triggerKey( e : Element.Event, key : String, config : Config ) {
		for( l in listeners )
			if( l(e) )
				return true;
		for( k in keys.keys() ) {
			var keyCode = config.get("key."+k);
			if( keyCode == null ) {
				trace("Key not defined " + k);
				continue;
			}
			if( keyCode == key ) {
				keys.get(k).cb();
				return true;
			}
		}
		return false;
	}

	public function register( name : String, ?doc : EntryDoc, callb : Void -> Void ) {
		keys.set(name, {doc: doc, cb:callb});
	}

	public static function get( e : Element ) : Keys {
		return Reflect.field(e.get(0), "__keys");
	}

	public function sortDocCategories(config: Config) : Map<String, Array<{name: String, shortcut: String}>> {
		var ret = new Map();
		for (k => v in keys) {
			var shortcut = config.get("key."+k);
			if (shortcut != null) {
				var name = null;
				var category = "none";
				if (v.doc != null) {
					name = v.doc.name;
					category = v.doc.category;
				}
				if (name == null) {
					name = k;
					var parts = name.split(".");
					name = parts[parts.length-1];
					name = name.charAt(0).toUpperCase() + name.substr(1);
				}
				if (!ret.exists(category)) {
					ret.set(category, new Array<{name: String, shortcut: String}>());
				}
				var arr = ret.get(category);
				arr.push({name: name, shortcut: shortcut});
			}
		}

		return ret;
	}

}