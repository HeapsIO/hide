package hide.tools;

import h3d.scene.Interactive;
import h3d.scene.RenderContext;

class ChunkScene {

	public var chunkSize : Float;
	public var chunks : Array<Chunk> = [];
	public var sceneKey : Float = 0;

	var tmpVec = new h3d.Vector();
	var tmpBounds = new h3d.col.Bounds();
	var defaultBounds = new h3d.col.Bounds();

	public function new( chunkSize ) {
		this.chunkSize = chunkSize;
		var global = new Chunk(new h3d.col.Point(0,0,0));
		global.isGlobal = true;
		chunks.push(global);
		defaultBounds.setMin(new h3d.col.Point(0,0,0));
		defaultBounds.setMax(new h3d.col.Point(0,0,0));
	}

	// Use a stack for an iterarive version
	var stack : Array<h3d.scene.Object> = [];
	inline public function getSceneKey( obj : h3d.scene.Object ) : Float {
		var key = 0.0;
		var curCount = 1;

		stack[0] = obj;
		while( curCount != 0 ) {
			var obj = stack[curCount - 1];
			stack[curCount - 1] = null;
			curCount--;

			if( !obj.visible )
				continue;

			var gizmo = Std.downcast(obj, hide.view.l3d.Gizmo);
			if( gizmo != null )
				continue;

			var terrainBrushPreview = Std.downcast(obj, hide.prefab.terrain.Brush.BrushPreview);
			if( terrainBrushPreview != null )
				continue;

			// Ignore animated objects
			if( obj.currentAnimation == null ) {
				var absPos = @:privateAccess obj.absPos.getPosition(tmpVec);
				key += absPos.x + absPos.y + absPos.z;
				for( c in @:privateAccess obj.children ) {
					stack[curCount] = c;
					curCount++;
				}
			}
		}
		return key;
	}

	inline public function refreshInFrustumFlag( ctx : RenderContext ) {
		for( c in chunks ) {
			if( c.isGlobal )
				c.inFrustum = true;
			else
				c.inFrustum = c.bounds.inFrustum(ctx.camera.frustum);
		}
	}

	public function chunkifyScene( scene : h3d.scene.Scene ) {
		for( c in chunks )
			c.reset();
		chunkifyInteractives(scene);
		chunkifyObjects(scene, null);
	}

	public function chunkifyInteractives( scene : h3d.scene.Scene ) {
		for( i in @:privateAccess scene.interactives ) {

			// Gizmo
			if(	i.priority >= 100 ) {
				getGlobalChunk().addInteractive(i);
			}
			else {
				var oc = Std.downcast(i.shape, h3d.col.ObjectCollider);
				if( oc != null && oc.obj != null && oc.obj.visible ) {
					var pos = oc.obj.getAbsPos().getPosition().toPoint();
					// Only a point for interactive
					tmpBounds.setMin(pos);
					tmpBounds.setMax(pos);
					var chunks = getChunks(tmpBounds);
					for( c in chunks )
						c.addInteractive(i);
				}
			}
		}
	}

	inline function chunkifyObjects( obj : h3d.scene.Object, chunkOverride : Array<Chunk> ) {

		// Gizmo exception
		if( Std.downcast(obj, hide.view.l3d.Gizmo) != null ) {
			var gc = getGlobalChunk();
			chunkOverride = [gc];
			gc.addObject(obj, null);
			for( c in @:privateAccess obj.children )
				chunkifyObjects(c, chunkOverride);
			return;
		}

		// Terrain  exception
		var terrainBrushPreview = Std.downcast(obj, hide.prefab.terrain.Brush.BrushPreview);
		if( terrainBrushPreview != null ) {
			var gc = getGlobalChunk();
			gc.addObject(obj, null);
			return;
		}

		if( !obj.visible )
			return;

		if( Std.downcast(obj, h3d.scene.Light) != null ) {
			var gc = getGlobalChunk();
			gc.addObject(obj, null);
		}
		else {

			if( chunkOverride == null || chunkOverride.length == 0 ) {

				tmpBounds.load(defaultBounds);
				// Mesh Support
				var mesh = Std.downcast(obj, h3d.scene.Mesh);
				if( mesh != null ) {
					if( mesh.primitive != null ) {
						var b = mesh.primitive.getBounds();
						if( b != null && !b.isEmpty() )
							tmpBounds.load(b);
					}
				}
				tmpBounds.transform(obj.getAbsPos());

				var chunks : Array<Chunk> = getChunks(tmpBounds);
				for( c in chunks )
					c.addObject(obj, null);
				if( obj.currentAnimation != null ) {
					chunkOverride = chunks;
				}
			}
			else {
				for( c in chunkOverride ) {
					c.addObject(obj, null);
				}
			}
		}

		for( c in @:privateAccess obj.children )
			chunkifyObjects(c, chunkOverride);
	}

	inline function getGlobalChunk() : Chunk {
		var result = null;
		for( c in chunks ) {
			if( c.isGlobal ) {
				result = c;
				break;
			}
		}
		return result;
	}

	inline function getChunk( x : Int, y : Int ) {
		var r = null;
		for( c in chunks ) {
			if( c.pos.x == x * chunkSize && c.pos.y == y * chunkSize) {
				r = c;
				break;
			}
		}
		return r;
	}

	inline function getChunks( bounds : h3d.col.Bounds ) : Array<Chunk> {
		var result = [];
		for( x in hxd.Math.floor(bounds.xMin / chunkSize) ... hxd.Math.floor(bounds.xMax / chunkSize) + 1) {
			for( y in hxd.Math.floor(bounds.yMin / chunkSize) ... hxd.Math.floor(bounds.yMax / chunkSize) + 1) {
				var c = getChunk(x,y);
				if( c == null ) {
					c = new Chunk(new h3d.col.Point(x * chunkSize, y * chunkSize));
					c.updateBounds(chunkSize);
					chunks.push(c);
				}
				result.push(c);
			}
		}
		return result;
	}
}

class Chunk {

	public var isGlobal = false;
	public var inFrustum = false;
	public var bounds = new h3d.col.Bounds();
	public var pos : h3d.col.Point;

	public var objects : Array<{o : h3d.scene.Object, emitFlag : Bool}> = [];
	public var objectCount = 0;

	public var interactives : Array<h3d.scene.Interactive> = [];
	public var interactiveCount = 0;

	public function new( pos : h3d.col.Point ) {
		this.pos = pos;
	}

	public inline function reset() {
		objectCount = 0;
		interactiveCount = 0;
		bounds.zMin = 0;
		bounds.zMax = 0;
	}

	public inline function updateBounds( chunkSize : Float ) {
		bounds.addPoint(new h3d.col.Point(pos.x, pos.y));
		bounds.addPoint(new h3d.col.Point(pos.x + chunkSize, pos.y));
		bounds.addPoint(new h3d.col.Point(pos.x + chunkSize, pos.y + chunkSize));
		bounds.addPoint(new h3d.col.Point(pos.x, pos.y + chunkSize));
		bounds.zMin = 0;
		bounds.zMax = 0;
	}

	public inline function addObject( obj : h3d.scene.Object, b : h3d.col.Bounds) {
		objectCount++;
		if( objectCount > objects.length )
			objects.resize(objectCount);
		objects[objectCount - 1] = { o : obj, emitFlag : false };
		if( b != null ) {
			bounds.zMin = hxd.Math.min(bounds.zMin, b.zMin);
			bounds.zMax = hxd.Math.max(bounds.zMax, b.zMax);
		}
	}

	public inline function addInteractive( i : Interactive ) {
		interactiveCount++;
		if( interactiveCount > interactives.length )
			interactives.resize(interactiveCount);
		interactives[interactiveCount - 1] = i;
	}
}

class ChunkedScene extends h3d.scene.Scene {

	var cs = new ChunkScene(15.0);
	var lastChunkifyTime = 0.0;

	public function new() {
		super();
	}

	public function reset() {
		for( c in cs.chunks ) {
			c.reset();
			c.objects = [];
			c.interactives = [];
		}
	}

	override function emitRec( ctx : h3d.scene.RenderContext ) {

		var needChunkify = (ctx.time - lastChunkifyTime) > 1.0;
		if( !needChunkify ) {
			var newKey = cs.getSceneKey(this);
			needChunkify = newKey != cs.sceneKey;
			cs.sceneKey = newKey;
		}
		if( needChunkify ) {
			cs.chunkifyScene(this);
			lastChunkifyTime = ctx.time;
		}

		cs.refreshInFrustumFlag(ctx);

		for( c in cs.chunks ) {

			if( !c.isGlobal && !c.inFrustum )
				continue;

			for( i in 0 ... c.objectCount ) {
				var o = c.objects[i].o;

				// Some object can be in the objectlist without being visible ( Gizmo )
				var visible = o.visible;
				var curParent = o.parent;
				while( curParent != null && visible ) {
					visible = curParent.visible && visible;
					curParent = curParent.parent;
				}
				if( !visible )
					continue;

				if( c.objects[i].emitFlag )
					continue;
				else
					c.objects[i].emitFlag = true;

				if( o.posChanged ) {
					if( currentAnimation != null ) currentAnimation.sync();
					posChanged = false;
					o.calcAbsPos();
					for( c in o.children )
						c.posChanged = true;
				}
				if( !o.culled || ctx.computingStatic )
					o.emit(ctx);
			}
		}

		for( c in cs.chunks ) {
			for( i in 0 ... c.objectCount ) {
				c.objects[i].emitFlag = false;
			}
		}
	}

	override function handleEvent( event : hxd.Event, last : hxd.SceneEvents.Interactive ) {
		var	visibleInteractives : Array<h3d.scene.Interactive> = [];

		var interactiveCount = 0;
		for( c in cs.chunks ) {
			if( !c.isGlobal && !c.inFrustum )
				continue;
			interactiveCount += c.interactiveCount;
		}
		visibleInteractives.resize(interactiveCount);

		var i = 0;
		for( c in cs.chunks ) {
			if( !c.isGlobal && !c.inFrustum )
				continue;
			for( j in 0 ... c.interactiveCount ) {
				visibleInteractives[i] = c.interactives[j];
				i++;
			}
		}

		var old = interactives;
		interactives = visibleInteractives;
		var r = super.handleEvent(event, last);
		interactives = old;
		return r;
	}
}