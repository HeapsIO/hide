package hide.comp;

class Component {

	var ide : hide.Ide;
	public var name(get, never) : String;
	public var root : Element;
	public var saveDisplayKey : String;

	public function new(root) {
		ide = hide.Ide.inst;
		this.root = root;
	}

	@:final function get_name() return Type.getClassName(Type.getClass(this));

	function getDisplayState( key : String ) : Dynamic {
		if( saveDisplayKey == null )
			return null;
		var v = js.Browser.window.localStorage.getItem(saveDisplayKey + "/" + key);
		if( v == null )
			return null;
		return haxe.Json.parse(v);
	}

	function saveDisplayState( key : String, value : Dynamic ) {
		if( saveDisplayKey == null )
			return;
		js.Browser.window.localStorage.setItem(saveDisplayKey + "/" + key, haxe.Json.stringify(value));
	}

}