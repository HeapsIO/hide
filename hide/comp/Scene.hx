package hide.comp;

@:access(hide.comp.Scene)
class SceneLoader extends h3d.impl.Serializable.SceneSerializer {

	var scnPath : String;
	var projectPath : String;
	var scene : Scene;

	public function new(scnPath,scene) {
		super();
		this.scnPath = scnPath;
		this.scene = scene;
	}

	override function initSCNPaths(resPath:String, projectPath:String) {
		this.resPath = resPath.split("\\").join("/");
		this.projectPath = projectPath == null ? null : projectPath.split("\\").join("/");
	}

	override function loadHMD(path:String) {
		var path = resolvePath(path);
		if( path == null )
			throw "Missing HMD file " + path;
		return scene.loadHMD(path, false);
	}

	override function resolveTexture(path:String) {
		var path = resolvePath(path);
		if( path == null )
			return h3d.mat.Texture.fromColor(0xFF00FF);
		return scene.loadTextureFile(scnPath, path);
	}

	function resolvePath( path : String ) {
		var p = null;
		if( projectPath != null )
			p = scene.resolvePath(projectPath + resPath + "/" + scnPath.split("/").pop(), path);
		if( p == null )
			p = scene.resolvePath(scnPath, path);
		return p;
	}

}

class Scene extends Component implements h3d.IDrawable {

	static var UID = 0;

	var id = ++UID;
	var stage : hxd.Stage;
	var canvas : js.html.CanvasElement;
	var engine : h3d.Engine;
	public var s2d : h2d.Scene;
	public var s3d : h3d.scene.Scene;
	public var sevents : hxd.SceneEvents;

	public function new(root) {
		super(root);
		root.addClass("hide-scene-container");
		canvas = cast new Element("<canvas class='hide-scene' style='width:100%;height:100%'/>").appendTo(root)[0];
		canvas.addEventListener("mousemove",function(_) canvas.focus());
		canvas.addEventListener("mouseleave",function(_) canvas.blur());
		canvas.oncontextmenu = function(e){
			e.stopPropagation();
			e.preventDefault();
			return false;
		};
		untyped canvas.__scene = this;
		haxe.Timer.delay(delayedInit,0); // wait canvas added to window
	}

	function delayedInit() {
		canvas.id = "webgl";
		stage = @:privateAccess new hxd.Stage(canvas);
		stage.setCurrent();
		engine = new h3d.Engine();
		engine.backgroundColor = 0xFF111111;
		canvas.id = null;
		engine.onReady = function() {
			new Element(canvas).on("resize", function() {
				@:privateAccess stage.checkResize();
			});
			engine.setCurrent();
			stage.setCurrent();
			s2d = new h2d.Scene();
			s3d = new h3d.scene.Scene();
			sevents = new hxd.SceneEvents(stage);
			sevents.addScene(s2d);
			sevents.addScene(s3d);
			onReady();
			sync();
			ide.registerUpdate(sync);
		};
		engine.onResized = function() {
			if( s2d != null ) s2d.setFixedSize(engine.width, engine.height);
		};
		engine.init();
	}

	function setCurrent() {
		engine.setCurrent();
		stage.setCurrent();
	}

	function sync() {
		if( new Element(canvas).parents("html").length == 0 ) {
			stage.dispose();
			ide.unregisterUpdate(sync);
			return;
		}
		setCurrent();
		sevents.checkEvents();
		onUpdate(hxd.Timer.tmod);
		engine.render(this);
	}

	public function loadTexture( path : String, onReady : h3d.mat.Texture -> Void, ?target : h3d.mat.Texture ) {
		var path = ide.getPath(path);
		var img = new Element('<img src="file://$path"/>');
		img.on("load",function() {
			setCurrent();
			var bmp : js.html.ImageElement = cast img[0];
			var t;
			if( target == null )
				t = new h3d.mat.Texture(bmp.width, bmp.height);
			else {
				t = target;
				target.resize(bmp.width, bmp.height);
			}
			untyped bmp.ctx = { getImageData : function(_) return bmp, canvas : { width : 0, height : 0 } };
			engine.driver.uploadTextureBitmap(t, cast bmp, 0, 0);
			onReady(t);
		});
	}

	function loadSCN( path : String ) {
		var ctx = new SceneLoader(path,this);
		var fullPath = ide.getPath(path);
		var bytes = sys.io.File.getBytes(fullPath);
		var root = new h3d.scene.Object();
		for( o in ctx.loadSCN(bytes).content )
			root.addChild(o);
		return root;
	}

	public function loadModel( path : String ) {
		if( StringTools.endsWith(path.toLowerCase(), ".scn") )
			return loadSCN(path);
		var lib = loadHMD(path,false);
		return lib.makeObject(loadTextureFile.bind(path));
	}

	public function loadAnimation( path : String ) {
		var lib = loadHMD(path,true);
		return lib.loadAnimation();
	}

	function resolvePath( modelPath : String, filePath : String ) {
		inline function exists(path) return sys.FileSystem.exists(path);
		var fullPath = ide.getPath(filePath);
		if( exists(fullPath) )
			return fullPath;
		filePath = filePath.split("\\").join("/");
		modelPath = ide.getPath(modelPath);

		var path = modelPath.split("/");
		path.pop();
		var relToModel = path.join("/") + "/" + filePath.split("/").pop();
		if( exists(relToModel) )
			return relToModel;

		return null;
	}

	public function loadTextureFile( modelPath : String, texturePath : String ) {
		var path = resolvePath(modelPath, texturePath);
		if( path != null ) {
			var t = new h3d.mat.Texture(1,1);
			t.clear(0x102030);
			t.name = ide.makeRelative(path);
			loadTexture(path, function(_) {}, t);
			return t;
		}
		trace("Could not load texture " + { modelPath : modelPath, texturePath : texturePath });
		return null;
	}

	function loadHMD( path : String, isAnimation : Bool ) {
		var fullPath = ide.getPath(path);
		var data = sys.io.File.getBytes(fullPath);
		if( data.get(0) != 'H'.code ) {
			var hmdOut = new hxd.fmt.fbx.HMDOut();
			hmdOut.absoluteTexturePath = true;
			hmdOut.loadTextFile(data.toString());
			var hmd = hmdOut.toHMD(null, !isAnimation);
			var out = new haxe.io.BytesOutput();
			new hxd.fmt.hmd.Writer(out).write(hmd);
			data = out.getBytes();
		}
		return hxd.res.Any.fromBytes(path,data).toModel().toHmd();
	}

	public function render( e : h3d.Engine ) {
		s3d.render(e);
		s2d.render(e);
	}

	public dynamic function onUpdate(dt:Float) {
	}

	public dynamic function onReady() {
	}

	public static function getNearest( e : Element ) : Scene {
		while( e.length > 0 ) {
			var c : Dynamic = e.find("canvas")[0];
			if( c != null && c.__scene != null )
				return c.__scene;
			e = e.parent();
		}
		return null;
	}

}