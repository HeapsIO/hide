package hide.prefab.materialEditor;

class Material extends MaterialEditor<h3d.mat.Material> {

	override function edit2(ctx:hrt.prefab.EditContext2) {
		ctx.build(
			<root>
				<select(["Opaque", "Alpha", "AlphaKill", "Add", "SoftAdd", "Hidden"]) field={kind}/>
				<checkbox field={shadows}/>
				<checkbox field={culling}/>
				<checkbox field={light}/>
			</root>, material.props
		);
	}

	static var _ = MaterialEditor.registerEditor(h3d.mat.Material, Material);
}