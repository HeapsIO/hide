package hrt.prefab;

typedef MaterialSelection = {
	passName : String,
}

class MaterialSelector extends hrt.prefab.Prefab {

	@:s public var selections : Array<MaterialSelection> = []; 

	public function getPasses(local3d: h3d.scene.Object = null) : Array<h3d.mat.Pass> {
		if (local3d == null)
			local3d = findFirstLocal3d();
		var mats = local3d.getMaterials();
		var passes = [];
		for ( m in mats ) {
			for ( selection in selections ) {
				if ( selection.passName == "all" || selection.passName == "mainPass" ) {
					passes.push(m.mainPass);
					break;
				} else {
					var p = m.getPass(selection.passName);
					if ( p != null )
						passes.push(p);
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

		var e1 = new hide.Element('
			<div class="group" name="Selections">
				<ul id="selections"></ul>
			</div>
		');
		ctx.properties.add(e1, function(propName) {
			ctx.onChange(this, propName);
			ctx.rebuildPrefab(this);
		});

		var list = e1.find("ul#selections");
		for ( s in selections ) {
			var es = new hide.Element('
			<div class="group" name="Selection">
				<dl>
					<dt>Pass Name</dt><dd><input type="text" field="passName"/></dd>
				</dl>
			</div>
			');
			es.appendTo(list);
			ctx.properties.build(es, s, (pname) -> {
				updateInstance("selections");
				ctx.rebuildPrefab(this, true);
			});
		}
		var add = new hide.Element('<li><p><a href="#">[+]</a></p></li>');
		add.appendTo(list);
		add.find("a").click(function(_) {
			selections.push({ 
				passName : "",
			});
			ctx.rebuildProperties();
		});
		var sub = new hide.Element('<li><p><a href="#">[-]</a></p></li>');
		sub.appendTo(list);
		sub.find("a").click(function(_) {
			selections.pop();
			ctx.rebuildProperties();
		});
	}
	#end

	static var _ = Prefab.register("materialSelector", MaterialSelector);
}