package hide.prefab.materialEditor;

class PbrMaterial extends MaterialEditor<h3d.mat.PbrMaterial> {

	override function edit2(ctx:hrt.prefab.EditContext2, root: hide.kit.Element) {
		var layers : Array< { name : String, value : Int }> = hide.Ide.inst.currentConfig.get("material.drawOrder", []);

		var drawOrder : Array<hide.kit.Select.SelectEntry> = [for( layer in layers) {
			value: layer.value,
			label: layer.name,
		}];
		drawOrder.unshift({value: null, label: "Default"});

		root.build(
			<root>
				<select([
					{value: "PBR", label: "PBR"},
					{value: "BeforeTonemapping", label: "Before Tonemapping"},
					{value: "Forward", label:"Forward PBR"},
					{value: "BeforeTonemapping", label:"Before Tonemapping"},
					{value: "BeforeTonemappingDecal", label:"Before Tonemapping Decal"},
					{value: "AfterTonemapping", label:"After Tonemapping"},
					{value: "AfterTonemappingDecal", label:"After Tonemapping Decal"},
					{value: "Overlay", label:"Overlay"},
					{value: "Distortion", label:"Distortion"},
					{value: "Decal", label:"Decal"},
					{value: "DecalPass", label:"Decal Pass"},
					{value: "TerrainPass", label:"Terrain Pass"}
				]) field={mode}/>
				<select([
					{value: "None", label:"None"},
					{value: "Alpha", label:"Alpha"},
					{value: "Add", label:"Add"},
					{value: "AlphaAdd", label:"AlphaAdd"},
					{value: "Multiply", label:"Multiply"},
					{value: "AlphaMultiply", label:"AlphaMultiply"},
				]) field={blend}/>
				<select([
					{value: "Less", label:"Less"},
					{value: "LessEqual", label:"LessEqual"},
					{value: "Greater", label:"Greater"},
					{value: "GreaterEqual", label:"GreaterEqual"},
					{value: "Always", label:"Always"},
					{value: "Never", label:"Never"},
					{value: "Equal", label:"Equal"},
					{value: "NotEqual", label:"NotEqual"}
				]) field={depthTest}/>
				<select([
					{value: "Default", label: "Default", equalsNull: true},
					{value: "On", label: "On"},
					{value: "Off", label: "Off"},
				]) field={depthWrite}/>
				<slider field={emissive} min={0}/>
				<slider field={parallax} min={0}/>
				<slider int field={parallaxSteps} min={0}/>
				<checkbox field={shadows}/>
				<select([
					{value: "None", label:"None"},
					{value: "Back", label:"Back"},
					{value: "Front", label:"Front"},
					{value: "Both", label:"Both"},
				]) field={culling}/>
				<checkbox field={alphaKill}/>
				<checkbox field={textureWrap}/>
				<select(drawOrder) field={drawOrder}/>
				<checkbox field={depthPrepass}/>
				<checkbox field={flipBackFaceNormal}/>
				<checkbox field={ignoreCollide}/>
			</root>, material.props
		);
	}

	static var _ = MaterialEditor.registerEditor(h3d.mat.PbrMaterial, PbrMaterial);
}