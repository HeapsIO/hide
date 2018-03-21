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

class FileTree extends FileView {

	var tree : hide.comp.IconTree<String>;
	var lastOpen : hide.ui.View<Dynamic>;

	public function new(state) {
		super(state);
		if( state.path == null ) {
			ide.chooseDirectory(function(dir) {
				if( dir == null ) {
					close();
					return;
				}
				state.path = dir.split("\\").join("/")+"/";
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
		if( state.path == "" )
			return "Resources";
		if( state.path == null )
			return "";
		return super.getTitle();
	}

	override function onDisplay() {

		if( state.path == null ) return;

		var panel = new Element("<div class='hide-scroll'>").appendTo(root);
		tree = new hide.comp.IconTree(panel);
		tree.async = true;
		tree.saveDisplayKey = "FileTree:" + getPath().split("\\").join("/").substr(0,-1);
		tree.get = function(path) {
			if( path == null ) path = "";
			var basePath = getFilePath(path);
			var content = new Array<hide.comp.IconTree.IconTreeItem<String>>();
			for( c in sys.FileSystem.readDirectory(basePath) ) {
				if( isIgnored(basePath, c) ) continue;
				var fullPath = basePath + "/" + c;
				var isDir = sys.FileSystem.isDirectory(fullPath);
				var ext = getExtension(fullPath);
				var id = ( path == "" ? c : path+"/"+c );
				content.push({
					value : id,
					text : c,
					icon : "fa fa-" + (isDir ? "folder" : (ext != null && ext.options.icon != null ? ext.options.icon : "file-text")),
					children : isDir,
				});
			}
			watch(basePath, function() rebuild(),{checkDelete:true});
			content.sort(function(a,b) { if( a.children != b.children ) return a.children?-1:1; return Reflect.compare(a.text,b.text); });
			return content;
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
			if( current != null )
				tree.setSelection([current]);
			e.preventDefault();
			var newMenu = [for( e in EXTENSIONS ) if( e.options.createNew != null ) { label : e.options.createNew, click : createNew.bind(current, e) }];
			newMenu.unshift({ label : "Directory", click : createNew.bind(current, { options : { createNew : "Directory" }, extensions : null, component : null }) });
			new hide.comp.ContextMenu([
				{ label : "New..", menu:newMenu },
				{ label : "Delete", enabled : current != null, click : function() if( js.Browser.window.confirm("Delete " + current + "?") ) { onDeleteFile(current); tree.refresh(); } },
			]);
		});
		tree.onDblClick = onOpenFile;
		tree.init();
	}

	function onDeleteFile( path : String ) {
		var fullPath = getFilePath(path);
		if( sys.FileSystem.isDirectory(fullPath) ) {
			for( f in sys.FileSystem.readDirectory(fullPath) )
				onDeleteFile(path + "/" + f);
			sys.FileSystem.deleteDirectory(fullPath);
		} else
			sys.FileSystem.deleteFile(fullPath);
	}

	function getFilePath(path:String) {
		if( path == "" )
			return ide.getPath(state.path).substr(0, -1);
		return ide.getPath(state.path) + path;
	}

	function onOpenFile( path : String ) {
		var fullPath = getFilePath(path);
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
		if( basePath == null )
			basePath = "";
		var fullPath = getFilePath(basePath);
		if( !sys.FileSystem.isDirectory(fullPath) ) {
			basePath = new haxe.io.Path(basePath).dir;
			if( basePath == null ) basePath = "";
			fullPath = getFilePath(basePath);
		}

		var file = ide.ask(ext.options.createNew + " name:");
		if( file == null ) return;
		if( file.indexOf(".") < 0 && ext.extensions != null )
			file += "." + ext.extensions[0].split(".").shift();

		if( sys.FileSystem.exists(fullPath + "/" + file) ) {
			ide.error("File '" + file+"' already exists");
			createNew(basePath, ext);
			return;
		}

		// directory
		if( ext.component == null ) {
			sys.FileSystem.createDirectory(fullPath + "/" + file);
			return;
		}

		var view : hide.view.FileView = Type.createEmptyInstance(Type.resolveClass(ext.component));
		view.ide = ide;
		sys.io.File.saveBytes(fullPath + "/" + file, view.getDefaultContent());

		var fpath = basePath == "" ? file : basePath + "/" + file;
		tree.refresh(function() tree.setSelection([fpath]));
		onOpenFile(fpath);
	}

	function isIgnored( path : String, file : String ) {
		if( file.charCodeAt(0) == ".".code )
			return true;
		if( StringTools.startsWith(file, "Anim_") && file.split(".").pop().toLowerCase() == "fbx" )
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