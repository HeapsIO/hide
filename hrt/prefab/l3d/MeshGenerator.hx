package hrt.prefab.l3d;

class Socket {

	public var type : String;
	public var name : String;

	public function new( ?type, ?name ) {
		this.type = type;
		this.name = name;
	}

}

class MeshPart {

	public var socket : Socket;
	public var meshPath : String;
	public var offset : h3d.Vector;
	public var enable : Bool = false;
	public var childParts : Array<MeshPart> = [];

	#if editor
	public var previewPos = false;
	#end

	public function new() {
		socket = new Socket();
		offset = new h3d.Vector(0);
	}

	public function clone() : MeshPart {
		var clone = new MeshPart();
		clone.socket.name = socket.name;
		clone.socket.type = socket.type;
		clone.offset = offset;
		clone.enable = enable;
		clone.meshPath = meshPath;
		clone.childParts = childParts.copy();
		clone.childParts.reverse();
		return clone;
	}

	public function loadFrom( mp : MeshPart ) {
		socket.name = mp.socket.name;
		socket.type = mp.socket.type;
		offset = mp.offset;
		meshPath = mp.meshPath;
		enable = mp.enable;
		childParts = mp.childParts.copy();
	}

	public function save() {
		var o : Dynamic = {};

		if( offset.length() != 0 ) o.offset = { x : offset.x, y : offset.y, z : offset.z };
		o.socket = { type : socket.type, name : socket.name };
		o.meshPath = meshPath;
		o.enable = enable;

		if( childParts.length > 0 ) {
			var sp : Array<Dynamic> = [];
			for( mp in childParts )
				if( mp.meshPath != null )
					sp.push(mp.save());
			o.childParts = sp;
		}

		return o;
	}

	public function load( o : Dynamic ) {
		enable = o.enable == null ? true : o.enable;
		if( o.socket != null ) {
			socket.type = o.socket.type;
			socket.name = o.socket.name;
		}
		if( o.offset != null )
			offset.set(o.offset.x, o.offset.y, o.offset.z, 0.0);
		meshPath = o.meshPath == "none" ? null : o.meshPath;
		var ps : Array<Dynamic> = o.childParts;
		if( ps != null ) {
			for( p in ps ) {
				var mp = new MeshPart();
				mp.load(p);
				childParts.push(mp);
			}
		}
	}

	public function isRoot() : Bool {
		return socket.type == "Root";
	}

	public function getSocketFullName() : String {
		return socket.type + (socket.name == null ? "" : " " + socket.name);
	}
}

class MeshGeneratorRoot extends h3d.scene.Object {

	public function new( ?parent : h3d.scene.Object ) {
		super(parent);
	}

	override function syncRec( ctx ) {
		if( posChanged )
			super.syncRec(ctx);
	}
}

class MeshGenerator extends Object3D {

	public var root : MeshPart;

	#if editor
	static var filterInit = false;
	static var filter : Array<String> = [];
	static var customScene : h3d.scene.Scene;
	var undo : hide.ui.UndoHistory;
	#end

	public var maxDepth = 1;
	public var shadows = true;

	override function save() {
		var obj : Dynamic = super.save();
		obj.root = root.save();
		obj.shadows = shadows;
		return obj;
	}

	override function load( obj : Dynamic ) {
		super.load(obj);
		root = new MeshPart();
		root.load(obj.root);
		shadows = obj.shadows == null ? true : obj.shadows;
	}

	override function makeInstance( ctx : Context ) : Context {
		ctx = ctx.clone(this);
		ctx.local3d = new h3d.scene.Object(ctx.local3d);
		ctx.local3d.name = name;

		var rootObject = new MeshGeneratorRoot(ctx.local3d);
		rootObject.name = "rootObject";

		if( root == null ) {
			root = new MeshPart();
			root.socket.type = "Root";
		}
		updateInstance(ctx);

		#if editor
		if( customScene == null ) {
			customScene = new h3d.scene.Scene(true, false);
			#if debug
			customScene.checkPasses = false;
			#end
		}
		#end

		return ctx;
	}

	override function updateInstance( ctx: Context, ?propName : String ) {
		super.updateInstance(ctx,propName);
		resetMesh(ctx);

		#if editor
		createEmptyMeshPart(ctx, root);
		#end

		var rootObject = ctx.local3d.getObjectByName("rootObject");
		createMeshPart(ctx, root, rootObject);

		#if editor
		var int = ctx.local3d.find(o -> Std.downcast(o, h3d.scene.Interactive));
		if(int != null) {
			var dummy = Std.downcast(makeInteractive(ctx), h3d.scene.Interactive);
			int.preciseShape = dummy.preciseShape;
			dummy.remove();
		}
		#end
	}

	public function getSocket( obj : h3d.scene.Object, s : Socket ) : h3d.scene.Object {
		for( c in @:privateAccess obj.children ) {
			if( c.name == null ) continue;
			var nameInfos = c.name.split("_");
			if( nameInfos.length < 1 ) continue;
			if( nameInfos[0] == "Socket" ) {
				if( nameInfos.length < 2 ) continue;
				if( nameInfos[1] == s.type ) {
					if( s.name == null ) return c;
					else {
						if( nameInfos.length < 3 ) continue;
						if( nameInfos[2] == s.name ) return c;
					}
				}
			}
		}
		return null;
	}

	function createMeshPart( ctx : Context, mp : MeshPart, parent : h3d.scene.Object ) {

		#if editor
		if( mp.previewPos ) {
			if( mp.isRoot() )
				parent.addChild(createPreviewSphere(ctx));
			else {
				var socket = getSocket(parent, mp.socket);
				if( socket != null )
					socket.addChild(createPreviewSphere(ctx));
			}
		}
		#end

		if( !mp.isRoot() && !mp.enable )
			return;

		if( mp.meshPath == null )
			return;

		var obj = ctx.loadModel(mp.meshPath);
		for( m in obj.getMaterials() ) {
			m.castShadows = shadows;
		}

		if( mp.isRoot() ) {
			parent.addChild(obj);
		}
		else {
			var socket = getSocket(parent, mp.socket);
			if( socket != null ) {
				socket.addChild(obj);
			}
		}

		obj.setPosition(mp.offset.x, mp.offset.y, mp.offset.z);

		for( cmp in mp.childParts )
			createMeshPart(ctx, cmp, obj);
	}

	function resetMesh( ctx : Context ) {
		ctx.local3d.getObjectByName("rootObject").removeChildren();
	}

	function getSocketMatFromHMD( hmd : hxd.fmt.hmd.Library, s : Socket ) : h3d.Matrix {
		if( hmd == null ) return null;
		for( m in @:privateAccess hmd.header.models ) {
			if( m.name == null ) continue;
			var nameInfos = m.name.split("_");
			if( nameInfos.length < 2 ) continue;
			if( nameInfos[0] == "Socket" && nameInfos[1] == s.type && ((s.name == null && nameInfos.length < 3) || (nameInfos.length >= 3 && s.name == nameInfos[2])) ) {
				return m.position.toMatrix();
			}
		}
		return null;
	}

	#if editor

	function generate( ctx : EditContext, mp : MeshPart, maxDepth : Int, curDepth : Int) {
		if( curDepth >  maxDepth ) return;
		curDepth++;
		mp.meshPath = getRandomMeshPath(ctx.scene.config, mp.socket);
		if( root.meshPath == null ) return;
		mp.childParts = createMeshParts(getSocketListFromHMD(getHMD(ctx.rootContext, mp.meshPath)));
		for( cmp in mp.childParts )
			generate(ctx, cmp, maxDepth, curDepth);
	}

	function createEmptyMeshPart( ctx : Context, mp : MeshPart ) {
		var sl = getSocketListFromHMD(getHMD(ctx, mp.meshPath));
		if( mp.childParts.length < sl.length ) {
			for( s in sl ) {
				var b = true;
				for( cmp in mp.childParts ){
					if ( cmp.socket.name == s.name && cmp.socket.type == s.type ){
						b = false;
						break;
					}
				}
				if( b ) {
					var cmp = new MeshPart();
					cmp.socket.name = s.name;
					cmp.socket.type = s.type;
					mp.childParts.push(cmp);
				}
			}
		}
		for( cmp in mp.childParts )
			createEmptyMeshPart(ctx, cmp);
	}

	var target : h3d.mat.Texture;
	function renderMeshThumbnail( ctx : Context, meshPath : String ) {

		if( target == null )
			target = new h3d.mat.Texture(256, 256, [Target], RGBA);

		if( meshPath == null )
			return;

		var obj = ctx.loadModel(meshPath);
		if( obj == null )
			return;

		for( m in obj.getMaterials() ) {
			m.mainPass.culling = None;
		}

		if(!sys.FileSystem.isDirectory(hide.Ide.inst.getPath(".tmp/meshGeneratorData")))
			sys.FileSystem.createDirectory(hide.Ide.inst.getPath(".tmp/meshGeneratorData"));

		var path = new haxe.io.Path("");
		path.dir = ".tmp/meshGeneratorData/";
		path.file =  extractMeshName(meshPath) + "_thumbnail";
		path.ext = "png";
		var file = hide.Ide.inst.getPath(path.toString());

		if(sys.FileSystem.exists(file))
			return;

		var mainScene = @:privateAccess ctx.local3d.getScene();
		@:privateAccess customScene.children = [];
		@:privateAccess customScene.children.push(obj);

		var cam = new h3d.Camera(45, 1.0, 1.0);
		obj.rotate(0, 0, hxd.Math.degToRad(45));
		var b = obj.getBounds();
		var s = b.toSphere();
		cam.pos.set(0, s.r * 1.8, s.r * 1.25);
		cam.target.set((b.xMax + b.xMin) * 0.5, (b.yMax + b.yMin) * 0.5, (b.zMax + b.zMin) * 0.5);

		customScene.camera = cam;
		var engine = h3d.Engine.getCurrent();
		engine.begin();
		engine.pushTarget(target);
		engine.clear(0,1,0);
		customScene.render(engine);
		engine.popTarget();
		customScene.camera = null;

		var pixels = target.capturePixels();
		var bytes = pixels.toPNG();

		sys.io.File.saveBytes(file, bytes);
	}

	function hasFilter( s : String ) {
		for( f in filter )
			if ( s == f )
				return true;
		return false;
	}

	function createPreviewSphere( ctx : Context ) {
		var root = new h3d.scene.Object();
		root.setRotation(0,0, hxd.Math.degToRad(180));
		var m : h3d.scene.Mesh = cast ctx.loadModel("${HIDE}/res/meshGeneratorArrow.fbx");
		m.material.shadows = false;
		root.addChild(m);
		m.scale(0.5);
		m.name = "previewSphere";
		m.material.color.set(0.05,0,0.05,1);
		m.material.mainPass.depthTest = GreaterEqual;
		m.material.mainPass.depthWrite = false;
		m.material.mainPass.setPassName("overlay");
		var m : h3d.scene.Mesh = cast ctx.loadModel("${HIDE}/res/meshGeneratorArrow.fbx");
		m.material.shadows = false;
		root.addChild(m);
		m.scale(0.5);
		m.name = "previewSphere";
		m.material.color.set(1,0,0,1);
		m.material.mainPass.depthTest = LessEqual;
		m.material.mainPass.depthWrite = false;
		m.material.mainPass.setPassName("overlay");
		return root;
	}

	function resetPreview( mp : MeshPart ) {
		mp.previewPos = false;
		for( cmp in mp.childParts )
			resetPreview(cmp);
	}

	override function getHideProps() : HideProps {
		return { icon : "paint-brush", name : "MeshGenerator" };
	}

	override function setSelected( ctx : Context, b : Bool ) {
		super.setSelected(ctx, b);

		if( !b ) {
			var previewSpheres = ctx.local3d.findAll(c -> if(c.name == "previewSphere") c else null);
			for( s in previewSpheres ) {
				s.remove();
			}
		}
		return true;
	}

	function getHMD( ctx : Context, meshPath : String ) : hxd.fmt.hmd.Library {
		if( meshPath == null ) return null;
		return @:privateAccess ctx.shared.cache.loadLibrary(hxd.res.Loader.currentInstance.load(meshPath).toModel());
	}

	function createMeshParts( sl : Array<Socket> ) : Array<MeshPart> {
		var r : Array<MeshPart> = [];
		for( s in sl ){
			var mp = new MeshPart();
			mp.socket.name = s.name;
			mp.socket.type = s.type;
			r.push(mp);
		}
		return r;
	}

	function getSocketListFromHMD( hmd : hxd.fmt.hmd.Library ) : Array<Socket> {
		if( hmd == null ) return [];
		var r : Array<Socket> = [];
		for( m in @:privateAccess hmd.header.models ) {
			if( m.name == null ) continue;
			var nameInfos = m.name.split("_");
			if( nameInfos.length < 2 ) continue;
			if( nameInfos[0] == "Socket" ) {
				var s = new Socket();
				s.type = nameInfos[1];
				if( nameInfos.length >= 3 ) s.name = nameInfos[2];
				r.push(s);
			}
		}
		return r;
	}

	function extractMeshName( path : String ) : String {
		if( path == null ) return "None";
		var childParts = path.split("/");
		return childParts[childParts.length - 1].split(".")[0];
	}

	function getThumbnailPath( ctx : EditContext, meshPath : String ) : String {
		return ctx.ide.getPath(".tmp/meshGeneratorData/"+ extractMeshName(meshPath) +"_thumbnail.png");
	}

	function getRandomMeshPath( config : hide.Config, socket : Socket ) : String {
		var available : Array<String> = [];
		for( f in filter ) {
			var meshList : Array<Dynamic> = config.get("meshGenerator." + f);
			if( meshList == null ) continue;
			for( m in meshList ) {
				var sockets : Array<String> = m.socket;
				if( sockets == null || sockets.length == 0 ) continue;
				for( s in sockets ) {
					if( s == socket.type ) {
						available.push(m.path);
						break;
					}
				}
			}
		}
		if( available.length == 0 )
			return null;
		return available[hxd.Math.round(hxd.Math.random() * (available.length - 1))];
	}

	function fillSelectMenu( ctx : EditContext, select : hide.Element, socket : Socket ) {
		for( f in filter ) {
			var meshList : Array<Dynamic> = ctx.scene.config.get("meshGenerator." + f);
			if( meshList == null ) continue;
			for( m in meshList ) {
				var sockets : Array<String> = m.socket;
				var available = false;
				if( sockets == null || sockets.length == 0 )
					available = true;
				else {
					for( s in sockets ) {
						if( s == socket.type ) {
							available = true;
							break;
						}
					}
				}
				if( available )
					new hide.Element('<option>').attr("value", m.path).text(extractMeshName(m.path)).appendTo(select);
			}
		}
	}

	function createMenu( ctx : EditContext, mp : MeshPart ) {

		if( mp.isRoot() ) {
			var rootElement = new hide.Element('
				<div class="group" name="Root">
					<dl>
						<dt>Mesh</dt><dd><select><option value="none">None</option></select>
					</dl>
				</div>
			');
			var select = rootElement.find("select");
			fillSelectMenu(ctx, select, mp.socket);
			if( mp.meshPath != null && select.find('option[value="${mp.meshPath}"]').length == 0 )
				new hide.Element('<option>').attr("value", mp.meshPath).text(extractMeshName(mp.meshPath)).appendTo(select);

			select.change(function(_) {
				var val = select.val();
				var previous = mp.clone();
				var actual = mp;
				mp.meshPath = val == "none" ? null : val;
				mp.childParts = createMeshParts(getSocketListFromHMD(getHMD(ctx.rootContext, mp.meshPath)));
				ctx.properties.undo.change(Custom(function(undo) {
					undo ? mp.loadFrom(previous) : mp.loadFrom(actual);
					ctx.onChange(this, null);
					ctx.rebuildProperties();
				}));
				ctx.onChange(this, null);
				ctx.rebuildProperties();
			});
			select.val(mp.meshPath);

			ctx.properties.add(rootElement, mp, function(pname) {});
		}

		var socketList = getSocketListFromHMD(getHMD(ctx.rootContext, mp.meshPath));
		if( mp.meshPath != null && socketList.length != 0 ) {
			var s = '<div class="group" name="${extractMeshName(mp.meshPath)}">';
			s += '<div align="center"><div class="meshGenerator-thumbnail"></div></div><dl>';
			for( cmp in mp.childParts ) {
				var index = mp.childParts.indexOf(cmp);
				if( cmp.enable ) {
					s += '<dt><b>${cmp.getSocketFullName()}</b></dt><dd><input type="checkbox" class="enable$index"></dd>';
					s += '<dt>Mesh</dt><dd><select class="$index"><option value="none">None</option></select>';
					s += '<dt>Offset</dt>
									<dd>
										<div class="flex">
											<input type="number" style="max-width:50px" class="x$index" min="-100" max="100" step="0.1">
											<input type="number" style="max-width:50px" class="y$index" min="-100" max="100" step="0.1">
											<input type="number" style="max-width:50px" class="z$index" min="-100" max="100" step="0.1">
										</div>
									</dd>';
				}
				else
					s += '<dt>${cmp.getSocketFullName()}</dt><dd><input type="checkbox" class="enable$index"></dd>';
			}
			s += '</dl></div>';
			var rootElement = new hide.Element(s);
			for( cmp in mp.childParts ) {
				var index = mp.childParts.indexOf(cmp);

				var enable = rootElement.find('.enable$index');
				enable.prop("checked", cmp.enable);
				enable.change(function(_) {
					cmp.enable = enable.prop("checked");
					ctx.onChange(this, null);
					ctx.rebuildProperties();

					ctx.properties.undo.change(Custom(function(undo) {
						cmp.enable = !cmp.enable;
						ctx.onChange(this, null);
						ctx.rebuildProperties();
					}));
				});


				if( cmp.enable ) {
					// Offset
					var x = rootElement.find('.x$index');
					x.val(cmp.offset.x);
					x.change(function(_) {
						var prev : Float = cmp.offset.x;
						var newv : Float = Std.parseFloat(x.val());
						cmp.offset.x = newv;
						ctx.onChange(this, null);
						ctx.properties.undo.change(Custom(function(undo) {
							cmp.offset.x = undo ? prev : newv;
							ctx.onChange(this, null);
							ctx.rebuildProperties();
						}));
					});
					var y = rootElement.find('.y$index');
					y.val(cmp.offset.y);
					y.change(function(_) {
						var prev : Float = cmp.offset.y;
						var newv : Float = Std.parseFloat(y.val());
						cmp.offset.y = newv;
						ctx.onChange(this, null);
						ctx.properties.undo.change(Custom(function(undo) {
							cmp.offset.y = undo ? prev : newv;
							ctx.onChange(this, null);
							ctx.rebuildProperties();
						}));
					});
					var z = rootElement.find('.z$index');
					z.val(cmp.offset.z);
					z.change(function(_) {
						var prev : Float = cmp.offset.z;
						var newv : Float = Std.parseFloat(z.val());
						cmp.offset.z = newv;
						ctx.onChange(this, null);
						ctx.properties.undo.change(Custom(function(undo) {
							cmp.offset.z = undo ? prev : newv;
							ctx.onChange(this, null);
							ctx.rebuildProperties();
						}));
					});

					// MeshPath
					var select = rootElement.find('.$index');
					fillSelectMenu(ctx, select, cmp.socket);
					if( cmp.meshPath != null && select.find('option[value="${cmp.meshPath}"]').length == 0 )
						new hide.Element('<option>').attr("value", cmp.meshPath).text(extractMeshName(cmp.meshPath)).appendTo(select);
					select.change(function(_) {
						var mp = mp.childParts[index];
						var val = select.val();
						var previous = mp.clone();
						var actual = mp;
						mp.meshPath = val == "none" ? null : val;
						mp.childParts = createMeshParts(getSocketListFromHMD(getHMD(ctx.rootContext, cmp.meshPath)));
						ctx.properties.undo.change(Custom(function(undo) {
							undo ? mp.loadFrom(previous) : mp.loadFrom(actual);
							ctx.onChange(this, null);
							ctx.rebuildProperties();
						}));
						ctx.onChange(this, null);
						ctx.rebuildProperties();
					});
					select.val(cmp.meshPath);
				}

				enable.on("mouseover", function(_) {
					resetPreview(root);
					cmp.previewPos = true;
					ctx.onChange(this, null);
				});
				enable.on("mouseleave", function(_) {
					resetPreview(root);
					ctx.onChange(this, null);
				});
			}

			//renderMeshThumbnail(ctx.rootContext, mp.meshPath);
			//rootElement.find('.meshGenerator-thumbnail').css("background-image", 'url("file://${getThumbnailPath(ctx, mp.meshPath)}")');

			ctx.properties.add(rootElement, mp, function(pname) {});

			for( cmp in mp.childParts ) {
				createMenu(ctx, cmp);
			}
		}
	}

	override function edit( ctx : EditContext ) {
		super.edit(ctx);

		undo = ctx.properties.undo;

		var families : Array<Dynamic> = ctx.scene.config.get("meshGenerator.families");

		if( !filterInit ) {
			for( f in families )
				filter.push(f);
			filterInit = true;
		}

		var editMenu : String = "";

		// Render Params
		editMenu += '<div class="group" name="Material"><dl>
						<dt>Shadows</dt><dd><input type="checkbox" field="shadows"></dd>
					</div>';

		// Procedural Generation
		editMenu += '<div class="group" name="Procedural Generation"><dl>
						<dt>Max Depth</dt><dd><input type="range" min="0" max="10" step="1" field="maxDepth"/></dd>
						<div align="center">
							<input type="button" value="Generate" class="generate" />
						</div>
					</div>';

		editMenu += '<div class="group" name="Filter"><dl>';
		for( f in families )
			editMenu += '<dt>${f}</dt><dd><input type="checkbox" class="${families.indexOf(f)}"/></dd>';
		editMenu += '</dl></div>';
		var props = new hide.Element(editMenu);
		for( f in families ) {
			var checkBox = props.find('.${families.indexOf(f)}');
			checkBox.prop("checked", hasFilter(f));
			checkBox.change(function(_) {
				var checked : Bool = checkBox.prop("checked");
				checked ? filter.push(f) : filter.remove(f);
				ctx.rebuildProperties();
			});
		}

		var generateButton = props.find('.generate');
		generateButton.click(function(_) {
			var previous = root.clone();
			var actual = root;
			generate(ctx, root, maxDepth, 0);
			ctx.properties.undo.change(Custom(function(undo) {
				undo ? root.loadFrom(previous) : root.loadFrom(actual);
				ctx.onChange(this, null);
				ctx.rebuildProperties();
			}));
			ctx.onChange(this, null);
			ctx.rebuildProperties();
		});

		ctx.properties.add(props, this, function(pname) { ctx.onChange(this, null); });

		createMenu(ctx, root);
	}
	#end

	static var _ = Library.register("meshGenerator", MeshGenerator);
}