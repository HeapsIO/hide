package hrt.prefab;

typedef MaterialSelection = {
	passName : String,
}

typedef SelectedPass = {
	pass : h3d.mat.Pass,
	all : Bool,
}

class MaterialSelector extends hrt.prefab.Prefab {

	@:s public var blendModeEnabled : Bool = false;
	@:s public var blendModesSelected : Array<String> = [];
	@:s public var selections : Array<MaterialSelection> = [{
		passName : "all",
	}];

	public function getPasses(local3d: h3d.scene.Object = null, filterObj : (obj : h3d.scene.Object) -> Bool = null) : Array<SelectedPass> {
		if (local3d == null)
			local3d = findFirstLocal3d();
		var mats = [];
		if ( filterObj == null )
			mats = local3d.getMaterials();
		else {
			function recObj(o : h3d.scene.Object) {
				mats = mats.concat(o.getMaterials(false));
				for ( c in @:privateAccess o.children ) {
					if ( !filterObj(c) )
						continue;
					recObj(c);
				}
			}
			recObj(local3d);
		}

		var passes = [];
		var selectionSorted = selections.copy();
		selectionSorted.sort((s1, s2) -> s1.passName == "all" ? return 1 : -1);
		for ( m in mats ) {
			if (blendModesSelected.length > 0 && this.blendModeEnabled) {
				if (blendModesSelected.contains(m.blendMode.getName()))
					passes.push({pass : m.mainPass, all : true});
				continue;
			}

			for ( selection in selections ) {
				if ( selection.passName == "all" ) {
					passes.push({pass : m.mainPass, all : true});
					break;
				} else if ( selection.passName == "mainPass" ) {
					passes.push({pass : m.mainPass, all : false });
				} else {
					var p = m.getPass(selection.passName);
					if ( p != null )
						passes.push({pass : p, all : false });
				}
			}
		}
		return passes;
	}

	#if editor
	override function getHideProps() : hide.prefab.HideProps {
		return {
			icon : "cog",
			name : "Material Selector",
			allowChildren: function(t) return true,
		};
	}

	override function edit( ctx : hide.prefab.EditContext ) {
		super.edit(ctx);

		var e = new hide.Element('
			<div class="group" name="Material selector">
				<div class="group blend-mode-group" name="Blend mode">
					<dl>
						<dt>Enabled</dt><dd><input type="checkbox" field="blendModeEnabled"/></dd>
					</dl>
				</div>
				<div class="group passes-group" name="Passes"></div>
			</div>
		');

		ctx.properties.add(e, this, function(propName) {
			if (propName == "blendModeEnabled") {
				var blendModeSelector = e.find(".blend-mode-selector");
				blendModeSelector.toggleClass("disabled", !this.blendModeEnabled);
				blendModeSelector.find('input').prop('disabled', !this.blendModeEnabled);
			}

			ctx.onChange(this, propName);
			ctx.rebuildPrefab(this);
		});

		// Blend mode selection
		var blendModeSelector = new hide.Element('<div class="blend-mode-selector array ${!this.blendModeEnabled ? 'disabled' : ''}">
		</div>');
		for (b in Type.allEnums(h3d.mat.BlendMode)) {
			var el = new hide.Element('<div class="blend-mode line">
				<input type="checkbox" ${blendModesSelected != null && blendModesSelected.contains(b.getName()) ? 'checked' : ''}/>
				<label>$b</label>
			</div>').appendTo(blendModeSelector);

			var cb = el.find("input");
			cb.change(function(e) {
				var newVal = cb.prop('checked');
				function exec(undo : Bool) {
					var val = undo ? !newVal : newVal;
					cb.prop('checked', val);
					if (val)
						blendModesSelected.push(b.getName());
					else
						blendModesSelected.remove(b.getName());
				}

				exec(false);
				ctx.properties.undo.change(Custom(exec));
			});

			cb.prop('disabled', !this.blendModeEnabled);
		}
		blendModeSelector.appendTo(e.find(".blend-mode-group").find('.content'));

		// Passes selection
		var passesEl = new hide.Element('<div>
			<div class="passes array"></div>
			<div class="array-sub-buttons">
				<div class="ico ico-plus add"></div>
			</div>
		</div>');

		passesEl.find(".add").click(function(e) {
			var newP = { passName: "" };
			function exec(undo : Bool) {
				if (undo)
					selections.remove(newP);
				else
					selections.push(newP);
				ctx.rebuildProperties();
				ctx.rebuildPrefab(this, true);
			}

			exec(false);
			ctx.properties.undo.change(Custom(exec));
		});

		for ( s in selections ) {
			var passEl = new hide.Element('<div class="line">
				<input field="passName"/>
				<div class="ico ico-remove remove"></div>
			</div>');
			passEl.appendTo(passesEl.find(".passes"));

			passEl.find('.remove').click(function(e) {
				var idx = selections.indexOf(s);
				function exec(undo : Bool) {
					if (undo)
						selections.insert(idx, s);
					else
						selections.remove(s);

					ctx.rebuildProperties();
					ctx.rebuildPrefab(this, true);
				}

				exec(false);
				ctx.properties.undo.change(Custom(exec));
			});

			ctx.properties.build(passEl, s, (pname) -> {
				updateInstance("selections");
				ctx.rebuildPrefab(this, true);
			});
		}
		passesEl.appendTo(e.find('.passes-group').find('.content'));
	}
	#end

	static var _ = Prefab.register("materialSelector", MaterialSelector);
}