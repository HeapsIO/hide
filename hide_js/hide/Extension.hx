package hide;

typedef ExtensionOptions = {
	?icon : String,
	?createNew : String,
	?name : String,
}

typedef ExtensionDesc = {
	var component : String;
	var extensions : Array<String>;
	var options : ExtensionOptions;
}

class Extension {
	public static var EXTENSIONS = new Map<String, ExtensionDesc>();

	public static function registerExtension<T>( c : Class<hide.ui.View<T>>, extensions : Array<String>, ?options : ExtensionOptions ) {
		hide.ui.View.register(c);
		for (e in extensions) {
			var registered = EXTENSIONS.get(e);
			if (registered == null) {
				registered = {component: Type.getClassName(c), options: {}, extensions: extensions };
				EXTENSIONS.set(e, registered);
			}
			else {
				// Override views in projects
				registered.component = Type.getClassName(c);
			}
			if( options == null ) options = {};
			for (field in Reflect.fields(options)) {
				Reflect.setField(registered.options, field, Reflect.field(options, field));
			}
		}
		return null;
	}

	public static function getExtension( file : String ) {
		var ext = new haxe.io.Path(file).ext;
		if( ext == null ) return null;
		ext = ext.toLowerCase();
		if( ext == "json" ) {
			try {
				var obj : Dynamic = haxe.Json.parse(sys.io.File.getContent(file));
				if( obj.type != null && Std.isOfType(obj.type, String) ) {
					var e = EXTENSIONS.get("json." + obj.type);
					if( e != null ) return e;
				}
			} catch( e : Dynamic ) {
			}
		}
		return EXTENSIONS.get(ext);
	}
}