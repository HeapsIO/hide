package hrt.prefab.pbr;

import hrt.shader.AnisotropicFoward.FlatValue;
import hrt.shader.AnisotropicFoward.NoiseTexture;
import hrt.shader.AnisotropicFoward;

class Anisotropy extends Prefab {

	public var amount : Float = 0.0;
	public var direction : Float = 0.0;
	public var noiseTexturePath : String = null;

	public function new(?parent) {
		super(parent);
		type = "anisotropy";
	}

	override function load( obj : Dynamic ) {
		super.load(obj);
		if( obj.amount != null ) amount = obj.amount;
		if( obj.direction != null ) direction = obj.direction;
		if( obj.noiseTexturePath != null ) noiseTexturePath = obj.direcnoiseTexturePathtion;
	}

	override function save() {
		var obj : Dynamic = super.save();
		obj.amount = amount;
		obj.direction = direction;
		obj.noiseTexturePath = noiseTexturePath;
		return obj;
	}

	override function makeInstance( ctx : Context ):Context {
		ctx = ctx.clone(this);
		refreshShaders(ctx);
		updateInstance(ctx);
		return ctx;
	}

	function refreshShaders( ctx : Context ) {
		var af = new FlatValue();
		var as = new AnisotropicFoward();
		as.setPriority(-1);
		var an = new NoiseTexture();
		var noiseTexture = noiseTexturePath != null ? ctx.loadTexture(noiseTexturePath) : null;
		var o = ctx.local3d;
		for( m in o.getMaterials() ) {
			m.mainPass.removeShader(m.mainPass.getShader(NoiseTexture));
			m.mainPass.removeShader(m.mainPass.getShader(FlatValue));
			m.mainPass.removeShader(m.mainPass.getShader(AnisotropicFoward));
		}
		for( m in o.getMaterials() ) {

			if( m.mainPass.name != "forward" )
				continue;

			if( noiseTexture != null ) {
				if( m.mainPass.getShader(NoiseTexture) == null )
					m.mainPass.addShader(an);
			}
			else if( m.mainPass.getShader(FlatValue) == null ) {
				m.mainPass.addShader(af);
			}

			if( m.mainPass.getShader(AnisotropicFoward) == null ) {
				m.mainPass.addShader(as);
			}
		}
	}

	override function updateInstance( ctx : Context, ?propName : String ) {
		for( m in ctx.local3d.getMaterials() ) {
			var af = m.mainPass.getShader(FlatValue);
			var an = m.mainPass.getShader(NoiseTexture);
			if( af != null ) {
				af.amount = amount;
				var angle = hxd.Math.degToRad(direction);
				af.dirVector.set(hxd.Math.cos(angle), hxd.Math.sin(angle), 0);
			}
			if( an != null ) {
				an.noiseTexture = noiseTexturePath != null ? ctx.loadTexture(noiseTexturePath) : null;
			}
		}
	}

	#if editor
	override function getHideProps() : HideProps {
		return { 	icon : "cube", 
					name : "Anisotropy",
					allowParent : function(p) return p.to(Material) != null  };
	}

	override function edit( ctx : EditContext ) {
		super.edit(ctx);

		var props = new hide.Element('
			<div class="group" name="Anisotropy">
				<dl>
					<dt>Amount</dt><dd><input type="range" min="0" max="1" field="amount"/></dd>
					<dt>Direction</dt><dd><input type="range" min="0" max="180" field="direction"/></dd>
					<dt>Noise Texture</dt><dd><input type="texturepath" field="noiseTexturePath"/>
				</dl>
			</div>
		');

		ctx.properties.add(props, this, function(pname) {
			if( pname == "noiseTexturePath" )
				refreshShaders(ctx.getContext(this));
			ctx.onChange(this, pname);
		});
	}
	#end

	static var _ = Library.register("anisotropy", Anisotropy);
}