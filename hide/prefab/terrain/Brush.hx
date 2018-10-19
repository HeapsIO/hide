package hide.prefab.terrain;
using Lambda;
import hxd.Key as K;

class Brush {
	public var name : String;
	public var size : Float;
	public var strength : Float;
	public var step : Float;
	public var tex : h3d.mat.Texture;
	public var bitmap : h2d.Bitmap;
	public var texPath : String;
	public var index : Int = -1;
	public var brushMode : BrushMode;

	public function new(){
		brushMode = new BrushMode();
	}

	public function isValid() : Bool{
		return ( brushMode.mode == Delete || (bitmap != null && tex != null && name != null && step > 0.0 && texPath != null));
	}

	public function scaleForTex(tileSize : Float, texResolution : Float){
		var scale = size / ((tileSize / texResolution) * tex.width);
		bitmap.setScale(scale);
	}

	public function drawTo( target : h3d.mat.Texture, pos : h3d.Vector, tileSize : Float, ?offset = 0){
		var texSize = target.width + offset;
		scaleForTex(tileSize, texSize);
		bitmap.setPosition(
						(pos.x * texSize - ( size / (tileSize / texSize) * 0.5 )),
						(pos.y * texSize - ( size / (tileSize / texSize) * 0.5 )));
		bitmap.drawTo(target);
	}
}

enum Mode {
	Paint;
	Sculpt;
	Delete;
}

enum SculptMode {
	AddSub;
	Set;
	Smooth;
}

class BrushMode {
	public var accumulate = false;
	public var substract = false;
	public var mode = Paint;
	public var scultpMode = AddSub;
	public function new(){}
}

class BrushPreview {

	var terrain : h3d.scene.pbr.terrain.Terrain;
	var tiles : Array<TilePreviewMesh> = [];
	var grid : h3d.prim.Grid;

	public function new(terrain){
		this.terrain = terrain;
		grid = new h3d.prim.Grid( terrain.cellCount, terrain.cellCount, terrain.cellSize, terrain.cellSize);
		grid.addUVs();
		grid.addNormals();
	}

	public function dispose(){
		for(tile in tiles)
			tile.dispose();
	}

	public function addPreviewMeshAt(x : Int, y : Int, brush : Brush, brushPos : h3d.Vector, ctx : Context) : TilePreviewMesh {
		var camera = @:privateAccess ctx.local3d.getScene().camera;
		var dir = camera.pos.sub(new h3d.Vector(terrain.getAbsPos().tx, terrain.getAbsPos().ty, terrain.getAbsPos().tz));
		var offsetDir = dir.z < 0 ? -1: 1;
		var tilePreview = null;
		for(tile in tiles){
			if(tile.used) continue;
			tilePreview = tile;
		}
		if(tilePreview == null){
			tilePreview = new TilePreviewMesh(grid, terrain);
			tiles.push(tilePreview);
		}
		tilePreview.used = true;
		var t = terrain.getTile(x,y);
		tilePreview.heightMap = t == null ? null : t.heightMap;
		tilePreview.shader.heightMapSize = terrain.heightMapResolution;
		var pos = new h3d.Vector(x * terrain.tileSize, y * terrain.tileSize);
		tilePreview.setPosition(pos.x, pos.y, pos.z + 0.1 * terrain.scaleZ * offsetDir);
		tilePreview.visible = true;
		tilePreview.shader.brushTex = brush.tex;
		tilePreview.shader.brushSize =  brush.size;
		tilePreview.shader.brushPos = brushPos;
		return tilePreview;
	}

	public function reset(){
		for(tile in tiles){
			tile.used = false;
			tile.visible = false;
		}
	}

	public function refreshMesh(){
		if(grid != null) grid.dispose();
		grid = new h3d.prim.Grid( terrain.cellCount, terrain.cellCount, terrain.cellSize, terrain.cellSize);
		grid.addUVs();
		grid.addNormals();
		for(tile in tiles)
			tile.primitive = grid;
	}
}

class TilePreviewMesh extends h3d.scene.Mesh {
	public var used = false;
	public var heightMap : h3d.mat.Texture;
	public var shader : hide.prefab.terrain.TilePreview;

	public function new(prim, parent){
		super(prim, null, parent);
		material.setDefaultProps("ui");
		material.shadows = false;
		material.blendMode = AlphaAdd;
		shader = new hide.prefab.terrain.TilePreview();
		material.mainPass.addShader(shader);
	}

	override function sync(ctx : h3d.impl.RenderContext) {
		shader.heightMap = heightMap;
		shader.heightMapSize = heightMap.width;
		shader.primSize = Std.instance(parent, h3d.scene.pbr.terrain.Terrain).tileSize;
	}
}
