package hide.view;

typedef ExtensionOptions = {
	?icon : String,
	?createNew : String,
};

typedef ExtensionDesc = {
	var component : String;
	var extensions : Array<String>;
	var options : ExtensionOptions;
}

class FileTree extends hide.ui.View<{ root : String, opened : Array<String> }> {

	var tree : hide.comp.IconTree;
	var lastOpen : hide.ui.View<Dynamic>;

	public function new(state) {
		super(state);
		if( state.root == null ) {
			ide.chooseDirectory(function(dir) {
				if( dir == null ) {
					close();
					return;
				}
				state.root = dir.split("\\").join("/")+"/";
				saveState();
				rebuild();
			});
		}
	}

	static function getExtension( file : String ) {
		var ext = new haxe.io.Path(file).ext;
		if( ext == null ) return null;
		ext = ext.toLowerCase();
		if( ext == "json" ) {
			try {
				var obj : Dynamic = haxe.Json.parse(sys.io.File.getContent(file));
				if( obj.type != null && Std.is(obj.type, String) ) {
					var e = EXTENSIONS.get("json." + obj.type);
					if( e != null ) return e;
				}
			} catch( e : Dynamic ) {
			}
		}
		return EXTENSIONS.get(ext);
	}

	override function getTitle() {
		if( state.root == "" )
			return "Resources";
		if( state.root == null )
			return "";
		return state.root;
	}

	override function onDisplay() {

		if( state.root == null ) return;

		if( state.opened == null ) state.opened = [];

		var panel = new Element("<div class='hide-scroll'>").appendTo(root);
		tree = new hide.comp.IconTree(panel);
		tree.get = function(path) {
			if( path == null ) path = "";
			var basePath = ide.getPath(state.root) + path;
			var content = new Array<hide.comp.IconTree.IconTreeItem>();
			for( c in sys.FileSystem.readDirectory(basePath) ) {
				if( isIgnored(basePath, c) ) continue;
				var fullPath = basePath + "/" + c;
				var isDir = sys.FileSystem.isDirectory(fullPath);
				var ext = getExtension(fullPath);
				var id = ( path == "" ? c : path+"/"+c );
				content.push({
					id : id,
					text : c,
					icon : "fa fa-" + (isDir ? "folder" : (ext != null && ext.options.icon != null ? ext.options.icon : "file-text")),
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
		root.on("mouseenter", function(_) {
			mouseLeft = false;
		});
		root.on("mouseleave", function(_) {
			mouseLeft = true;
			leftCount++;
			var k = leftCount;
			if( lastOpen != null )
				haxe.Timer.delay(function() {
					if( !mouseLeft || leftCount != k ) return;
					lastOpen = null;
				},1000);
		});
		root.contextmenu(function(e) {
			var current = tree.getCurrentOver();
			if( current == null ) return;
			tree.setSelection([current]);
			e.preventDefault();
			new hide.comp.ContextMenu([
				{ label : "New..", menu:[for( e in EXTENSIONS ) if( e.options.createNew != null ) { label : e.options.createNew, click : createNew.bind(current, e) }] },
				{ label : "Delete", click : function() if( js.Browser.window.confirm("Delete " + current + "?") ) { onDeleteFile(current); tree.refresh(); } },
			]);
		});
		tree.onDblClick = onOpenFile;
		tree.init();
	}

	function onDeleteFile( path : String ) {
		var fullPath = getPath(path);
		if( sys.FileSystem.isDirectory(fullPath) ) {
			for( f in sys.FileSystem.readDirectory(fullPath) )
				onDeleteFile(path + "/" + f);
			sys.FileSystem.deleteDirectory(fullPath);
		} else
			sys.FileSystem.deleteFile(fullPath);
	}

	function getPath(path:String) {
		return ide.getPath(state.root) + path;
	}

	function onOpenFile( path : String ) {
		var fullPath = getPath(path);
		if( sys.FileSystem.isDirectory(fullPath) )
			return;
		var ext = getExtension(fullPath);
		if( ext == null )
			return;
		var prev = lastOpen;
		lastOpen = null;
		ide.openFile(fullPath, function(c) {
			if( prev != null ) prev.close();
			lastOpen = c;
		});
	}

	function createNew( basePath : String, ext : ExtensionDesc ) {
		var fullPath = getPath(basePath);
		if( !sys.FileSystem.isDirectory(fullPath) ) {
			basePath = new haxe.io.Path(basePath).dir;
			fullPath = getPath(basePath);
		}
		var file = js.Browser.window.prompt(ext.options.createNew + " name:");
		if( file == null ) return;
		if( file.indexOf(".") < 0 ) file += "." + ext.extensions[0].split(".").shift();

		if( sys.FileSystem.exists(fullPath + "/" + file) ) {
			js.Browser.alert("File '" + file+"' already exists");
			createNew(basePath, ext);
			return;
		}

		var view : hide.view.FileView = Type.createEmptyInstance(Type.resolveClass(ext.component));
		sys.io.File.saveBytes(fullPath + "/" + file, view.getDefaultContent());
		tree.refresh(function() tree.setSelection([basePath + "/" + file]));
		onOpenFile(basePath+"/"+file);
	}

	function isIgnored( path : String, file : String ) {
		if( file.charCodeAt(0) == ".".code )
			return true;
		return false;
	}

	static var EXTENSIONS = new Map<String,ExtensionDesc>();
	public static function registerExtension<T>( c : Class<hide.ui.View<T>>, extensions : Array<String>, ?options : ExtensionOptions ) {
		hide.ui.View.register(c);
		if( options == null ) options = {};
		var obj = { component : Type.getClassName(c), options : options, extensions : extensions };
		for( e in extensions )
			EXTENSIONS.set(e, obj);
		return null;
	}

	static var _ = hide.ui.View.register(FileTree, { width : 200, position : Left });

}