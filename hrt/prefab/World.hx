package hrt.prefab;

using hrt.prefab.Object3D;
typedef ChunkData = {
	var id : String;
	var level : Int;
	var I : Int;
	var J : Int;
}

@:access(h3d.scene.HierarchicalWorld)
class World extends Object3D {

	#if editor
	public var editor : hide.comp.SceneEditor;
	#end

	var size : Int = 64;
	@:s public var worldUnit : Int = 1;
	@:s public var chunkGrid : Int = 32;
	@:s public var subdivPow : Float = 2.0;
	public var chunkSize(get, null) : Int;
	public function get_chunkSize() {
		return chunkGrid * worldUnit;
	}
	@:s public var chunkData : Array<ChunkData> = [];
	@:s public var debug : Bool = false;
	// Runtime map containing loaded prefabs.
	var chunkPrefabs : Map<String, hrt.prefab.Object3D>;

	public var depth(get, null) : Int;
	public function get_depth() {
		return Math.ceil(Math.log(size / chunkSize) / Math.log(2.0));
	}
	var datDir : String;

	public function new(parent, shared) {
		super(parent, shared);
		chunkPrefabs = [];
	}

	static var tmpMat = new h3d.Matrix();
	public function onCreateChunk(chunk : h3d.scene.HierarchicalWorld) {
		var chunkPos = chunk.getAbsPos().getPosition();
		var data = getChunkData(chunk.data.maxDepth - chunk.data.depth, chunkPos.x, chunkPos.y);
		var content = chunkPrefabs.get(data.id);
		if ( content == null )
			return;

		var tmp = new h3d.scene.Object();
		tmp.name = "chunk_inverse_transform";
		chunk.addChild(tmp);
		var chunkPos = getChunkPos(data);
		// create a tmp object to hold chunk inverse transform as prefab positions are stored relative to chunk position.
		tmp.x = -chunkPos.x;
		tmp.y = -chunkPos.y;
		for ( p in content.children ) {
			shared.current3d = tmp;
			var context = p.make(shared);
			if ( context.getLocal3d() == tmp )
				continue;
			#if editor
			for ( elt in p.flatten() )
				@:privateAccess editor.makeInteractive(elt);
			if ( editor != null ) {
				var curEdit = editor.curEdit;
				//var contexts = curEdit.rootContext.shared.contexts;
				//contexts.set(p, context);
				/*if ( context != null ) {
					var pobj = context.shared.root3d;
					var pobj2d = context.shared.root2d;
					if ( context.local3d != pobj && context.local3d != null )
						editor.curEdit.rootObjects.push(context.local3d);
					if ( context.local2d != pobj2d && context.local2d != null )
						editor.curEdit.rootObjects2D.push(context.local2d);
				}*/
			}
			#end
		}
	}

	function loadDataFromFiles() {
		for ( data in chunkData ) {
			var id = data.id;
			var path = datDir + id + "/content.prefab";
			var p = hxd.res.Loader.currentInstance.load(path).toPrefab().load();
			var content = new hrt.prefab.Object3D(this, shared);
			chunkPrefabs.set(id, content);
			var i = p.children.length;
			while ( i-- > 0 ) {
				var c = p.children[i];
				var object3D = Std.downcast(c, hrt.prefab.Object3D);
				if ( object3D != null ) {
					var trs = object3D.getTransform();
					var pos = getChunkPos(data);
					trs.translate(pos.x, pos.y, 0.0);
					object3D.setTransform(trs);
				}
				content.children.push(c);
				c.parent = this; // beware, this line remove c from c.parent.children
			}
		}
	}

	function initBounds() {
		// As dat chunk can exist without associated content (such as terrain), check all existing dat folders to extends bounds.
		#if editor
		var ide = hide.Ide.inst;
		var datDir = ide.getPath(datDir);
		#else
		var datDir = "res/" + datDir;
		#end
		var bounds = new h2d.col.Bounds();
		if ( !sys.FileSystem.exists(datDir) )
			return;
		for ( dir in sys.FileSystem.readDirectory(datDir) ) {
			try {
				var parts = dir.split("_");
				var I = Std.parseInt(parts[1]);
				var J = Std.parseInt(parts[2]);

				var tmp = new h2d.col.Point((I + 0.5) * chunkSize, (J + 0.5) * chunkSize);
				tmp.x += chunkSize * 0.5;
				tmp.y += chunkSize * 0.5;
				bounds.addPoint(tmp);
				tmp.x -= chunkSize;
				tmp.y -= chunkSize;
				bounds.addPoint(tmp);
			} catch (e : Dynamic) {
				continue;
			}
		}
		var maxX = Math.max(Math.abs(bounds.xMin), Math.abs(bounds.xMax));
		var maxY = Math.max(Math.abs(bounds.yMin), Math.abs(bounds.yMax));
		size = Math.ceil(Math.max(maxX, maxY) / worldUnit);
		size = hxd.Math.nextPOT(size) * worldUnit;
		size *= 2;
	}

	inline function getChunkSizeAtLevel(level : Int) {
		return chunkSize << level;
	}

	function getChunkData(level : Int, x : Float, y : Float) : ChunkData{
		var chunkSize = getChunkSizeAtLevel(level);
		var I = Math.floor(x / chunkSize) + 1;
		var J = Math.floor(y / chunkSize) + 1;
		var id = 'L${level}_${I >= 0 ? '+' : ''}${I}_${J >= 0 ? '+' : ''}${J}';
		return {id : id, level : level, I : I, J : J};
	}

	inline function getChunkPos(data : ChunkData) {
		var chunkSize = getChunkSizeAtLevel(data.level);
		return new h2d.col.Point((data.I - 0.5) * chunkSize, (data.J - 0.5) * chunkSize);
	}

	function findChunk(id : String) {
		for ( c in chunkData )
			if ( c.id == id )
				return c;
		return null;
	}

	function getObjectLevel(p : hrt.prefab.Object3D) {
		return 0;
	}

	override function serialize() : Dynamic {
		var tmpChildren = [];

		var chunks = new Map();
		if ( children.length > 0 ) {
			for ( c in children ) {
				if ( !isStreamable(c) )
					tmpChildren.push(c.serialize());
				else {
					var object3D = Std.downcast(c, hrt.prefab.Object3D);
					if ( object3D == null )
						throw "TODO : stream prefab that are not 3D objects";
					object3D = cast(object3D.clone(null, null), hrt.prefab.Object3D);
					var data = getChunkData(getObjectLevel(object3D), object3D.x, object3D.y);
					// prefab positions are stored relative to the chunk parent.
					// it's arbitrary but some work has to be done as the make occurs with the chunk as parent.
					var trs = object3D.getTransform();
					var chunkPos = getChunkPos(data);
					trs.translate(-chunkPos.x, -chunkPos.y, 0.0);
					object3D.setTransform(trs);
					var chunk : Dynamic = chunks.get(data.id);
					if ( chunk == null ) {
						chunk = {};
						chunk.children = [];
						chunks.set(data.id, chunk);
					}
					chunk.children.push(object3D.serialize());
					if ( findChunk(data.id) == null ) {
						chunkData.push(data);
					}
				}
			}
		}

		#if editor
		var ide = hide.Ide.inst;
		var i = chunkData.length;
		var datDir = ide.getPath(datDir);
		while ( i-- > 0 ) {
			var data = chunkData[i];
			var id = data.id;
			if ( chunks.get(id) == null ) {
				chunkData.remove(data);
				var chunkDir = datDir + id;
				var contentPath = chunkDir + "/content.prefab";
				if ( sys.FileSystem.exists(contentPath) )
					sys.FileSystem.deleteFile(contentPath);
				if ( sys.FileSystem.exists(chunkDir) && sys.FileSystem.readDirectory(chunkDir).length == 0 )
					sys.FileSystem.deleteDirectory(chunkDir);
			}
		}

		// TODO : optimize and flag chunks as dirty during edition if needed.
		var first = true;
		for ( id in chunks.keys() ) {
			var data = chunks.get(id);
			if(first && !sys.FileSystem.exists(datDir))
				sys.FileSystem.createDirectory(datDir);
			if ( !sys.FileSystem.exists(datDir + id) )
				sys.FileSystem.createDirectory(datDir + id);
			var content = ide.toJSON(data);
			sys.io.File.saveContent('${datDir}/${id}/content.prefab', content);
			first = false;
		}

		if ( sys.FileSystem.exists(datDir) && sys.FileSystem.readDirectory(datDir).length == 0 )
			sys.FileSystem.deleteDirectory(datDir);
		#end
		var obj : Dynamic = save();
		obj.type = type;
		obj.children = tmpChildren;
		return obj;
	}

	function initPath() {
		var path = new haxe.io.Path(shared.currentPath);
		datDir = if ( path.dir == null )
			'${path.file}.dat/';
		else
			'${path.dir}/${path.file}.dat/';
	}

	function isStreamable(p : hrt.prefab.Prefab) {
		return Std.isOfType(p, hrt.prefab.Object3D);
	}

	function createObjectFromData(data : h3d.scene.HierarchicalWorld.WorldData) : h3d.scene.HierarchicalWorld {
		return new h3d.scene.HierarchicalWorld(shared.current3d, data);
	}

	override function make(?sh:hrt.prefab.Prefab.ContextMake) : Prefab {
		initPath();
		loadDataFromFiles();
		initBounds();
		var d = { size : size,
			x : 0,
			y : 0,
			depth : 0,
			subdivPow : subdivPow,
			maxDepth : depth,
			onCreate : onCreateChunk,
		};
		var worldObj = createObjectFromData(d);

		local3d = worldObj;

		var old3d = shared.current3d;
		shared.current3d = local3d ?? shared.current3d;

		for( c in children ) {
			if ( !isStreamable(c) )
				makeChild(c);
		}

		shared.current3d = old3d;

		// Calling init on root after non streamable objects are made.
		// This way objects such as terrain can be created in custom onCreateChunk.
		worldObj.init();
		updateInstance();
		postMakeInstance();
		return this;
	}

	override function updateInstance(?propName : String) {
		super.updateInstance(propName);
		h3d.scene.HierarchicalWorld.DEBUG = debug;
	}

	#if editor
	override function edit( ctx : hide.prefab.EditContext ) {
		super.edit(ctx);
		var props = new hide.Element('
		<div class="group" name="World">
			<dl>
				<dt>Chunk grid</dt>
				<dd>
					<select field="chunkGrid" type="number">
						<option value="8">8</option>
						<option value="16">16</option>
						<option value="32">32</option>
						<option value="64">64</option>
						<option value="128">128</option>
						<option value="256">256</option>
						<option value="512">512</option>
						<option value="1024">1024</option>
					</select>
				</dd>
			</dl>
			<dl>
				<dt>World unit</dt><dd><input type="range" field="worldUnit" min="1" step="1"/></dd>
				<dt>Distance pow</dt><dd><input type="range" min="0.5" max="5" field="subdivPow" min="0.5"/></dd>
				<dt>Debug</dt><dd><input type="checkbox" field="debug"/></dd>
			</dl>
		</div>');
		ctx.properties.add(props, this, function(pname) {
			ctx.onChange(this, pname);
		});
	}
	#end

	static var _ = Prefab.register("world", World);
}
