package hide.ui;

class Keys {

	var config : Props;
	var keys = new Map<String,Void->Void>();
	var listeners = new Array<js.jquery.Event -> Bool>();
	// allow a sub set to hierarchise and prevent leaks wrt refresh
	public var subKeys : Array<Keys> = [];

	public function new( config : Props ) {
		this.config = config;
	}

	public function addListener( l ) {
		listeners.push(l);
	}

	public function processEvent( e : js.jquery.Event ) {
		var active = js.Browser.document.activeElement;
		if( active != null && active.nodeName == "INPUT" ) return;

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
		if( triggerKey(e, key) ) {
			e.stopPropagation();
			e.preventDefault();
		}
	}

	public function triggerKey( e : js.jquery.Event, key : String ) {
		for( s in subKeys )
			if( s.triggerKey(e, key) )
				return true;
		for( l in listeners )
			if( l(e) )
				return true;
		var callb = keys.get(key);
		if( callb != null ) {
			callb();
			return true;
		}
		return false;
	}

	public function register( name : String, callb : Void -> Void ) {
		var key = config.get("key." + name);
		if( key == null ) {
			trace("Key not defined " + name);
			return;
		}
		keys.set(key, callb);
	}

}