package hrt.shgraph;

using hxsl.Ast;

// @name("Camera")
// @description("Inputs from Camera")
// @group("Property")
// @color("#0e8826")
// class ShaderCameraInput extends ShaderInput {

// 	static var cameraInputs = [	{ parent: null, id: 0, kind: Global, name: "camera.view", type: TMat4 },
// 								{ parent: null, id: 0, kind: Global, name: "camera.proj", type: TVec(3, VFloat) },
// 								{ parent: null, id: 0, kind: Global, name: "camera.position", type: TVec(3, VFloat) },
// 								{ parent: null, id: 0, kind: Global, name: "camera.projFlip", type: TFloat },
// 								{ parent: null, id: 0, kind: Global, name: "camera.projDiag", type: TVec(3, VFloat) },
// 								{ parent: null, id: 0, kind: Global, name: "camera.viewProj", type: TMat4 },
// 								{ parent: null, id: 0, kind: Global, name: "camera.inverseViewProj", type: TMat4 },
// 								{ parent: null, id: 0, kind: Global, name: "camera.zNear", type: TFloat },
// 								{ parent: null, id: 0, kind: Global, name: "camera.zFar", type: TFloat },
// 								{ parent: null, id: 0, kind: Global, name: "camera.dir", type: TVec(3, VFloat) } ];

// 	override public function loadProperties(props : Dynamic) {
// 		var paramVariable : String = Reflect.field(props, "variable");
// 		for (c in ShaderCameraInput.cameraInputs) {
// 			if (c.name == paramVariable) {
// 				this.variable = c;
// 				return;
// 			}
// 		}
// 	}

// 	#if editor
// 	override public function getPropertiesHTML(width : Float) : Array<hide.Element> {
// 		var elements = [];
// 		var element = new hide.Element('<div style="width: 120px; height: 30px"></div>');
// 		element.append(new hide.Element('<select id="variable"></select>'));

// 		if (this.variable == null)
// 			this.variable = ShaderCameraInput.cameraInputs[0];

// 		var input = element.children("select");
// 		var indexOption = 0;
// 		for (c in ShaderCameraInput.cameraInputs) {
// 			var name = c.name.split(".")[1];
// 			input.append(new hide.Element('<option value="${indexOption}">${name}</option>'));
// 			if (this.variable.name == c.name) {
// 				input.val(indexOption);
// 			}
// 			indexOption++;
// 		}
// 		input.on("change", function(e) {
// 			var value = input.val();
// 			this.variable = ShaderCameraInput.cameraInputs[value];
// 		});

// 		elements.push(element);

// 		return elements;
// 	}
// 	#end

// }