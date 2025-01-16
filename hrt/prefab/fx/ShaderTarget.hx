package hrt.prefab.fx;

class ShaderTargetObj extends h3d.scene.Object {
	public var tag : String;
	public var priority : Int = 1;
	public var shadersRoot : hrt.prefab.Object3D;

	public function apply(fx : hrt.prefab.fx.FX) {
		var fxAnim : hrt.prefab.fx.FX.FXAnimation = cast fx.local3d;
		shadersRoot.local3d = parent;
		for ( s in shadersRoot.findAll(Shader) ) {
			s.filterObj = o -> return o != fxAnim;
			if (s.shader == null) {
				s.makeShader();
				@:privateAccess s.updateInstance();
			}
			s.apply3d();
		}

		if (fxAnim == null)
			return;

		@:privateAccess fxAnim.onRemoveFun = () -> {
			this.remove();
		}
	}

	override function onRemove() {
		for ( s in shadersRoot.findAll(Shader) )
			s.dispose();
	}
}

class ShaderTarget extends Object3D {
	@:s public var tag : String;
	@:s public var priority : Int = 1;

	public var target : h3d.scene.Object;
	public var shaders : Array<hrt.prefab.Shader>;

	public function new(parent:Prefab, contextShared: ContextShared) {
		super(parent, contextShared);
		this.editorOnly = true;
	}

	public static function updateShaderTargets(o : h3d.scene.Object) {
		var sts = o.findAll(obj -> Std.downcast(obj, ShaderTargetObj));
		for (st in sts) {
			if (st.tag == null) continue;

			for (st2 in sts) {
				if (st2 == st) continue;
				if (st2.tag != st.tag) continue;

				var toRemove = st.priority > st2.priority ? st2 : st;
				toRemove.remove();
				sts.remove(toRemove);
				break;
			}
		}
	}

	public function applyShaderTarget(fx : hrt.prefab.fx.FX, target : h3d.scene.Object) {
		var o = new hrt.prefab.fx.ShaderTarget.ShaderTargetObj(target);
		o.priority = this.priority;
		o.tag = this.tag;
		o.shadersRoot = this;

		updateShaderTargets(target);

		if (o.parent != null)
			o.apply(fx);
	}

	#if editor
	override function getHideProps() : hide.prefab.HideProps {
		return { icon : "dot-circle-o", name : "Shader Target" };
	}

	override function edit( ctx : hide.prefab.EditContext ) {
		super.edit(ctx);

		var props = new hide.Element('
			<div class="group" name="Shader Target">
				<dl>
					<dt>Tag</dt><dd><input type="text" field="tag"/></dd>
					<dt>Priority</dt><dd><input type="number" min="0" max="10" value="0" field="priority"/></dd>
				</dl>
			</div>
		');
		ctx.properties.add(props, this, function(pname) {
			ctx.onChange(this, pname);
		});
	}
	#end

	static var _ = Prefab.register("ShaderTarget", ShaderTarget);
}
