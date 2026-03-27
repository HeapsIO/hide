package hrt.prefab.fx;

class ShaderTargetObj extends h3d.scene.Object {
	public var tag : String;
	public var priority : Int = 1;
	public var shadersRoot : ShaderTarget;

	public function apply(fx : hrt.prefab.fx.FX) {
		function reparentChildren(obj : hrt.prefab.Object3D) {
			var i = 0;
			while ( i < obj.children.length ) {
				var c = obj.children[i];
				if ( (c.enabled && !c.editorOnly) && (Std.isOfType(c, Shader) || Std.isOfType(c, Material) || Std.isOfType(c, MaterialSelector)) ) {
					shadersRoot.addChild(c);
					i--;
				}
				i++;
			}
		}

		var children = shadersRoot.children.copy();
		if (children.length > 0) {
			@:privateAccess shadersRoot._children = [];
			for (c in children) {
				if (Std.isOfType(c, Object3D))
					reparentChildren(cast c);
			}
		}

		var fxAnim : hrt.prefab.fx.FX.FXAnimation = cast fx.local3d;
		shadersRoot.local3d = parent;

		if (fxAnim == null)
			return;

		if (fxAnim.shaderTargets == null)
			fxAnim.shaderTargets = [];
		fxAnim.shaderTargets.push(this);
	}

	public function applyShaders() {
		for ( s in shadersRoot.findAll(Shader) ) {
			if (!s.enabled || s.editorOnly)
				continue;
			if (s.shader == null) {
				s.makeShader();
				@:privateAccess s.updateInstance();
			}
			applyShader(s);
		}
	}

	public function removeShaders() {
		for (s in shadersRoot.findAll(Shader))
			s.dispose();
	}

	function applyShader(s: Shader) {
		s.apply3d((o) -> return !Std.isOfType(o, hrt.prefab.fx.FX.FXAnimation) );
	}

	override function onRemove() {
		super.onRemove();
		removeShaders();
		if (parent?.allocated)
			ShaderTarget.updateShaderTargets(shadersRoot.target);
	}
}

class ShaderTarget extends Object3D {
	@:s public var tag : String;
	@:s public var priority : Int = 1;

	public var target : h3d.scene.Object;

	public function new(parent:Prefab, contextShared: ContextShared) {
		super(parent, contextShared);
	}

	public static function updateShaderTargets(o : h3d.scene.Object) {
		var sts = o.findAll(obj -> Std.downcast(obj, ShaderTargetObj));
		for (st in sts) {
			if (st.tag == null) continue;

			for (st2 in sts) {
				if (st2 == st) continue;
				if (st2.tag != st.tag) continue;

				var toRemove = st.priority > st2.priority ? st2 : st;
				toRemove.visible = false;
				toRemove.removeShaders();
				sts.remove(toRemove);
				break;
			}
		}

		if (sts.length > 0) {
			var actives = new Map<String, ShaderTargetObj>();
			for (s in sts) {
				if (actives.get(s.tag) != null)
					continue;
				actives.set(s.tag, s);
			}

			for (k in actives.keys())
				actives.get(k).applyShaders();
		}
	}

	function makeShaderTargetObj(target : h3d.scene.Object) {
		return new hrt.prefab.fx.ShaderTarget.ShaderTargetObj(target);
	}

	public function applyShaderTarget(fx : hrt.prefab.fx.FX, target : h3d.scene.Object) {
		if (target == null)
			return;
		var o = makeShaderTargetObj(target);
		o.priority = this.priority;
		o.tag = this.tag;
		o.shadersRoot = this;
		o.apply(fx);
		updateShaderTargets(target);
	}

	override function edit2(ctx:EditContext2) {
		super.edit2(ctx);

		var tags : Array<String> = #if editor cast hide.Ide.inst.currentConfig.get("fx.shaderTargetsTags") ?? #end [];

		ctx.build(
			<category("Shader Target")>
				<select(tags) field={tag}/>
				<slider field={priority} min={0}/>
			</category>
		);
	}

	override function load(data : Dynamic) {
		super.load(data);
		this.editorOnly = false;
	}

	override function copy(data: Prefab) {
		super.copy(data);
		this.editorOnly = false;
	}

	#if editor
	override function getHideProps() : hide.prefab.HideProps {
		return { icon : "dot-circle-o", name : "Shader Target" };
	}

	override function edit( ctx : hide.prefab.EditContext ) {
		super.edit(ctx);

		var tags : Array<String> = hide.Ide.inst.currentConfig.get("fx.shaderTargetsTags");
		if (tags == null)
			tags = [];
		var props = new hide.Element('
			<div class="group" name="Shader Target">
				<dl>
					<dt>Tag</dt><dd id="tag-selector"></dd>
					<dt>Priority</dt><dd><input type="number" min="0" max="10" value="0" field="priority"/></dd>
				</dl>
			</div>
		');

		var tagSelector = new hide.Element('<select>
			<option value="">none</option>
			${[for(t in tags) '<option value="$t" ${t == tag ? "selected" : ""}>$t</option>'].join("")}
		</select>').appendTo(props.find("#tag-selector"));

		tagSelector.change(function(e) {
			var oldVal = this.tag;
			this.tag = tagSelector.val();
			var newVal = this.tag;

			ctx.properties.undo.change(Custom(function(isUndo){
				this.tag = isUndo ? oldVal : newVal;
				tagSelector.val(this.tag);
			}));
		});

		ctx.properties.add(props, this, function(pname) {
			ctx.onChange(this, pname);
		});
	}
	#end

	static var _ = Prefab.register("ShaderTarget", ShaderTarget);
}
