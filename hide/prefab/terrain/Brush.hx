package hide.prefab.terrain;
import h3d.shader.pbr.AlphaMultiply;
import h3d.shader.FixedColor;
import h3d.mat.Stencil;
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

	public function isValid() : Bool {
		return ( brushMode.mode == Delete || (bitmap != null && tex != null && name != null && step > 0.0 && texPath != null) );
	}

	public function scaleForTex( tileSize : h2d.col.Point, texResolution : h2d.col.IPoint ) {
		if( tex != null ) {
			bitmap.scaleX = size / ((tileSize.x / texResolution.x) * tex.width);
			bitmap.scaleY = size / ((tileSize.y / texResolution.y) * tex.height);
		}
	}

	public function drawTo( target : h3d.mat.Texture, pos : h3d.col.Point, tileSize : h2d.col.Point, ?offset = 0 ) {
		var texSize = new h2d.col.IPoint(target.width + offset, target.height + offset);
		scaleForTex(tileSize, texSize);
		bitmap.setPosition(
						(pos.x * texSize.x - ( size / (tileSize.x / texSize.x) * 0.5 )),
						(pos.y * texSize.y - ( size / (tileSize.y / texSize.y) * 0.5 )));
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

class AlphaMult extends hxsl.Shader {
	static var SRC = {
		@param var amount : Float;
		var pixelColor : Vec4;
		function fragment() {
			pixelColor.a *= amount;
		}
	}
}

class BrushPreview extends h3d.scene.Mesh {

	var terrain : hrt.prefab.terrain.TerrainMesh;
	var decalShader : h3d.shader.pbr.VolumeDecal.DecalOverlay;
	public var opacity : Float = 1.0;

	public function new( terrain : hrt.prefab.terrain.TerrainMesh ) {
		this.terrain = terrain;
		var material = h3d.mat.MaterialSetup.current.createMaterial();
		material.props = material.getDefaultProps();
		material.mainPass.removeShader(material.mainPass.getShader(h3d.shader.pbr.PropsValues));
		material.mainPass.setPassName("afterTonemappingDecal");
		material.mainPass.depthWrite = false;
		material.mainPass.depthTest = GreaterEqual;
		material.mainPass.culling = Front;
		material.mainPass.setBlendMode(Alpha);
		material.shadows = false;
		super(h3d.prim.Cube.defaultUnitCube(), material, terrain.getScene());
		decalShader = new h3d.shader.pbr.VolumeDecal.DecalOverlay();
		decalShader.fadeStart = 1;
		decalShader.fadeEnd = 0;
		decalShader.fadePower = 1;
		decalShader.emissive = 0;
		decalShader.CENTERED = true;
		decalShader.GAMMA_CORRECT = false;
		material.mainPass.addShader(decalShader);
		var colorSet = new FixedColor();
		colorSet.color.set(1,1,1,1);
		colorSet.USE_ALPHA = false;
		material.mainPass.addShader(colorSet);
		var am = new AlphaMult();
		am.setPriority(-1);
		am.amount = opacity;
		material.mainPass.addShader(am);

		// Only draw the preview on terrain
		material.mainPass.stencil = new h3d.mat.Stencil();
		material.mainPass.stencil.setFunc(Equal, 0x01, 0x01, 0x01);
		material.mainPass.stencil.setOp(Keep, Keep, Keep);
	}

	public function previewAt( brush : Brush, pos : h3d.col.Point ) {
		setPosition(pos.x, pos.y, pos.z);
		setScale(brush.size);
		scaleZ = 1000;
		decalShader.colorTexture = brush.tex;
		material.mainPass.getShader(AlphaMult).amount = opacity;
		visible = true;
	}

	public function reset() {
		setPosition(0,0,0);
		visible = false;
		decalShader.colorTexture = null;
	}
}
