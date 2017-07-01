package hide.view;

typedef ExtensionOptions = {
	?icon : String,
};

class FileTree extends hide.ui.View<{ root : String, opened : Array<String> }> {

	var tree : hide.comp.IconTree;
	var lastOpen : hide.ui.View<Dynamic>;

	function getExtension( file : String ) {
		return file.indexOf(".") < 0 ? null : EXTENSIONS.get(file.split(".").pop().toLowerCase());
	}

	override function getTitle() {
		if( state.root == "" )
			return "Resources";
		return state.root.split("/").pop();
	}

	override function onDisplay( e : Element ) {

		if( state.opened == null ) state.opened = [];

		var panel = new hide.comp.ScrollZone(e);
		tree = new hide.comp.IconTree(panel.content);
		tree.get = function(path) {
			if( path == null ) path = "";
			var basePath = ide.getPath(state.root) + path;
			var content = new Array<hide.comp.IconTree.IconTreeItem>();
			for( c in sys.FileSystem.readDirectory(basePath) ) {
				if( isIgnored(basePath,c) ) continue;
				var isDir = sys.FileSystem.isDirectory(basePath+"/"+c); 
				var ext = getExtension(c);
				var id = ( path == "" ? c : path+"/"+c );
				content.push({
					id : id, 
					text : c,
					icon : isDir ? "fa fa-folder" : (ext != null && ext.options.icon != null ? "fa fa-"+ext.options.icon : "jstree-file"),
					children : isDir,
					state : state.opened.indexOf(id) >= 0 ? { opened : true } : null
				});
			}
			content.sort(function(a,b) { if( a.children != b.children ) return a.children?-1:1; return Reflect.compare(a.text,b.text); });	
			return content;
		};
		tree.onToggle = function(path, isOpen) {
			state.opened.remove(path);
			if( isOpen ) 
				state.opened.push(path);
			saveState();
		};
		
		
		// prevent dummy mouseLeft from breaking our quickOpen feature
		var mouseLeft = false;
		var leftCount = 0;
		e.on("mouseenter", function(_) {
			mouseLeft = false;
		});
		e.on("mouseleave", function(_) {
			mouseLeft = true;
			leftCount++;
			var k = leftCount;
			if( lastOpen != null ) 
				haxe.Timer.delay(function() {
					if( !mouseLeft || leftCount != k ) return;
					lastOpen = null;
				},1000);
		});

		tree.onDblClick = onOpenFile;
		tree.init();
	}

	function onOpenFile( path : String ) {
		var fullPath = ide.getPath(state.root) + path;
		if( sys.FileSystem.isDirectory(fullPath) )
			return;
		var ext = getExtension(path);
		if( ext == null )
			return;
		var prev = lastOpen;
		lastOpen = null;
		ide.open(ext.component, { path : path }, function(c) lastOpen = c);
		if( prev != null ) prev.close();
	}
 
	function isIgnored( path : String, file : String ) {
		if( file.charCodeAt(0) == ".".code )
			return true;
		return false;
	}

	static var EXTENSIONS = new Map<String,{ component : String, options : ExtensionOptions }>();
	public static function registerExtension<T>( c : Class<hide.ui.View<T>>, extensions : Array<String>, ?options : ExtensionOptions ) {
		hide.ui.View.register(c);
		if( options == null ) options = {};
		var obj = { component : Type.getClassName(c), options : options };
		for( e in extensions )
			EXTENSIONS.set(e, obj);
		return null;
	}

	static var _ = hide.ui.View.register(FileTree);

}