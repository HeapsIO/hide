package hrt.prefab.pbr;

import hrt.shader.CurvedNormal;
import hrt.prefab.fx.Emitter;
import hrt.shader.ParticleForward;

class BackLightingFlat extends hxsl.Shader implements h3d.scene.MeshBatch.MeshBatchAccess {
	public var perInstance : Bool = false;
	static var SRC = {

		@param var backLightingValue : Float;
		var backLightingIntensity : Float;

		function vertex() {
			backLightingIntensity = backLightingValue;
		}
	};
}

class BackLightingMask extends hxsl.Shader implements h3d.scene.MeshBatch.MeshBatchAccess {
	public var perInstance : Bool = false;
	static var SRC = {

		@const var VERTEX : Bool;
		@param var backLightingTexture : Sampler2D;
		@param var backLightingValue : Float;
		var backLightingIntensity : Float;
		var calculatedUV : Vec2;

		function vertex() {
			if( VERTEX ) {
				backLightingIntensity = backLightingTexture.get(calculatedUV).r * backLightingValue;
			}
		}

		function fragment() {
			if( !VERTEX ) {
				backLightingIntensity = backLightingTexture.get(calculatedUV).r * backLightingValue;
			}
		}
	};
}

class ParticleLit extends Prefab {

	@:s public var directLightingIntensity : Float = 1.0;
	@:s public var indirectLightingIntensity : Float = 1.0;
	@:s public var vertexShader : Bool = true;
	@:s public var backLightingIntensity : Float = 0.0;
	@:s public var backLightingMask : String = null;
	@:s public var curvature : Float = 0.0;

	@:s public var normalFlipY : Bool;
	@:s public var normalFlipX : Bool;
	@:s public var normalMap : String = null;
	@:s public var normalIntensity : Float = 1.0;

	public function new(?parent) {
		super(parent);
		type = "particleLit";
	}

	override function makeInstance( ctx : Context ):Context {
		ctx = ctx.clone(this);
		refreshShaders(ctx);
		updateInstance(ctx);
		return ctx;
	}

	function refreshShaders( ctx : Context ) {

		var pf = new ParticleForward();
		var cn = new CurvedNormal();
		var bl = backLightingMask != null && ctx.loadTexture(backLightingMask) != null ? new BackLightingMask() : new BackLightingFlat();
		var o = ctx.local3d;

		for( m in o.getMaterials() ) {

			m.mainPass.removeShader(m.mainPass.getShader(ParticleForward));
			m.mainPass.removeShader(m.mainPass.getShader(CurvedNormal));
			m.mainPass.removeShader(m.mainPass.getShader(BackLightingMask));
			m.mainPass.removeShader(m.mainPass.getShader(BackLightingFlat));

			if( m.mainPass.name != "forward" )
				continue;

			m.mainPass.addShader(bl);
			m.mainPass.addShader(pf);
			m.mainPass.addShader(cn);
		}
	}

	override function updateInstance( ctx : Context, ?propName : String ) {
		for( m in ctx.local3d.getMaterials() ) {
			var pf = m.mainPass.getShader(ParticleForward);
			if( pf != null ) {
				pf.VERTEX = vertexShader;
				pf.indirectLightingIntensity = indirectLightingIntensity;
				pf.directLightingIntensity = directLightingIntensity;
				pf.normalMap = normalMap == null ? null : ctx.loadTexture(normalMap);
				pf.normalIntensity = normalIntensity;
				pf.NORMAL = pf.normalMap != null;
				pf.NORMAL_FLIP_Y = normalFlipY;
				pf.NORMAL_FLIP_X = normalFlipX;
				pf.hl2_basis0.set(-1.0 / hxd.Math.sqrt(6.0), -1.0 / hxd.Math.sqrt(3.0), 1.0 / hxd.Math.sqrt(3.0));
				pf.hl2_basis1.set(-1.0 / hxd.Math.sqrt(6.0), 1.0 / hxd.Math.sqrt(2.0), 1.0 / hxd.Math.sqrt(3.0));
				pf.hl2_basis2.set(hxd.Math.sqrt(2.0/3.0), 0.0, 1.0 / hxd.Math.sqrt(3.0));
			}
			var cn = m.mainPass.getShader(CurvedNormal);
			if( cn != null ) {
				cn.VERTEX = vertexShader;
				cn.curvature = curvature;
			}
			var bl = m.mainPass.getShader(BackLightingFlat);
			if( bl != null ) {
				bl.backLightingValue = backLightingIntensity;
			}
			var blm = m.mainPass.getShader(BackLightingMask);
			if( blm != null ) {
				blm.VERTEX = vertexShader;
				blm.backLightingValue = backLightingIntensity;
				blm.backLightingTexture = ctx.loadTexture(backLightingMask);
			}
		}
	}

	#if editor
	override function getHideProps() : HideProps {
		return { 	icon : "cube",
					name : "ParticleLit",
					allowParent : function(p) return Std.is(p, Emitter)  };
	}

	override function edit( ctx : EditContext ) {
		super.edit(ctx);

		var props = new hide.Element('
			<div class="group" name="Particle Lit">
				<dl>
					<dt>Vertex Shader</dt><dd><input type="checkbox" field="vertexShader"/></dd>
					<dt>Curvature</dt><dd><input type="range" min="0.0" max="1.0" field="curvature"/></dd>
					<dt>Direct Intensity</dt><dd><input type="range" min="0.0" max="1.0" field="directLightingIntensity"/></dd>
					<dt>Indirect Intensity</dt><dd><input type="range" min="0.0" max="1.0" field="indirectLightingIntensity"/></dd>
				</dl>
			</div>
			<div class="group" name="Back Lighting">
				<dl>
					<dt>Intensity</dt><dd><input type="range" min="0.0" max="1.0" field="backLightingIntensity"/></dd>
					<dt>Mask</dt><dd><input type="texturepath" field="backLightingMask"/>
				</dl>
			</div>
			<div class="group" name="Normal Mapping">
				<dl>
					<dt>Texture</dt><dd><input type="texturepath" field="normalMap"/>
					<dt>Intensity</dt><dd><input type="range" min="0.0" max="1.0" field="normalIntensity"/></dd>
					<dt>Flip Y</dt><dd><input type="checkbox" field="normalFlipY"/></dd>
					<dt>Flip X</dt><dd><input type="checkbox" field="normalFlipX"/></dd>
				</dl>
			</div>
		');

		ctx.properties.add(props, this, function(pname) {
			ctx.onChange(this, pname);
		});
	}
	#end

	static var _ = Library.register("particleLit", ParticleLit);
}