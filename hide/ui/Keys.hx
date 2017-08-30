package hide.ui;

class Keys {

	var config : Props;
	var keys = new Map<String,Void->Void>();

	public function new( config : Props ) {
		this.config = config;
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
		if( e.keyCode >= 'A'.code && e.keyCode <= 'Z'.code )
			parts.push(String.fromCharCode(e.keyCode));
		else if( e.keyCode >= 96 && e.keyCode <= 105 )
			parts.push(String.fromCharCode('0'.code + e.keyCode - 96));
		else if( e.keyCode == ' '.code )
			parts.push("Space");
		else if( e.keyCode == 13 )
			parts.push("Enter");
		else if( e.keyCode == 27 )
			parts.push("Esc");
		else if( e.keyCode == 16 || e.keyCode == 17 || e.keyCode == 18 ) {
			// alt-ctrl-shift
		} else {
			//trace(e.key + "=" + e.keyCode+" (" + String.fromCharCode(e.keyCode) + ")");
			if( e.key != "" )
				parts.push(e.key);
			else
				return;
		}

		var key = parts.join("-");
		var callb = keys.get(key);
		if( callb != null ) {
			callb();
			e.stopPropagation();
			e.preventDefault();
		}
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