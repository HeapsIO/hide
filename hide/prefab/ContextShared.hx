package hide.prefab;

class ContextShared extends hxd.prefab.ContextShared {
	#if editor
	var scene : hide.comp.Scene;

	public function new(scene) {
		super();
		this.scene = scene;
	}

	function getScene() {
		return scene;
	}

	override function onError( e : Dynamic ) {
		hide.Ide.inst.error(e);
	}

	override function loadShader( path : String ) {
		return hide.Ide.inst.shaderLoader.loadSharedShader(path);
	}

	override function loadModel( path : String ) {
		return getScene().loadModel(path);
	}

	override function loadAnimation( path : String ) {
		return getScene().loadAnimation(path);
	}

	override function loadTexture( path : String ) {
		return getScene().loadTexture("",path);
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
	#end
}