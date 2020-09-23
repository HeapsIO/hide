package hide.comp;

@:access(hide.comp.Scene)
class SceneLoader extends hxd.fmt.hsd.Serializer {

	var ide : hide.Ide;
	var hsdPath : String;
	var projectPath : String;
	var scene : Scene;

	public function new(hsdPath, scene) {
		ide = hide.Ide.inst;
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
	var window : hxd.Window;
	var canvas : js.html.CanvasElement;
	var hmdCache = new Map<String, hxd.fmt.hmd.Library>();
	var texCache = new Map<String, h3d.mat.Texture>();
	var pathsMap = new Map<String, String>();
	var cleanup = new Array<Void->Void>();
	var defaultCamera : h3d.Camera;
	var listeners = new Array<Float -> Void>();
	public var config : hide.Config;
	public var engine : h3d.Engine;
	public var width(get, never) : Int;
	public var height(get, never) : Int;
	public var s2d : h2d.Scene;
	public var s3d : h3d.scene.Scene;
	public var sevents : hxd.SceneEvents;
	public var speed : Float = 1.0;
	public var visible(default, null) : Bool = true;
	public var editor : hide.comp.SceneEditor;
	public var refreshIfUnfocused = false;
	var chunkifyS3D : Bool = false;

	public function new(chunkifyS3D: Bool = false, config, parent, el) {
		super(parent,el);
		this.config = config;
		this.chunkifyS3D = chunkifyS3D;
		element.addClass("hide-scene-container");
		canvas = cast new Element("<canvas class='hide-scene' style='width:100%;height:100%'/>").appendTo(element)[0];
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

	public function addListener(f) {
		listeners.push(f);
	}

	public function removeListener(f) {
		for( f2 in listeners )
			if( Reflect.compareMethods(f,f2) ) {
				listeners.remove(f2);
				break;
			}
	}

	function delayedInit() {
		canvas.id = "webgl";
		window = @:privateAccess new hxd.Window(canvas);
		window.propagateKeyEvents = true;
		window.setCurrent();
		engine = @:privateAccess new h3d.Engine();
		@:privateAccess engine.resCache.set(Scene, this);
		engine.backgroundColor = 0xFF111111;
		canvas.id = null;
		engine.onReady = function() {
			new Element(canvas).on("resize", function() {
				@:privateAccess window.checkResize();
			});
			hxd.Key.initialize();
			engine.setCurrent();
			window.setCurrent();
			s2d = new h2d.Scene();
			if (chunkifyS3D) {
				s3d = new hide.tools.ChunkedScene();
			} else {
				s3d = new h3d.scene.Scene();
			}
			sevents = new hxd.SceneEvents(window);
			sevents.addScene(s2d);
			sevents.addScene(s3d);
			onReady();
			onResize();
			sync();
			ide.registerUpdate(sync);
		};
		engine.onResized = function() {
			if( s2d == null ) return;
			visible = engine.width > 32 && engine.height > 32; // 32x32 when hidden !
			s2d.scaleMode = Stretch(engine.width, engine.height);
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

	public function init( ?root : h3d.scene.Object ) {
		var autoHide : Array<String> = config.get("scene.autoHide");
		function initRec( obj : h3d.scene.Object ) {
			for(n in autoHide)
				if(obj.name != null && obj.name.indexOf(n) == 0)
					obj.visible = false;
			for( o in obj )
				initRec(o);
		}
		if( root == null ) {
			root = s3d;
			engine.backgroundColor = Std.parseInt("0x"+config.get("scene.backgroundColor").substr(1)) | 0xFF000000;
		}
		initRec(root);
	}

	public function setCurrent() {
		engine.setCurrent();
		window.setCurrent();
	}

	function checkCurrent() {
		if( h3d.Engine.getCurrent() != engine )
			throw "Invalid current engine : use setCurrent() first";
	}

	function sync() {
		if( new Element(canvas).parents("html").length == 0 ) {
			window.dispose();
			ide.unregisterUpdate(sync);
			return;
		}
		if( !visible || (!Ide.inst.isFocused && !refreshIfUnfocused) || pendingCount > 0)
			return;
		refreshIfUnfocused = false;
		setCurrent();
		sevents.checkEvents();
		var dt = hxd.Timer.tmod * speed / 60;
		s2d.setElapsedTime(dt);
		s3d.setElapsedTime(dt);
		for( f in listeners )
			f(dt);
		onUpdate(dt);
		engine.render(this);
	}

	var loadQueue : Array<Void->Void> = [];
	var pendingCount : Int = 0;

	function loadTextureData( img : hxd.res.Image, onReady : h3d.mat.Texture -> Void, ?target : h3d.mat.Texture ) {
		if( !img.getFormat().useAsyncDecode ) {
			// immediate read
			if( target == null )
				target = img.toTexture();
			else {
				var pix = img.getPixels();
				target.resize(pix.width, pix.height);
				target.uploadPixels(pix);
			}
			if( onReady != null ) {
				onReady(target);
				onReady = null;
			}
			return target;
		}

		if( target == null ) {
			var size = img.getSize();
			target = new h3d.mat.Texture(size.width,size.height);
			target.clear(0x102030);
			target.flags.set(Loading);
		}

		if( pendingCount < 10 ) {
			pendingCount++;
			_loadTextureData(img,function() {
				target.flags.unset(Loading);
				pendingCount--;
				var f = loadQueue.shift();
				if( f != null ) f();
				onReady(target);
			}, target);
		} else {
			loadQueue.push(loadTextureData.bind(img,onReady,target));
		}
		return target;
	}

	function _loadTextureData( img : hxd.res.Image, onReady : Void -> Void, t : h3d.mat.Texture ) {
		var path = ide.getPath(img.entry.path);
		var img = new Element('<img src="file://$path" crossorigin="anonymous"/>');
		function onLoaded() {
			setCurrent();
			var bmp : js.html.ImageElement = cast img[0];
			t.resize(bmp.width, bmp.height);
			untyped bmp.ctx = { getImageData : function(_) return bmp, canvas : { width : 0, height : 0 } };
			engine.driver.uploadTextureBitmap(t, cast bmp, 0, 0);
			t.realloc = onLoaded;
			t.flags.unset(Loading);
			@:privateAccess if( t.waitLoads != null ) {
				var arr = t.waitLoads;
				t.waitLoads = null;
				for( f in arr ) f();
			}
			if( onReady != null ) {
				onReady();
				onReady = null;
			}
		}
		img.on("load", onLoaded);
		var w = js.node.Fs.watch(path, function(_, _) {
			img.attr("src", 'file://$path?t='+Date.now().getTime());
		});
		cleanup.push(w.close);
	}

	public function listAnims( path : String ) {

		if( StringTools.endsWith(path.toLowerCase(), ".hsd") )
			return [];

		var config = hide.Config.loadForFile(ide, path);

		var dirs : Array<String> = config.get("hmd.animPaths");
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
			for( f in try sys.FileSystem.readDirectory(dir) catch( e : Dynamic ) [] ) {
				var file = f.toLowerCase();
				if( StringTools.startsWith(f,"Anim_") && (StringTools.endsWith(file,".hmd") || StringTools.endsWith(file,".fbx")) )
					anims.push(dir+"/"+f);
			}
		}
		return anims;
	}

	public function animationName( path : String ) {
		var name = path.split("/").pop();
		if( StringTools.startsWith(name, "Anim_") )
			name = name.substr(5);
		name = name.substr(0, -4);
		if( StringTools.endsWith(name,"_loop") )
			name = name.substr(0,-5);
		return name;
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
		return { root : root, camera : hsd.camera };
	}

	public function loadModel( path : String, mainScene = false, reload = false ) {
		checkCurrent();
		if( StringTools.endsWith(path.toLowerCase(), ".hsd") ) {
			var hsd = loadHSD(path);
			if( mainScene ) defaultCamera = hsd.camera;
			return hsd.root;
		}
		var lib = loadHMD(path, false, reload);
		return lib.makeObject(loadTexture.bind(path));
	}

	public function loadAnimation( path : String ) {
		var lib = loadHMD(path,true);
		return lib.loadAnimation();
	}

	function resolvePathImpl( modelPath : String, filePath : String ) {
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

		if( modelPath == null )
			return null;

		filePath = filePath.split("\\").join("/");
		modelPath = ide.getPath(modelPath);

		var path = modelPath.split("/");
		path.pop();
		var relToModel = path.join("/") + "/" + filePath.split("/").pop();
		if( exists(relToModel) )
			return relToModel;

		return null;
	}

	function resolvePath(modelPath : String, filePath : String) {
		var key = modelPath + ":" + filePath;
		var p = pathsMap.get(key);
		if(p != null)
			return p;
		p = resolvePathImpl(modelPath, filePath);
		pathsMap.set(key, p);
		return p;
	}

	public function loadTextureDotPath( path : String, ?onReady ) {
		var path = path.split(".").join("/");
		var t = resolvePath(null, path + ".png");
		if( t == null )
			t = resolvePath(null, path + ".jpg");
		if( t == null )
			t = resolvePath(null, path + ".jpeg");
		if( t == null )
			t = path;
		return loadTexture("", t, onReady);
	}

	public function loadTexture( modelPath : String, texturePath : String, ?onReady : h3d.mat.Texture -> Void ) {
		checkCurrent();
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
		var relPath = StringTools.startsWith(path, ide.resourceDir) ? path.substr(ide.resourceDir.length+1) : path;
		var res = try hxd.res.Loader.currentInstance.load(relPath) catch( e : hxd.res.NotFound ) {
			var bytes = sys.io.File.getBytes(path);
			hxd.res.Any.fromBytes(path, bytes);
		};
		if( onReady == null ) onReady = function(_) {};
		try {
			t = loadTextureData(res.toImage(), onReady, t);
			t.setName( ide.makeRelative(path));
			texCache.set(path, t);
		} catch( error : Dynamic ) {
			throw "Could not load texure " + texturePath + ":\n" + Std.string(error);
		};
		return t;
	}

	function loadHMD( path : String, isAnimation : Bool, reload = false ) {
		checkCurrent();
		var fullPath = ide.getPath(path);
		var key = fullPath;
		var hmd = hmdCache.get(key);

		if( !reload && hmd != null )
			return hmd;

		var relPath = StringTools.startsWith(path, ide.resourceDir) ? path.substr(ide.resourceDir.length+1) : path;
		var e;
		if( ide.isDebugger )
			e = hxd.res.Loader.currentInstance.load(relPath);
		else
			e = try hxd.res.Loader.currentInstance.load(relPath) catch( e : hxd.res.NotFound ) null;
		if( e == null || reload ) {
			var data = sys.io.File.getBytes(fullPath);
			if( data.get(0) != 'H'.code ) {
				var hmdOut = new hxd.fmt.fbx.HMDOut(fullPath);
				hmdOut.absoluteTexturePath = (e == null);
				hmdOut.loadFile(data);
				var hmd = hmdOut.toHMD(null, !isAnimation);
				var out = new haxe.io.BytesOutput();
				new hxd.fmt.hmd.Writer(out).write(hmd);
				data = out.getBytes();
			}
			e = hxd.res.Any.fromBytes(path, data);
		}
		hmd = e.toModel().toHmd();

		if (!reload && e != null) {
			e.watch(function() {
				if (sys.FileSystem.exists(ide.getPath(e.entry.path))) {
					var lib = e.toModel().toHmd();
					hmdCache.set(key, lib);
					editor.onResourceChanged(lib);
				}
			});
			cleanup.push(function() {
				e.watch(null);
			});
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
		if( b.isEmpty() )
			return;
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

	public static function getCurrent() : Scene {
		return @:privateAccess h3d.Engine.getCurrent().resCache.get(Scene);
	}

}