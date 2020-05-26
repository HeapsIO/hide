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
	var global : Chunk;

	public function new( chunkSize ) {
		this.chunkSize = chunkSize;
		global = new Chunk(new h3d.col.Point(0,0,0));
		global.isGlobal = true;
		chunks.push(global);
		defaultBounds.setMin(new h3d.col.Point(0,0,0));
		defaultBounds.setMax(new h3d.col.Point(0,0,0));
	}

	// Use a stack for an iterarive version
	var stack : Array<h3d.scene.Object> = [];
	public function getSceneKey( obj : h3d.scene.Object ) : Float {
		var key = 0.0;
		var curCount = 1;

		stack[0] = obj;
		while( curCount != 0 ) {
			var obj = stack[curCount - 1];
			stack[curCount - 1] = null;
			curCount--;

			if( !obj.visible )
				continue;

			if( isGlobal(obj) )
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
				global.addInteractive(i);
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

	inline function isGlobal( obj : h3d.scene.Object ) {
		return Std.is(obj,hide.view.l3d.Gizmo) || Std.is(obj, hide.prefab.terrain.Brush.BrushPreview) || Std.is(obj, hrt.prefab.l3d.MeshSpray.MeshSprayObject) || Std.is(obj, h3d.scene.Light);
	}

	function chunkifyObjects( obj : h3d.scene.Object, chunkOverride : Array<Chunk> ) {
		var shared = { o : obj, emitFlag : false };

		if( isGlobal(obj) ) {
			global.addObject(obj, shared);
			return;
		}

		if( !obj.visible )
			return;

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
				c.addObject(obj, shared);
			if( obj.currentAnimation != null )
				chunkOverride = chunks;
		}
		else {
			for( c in chunkOverride ) {
				c.addObject(obj, shared);
			}
		}

		for( c in @:privateAccess obj.children )
			chunkifyObjects(c, chunkOverride);
	}

	function getChunk( x : Int, y : Int ) {
		var r = null;
		for( c in chunks ) {
			if( c.pos.x == x * chunkSize && c.pos.y == y * chunkSize && !c.isGlobal ) {
				r = c;
				break;
			}
		}
		return r;
	}

	function getChunks( bounds : h3d.col.Bounds ) : Array<Chunk> {
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
	public var interactives : Array<h3d.scene.Interactive> = [];

	public function new( pos : h3d.col.Point ) {
		this.pos = pos;
	}

	public function reset() {
		bounds.zMin = 0;
		bounds.zMax = 0;
		objects = [];
		interactives = [];
	}

	public inline function updateBounds( chunkSize : Float ) {
		bounds.addPoint(new h3d.col.Point(pos.x, pos.y));
		bounds.addPoint(new h3d.col.Point(pos.x + chunkSize, pos.y));
		bounds.addPoint(new h3d.col.Point(pos.x + chunkSize, pos.y + chunkSize));
		bounds.addPoint(new h3d.col.Point(pos.x, pos.y + chunkSize));
		bounds.zMin = 0;
		bounds.zMax = 0;
	}

	public inline function addObject( obj : h3d.scene.Object, shared ) {
		objects.push(shared);
	}

	public inline function addInteractive( i : Interactive ) {
		interactives.push(i);
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

			for( obj in c.objects ) {

				if( obj.emitFlag )
					continue;
				obj.emitFlag = true;

				var o = obj.o;
				if( c.isGlobal ) {
					if( o == this ) continue;
					o.emitRec(ctx);
					continue;
				}

				// Some object can be in the objectlist without being visible ( Gizmo )
				var visible = o.visible;
				var curParent = o.parent;
				while( curParent != null && visible ) {
					visible = curParent.visible && visible;
					curParent = curParent.parent;
				}
				if( !visible )
					continue;



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

		for( c in cs.chunks )
			for( obj in c.objects )
				obj.emitFlag = false;
	}

	override function handleEvent( event : hxd.Event, last : hxd.SceneEvents.Interactive ) {
		var	visibleInteractives : Array<h3d.scene.Interactive> = [];

		var interactiveCount = 0;
		for( c in cs.chunks ) {
			if( !c.isGlobal && !c.inFrustum )
				continue;
			interactiveCount += c.interactives.length;
		}
		visibleInteractives.resize(interactiveCount);

		var i = 0;
		for( c in cs.chunks ) {
			if( !c.isGlobal && !c.inFrustum )
				continue;
			for( j in 0...c.interactives.length ) {
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