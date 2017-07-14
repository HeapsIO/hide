package hide.view;

class FileProps {

	var props : Dynamic;

	public function new(resPath : String, path : String) {
		var parts = path.split("/");
		parts.pop();
		props = {};
		while( true ) {
			var pfile = resPath + "/" + parts.join("/") + "/props.json";
			if( sys.FileSystem.exists(pfile) ) {
				try mergeRec(props, haxe.Json.parse(sys.io.File.getContent(pfile))) catch( e : Dynamic ) js.Browser.alert(pfile+":"+e);
			}
			if( parts.length == 0 ) break;
			parts.pop();
		}
	}

	function mergeRec( dst : Dynamic, src : Dynamic ) {
		for( f in Reflect.fields(src) ) {
			var v = Reflect.field(src,f);
			var t = Reflect.field(dst,f);
			if( t == null )
				Reflect.setField(dst,f,v);
			else if( Type.typeof(t) == TObject )
				mergeRec(t, v);
		}
	}

	public function get( key : String ) : Dynamic {
		return Reflect.field(props,key);
	}

}

class FileView extends hide.ui.View<{ path : String }> {

	var extension(get,never) : String;
	var modified(default,set) : Bool;
	var props(get, null) : FileProps;
	var undo = new hide.comp.UndoHistory();

	function get_extension() {
		var file = state.path.split("/").pop();
		return file.indexOf(".") < 0 ? "" : file.split(".").pop().toLowerCase();
	}

	public function getDefaultContent() : haxe.io.Bytes {
		return null;
	}

	override function setContainer(cont) {
		super.setContainer(cont);
		registerKey("undo", function() undo.undo());
		registerKey("redo", function() undo.redo());
	}

	override function onBeforeClose() {
		if( modified && !js.Browser.window.confirm(state.path+" has been modified, quit without saving?") )
			return false;
		return super.onBeforeClose();
	}

	function get_props() {
		if( props == null ) props = new FileProps(ide.resourceDir, state.path);
		return props;
	}

	function set_modified(b) {
		if( modified == b )
			return b;
		modified = b;
		syncTitle();
		return b;
	}

	function getPath() {
		return ide.getPath(state.path);
	}

	override function getTitle() {
		var parts = state.path.split("/");
		while( parts.length > 2 ) parts.shift();
		return parts.join(" / ")+(modified?" *":"");
	}

	override function syncTitle() {
		super.syncTitle();
		haxe.Timer.delay(function() container.tab.element.attr("title",getPath()), 100);
	}

}
