package hrt.prefab;

enum Inclusion {
	INCLUDE;
	EXCLUDE;
}

typedef PassQuery = {
	passName : String,
	inclusion : Inclusion
}

typedef SelectedPass = {
	pass : h3d.mat.Pass,
	all : Bool
}

class MaterialSelector extends hrt.prefab.Prefab {
	public static var CONFIG_KEY = "materialSelector";

	@:s public var blendModeEnabled : Bool = false;
	@:s public var blendModesSelected : Array<String> = [];
	@:s public var selections : Array<PassQuery> = [ { passName : "all", inclusion : Inclusion.INCLUDE } ];

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
		if (blendModesSelected.length > 0 && this.blendModeEnabled) {
			for ( m in mats ) {
				if (blendModesSelected.length > 0 && this.blendModeEnabled) {
					if (blendModesSelected.contains(m.blendMode.getName()))
						passes.push( { pass : m.mainPass, all : true } );
					continue;
				}
			}
		}
		else {
			var availablePasses = [];
			for ( m in mats )
				for (p in m.getPasses())
					availablePasses.push(p);

			var selectionSorted = selections.copy();
			selectionSorted.sort((s1, s2) -> s1.inclusion.match(INCLUDE) ? -1 : 1);

			for (s in selectionSorted) {
				switch (s.inclusion) {
					case Inclusion.INCLUDE:
						if (s.passName == "all") {
							for (p in availablePasses)
								passes.push( { pass: p, all: false } );
						}
						else {
							for (p in availablePasses)
								if (p.name == s.passName)
									passes.push( { pass: p, all: false } );
						}
					case Inclusion.EXCLUDE:
						for (p in passes)
							if (p.pass.name == s.passName)
								passes.remove(p);
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
			var newP = { passName: "all", inclusion: Inclusion.INCLUDE };
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

		var config : Array<{label: String, value: String}> = hide.Ide.inst.currentConfig.get(CONFIG_KEY);
		for ( s in selections ) {
			var passEl = new hide.Element('<div class="line">
				<span class="inclusion" style="background:${s.inclusion.match(Inclusion.INCLUDE) ? 'green' : 'red'}">${s.inclusion.match(Inclusion.INCLUDE) ? 'U' : '/'}</span>
				<div class="input"></div>
				<div class="ico ico-remove remove"></div>
			</div>');
			passEl.appendTo(passesEl.find(".passes"));

			var input : hide.Element;
			if (config != null) {
				input = new hide.Element('<select field="passName">
					<option value="all"}>All</option>
					${[for(c in config) '<option value="${c.value}">${c.label}</option>'].join("")}
				</select>');
			}
			else {
				input = new hide.Element('<input field="passName"/>');
			}
			input.appendTo(passEl.find(".input"));

			passEl.find('.inclusion').click(function(e) {
				var v = s.inclusion.match(Inclusion.INCLUDE) ? Inclusion.EXCLUDE : Inclusion.INCLUDE;
				function exec(undo : Bool) {
					var newV = v;
					var oldV = v.match(Inclusion.INCLUDE) ? Inclusion.EXCLUDE : Inclusion.INCLUDE;
					s.inclusion = undo ? oldV : newV;

					ctx.rebuildProperties();
					ctx.rebuildPrefab(this, true);
				}

				exec(false);
				ctx.properties.undo.change(Custom(exec));
			});

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