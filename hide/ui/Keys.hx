package hide.ui;

class Keys {

	var keys = new Map<String,Void->Void>();
	var parent : js.html.Element;
	var listeners = new Array<js.jquery.Event -> Bool>();
	var disabledStack : Int = 0;

	public function pushDisable() {
		
		disabledStack ++;
	}

	public function popDisable() {
		disabledStack--;
	}

	public function new( parent : Element ) {
		if( parent != null ) {
			this.parent = parent[0];
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

	public function processEvent( e : js.jquery.Event, config : Config ) {
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

	public function triggerKey( e : js.jquery.Event, key : String, config : Config ) {
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
				keys.get(k)();
				return true;
			}
		}
		return false;
	}

	public function register( name : String, callb : Void -> Void ) {
		keys.set(name, callb);
	}

	public static function get( e : Element ) : Keys {
		return Reflect.field(e[0], "__keys");
	}

}