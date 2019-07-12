package hide.prefab.terrain;
import h3d.shader.FixedColor;
import h3d.mat.Stencil;
import hrt.prefab.l3d.AdvancedDecal;
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
	public var firstClick = false;

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
	AddSub;
	Set;
	Smooth;
	Paint;
	Delete;
	NoMode;
}

enum LockAxe {
	LockX;
	LockY;
	NoLock;
}

class BrushMode {
	public var accumulate = false;
	public var subAction = false;
	public var lockDir = false;
	public var snapToGrid = false;
	public var mode = NoMode;
	public var lockAxe = NoLock;
	public var setHeightValue = 0.0;
	public function new(){}
}

class BrushPreview extends h3d.scene.Object {

	var terrain : hrt.prefab.terrain.TerrainMesh;
	var mesh : h3d.scene.pbr.Decal;
	var shader : h3d.shader.pbr.VolumeDecal.DecalOverlay;

	public function new( terrain : hrt.prefab.terrain.TerrainMesh ) {
		super(terrain.getScene());
		this.terrain = terrain;
		mesh = new h3d.scene.pbr.Decal(h3d.prim.Cube.defaultUnitCube(), this);
		shader = new h3d.shader.pbr.VolumeDecal.DecalOverlay();
		mesh.material.mainPass.addShader(shader);
		mesh.material.mainPass.setPassName("afterTonemappingDecal");
		mesh.material.mainPass.depthWrite = false;
		mesh.material.mainPass.depthTest = GreaterEqual;
		mesh.material.mainPass.culling = Front;
		mesh.material.shadows = false;
		mesh.material.blendMode = Alpha;
		mesh.scaleZ = 1000;
		shader.fadeStart = 1;
		shader.fadeEnd = 0;
		shader.fadePower = 1;
		shader.emissive = 0;
		var colorSet = new FixedColor();
		colorSet.color.set(1,1,1,1);
		colorSet.USE_ALPHA = false;
		mesh.material.mainPass.addShader(colorSet);
		shader.CENTERED = true;

		// Only draw the preview on terrain
		mesh.material.mainPass.stencil = new h3d.mat.Stencil();
		mesh.material.mainPass.stencil.setFunc(Equal, 0x01, 0x01, 0x01);
		mesh.material.mainPass.stencil.setOp(Keep, Keep, Keep);
	}

	public function setBrushTexture( texture : h3d.mat.Texture ) {
		shader.colorTexture = texture;
	}

	public function previewAt( brush : Brush, pos : h3d.Vector ) {
		setPosition(pos.x, pos.y, pos.z);
		setBrushTexture( brush.tex );
		setScale(brush.size);
		visible = true;
	}

	public function reset() {
		setPosition(0,0,0);
		visible = false;
		shader.colorTexture = null;
	}
}
