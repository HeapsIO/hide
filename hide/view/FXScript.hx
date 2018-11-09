package hide.view;
using Lambda;

enum ParamOption{
	Range(min : Float, max : Float);
}

enum FXParam{
	Float(name : String, value : Float, options : Array<ParamOption>);
	Int(name : String, value : Int, options : Array<ParamOption>);
}

@:access(hide.view.FXEditor)
class FXScript {

	var editor : hide.view.FXEditor;

	public function new(editor){
		this.editor = editor;
	}

	public function updateScriptParams(){
		var parser = new hscript.Parser();
		parser.allowMetadata = true;
		parser.allowTypes = true;
		parser.allowJSON = true;
		var params : Array<FXParam> = [];
		var expr : hscript.Expr = null;
		var parseDebug = true;

		function parseExpr(expr : hscript.Expr ) {
			if( expr == null ) return;
			switch(expr.e){

				case EBlock(e):
					for(expr in e)
						parseExpr(expr);

				case EMeta(name, args, e):
					switch(name){
						case "param" : params.push(createParam(e));
					}

				default:
			}
		}

		try {
			expr = parser.parseString(editor.scriptEditor.script, "");
			parseExpr(expr);
		} catch( e : hscript.Expr.Error ) { }

		generateUI(params);
	}


	function createParam( expr : hscript.Expr ) : FXParam {
		var options : Array<ParamOption> = [];
		function parse(expr : hscript.Expr) : FXParam {
			if( expr == null ) return null;
			switch(expr.e){
				case EMeta(name, args, e):
					switch(name){
						case "range":
						var min = 	switch(args[0].e){
										case EConst(c):
											switch(c){
												case CInt(v): v;
												case CFloat(f): f;
												default: null;
											}
										default: null;
									}
						var max = 	switch(args[1].e){
										case EConst(c):
											switch(c){
												case CInt(v): v;
												case CFloat(f): f;
												default: null;
											}
										default: null;
									}
						options.push(Range(min, max));
						default:
					}
					return parse(e);

				case EVar(n, t, e):
					if(e == null){
						switch(t){
							case CTPath(path, params):
								switch(path){
									case ["Int"]: return FXParam.Int(n, null, options);
									case ["Float"]: return FXParam.Float(n, null, options);
									default:
								}
							default:
						}
					}
					else{
						switch(e.e){
							case EConst(c):
								switch(c){
									case CInt(v): return FXParam.Int(n, v, options);
									case CFloat(f): return FXParam.Float(n, f, options);
									default: null;
								}
							default: null;
						}
					}

				default:
					return null;
			}
			return null;
		}
		return parse(expr);
	}

	function generateUI( params : Array<FXParam> ){
		var elem = editor.element.find(".fx-scriptParams");
		elem.empty();
		var root = new Element('<div class="group" name="Params"></div>');
		for(p in params){
			switch(p){
				case Float(name, value, options):
					var sliderMin = 0.0;
					var sliderMax = 1.0;
					for(o in options){
						switch(o){
							case Range(min, max):
								sliderMin = min;
								sliderMax = max;
							default:
						}
					}
					root.append(createSlider(name, sliderMin, sliderMax, 0.1, value));
				case Int(name, value, options):
					var sliderMin = 0.0;
					var sliderMax = 1.0;
					for(o in options){
						switch(o){
							case Range(min, max):
								sliderMin = min;
								sliderMax = max;
							default:
						}
					}
					root.append(createSlider(name, sliderMin, sliderMax, 1.0, value));
			}
		}
		elem.append(root);
	}

	function createSlider(name : String, min : Float, max : Float, step : Float, defaultVal : Float) : Element {
		var root = new Element('<div class="fx-slider"></div>');
		var name = new Element('<label> $name : </label>');
		var min = new Element('<label> $min </label>');
		var max = new Element('<label> $max </label>');
		var slider = new Element('<input class="param" type="range" min="$min" max="$max" step="$step" value="$defaultVal"/>');
		var range = new hide.comp.Range(slider, null);
		root.append(name);
		root.append(min);
		root.append(slider);
		root.append(max);
		return root;
	}
}