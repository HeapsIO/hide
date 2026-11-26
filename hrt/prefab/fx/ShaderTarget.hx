package hrt.prefab.fx;

@:access(hrt.prefab.Shader)
@:access(hrt.prefab.fx.ShaderTarget)
class ShaderTargetObj extends h3d.scene.Object {
	public var tag : String;
	public var priority : Int = 1;
	public var shadersRoot : ShaderTarget;
	var applied = false;

	// The shader prefabs of shadersRoot.getSelection() and their instances, same indices
	var selection : Array<Shader>;
	var instances : Array<hxsl.Shader>;

	public function init(fx : hrt.prefab.fx.FX) {
		// Made during the make of the fx, so that its animations use these instances
		var sel = shadersRoot.getSelection();
		instances = [for (s in sel) s.shader ?? s.makeShaderInstance()];
		selection = sel;

		var fxAnim : hrt.prefab.fx.FX.FXAnimation = cast fx.local3d;
		if (fxAnim == null)
			return;

		if (fxAnim.shaderTargets == null)
			fxAnim.shaderTargets = [];
		fxAnim.shaderTargets.push(this);
	}

	public function applyShaders() {
		if (selection == null)
			return;
		for (i => s in selection)
			applyShader(s, instances[i]);
		applied = true;
	}

	public function removeShaders() {
		if (selection != null) {
			for (i => s in selection) {
				if (instances[i] != null)
					s.removeFrom(parent, instances[i]);
			}
		}
		applied = false;
	}

	public function isApplied() {
		return applied;
	}

	function applyShader(s: Shader, shader: hxsl.Shader) {
		if (shader != null)
			s.applyTo(parent, shader, (o) -> return !Std.isOfType(o, hrt.prefab.fx.FX.FXAnimation) );
	}

	override function onRemove() {
		super.onRemove();
		removeShaders();
		if (parent?.allocated)
			ShaderTarget.updateShaderTargets(parent);
	}
}

@:prefabIcon(HuiRes.ui.icons.prefab.shader_target)
@:prefabName("Shader Target")
class ShaderTarget extends Object3D {
	@:s public var tag : String;
	@:s public var priority : Int = 1;

	public var target : h3d.scene.Object;

	// Cache of getSelection(), only depends on the prefab data
	var selection : Array<Shader>;

	public function new(parent:Prefab, contextShared: ContextShared) {
		super(parent, contextShared);
	}

	/**
		The enabled shaders applied to the target : the ones of the Shader, Material and MaterialSelector children of the Object3D children
	**/
	function getSelection() : Array<Shader> {
		#if !(editor || editor_hl)
		if (selection != null)
			return selection;
		#end

		var shaders : Array<Shader> = [];
		for (c in children) {
			if (!Std.isOfType(c, Object3D))
				continue;
			for (gc in c.children) {
				if (gc.enabled && !gc.editorOnly && (Std.isOfType(gc, Shader) || Std.isOfType(gc, Material) || Std.isOfType(gc, MaterialSelector)))
					gc.findAll(Shader, (s) -> s.enabled && !s.editorOnly, false, shaders);
			}
		}

		#if !(editor || editor_hl)
		selection = shaders;
		#end
		return shaders;
	}

	override public function reload(p : Dynamic) {
		super.reload(p);
		selection = null;
	}

	public static function updateShaderTargets(o : h3d.scene.Object) {
		var sts : Array<ShaderTargetObj> = [];
		for (idx in 0...o.numChildren) {
			if (!Std.isOfType(o.getChildAt(idx), ShaderTargetObj))
				continue;
			sts.push(cast o.getChildAt(idx));
		}

		var actives = new Map<String, Array<ShaderTargetObj>>();
		for (st in sts) {
			if (st.tag == null) {
				if (!st.isApplied())
					st.applyShaders();
				continue;
			}

			var arr = actives.get(st.tag);
			if (arr == null) {
				arr = [];
				actives.set(st.tag, arr);
			}

			var idx = 0;
			while (idx < arr.length) {
				if (arr[idx].priority <= st.priority)
					break;
				idx++;
			}

			arr.insert(idx, st);
		}

		for (arr in actives) {
			for (idx in 1...arr.length) {
				if (arr[idx].isApplied())
					arr[idx].removeShaders();
			}
		}

		for (arr in actives) {
			if (!arr[0].isApplied())
				arr[0].applyShaders();
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
		o.init(fx);
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
