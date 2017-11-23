package hide.comp;

@:access(hide.comp.Scene)
class SceneLoader extends h3d.impl.Serializable.SceneSerializer {

	var ide : hide.ui.Ide;
	var hsdPath : String;
	var projectPath : String;
	var scene : Scene;

	public function new(hsdPath, scene) {
		ide = hide.ui.Ide.inst;
		super();
		this.hsdPath = hsdPath;
		this.scene = scene;
	}

	override function initHSDPaths(resPath:String, projectPath:String) {
		this.resPath = resPath.split("\\").join("/");
		this.projectPath = projectPath == null ? null : projectPath.split("\\").join("/");
	}

	override function loadShader(name:String) : hxsl.Shader {
		return ide.shaderLoader.load(name);
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
		return scene.loadTexture(hsdPath, path);
	}

	function resolvePath( path : String ) {
		var p = null;
		if( projectPath != null )
			p = scene.resolvePath(projectPath + resPath + "/" + hsdPath.split("/").pop(), path);
		if( p == null )
			p = scene.resolvePath(hsdPath, path);
		return p;
	}

}

class Scene extends Component implements h3d.IDrawable {

	static var UID = 0;

	var id = ++UID;
	var stage : hxd.Stage;
	var canvas : js.html.CanvasElement;
	var hmdCache = new Map<String, hxd.fmt.hmd.Library>();
	var texCache = new Map<String, h3d.mat.Texture>();
	var cleanup = new Array<Void->Void>();
	var defaultCamera : h3d.Camera;
	public var engine : h3d.Engine;
	public var width(get, never) : Int;
	public var height(get, never) : Int;
	public var s2d : h2d.Scene;
	public var s3d : h3d.scene.Scene;
	public var sevents : hxd.SceneEvents;
	public var speed : Float = 1.0;

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

	public function dispose() {
		for( c in cleanup )
			c();
		cleanup = [];
		engine.dispose();
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
			onResize();
			sync();
			ide.registerUpdate(sync);
		};
		engine.onResized = function() {
			if( s2d == null ) return;
			s2d.setFixedSize(engine.width, engine.height);
			onResize();
		};
		engine.init();
	}

	function get_width() {
		return engine.width;
	}

	function get_height() {
		return engine.height;
	}

	public function init( props : hide.ui.Props, ?root : h3d.scene.Object ) {
		var autoHide : Array<String> = props.get("scene.autoHide");
		function initRec( obj : h3d.scene.Object ) {
			if( autoHide.indexOf(obj.name) >= 0 )
				obj.visible = false;
			for( o in obj )
				initRec(o);
		}
		if( root == null ) {
			root = s3d;
			engine.backgroundColor = Std.parseInt("0x"+props.get("scene.backgroundColor").substr(1)) | 0xFF000000;
		}
		initRec(root);
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
		s2d.setElapsedTime(hxd.Timer.tmod * speed / 60);
		s3d.setElapsedTime(hxd.Timer.tmod * speed / 60);
		onUpdate(hxd.Timer.tmod * speed);
		engine.render(this);
	}

	function loadTextureData( path : String, onReady : h3d.mat.Texture -> Void, ?target : h3d.mat.Texture ) {
		var path = ide.getPath(path);
		var img = new Element('<img src="file://$path"/>');
		img.on("load", function() {
			setCurrent();
			var bmp : js.html.ImageElement = cast img[0];
			var t;
			if( target == null )
				t = target = new h3d.mat.Texture(bmp.width, bmp.height);
			else {
				t = target;
				target.resize(bmp.width, bmp.height);
			}
			untyped bmp.ctx = { getImageData : function(_) return bmp, canvas : { width : 0, height : 0 } };
			engine.driver.uploadTextureBitmap(t, cast bmp, 0, 0);
			if( onReady != null ) {
				onReady(t);
				onReady = null;
			}
		});
		var w = js.node.Fs.watch(path, function(_, _) {
			img.attr("src", 'file://$path?t='+Date.now().getTime());
		});
		cleanup.push(w.close);
	}

	public function listAnims( path : String ) {

		if( StringTools.endsWith(path.toLowerCase(), ".hsd") )
			return [];

		var props = hide.ui.Props.loadForFile(ide, path);

		var dirs : Array<String> = props.get("hmd.animPaths");
		if( dirs == null ) dirs = [];
		dirs = [for( d in dirs ) ide.resourceDir + d];

		var parts = path.split("/");
		parts.pop();
		dirs.unshift(ide.getPath(parts.join("/")));

		var anims = [];

		var lib = loadHMD(path, false);
		if( lib.header.animations.length > 0 )
			anims.push(ide.getPath(path));

		for( dir in dirs ) {
			var dir = dir;
			if( StringTools.endsWith(dir, "/") ) dir = dir.substr(0,-1);
			for( f in try sys.FileSystem.readDirectory(dir) catch( e : Dynamic ) [] )
				if( StringTools.startsWith(f,"Anim_") )
					anims.push(dir+"/"+f);
		}
		return anims;
	}

	public function animationName( path : String ) {
		var name = path.split("/").pop();
		if( StringTools.startsWith(name, "Anim_") )
			name = name.substr(5);
		return name.substr(0, -4);
	}

	function initMaterials( obj : h3d.scene.Object, path : String, reset = true ) {
		var res = hxd.res.Any.fromBytes(path, haxe.io.Bytes.alloc(0));
		for( m in obj.getMaterials() ) {
			if( m.name == null ) continue;
			m.model = res;
			if( reset ) h3d.mat.MaterialSetup.current.initModelMaterial(m);
		}
	}

	function loadHSD( path : String ) {
		var ctx = new SceneLoader(path,this);
		var fullPath = ide.getPath(path);
		var bytes = sys.io.File.getBytes(fullPath);
		var root = new h3d.scene.Object();
		var hsd = ctx.loadHSD(bytes);
		if( hsd.content.length == 1 )
			root = hsd.content[0];
		else {
			for( o in hsd.content )
				root.addChild(o);
		}
		initMaterials(root, path, false);
		return { root : root, camera : hsd.camera };
	}

	public function loadModel( path : String, mainScene = false ) {
		if( StringTools.endsWith(path.toLowerCase(), ".hsd") ) {
			var hsd = loadHSD(path);
			if( mainScene ) defaultCamera = hsd.camera;
			return hsd.root;
		}
		var lib = loadHMD(path,false);
		var obj = lib.makeObject(loadTexture.bind(path));
		initMaterials(obj, path);
		return obj;
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

		// swap drive letter
		if( fullPath.charAt(1) == ":" && fullPath.charAt(0) != ide.projectDir.charAt(0) ) {
			fullPath = ide.projectDir.charAt(0) + fullPath.substr(1);
			if( exists(fullPath) )
				return fullPath;
		}

		filePath = filePath.split("\\").join("/");
		modelPath = ide.getPath(modelPath);

		var path = modelPath.split("/");
		path.pop();
		var relToModel = path.join("/") + "/" + filePath.split("/").pop();
		if( exists(relToModel) )
			return relToModel;

		return null;
	}

	public function loadTexture( modelPath : String, texturePath : String, ?onReady : h3d.mat.Texture -> Void ) {
		var path = resolvePath(modelPath, texturePath);
		if( path == null ) {
			ide.error("Could not load texture " + { modelPath : modelPath, texturePath : texturePath });
			return null;
		}
		var t = texCache.get(path);
		if( t != null ) {
			if( onReady != null ) haxe.Timer.delay(onReady.bind(t), 1);
			return t;
		}
		var bytes = sys.io.File.getBytes(path);
		var size = hxd.res.Any.fromBytes(path, bytes).toImage().getSize();
		t = new h3d.mat.Texture(size.width,size.height);
		t.clear(0x102030);
		t.name = ide.makeRelative(path);
		texCache.set(path, t);
		if( onReady == null ) onReady = function(_) {};
		loadTextureData(path, onReady, t);
		return t;
	}

	function loadHMD( path : String, isAnimation : Bool ) {
		var fullPath = ide.getPath(path);
		var key = fullPath;
		var hmd = hmdCache.get(key);

		if( hmd != null )
			return hmd;

		var relPath = StringTools.startsWith(path, ide.resourceDir) ? path.substr(ide.resourceDir.length+1) : path;
		var e = try hxd.res.Loader.currentInstance.load(relPath) catch( e : hxd.res.NotFound ) null;
		if( e == null ) {
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
			hmd = hxd.res.Any.fromBytes(path, data).toModel().toHmd();
		} else {
			hmd = e.toHmd();
		}

		hmdCache.set(key, hmd);
		return hmd;
	}

	public function resetCamera( ?obj : h3d.scene.Object, distanceFactor = 1. ) {

		if( defaultCamera != null ) {
			s3d.camera.load(defaultCamera);
			return;
		}

		if( obj == null ) obj = s3d;
		var b = obj.getBounds();
		var dx = Math.max(Math.abs(b.xMax),Math.abs(b.xMin));
		var dy = Math.max(Math.abs(b.yMax),Math.abs(b.yMin));
		var dz = Math.max(Math.abs(b.zMax),Math.abs(b.zMin));
		var dist = Math.max(Math.max(dx * 6, dy * 6), dz * 4) * distanceFactor;
		var ang = Math.PI / 4;
		var zang = Math.PI * 0.4;
		s3d.camera.pos.set(Math.sin(zang) * Math.cos(ang) * dist, Math.sin(zang) * Math.sin(ang) * dist, Math.cos(zang) * dist);
		s3d.camera.target.set(0, 0, (b.zMax + b.zMin) * 0.5);
	}

	public function render( e : h3d.Engine ) {
		s3d.render(e);
		s2d.render(e);
	}

	public dynamic function onUpdate(dt:Float) {
	}

	public dynamic function onReady() {
	}

	public dynamic function onResize() {
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