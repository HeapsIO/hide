package hrt.prefab.rfx;

#if hscript

private typedef ChangedVar = { obj : Dynamic, field : String, value : Dynamic, set : Bool };

class ConfiguratorInterp extends hscript.Interp {
	var prevVars : Map<String,Array<ChangedVar>> = [];
	var allVars : Array<ChangedVar> = [];
	public function new() {
		super();
	}

	override function set( o : Dynamic, f : String, v : Dynamic ) : Dynamic {
		var prev = prevVars.get(f);
		if( prev == null ) {
			prev = [];
			prevVars.set(f, prev);
		}
		var found = null;
		for( v in prev ) {
			if( v.obj == o ) {
				found = v;
				break;
			}
		}
		if( found == null ) {
			#if editor
			if( !Reflect.hasField(o,f) ) {
				var c = Type.getClass(o);
				while( c != null ) {
					if( Type.getInstanceFields(c).indexOf(f) >= 0 )
						break;
					c = Type.getSuperClass(c);
				}
				if( c == null )
					throw o+" has no field "+f;
			}
			#end
			found = { obj : o, field : f, value : null, set : false };
			allVars.push(found);
			prev.push(found);
			if( allVars.length > 200 ) throw "Vars are leaking";
		}
		if( !found.set ) {
			found.set = true;
			found.value = Reflect.getProperty(o, f);
		}
		Reflect.setProperty(o, f, v);
		return v;
	}

	public function restoreVars() {
		for( v in allVars ) {
			if( v.set ) {
				Reflect.setProperty(v.obj, v.field, v.value);
				v.set = false;
			}
		}
	}

}
#end


class Configurator extends RendererFX {

	public var vars : Array<{ name : String, defValue : Float }> = [];
	var script : String = "";
	var values : Map<String, Float> = new Map();

	var prefabCache : Map<String, Prefab> = new Map();

	#if hscript
	var interp : ConfiguratorInterp;
	var parsedExpr : hscript.Expr;
	#end
	#if editor
	var errorTarget : hide.Element;
	#end

	public function new(?parent) {
		super(parent);
		type = "configurator";
	}

	override function save():{} {
		var obj : Dynamic = super.save();
		obj.vars = vars;
		obj.script = script;
		return obj;
	}

	override function load(v:Dynamic) {
		super.load(v);
		vars = v.vars;
		script = v.script;
	}

	public function set( name : String, value : Float ) {
		values.set(name,value);
	}

	function smoothValue( v : Float, easing : Float ) : Float {
		var bpow = Math.pow(v, 1 + easing);
		return bpow / (bpow + Math.pow(1 - v, easing + 1));
	}

	function getPrefab( id : String ) {
		var p = prefabCache.get(id);
		if( p != null )
			return p;
		var root : Prefab = this;
		while( root.parent != null ) root = root.parent;
		var p = root.getOpt(hrt.prefab.Prefab,id);
		if( p == null ) throw "Missing prefab #"+id;
		#if !editor
		prefabCache.set(id, p);
		#end
		return p;
	}

	override function makeInstance(ctx:Context):Context {
		for( v in vars )
			values.set(v.name, v.defValue);
		#if hscript
		interp = null;
		#end
		return super.makeInstance(ctx);
	}

	override function begin(r:h3d.scene.Renderer, step:h3d.impl.RendererFX.Step) {
		#if !hscript
		throw "Requires -lib hscript";
		#else
		if( step == MainDraw ) {
			var errorMessage = null;
			if( parsedExpr == null ) {
				var parser = new hscript.Parser();
				parsedExpr = try parser.parseString(script) catch( e : hscript.Expr.Error ) { errorMessage = e.toString(); null; };
			}
			if( interp == null ) {
				interp = new ConfiguratorInterp();
				interp.variables.set("get", getPrefab);
				interp.variables.set("smooth", smoothValue);
			}
			for( k => v in values )
				interp.variables.set(k, v);
			if( errorMessage == null )
				try {
					interp.execute(parsedExpr);
				} catch( e : Dynamic ) {
					errorMessage = Std.string(e);
				}
			if( errorMessage != null ) {
				#if !editor
				throw errorMessage;
				#else
				if( errorTarget != null ) errorTarget.text(errorMessage);
				#end
			} else {
				#if editor
				if( errorTarget != null ) errorTarget.html("&nbsp;");
				#end
			}
		}
		#end
	}

	#if hscript
	override function end(r:h3d.scene.Renderer, step:h3d.impl.RendererFX.Step) {
		if( step == Overlay )
			interp.restoreVars();
	}
	#end

	#if editor
	override function getHideProps() : HideProps {
		return { name : "Configurator", icon : "dashboard" };
	}

	override function edit( ectx : EditContext ) {
		var props = new hide.Element('
		<div>
			<div class="group" name="Variables">
				<dl id="vars">
				</dl>
				<dl>
					<dt></dt>
					<dd><input type="button" value="Add" id="addvar"/></dd>
				</dl>
			</div>
			<div class="group" name="Script">
			<div>
				<div class="error">&nbsp;</div>
				<div id="script" style="height:200px"></div>
			</div>
			</div>
		</div>
		');
		errorTarget = props.find(".error");
		var evars = props.find("#vars");
		props.find("#addvar").click(function(_) {
			var name = ectx.ide.ask("Variable name");
			if( name == null ) return;
			ectx.makeChanges(this, function() vars.push({ name : name, defValue: 0 }));
			values.set(name, 0);
			ectx.rebuildProperties();
		});
		ectx.properties.add(props);
		for( v in vars ) {
			var ref = { v : values.get(v.name) };
			var def = new hide.Element('<div><dt>${v.name}</dt><dd><input type="range" min="0" max="1" field="v"/></dd></div>').appendTo(evars);
			ectx.properties.build(def, ref, function(_) {
				values.set(v.name, ref.v);
			});
			def.find("dt").contextmenu(function(e) {
				new hide.comp.ContextMenu([
					{ label : "Set Default", click : () -> v.defValue = ref.v },
					{ label : "Remove", click : () -> {
						vars.remove(v);
						values.remove(v.name);
						interp.variables.remove(v.name);
						ectx.rebuildProperties();
					}},
				]);
				return false;
			});
		}

		var selt = props.find("#script");
		var editor = new hide.comp.ScriptEditor(this.script, selt, selt);
		editor.onSave = function() {
			script = editor.code;
			parsedExpr = null;
			interp = null;
		};
	}
	#end

	static var _ = Library.register("rfx.configurator", Configurator);


}