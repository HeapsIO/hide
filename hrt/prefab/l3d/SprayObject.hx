package hrt.prefab.l3d;

private class Block {
	public var objs : Array<h3d.scene.Object>;
	public var bounds : h3d.col.Bounds;
	public var next : Block;

	public function new() {
		objs = [];
		bounds = new h3d.col.Bounds();
	}

	public function addObject(o : h3d.scene.Object) {
		objs.push(o);
		var b = o.getBounds();
		bounds.addPos(b.xMin, b.yMin, b.zMin);
		bounds.addPos(b.xMax, b.yMax, b.zMax);
	}
}

class SprayObject extends h3d.scene.Object {
	static var gridSize : Int = 32;

	var grid : Array<Block>;
	var bounds : h3d.col.Bounds;
	var blockHead : Block;

	public function new( ?parent : h3d.scene.Object ) {
		bounds = new h3d.col.Bounds();
		super(parent);
	}

	override function syncRec(ctx : h3d.scene.RenderContext) {
		if(posChanged || blockHead == null) {
			super.syncRec(ctx);
			makeBlocks();
		}
	}

	public function makeBlocks() {
		blockHead = null;
		grid = [for(_ in 0...gridSize) for(_ in 0...gridSize) null];
		bounds.empty();
		for(c in children) {
			if(!Std.is(c, h3d.scene.Interactive)) {
				c.calcAbsPos();
				var b = c.getBounds();
				bounds.addPos(b.xMin, b.yMin, b.zMin);
				bounds.addPos(b.xMax, b.yMax, b.zMax);
			}
		}
		for(c in children) {
			if(!Std.is(c, h3d.scene.Interactive)) {
				var x = (c.x - bounds.xMin) * gridSize / (bounds.xMax - bounds.xMin);
				var y = (c.y - bounds.yMin) * gridSize / (bounds.yMax - bounds.yMin);
				var off = gridSize * hxd.Math.floor(y) + hxd.Math.floor(x);
				var b = grid[off];
				if(b == null) {
					b = new Block();
					grid[off] = b;
					b.next = blockHead;
					blockHead = b;
				}
				b.addObject(c);
			}
		}
	}

	override function emitRec( ctx : h3d.scene.RenderContext ) {
		var b = blockHead;
		while(b != null) {
			if(b.bounds.inFrustum(ctx.camera.frustum)) {
				for(o in b.objs) {
					o.emitRec(ctx);
				}
			}
			b = b.next;
		}
	}
}