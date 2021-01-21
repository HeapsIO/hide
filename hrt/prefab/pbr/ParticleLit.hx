package hrt.prefab.pbr;

import hrt.shader.ParticleForward;

class ParticleLit extends Prefab {

	public var vertexShader : Bool = true;

	public function new(?parent) {
		super(parent);
		type = "particleLit";
	}

	override function load( obj : Dynamic ) {
		super.load(obj);
		if( obj.vertexShader != null ) vertexShader = obj.vertexShader;
	}

	override function save() {
		var obj : Dynamic = super.save();
		obj.vertexShader = vertexShader;
		return obj;
	}

	override function makeInstance( ctx : Context ):Context {
		ctx = ctx.clone(this);
		refreshShaders(ctx);
		updateInstance(ctx);
		return ctx;
	}

	function refreshShaders( ctx : Context ) {

		var pf = new ParticleForward();
		var o = ctx.local3d;

		for( m in o.getMaterials() ) {
			if( m.mainPass.name != "forward" )
				continue;
			m.mainPass.removeShader(m.mainPass.getShader(ParticleForward));
			m.mainPass.addShader(pf);
			pf.VERTEX = vertexShader;
		}
		
	}

	override function updateInstance( ctx : Context, ?propName : String ) {
		for( m in ctx.local3d.getMaterials() ) {
			var pf = m.mainPass.getShader(ParticleForward);
			if( pf != null ) {
				pf.VERTEX = vertexShader;
			}
		}
	}

	#if editor
	override function getHideProps() : HideProps {
		return { 	icon : "cube", 
					name : "ParticleLit",
					allowParent : function(p) return true  };
	}

	override function edit( ctx : EditContext ) {
		super.edit(ctx);

		var props = new hide.Element('
			<div class="group" name="Particle Lit">
				<dl>
					<dt>Vertex Shader</dt><dd><input type="checkbox" field="vertexShader"/></dd>
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