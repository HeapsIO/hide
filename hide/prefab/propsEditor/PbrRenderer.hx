package hide.prefab.propsEditor;

class PbrRenderer extends AnyPropsEditor<h3d.scene.pbr.Renderer> {

	override function edit2(ctx:hrt.prefab.EditContext2, root: hide.kit.Element, ?customProps: Dynamic) {
		var props : h3d.scene.pbr.Renderer.RenderProps = customProps ?? props.props;

		root.build(
			<root>
				<select field={mode}/>

				<category("Tone Mapping")>
					<select field={tone}/>
					<range(0.0, 5.0) field={a}/>
					<range(0.0, 2.0) field={b}/>
					<range(0.0, 5.0) field={c}/>
					<range(0.0, 5.0) field={d}/>
					<range(0.0, 0.5) field={e}/>
				</category>

				<category("Environment")>
					<select field={sky} label="Env" onValueChange={(_) -> ctx.rebuildInspector()}/>
					<color field={skyColor} if(props.sky==CustomColor)/>
					<checkbox field={forceDirectDiscard}/>
				</category>

				<category("Params")>
					<range(0.0, 2.0) field={emissive}/>
					<range(0.0, 2.0) field={occlusion}/>
					<range(-3.0, 3.0) field={exposure}/>
				</category>
			</root>
		, props);
	}

	static var _ = AnyPropsEditor.registerEditor(h3d.scene.pbr.Renderer, PbrRenderer);
}