package hide.prefab.propsEditor;

class Material extends AnyPropsEditor<h3d.mat.Material> {

	override function edit2(ctx:hrt.prefab.EditContext2, root: hide.kit.Element, ?customProps: Dynamic) {
		root.build(
			<root>
				<select(["Opaque", "Alpha", "AlphaKill", "Add", "SoftAdd", "Hidden"]) field={kind}/>
				<checkbox field={shadows}/>
				<checkbox field={culling}/>
				<checkbox field={light}/>
			</root>, props.props
		);
	}

	static var _ = AnyPropsEditor.registerEditor(h3d.mat.Material, Material);
}