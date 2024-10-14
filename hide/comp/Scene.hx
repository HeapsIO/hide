package hide.comp;

class Scene extends hide.comp.Component implements h3d.IDrawable {

	static var UID = 0;

	var id = ++UID;
	var window : hxd.Window;
	public var canvas : js.html.CanvasElement;
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
	public var autoDisposeOutOfDocument : Bool = true;
	var unFocusedTime = 0.;

	public static var cache : h3d.prim.ModelCache = new h3d.prim.ModelCache();

	public function new(config, parent, el) {
		super(parent,el);
		this.config = config;
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
		ide.unregisterUpdate(sync);
		if (s2d != null) {
			@:privateAccess s2d.window.removeResizeEvent(s2d.checkResize);
			s2d.dispose();
		}
		if ( s3d != null )
			s3d.dispose();
		if (engine != null && engine.driver != null) {
			engine.dispose();
			@:privateAccess engine.driver = null;
		}
		if (canvas != null) {
			untyped canvas.__scene = null;
			canvas = null;
		}
		if( h3d.Engine.getCurrent() == engine ) @:privateAccess h3d.Engine.CURRENT = null;
		untyped js.Browser.window.$_ = null; // jquery can sometimes leak s2d
		@:privateAccess haxe.NativeStackTrace.lastError = null; // possible leak there
		if ( window != null )
			window.dispose();
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
		h3d.impl.MemoryManager.enableTrackAlloc(Ide.inst.ideConfig.trackGpuAlloc);
		engine = @:privateAccess new h3d.Engine();
		@:privateAccess engine.resCache.set(Scene, this);
		engine.backgroundColor = 0xFF111111;
		canvas.id = null;
		engine.onResized = function() {
			if( s2d == null ) return;
			setCurrent();
			visible = engine.width > 32 && engine.height > 32; // 32x32 when hidden !
			s2d.scaleMode = Resize; // setter call
			onResize();
		};
		engine.onReady = function() {
			if( engine.driver == null ) return;
			new Element(canvas).on("resize", function() {
				window.setCurrent();
				@:privateAccess window.checkResize();
			});
			setCurrent();
			hxd.Key.initialize();
			s2d = new h2d.Scene();
			s3d = new h3d.scene.Scene();

			sevents = new hxd.SceneEvents(window);
			sevents.addScene(s2d);
			sevents.addScene(s3d);
			@:privateAccess window.checkResize();
			onReady();
			onResize();
			sync();
			ide.registerUpdate(sync);
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

	public function hasFocus() {
		return js.Browser.document.activeElement == canvas;
	}

	function sync() {
		if( new Element(canvas).parents("html").length == 0) {
			if (autoDisposeOutOfDocument) {
				dispose();
			}
			return;
		}
		if( !visible || pendingCount > 0)
			return;
		var dt = hxd.Timer.tmod * speed / 60;
		if( !Ide.inst.isFocused ) {
			// refresh at 1FPS
			unFocusedTime += dt;
			if( unFocusedTime < 1 ) return;
			unFocusedTime -= 1;
			dt = 1;
		} else
			unFocusedTime = 0;
		setCurrent();
		sevents.checkEvents();
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
		if( !img.getFormat().useLoadBitmap ) {
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
		var img = new Element('<img src="${ide.getUnCachedUrl(path)}" crossorigin="anonymous"/>');
		function onLoaded() {
			if( engine.driver == null ) return;
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
		function onChange() {
			img.attr("src", ide.getUnCachedUrl(path));
		}
		ide.fileWatcher.register( path, onChange, true, element );
		cleanup.push(function() { ide.fileWatcher.unregister( path, onChange ); });
	}

	public function listAnims( path : String ) {

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

	public function loadModel( path : String, mainScene = false, reload = false ) {
		checkCurrent();
		var lib = loadHMD(path, false, reload);
		return lib.makeObject(texturePath -> loadTexture(path, texturePath));
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

	public function loadTexture( modelPath : String, texturePath : String, ?onReady : h3d.mat.Texture -> Void, async=false, ?uncompressed: Bool = false) {
		checkCurrent();
		var path = resolvePath(modelPath, texturePath);
		if( path == null ) {
			ide.quickError("Could not load texture " + { modelPath : modelPath, texturePath : texturePath });
			return null;
		}
		var t = texCache.get(path);
		if( t != null ) {
			if( onReady != null ) haxe.Timer.delay(onReady.bind(t), 1);
			return t;
		}
		var relPath = StringTools.startsWith(path, ide.resourceDir) ? path.substr(ide.resourceDir.length+1) : path;

		function loadUncompressed() {
			var bytes = sys.io.File.getBytes(path);
			return hxd.res.Any.fromBytes(path, bytes);
		}

		var res = try hxd.res.Loader.currentInstance.load(relPath) catch( e : hxd.res.NotFound ) {
			loadUncompressed();
		};

		if (uncompressed)
			loadUncompressed();

		if( onReady == null ) onReady = function(_) {};
		try {
			var img = res.toImage();
			img.enableAsyncLoading = async;
			t = loadTextureData(img, onReady, t);
			t.setName( ide.makeRelative(path));
			texCache.set(path, t);
		} catch( error : Dynamic ) {
			ide.quickError("Could not load texure " + texturePath + ":\n" + Std.string(error));
			return null;
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
		if( reload )
			@:privateAccess hxd.res.Loader.currentInstance.cache.remove(path);
		if( ide.isDebugger )
			e = hxd.res.Loader.currentInstance.load(relPath);
		else
			e = try hxd.res.Loader.currentInstance.load(relPath) catch( e : hxd.res.NotFound ) null;
		if( e == null ) {
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
		if (Ide.inst.currentConfig.get("sceneeditor.tog-scene-render", false))
			return;

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

	public function listMatLibraries(path : String) {
		var config = hide.Config.loadForFile(ide, path);

		var matLibs : Array<Dynamic> = config.get("materialLibraries");
		if( matLibs == null ) matLibs = [];

		if (matLibs.length > 0 && matLibs[0] is String) {
			for (idx in 0...matLibs.length) {
				matLibs[idx] = { name : matLibs[idx], path : matLibs[idx] };
			}
		}

		return matLibs;
	}

	public function findMat(materials : Array<Dynamic>, key:String) : { path : String, mat : h3d.mat.Material } {
		var p = key.split("/");
		var name = p.pop();
		var path = p.join("/");
		for ( m in materials ) {
			if ( m.path == path && m.mat.name == name )
				return m;
		}

		return null;
	}

	public function listMaterialFromLibrary( path : String, library : String ) {
		var libraries = listMatLibraries(path);
		var lPath = "";
		for (l in libraries) {
			if (l.name == library) {
				lPath = l.path;
				break;
			}
		}

		if (lPath == "")
			return [];

		var materials = [];
		function pathRec(p : String) {
			try {
				var prefab = hxd.res.Loader.currentInstance.load(p).toPrefab().load();
				var mats = prefab.findAll(hrt.prefab.Material);
				for ( m in mats )
					materials.push({ path : p, mat : m});
			} catch ( e : hxd.res.NotFound ) {
				ide.error('Material library ${p} not found, please update props.json');
			}
		}

		pathRec(lPath);

		materials.sort((m1, m2) -> { return (m1.mat.name > m2.mat.name ? 1 : -1); });
		return materials;
	}
}

class PreviewCamController extends h3d.scene.Object {
	var target : h3d.Vector = new h3d.Vector();
	var targetInterp : h3d.Vector = new h3d.Vector();
	var pos : h3d.Vector = new h3d.Vector();

	var phi : Float = 0.4;
	var theta : Float = 0.4;
	var r : Float = 4.0;

	var phiInterp : Float = 0.4;
	var thetaInterp : Float = 0.4;
	var rInterp : Float = 4.0;

	function computePos() {
		pos.x = rInterp * hxd.Math.sin(thetaInterp) * hxd.Math.cos(phiInterp);
		pos.y = rInterp * hxd.Math.sin(thetaInterp) * hxd.Math.sin(phiInterp);
		pos.z = rInterp * hxd.Math.cos(thetaInterp);
		pos += targetInterp;
	}

	public function set(r: Float, phi: Float, theta: Float, target: h3d.Vector) {
		this.r = r;
		this.phi = phi;
		this.theta = theta;
		this.target.load(target);
	}

	var pushing : Int = -1;
	var ignoreNext : Bool = false;
	function onEvent(e : hxd.Event) {
		if (getScene().children.length <= 1)
			return;
		switch (e.kind) {
			case EPush: {
				if (pushing != -1)
					return;
				pushing = e.button;
				var win = hxd.Window.getInstance();
				ignoreNext = true;
				win.mouseMode = Relative(onCapture, true);
			}
			case EWheel: {
				r *= hxd.Math.pow(2, e.wheelDelta * 0.5);
			}
			case ERelease, EReleaseOutside:
				if (pushing != e.button) {
					return;
				}
				var win = hxd.Window.getInstance();
				win.mouseMode = Absolute;
				pushing = -1;
			default:
		}
	}

	function pan(dx, dy, dz = 0.) {
		var v = new h3d.Vector(dx, dy, dz);
		var cam = getScene().camera;
		cam.update();
		v.transform3x3(cam.getInverseView());
		target = target.add(v);
	}

	override function sync(ctx: h3d.scene.RenderContext) {
		var cam = getScene().camera;
		if (cam == null)
			return;


		var dt = hxd.Math.min(1, 1 - Math.pow(0.6, ctx.elapsedTime * 60));
		var dt2 = hxd.Math.min(1, 1 - Math.pow(0.4, ctx.elapsedTime * 60));

		thetaInterp = hxd.Math.lerp(thetaInterp, theta, dt2);
		phiInterp = hxd.Math.lerp(phiInterp, phi, dt2);
		rInterp = hxd.Math.lerp(rInterp, r, dt);
		targetInterp.lerp(targetInterp, target, dt);

		computePos();

		cam.target.load(targetInterp);
		cam.pos.load(pos);
	}

	override function onAdd() {
		getScene().addEventListener(onEvent);
	}

	override function onRemove() {
		getScene().removeEventListener(onEvent);
	}

	function onCapture(e: hxd.Event) {
		// For some reason sometimes the first
		// input from a capture has extreme values.
		// We just filter out all first events from a capture to mitigate this
		if (ignoreNext) {
			ignoreNext = false;
			return;
		}

		switch (e.kind) {
			case EMove:
				switch (pushing) {
					case 1:
						pan(-e.relX * 0.01, e.relY * 0.01);
					case 2:
						var dx = e.relX;
						var dy = e.relY;
						phi += dx * 0.01;
						theta -= dy * 0.01;
						theta = hxd.Math.clamp(theta, 0, hxd.Math.PI);
				}
			default:
		}

	}

	function onCleanup() {
		pushing = -1;
	}
}

class Preview2DCamController extends h2d.Object {
	var pushing : Int;
	var zoom: Float = 1.0;
	var ignoreNext: Bool;

	function onEvent(e : hxd.Event) {
		if (getScene().children.length <= 1)
			return;
		switch (e.kind) {
			case EPush: {
				if (pushing != -1)
					return;
				pushing = e.button;
				var win = hxd.Window.getInstance();
				ignoreNext = true;
				win.mouseMode = Relative(onCapture, true);
			}
			case EWheel: {
				zoom *= hxd.Math.pow(2, -e.wheelDelta * 0.5);
			}
			case ERelease, EReleaseOutside:
				if (pushing != e.button) {
					return;
				}
				var win = hxd.Window.getInstance();
				win.mouseMode = Absolute;
				pushing = -1;
			default:
		}
	}

	function onCapture(e: hxd.Event) {
		// For some reason sometimes the first
		// input from a capture has extreme values.
		// We just filter out all first events from a capture to mitigate this
		if (ignoreNext) {
			ignoreNext = false;
			return;
		}

	}

	override function onAdd() {
		getScene().addEventListener(onEvent);
	}

	override function onRemove() {
		getScene().removeEventListener(onEvent);
	}

	override function sync(ctx: h2d.RenderContext) {
		var cam = getScene().camera;
		if (cam == null)
			return;

		cam.setScale(zoom, zoom);
	}
}