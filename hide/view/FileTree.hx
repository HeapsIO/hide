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
	var ignorePatterns : Array<EReg> = [];

	public function new(state) {
		super(state);

		var exclPatterns : Array<String> = ide.currentConfig.get("filetree.excludes", []);
		for(pat in exclPatterns)
			ignorePatterns.push(new EReg(pat, "i"));

		if( state.path == null ) {
			ide.chooseDirectory(function(dir) {
				if( dir == null ) {
					close();
					return;
				}
				state.path = dir.split("\\").join("/")+"/";
				saveState();
				rebuild();
			},true);
		}

		keys.register("search", function() tree.openFilter());
	}

	override function canSave() {
		return false;
	}

	static function getExtension( file : String ) {
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

	override function getTitle() {
		if( state.path == "" )
			return "Resources";
		if( state.path == null )
			return "";
		return super.getTitle();
	}

	override function onFileChanged(wasDeleted:Bool, rebuildView:Bool = true) {
	}

	override function onDisplay() {

		if( state.path == null ) return;

		var panel = new Element("<div class='hide-scroll'>").appendTo(element);
		tree = new hide.comp.IconTree(null,panel);
		tree.async = true;
		tree.allowRename = true;
		tree.saveDisplayKey = saveDisplayKey;
		tree.element.addClass("small");
		tree.get = function(path) {
			if( path == null ) path = "";
			var basePath = getFilePath(path);
			var content = new Array<hide.comp.IconTree.IconTreeItem<String>>();
			for( c in sys.FileSystem.readDirectory(basePath) ) {
				var fullPath = basePath + "/" + c;
				if( isIgnored(fullPath) ) continue;
				var isDir = sys.FileSystem.isDirectory(fullPath);
				var ext = getExtension(fullPath);
				var id = ( path == "" ? c : path+"/"+c );
				content.push({
					value : id,
					text : c,
					icon : "ico ico-" + (isDir ? "folder" : (ext != null && ext.options.icon != null ? ext.options.icon : "file-text")),
					children : isDir,
				});
			}
			watch(basePath, function() rebuild(),{checkDelete:true});
			content.sort(function(a,b) { if( a.children != b.children ) return a.children?-1:1; return Reflect.compare(a.text,b.text); });
			return content;
		};

		tree.onRename = doRename;

		element.contextmenu(function(e) {
			var current = tree.getCurrentOver();
			if( current != null )
				tree.setSelection([current]);
			e.preventDefault();
			var allowedNew : Array<String> = config.get("filetree.allowednew");
			function allowed( ext : String ) return allowedNew.indexOf(ext) >= 0 || allowedNew.indexOf("*") >= 0;
			var newMenu = [for( e in EXTENSIONS ) if( e.options.createNew != null && Lambda.exists(e.extensions, allowed) ) {
				label : e.options.createNew,
				click : createNew.bind(current, e),
				icon : e.options.icon,
			}];
			if( allowed("dir") )
				newMenu.unshift({
					label : "Directory",
					click : createNew.bind(current, { options : { createNew : "Directory" }, extensions : null, component : null }),
					icon : "folder",
				});
			new hide.comp.ContextMenu([
				{ label : "New..", menu:newMenu },
				{ label : "Collapse", click : tree.collapseAll },
				{ label : "", isSeparator: true },
				{ label : "Copy Path", enabled : current != null, click : function() { ide.setClipboard(current); } },
				{ label : "Open in Explorer", enabled : current != null, click : function() { onExploreFile(current); } },
				{ label : "", isSeparator: true },
				{ label : "Clone", enabled : current != null, click : function() {
						try {
							if (onCloneFile(current)) {
								tree.refresh();
							}
						} catch (e : Dynamic) {
							js.Browser.window.alert(e);
						}
					} },
				{ label : "Rename", enabled : current != null, click : function() {
					try {
						onRenameFile(current);
					} catch (e : Dynamic) {
						js.Browser.window.alert(e);
					}
					} },
				{ label : "Move", enabled : current != null, click : function() {
					ide.chooseDirectory(function(dir) {
						doRename(current, "/"+dir+"/"+current.split("/").pop());
					});
				}},
				{ label : "Delete", enabled : current != null, click : function() {
					if( js.Browser.window.confirm("Delete " + current + "?") ) {
						onDeleteFile(current);
						tree.refresh();
					}
				}},
			]);
		});
		tree.onDblClick = onOpenFile;
		tree.init();
	}

	function onRenameFile( path : String ) {
		var newFilename = ide.ask("New name:", path.substring( path.lastIndexOf("/") + 1 ));

		while ( newFilename != null && sys.FileSystem.exists(ide.getPath(newFilename))) {
			newFilename = ide.ask("This file already exists. Another new name:");
		}
		if (newFilename == null) {
			return false;
		}

		doRename(path, newFilename);
		return true;
	}

	function doRename(path:String, name:String) {
		var isDir = sys.FileSystem.isDirectory(ide.getPath(path));
		if( isDir ) ide.fileWatcher.pause();
		var ret = onRenameRec(path, name);
		if( isDir ) ide.fileWatcher.resume();
		return ret;
	}

	function onRenameRec(path:String, name:String) {

		var parts = path.split("/");
		parts.pop();
		for( n in name.split("/") ) {
			if( n == ".." )
				parts.pop();
			else
				parts.push(n);
		}
		var newPath = name.charAt(0) == "/" ? name.substr(1) : parts.join("/");

		if( newPath == path )
			return false;

		if( sys.FileSystem.exists(ide.getPath(newPath)) ) {
			function addPath(path:String,rand:String) {
				var p = path.split(".");
				if( p.length > 1 )
					p[p.length-2] += rand;
				else
					p[p.length-1] += rand;
				return p.join(".");
			}
			if( path.toLowerCase() == newPath.toLowerCase() ) {
				// case change
				var rand = "__tmp"+Std.random(10000);
				onRenameRec(path, "/"+addPath(path,rand));
				onRenameRec(addPath(path,rand), name);
			} else {
				if( !ide.confirm(newPath+" already exists, invert files?") )
					return false;
				var rand = "__tmp"+Std.random(10000);
				onRenameRec(path, "/"+addPath(path,rand));
				onRenameRec(newPath, "/"+path);
				onRenameRec(addPath(path,rand), name);
			}
			return false;
		}

		var isDir = sys.FileSystem.isDirectory(ide.getPath(path));
		var wasRenamed = false;
		var isSVNRepo = sys.FileSystem.exists(ide.projectDir+"/.svn") || js.node.ChildProcess.spawnSync("svn",["info"], { cwd : ide.resourceDir }).status == 0; // handle not root dirs
		if( isSVNRepo ) {
			if( js.node.ChildProcess.spawnSync("svn",["--version"]).status != 0 ) {
				if( isDir && !ide.confirm("Renaming a SVN directory, but 'svn' system command was not found. Continue ?") )
					return false;
			} else {
				var cwd = Sys.getCwd();
				Sys.setCwd(ide.resourceDir);
				var code = Sys.command("svn",["rename",path,newPath]);
				Sys.setCwd(cwd);
				if( code == 0 )
					wasRenamed = true;
				else {
					if( !ide.confirm("SVN rename failure, perform file rename ?") )
						return false;
				}
			}
		}
		if( !wasRenamed )
			sys.FileSystem.rename(ide.getPath(path), ide.getPath(newPath));

		var changed = false;
		function filter(p:String) {
			if( p == null )
				return null;
			if( p == path ) {
				changed = true;
				return newPath;
			}
			if( p == "/"+path ) {
				changed = true;
				return "/"+newPath;
			}
			if( isDir ) {
				if( StringTools.startsWith(p,path+"/") ) {
					changed = true;
					return newPath + p.substr(path.length);
				}
				if( StringTools.startsWith(p,"/"+path+"/") ) {
					changed = true;
					return "/"+newPath + p.substr(path.length+1);
				}
			}
			return p;
		}

		function filterContent(content:Dynamic) {
			var visited = new Array<Dynamic>();
			function browseRec(obj:Dynamic) : Dynamic {
				switch( Type.typeof(obj) ) {
				case TObject:
					if( visited.indexOf(obj) >= 0 ) return null;
					visited.push(obj);
					for( f in Reflect.fields(obj) ) {
						var v : Dynamic = Reflect.field(obj, f);
						v = browseRec(v);
						if( v != null ) Reflect.setField(obj, f, v);
					}
				case TClass(Array):
					if( visited.indexOf(obj) >= 0 ) return null;
					visited.push(obj);
					var arr : Array<Dynamic> = obj;
					for( i in 0...arr.length ) {
						var v : Dynamic = arr[i];
						v = browseRec(v);
						if( v != null ) arr[i] = v;
					}
				case TClass(String):
					return filter(obj);
				default:
				}
				return null;
			}
			for( f in Reflect.fields(content) ) {
				var v = browseRec(Reflect.field(content,f));
				if( v != null ) Reflect.setField(content,f,v);
			}
		}
		ide.filterPrefabs(function(p:hrt.prefab.Prefab) {
			changed = false;
			p.source = filter(p.source);
			var h = p.getHideProps();
			if( h.onResourceRenamed != null )
				h.onResourceRenamed(filter);
			else {
				filterContent(p);
			}
			return changed;
		});

		ide.filterProps(function(content:Dynamic) {
			changed = false;
			filterContent(content);
			return changed;
		});

		changed = false;
		var tmpSheets = [];
		for( sheet in ide.database.sheets ) {
			if( sheet.props.dataFiles != null && sheet.lines == null ) {
				// we already updated prefabs, no need to load data files
				tmpSheets.push(sheet);
				@:privateAccess sheet.sheet.lines = [];
			}
			for( c in sheet.columns ) {
				switch( c.type ) {
				case TFile:
					for( o in sheet.getLines() ) {
						var v : Dynamic = filter(Reflect.field(o, c.name));
						if( v != null ) Reflect.setField(o, c.name, v);
					}
				default:
				}
			}
		}
		if( changed ) {
			ide.saveDatabase();
			hide.comp.cdb.Editor.refreshAll(true);
		}
		for( sheet in tmpSheets )
			@:privateAccess sheet.sheet.lines = null;

		var dataDir = new haxe.io.Path(path);
		if( dataDir.ext != "dat" ) {
			dataDir.ext = "dat";
			var dataPath = dataDir.toString();
			if( sys.FileSystem.isDirectory(ide.getPath(dataPath)) ) {
				var destPath = new haxe.io.Path(name);
				destPath.ext = "dat";
				onRenameRec(dataPath, destPath.toString());
			}
		}

		return true;
	}

	public static function exploreFile(path : String) {
		var fullPath = sys.FileSystem.absolutePath(path);

		switch(Sys.systemName()) {
			case "Windows": Sys.command("explorer.exe /select," + fullPath);
			case "Mac":	Sys.command("open " + haxe.io.Path.directory(fullPath));
			default: throw "Exploration not implemented on this platform";
		}
	}

	function onExploreFile( path : String ) {
		exploreFile(getFilePath(path));
	}

	function onCloneFile( path : String ) {
		var sourcePath = getFilePath(path);
		var nameNewFile = ide.ask("New filename:", new haxe.io.Path(sourcePath).file);
		if (nameNewFile == null || nameNewFile.length == 0) {
			return false;
		}

		var targetPath = new haxe.io.Path(sourcePath).dir + "/" + nameNewFile;
		if ( sys.FileSystem.exists(targetPath) ) {
			throw "File already exists";
		}

		if( sys.FileSystem.isDirectory(sourcePath) ) {
			sys.FileSystem.createDirectory(targetPath + "/");
			for( f in sys.FileSystem.readDirectory(sourcePath) ) {
				sys.io.File.saveBytes(targetPath + "/" + f, sys.io.File.getBytes(sourcePath + "/" + f));
			}
		} else {
			var extensionNewFile = getExtension(targetPath);

			if (extensionNewFile == null) {
				var extensionSourceFile = getExtension(sourcePath).extensions[0];
				if (extensionSourceFile != null) {
					targetPath =  targetPath + "." + extensionSourceFile;
				}
			}
			sys.io.File.saveBytes(targetPath, sys.io.File.getBytes(sourcePath));
		}
		return true;
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
			return false;
		var ext = getExtension(fullPath);
		if( ext == null )
			return false;
		ide.openFile(fullPath);
		tree.closeFilter();
		return true;
	}

	public function revealNode( path : String ) {
		var folders = path.split("/");
		var currentFolder = "";
		function _revealNode() {
			if( folders.length == 0 ) {
				tree.setSelection([path]);
				tree.revealNode(currentFolder);
				return;
			}
			if( currentFolder.length > 0 ) currentFolder += "/";
			currentFolder += folders.shift();
			tree.openNodeAsync(currentFolder, _revealNode);
		}
		_revealNode();
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
		view.state = { path : basePath+"/"+file };
		sys.io.File.saveBytes(fullPath + "/" + file, view.getDefaultContent());

		var fpath = basePath == "" ? file : basePath + "/" + file;
		tree.refresh(function() tree.setSelection([fpath]));
		onOpenFile(fpath);
	}

	function isIgnored( fullpath : String ) {
		for(pat in ignorePatterns) {
			if(pat.match(fullpath))
				return true;
		}
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

	static var _ = hide.ui.View.register(FileTree, { width : 350, position : Left });

}