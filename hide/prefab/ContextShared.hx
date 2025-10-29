package hide.prefab;

class ContextShared extends hrt.prefab.ContextShared.ContextSharedBase {
	#if editor
	public var editor : hide.comp.SceneEditor;
	public var scene : hide.comp.Scene;
	public var editorDisplay : Bool;

	public function new(?path : String, ?root2d: h2d.Object = null, ?root3d: h3d.scene.Object = null, isInstance: Bool = true) {
		super(path, root2d, root3d, isInstance);
	}

	override function onError( e : Dynamic ) {
		hide.Ide.inst.error(e);
	}

	override function loadShader( path : String ) {
		return hide.Ide.inst.shaderLoader.loadSharedShader(path);
	}

	override function loadModel( path : String, opt = false ) {
		scene.setCurrent();
		if( opt ) hxd.res.Loader.currentInstance.load(path); // will raise hxd.res.NotFound
		return scene.loadModel(path);
	}

	override function loadAnimation( path : String ) {
		return scene.loadAnimation(path);
	}

	override function loadTexture( path : String, async : Bool = false ) {
		return scene.loadTexture("",path, async);
	}

	override function loadBakedFile():Null<haxe.io.Bytes> {
		var path = new haxe.io.Path(currentPath);
		path.ext = "bake";
		return try sys.io.File.getBytes(hide.Ide.inst.getPath(path.toString())) catch( e : Dynamic ) null;
	}

	override function saveBakedFile( bytes ) {
		var path = new haxe.io.Path(currentPath);
		path.ext = "bake";
		var file = hide.Ide.inst.getPath(path.toString());
		if( bytes == null )
			try sys.FileSystem.deleteFile(file) catch( e : Dynamic ) {};
		else
			sys.io.File.saveBytes(file, bytes);
	}

	override function saveTexture(file:String, bytes:haxe.io.Bytes, dir:String, ext:String) {
		var path = new haxe.io.Path("");
		path.dir = dir + "/";
		path.file = file;
		path.ext = ext;

		if(!sys.FileSystem.isDirectory( hide.Ide.inst.getPath(dir)))
			sys.FileSystem.createDirectory( hide.Ide.inst.getPath(dir));

		var file = hide.Ide.inst.getPath(path.toString());
		sys.io.File.saveBytes(file, bytes);
	}

	override function savePrefabDat(file : String, ext:String, p : String, bytes : haxe.io.Bytes ){
		var path = new haxe.io.Path(currentPath);
		path.ext = "dat";
		var datDir = path.toString();
		var instanceDir = datDir + "/" + p;

		if( bytes == null ){
			hxd.res.Loader.currentInstance.delete(getPrefabDatPath(file, ext, p));
			var p = hide.Ide.inst.getPath(instanceDir);
			if(sys.FileSystem.isDirectory(p)){
				var dir = sys.FileSystem.readDirectory(p);
				if(dir.length == 0) sys.FileSystem.deleteDirectory(p);
			}
			var p = hide.Ide.inst.getPath(datDir);
			if(sys.FileSystem.isDirectory(p)){
				var dir = sys.FileSystem.readDirectory(p);
				if(dir.length == 0) sys.FileSystem.deleteDirectory(p);
			}
		} else {
			var path = new haxe.io.Path("");
			path.dir = instanceDir;
			path.file = file;
			path.ext = ext;

			var file = hide.Ide.inst.getPath(path.toString());
			if(!sys.FileSystem.isDirectory( hide.Ide.inst.getPath(datDir)))
				sys.FileSystem.createDirectory( hide.Ide.inst.getPath(datDir));
			if(!sys.FileSystem.isDirectory( hide.Ide.inst.getPath(instanceDir)))
				sys.FileSystem.createDirectory( hide.Ide.inst.getPath(instanceDir));

			final numRetries = 5;
			var success = false;
			var lastError = null;
			for (i in 0...numRetries) {
				try {
					sys.io.File.saveBytes(file, bytes);
					success = true;
					break;
				} catch (e) {
					lastError = e;
					Sys.sleep(0.1);
					continue;
				}
			}
			if (!success) {
				throw lastError;
			}
		}
	}
	#end
}