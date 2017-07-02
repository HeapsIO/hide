package hide.comp;

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
		canvas = cast new Element("<canvas class='hide-scene' style='width:100%;height:100%'/>").appendTo(root)[0];
		canvas.addEventListener("mousemove",function(_) canvas.focus());
		canvas.addEventListener("mouseleave",function(_) canvas.blur());
		canvas.oncontextmenu = function(e){
			e.stopPropagation();
			e.preventDefault();
			return false;
		};
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

	public function loadModel( path : String ) {
		var lib = loadHMD(path,false);
		return lib.makeObject(loadHMDTexture.bind(path));
	}

	public function loadAnimation( path : String ) {
		var lib = loadHMD(path,true);
		return lib.loadAnimation();
	}
 
	function loadHMDTexture( basePath : String, texturePath : String ) {
		if( sys.FileSystem.exists(texturePath) ) {
			var t = new h3d.mat.Texture(1,1);
			t.clear(0x102030);
			loadTexture(texturePath, function(_) {}, t);
			return t;
		}
		trace("TODO:",basePath, texturePath);
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

}