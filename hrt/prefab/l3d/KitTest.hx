package hrt.prefab.l3d;

typedef SubStruct = {
	innerValue: Float,
	?rec: SubStruct,
};

class KitTest extends Object3D {

	override function makeObject(parent3d: h3d.scene.Object) : h3d.scene.Object {
		var mesh = new h3d.scene.Mesh(h3d.prim.Cube.defaultUnitCube(), parent3d);

		#if editor
		var wire = new h3d.scene.Box(mesh);
		wire.color = 0;
		wire.ignoreCollide = true;
		wire.material.shadows = false;
		#end

		return mesh;
	}

	@:s var inputString : String;
	@:s var filePath : String;
	@:s var color : Int;
	@:s var gradient : hrt.impl.Gradient.GradientData;
	@:s var select : String;
	@:s var checkbox: Bool;
	@:s var texture: Dynamic;
	var substruct: SubStruct = { innerValue: 0.0, };

	#if js
	override function edit2(ctx:hrt.prefab.EditContext2) {
		ctx.build(
			<category("All Elements")>
				<text("Text")/>
				<slider label="Slider" value={12.34}/>
				<slider label="Disabled slider" value={12.34} disabled/>
				<slider label="Slider Exp" value={12.34} exp step={0.001}/>
				<slider label="Slider Exp Custom" value={12.34} exp={1.5} step={0.001}/>
				<slider label="Slider Poly" value={12.34} poly step={0.001}/>
				<slider label="Slider Poly Custom" value={12.34} poly={1.5} step={0.001}/>
				<range(0.0, 100.0) label="Range" value={12.34}/>
				<range(0,100) label="Range Int" value={12} int/>
				<range(0.001, 1000.0) label="Range Exp" value={12.34} exp={100} step={0.01}/>
				<range(0.001, 1000.0) label="Range Poly" value={12.34} poly step={0.01}/>
				<line>
					<slider label="A" value={12.34}/>
					<slider label="B" value={12.34}/>
				</line>
				<text("Separator")/>
				<separator/>
				<file field={filePath} type="texture"/>
				<button("Button")/>
				<button("Button Highlight") highlight/>
				<button("Button Disabled") disabled/>
				<button("Button Single Edit") single-edit/>
				<input label="Input" placeholder="Placeholder text" field={inputString}/>
				<color field={color}/>
				<gradient field={gradient}/>
				<texture field={texture}/>
				<select(["Fire", "Earth", "Water", "Air"]) field={select} />
				<checkbox field={checkbox}/>

				<line full>
					<image-button("ui/search.png") medium/>
					<image-button("ui/home.png") medium/>
					<image-button("ui/menu.png") medium/>
					<image-button("ui/close.png") medium/>
				</line>

				<line id="parentLine" multiline>
				</line>

				<block id="addToMe"></block>
			</category>,
		this);

		parentLine.build(<image-button("textures/dirt01.jpg") big/>, null);
		parentLine.build(<image-button("textures/dirt01.jpg") big/>, null);
		parentLine.build(<image-button("textures/dirt01.jpg") big/>, null);

		for (i in 0...3) {
			addToMe.build(<button({'$i';}) id="button"/>, null);
			button.onClick = () -> trace('onclick $i');
		}

		ctx.build(
			<root>
				<category("A")>
				</category>
				<category("Closed by default") closed>
					<text("Not visible by default because parent is closed")/>
				</category>
			</root>
		);

		// DML TESTS
		hide.kit.Macros.testError(
			"c'est pas du dml", this, "dml argument should be a DML Expression"
		);

		hide.kit.Macros.testError(
			<unknown-component/>, this, "hide-kit element hide.kit.UnknownComponent doesn't exist"
		);

		hide.kit.Macros.testError(
			<native-element/>, this, "type hide.kit.NativeElement is not a class"
		);

		// LABEL RELATED TESTS

		hide.kit.Macros.testNoError(
			<range label="label"/>, this
		);

		{
			var monLabel = "label";
			hide.kit.Macros.testNoError(
				<range label={monLabel}/>, this
			);
		}

		hide.kit.Macros.testError(
			<range label={123}/>, this, "label value must be string expression or a string constant"
		);

		// Can't test this because the error is a hide error after the codegen pass is done
		// hide.kit.Macros.testError(
		// 	<range label={unknownVariable}/>, this, "label value must be string expression or a string constant"
		// );

		// ID Related tests

		hide.kit.Macros.testNoError(
			<range id="id"/>, this
		);

		hide.kit.Macros.testNoError(
			<range id={"id"}/>, this
		);

		// Id must be comptime known
		{
			var id = "id";
			hide.kit.Macros.testError(
				<range id={id}/>, this, "id value must be a const string"
			);
		}

		hide.kit.Macros.testError(
			<root>
				<range id="a"/>
				<range id="a"/>
			</root>
		, this, "A component with the id a already exists in this build");

		// Field related tests

		hide.kit.Macros.testNoError(
			<range field={x}/>, this
		);

		hide.kit.Macros.testNoError(
			<range field={this.x}/>, this
		);

		hide.kit.Macros.testNoError(
			<range field={substruct.rec.innerValue}/>, this
		);

		{
			var local : Float = 42.0;
			hide.kit.Macros.testNoError(
				<range field={local}/>, this
			);
		}

		hide.kit.Macros.testError(
			<range field="x"/>, this, "field must be an identifier expression or a structure field expression"
		);

		hide.kit.Macros.testError(
			<range field={123}/>, this, "field must be an identifier expression or a structure field expression"
		);

		// Attributes related tests

		// Parse string as correct type
		hide.kit.Macros.testNoError(
			<range min="0"/>, this
		);

		hide.kit.Macros.testError(
			<range min="notANumber"/>, this, 'cannot convert "notANumber" to Float for attribute min'
		);

		hide.kit.Macros.testError(
			<range unknown-attribute="true"/>, this, "hide.kit.Range has no attribute named unknownAttribute"
		);

		hide.kit.Macros.testError(
			<range unknown-attribute/>, this, "hide.kit.Range has no attribute named unknownAttribute"
		);

		hide.kit.Macros.testNoError(
			<line multiline/>, this,
		);

		hide.kit.Macros.testNoError(
			<line multiline="false"/>, this,
		);

		hide.kit.Macros.testNoError(
			<line multiline={true}/>, this,
		);

		{
			var local = true;
			hide.kit.Macros.testNoError(
				<line multiline={local}/>, this
			);
		}

		hide.kit.Macros.testNoError(
			<line multiline="true"/>, this,
		);

		hide.kit.Macros.testError(
			<line multiline="True"/>, this, 'cannot convert "True" to Bool for attribute multiline (must be either "true" or "false")'
		);
	}

	override function getHideProps():Null<hide.prefab.HideProps> {
		return {
			name: "Kit Test",
			icon: "question-cicle",
		}
	}

	#end

	static var _ = hrt.prefab.Prefab.register("kitTest", KitTest);
}