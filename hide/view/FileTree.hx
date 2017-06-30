package hide.view;

class FileTree extends hide.ui.View<{ root : String }> {

	var tree : hide.comp.IconTree;

	function getPath() {
		if( haxe.io.Path.isAbsolute(state.root) )
			return state.root;
		return ide.resourceDir+"/"+state.root;
	}

	override function onDisplay( e : Element ) {
		var panel = new hide.comp.ScrollZone(e); 
		tree = new hide.comp.IconTree(panel.content);
		tree.get = function(path) {
			if( path == null ) path = "";
			var basePath = getPath() + path;
			var content = new Array<hide.comp.IconTree.IconTreeItem>();
			for( c in sys.FileSystem.readDirectory(basePath) ) {
				if( isIgnored(basePath,c) ) continue;
				var isDir = sys.FileSystem.isDirectory(basePath+"/"+c); 
				content.push({
					id : path+"/"+c, 
					text : c,
					icon : isDir ? null : "jstree-file",
					children : isDir 
				});
			}
			content.sort(function(a,b) { if( a.children != b.children ) return a.children?-1:1; return Reflect.compare(a.text,b.text); });	
			return content;
		};
		tree.init();
	}

	function isIgnored( path : String, file : String ) {
		if( file.charCodeAt(0) == ".".code )
			return true;
		return false;
	}

	static var _ = hide.ui.View.register(FileTree);

}