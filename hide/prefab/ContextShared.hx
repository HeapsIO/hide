package hide.prefab;

class ContextShared extends hrt.prefab.ContextShared {
	#if editor
	public var editor : hide.comp.SceneEditor;

	public function new(?res : hxd.res.Resource ) {
		super(res);
	}



	override function onError( e : Dynamic ) {
		hide.Ide.inst.error(e);
	}

	override function loadShader( path : String ) {
		return hide.Ide.inst.shaderLoader.loadSharedShader(path);
	}

	override function loadModel( path : String ) {
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

		if(!sys.FileSystem.isDirectory( hide.Ide.inst.getPath(datDir)))
			sys.FileSystem.createDirectory( hide.Ide.inst.getPath(datDir));
		if(!sys.FileSystem.isDirectory( hide.Ide.inst.getPath(instanceDir)))
			sys.FileSystem.createDirectory( hide.Ide.inst.getPath(instanceDir));

		var path = new haxe.io.Path("");
		path.dir = instanceDir;
		path.file = file;
		path.ext = ext;
		var file = hide.Ide.inst.getPath(path.toString());

		if( bytes == null ){
			try sys.FileSystem.deleteFile(file) catch( e : Dynamic ) {};
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
			return;
		}else{
			sys.io.File.saveBytes(file, bytes);
		}
	}

	#end
}