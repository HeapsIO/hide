package hide.comp;

class Component {

	var ide : hide.Ide;
	public var componentName(get, never) : String;
	public var element(default,null) : Element;
	public var saveDisplayKey : String;

	function new(parent:Element,el:Element) {
		ide = hide.Ide.inst;
		if( el == null )
			el = new Element('<div>');
		this.element = el;
		if( parent != null )
			parent.append(element);
	}

	public function remove() {
		element.remove();
	}

	@:final function get_componentName() return Type.getClassName(Type.getClass(this));

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

	function removeDisplayState( key : String ) {
		if( saveDisplayKey == null )
			return;
		js.Browser.window.localStorage.removeItem(saveDisplayKey + "/" + key);
	}

}