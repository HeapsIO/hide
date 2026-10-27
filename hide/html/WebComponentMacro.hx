package hide.html;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import haxe.io.Path;
import sys.FileSystem;

class WebComponentMacro {
	/**
		Errors on the css files of a `style` folder under `hide/html` that don't match a component compiled from the parent folder.
	**/
	static function init() {
		Context.onAfterTyping(types -> {
			function norm(file : String)
				return Path.normalize(FileSystem.fullPath(file)).toLowerCase();
			function isComponent(c : ClassType) {
				if (c.superClass == null || c.superClass.t.get().isExtern)
					return false;
				while (c != null) {
					for (i in c.interfaces)
						if (i.t.toString() == "hide.html.IWebComponent")
							return true;
					c = c.superClass?.t.get();
				}
				return false;
			}
			var typed = new Map<String, Bool>();
			for (t in types)
				switch (t) {
					case TClassDecl(c):
						var c = c.get();
						var file = norm(Context.getPosInfos(c.pos).file);
						if (isComponent(c))
							typed.set(file, true);
						else if (!typed.exists(file))
							typed.set(file, false);
					default:
				}
			function check(dir : String) {
				for (f in FileSystem.readDirectory(dir)) {
					var path = '$dir/$f';
					if (FileSystem.isDirectory(path))
						check(path);
					else if (Path.extension(f) == "css" && Path.withoutDirectory(dir) == "style") {
						// Modules not compiled can't be checked
						var src = Path.directory(dir) + "/" + Path.withoutExtension(f) + ".hx";
						if (!FileSystem.exists(src) || typed.get(norm(src)) == false)
							Context.reportError('$f doesn\'t match any web component of ${Path.directory(dir)}', Context.makePosition({min: 0, max: 0, file: path}));
					}
				}
			}
			check(Path.directory(Context.resolvePath("hide/html/WebComponent.hx")));
		});
	}

	/**
		Adds the default callbacks shared by all web component base classes.
		The native constructor is called by the class `register` wraps the component in, so it is skipped here.
	**/
	static function base() : Array<Field> {
		var tpl = macro class {
			public function new() {
				if (js.Syntax.code("false")) super();
			}

			public function connectedCallback() : Void {}
			public function disconnectedCallback() : Void {}
			public function adoptedCallback() : Void {}
			public function attributeChangedCallback(name : String, oldValue : Null<String>, newValue : Null<String>) : Void {}
		};
		return Context.getBuildFields().concat(tpl.fields);
	}

	/**
		Adds `create()`, which creates the component through the DOM, and makes `new` throw.
		Adds a static `styleSheet` from `style/<module>.css` next to the source file, if it exists.
		If the running hide is a git checkout, the sheet is reloaded from its copy of the file when it changes.
	**/
	static function build() : Array<Field> {
		var cl = Context.getLocalClass().get();
		if (cl.superClass.t.get().isExtern)
			return null;
		var fields = Context.getBuildFields();
		var path = cl.module.split(".");
		if (path[path.length - 1] != cl.name)
			path.push(cl.name);
		if (!cl.isAbstract) {
			var self = Context.toComplexType(TInst(Context.getLocalClass(), []));
			fields.push((macro class {
				public static function create() : $self {
					var cl : Dynamic = $p{path};
					return cast cl.__extends__ == null ? js.Browser.document.createElement(cl.__tag__) : js.Browser.document.createElement(cl.__extends__, {is: cl.__tag__});
				}
			}).fields[0]);
		}

		var src = Context.getPosInfos(cl.pos).file;
		var css = Path.directory(src) + "/style/" + Path.withoutDirectory(Path.withoutExtension(src)) + ".css";
		if (FileSystem.exists(css)) {
			Context.registerModuleDependency(cl.module, css);
			var init = [
				(macro var s = new js.html.CSSStyleSheet()),
				macro s.replaceSync($v{sys.io.File.getContent(css)}),
			];
			// The folder is watched because editors may save by replacing the file
			var dir = Path.directory(Path.normalize(FileSystem.fullPath(css)));
			var root = dir;
			while (root != null && !FileSystem.exists(root + "/.git"))
				root = root.indexOf("/") < 0 ? null : Path.directory(root);
			if (root != null) {
				var rel = dir.substr(root.length + 1);
				var file = Path.withoutDirectory(css);
				init.push(macro {
					var root = js.node.Path.join(js.Node.__dirname, "..");
					var dir = js.node.Path.join(root, $v{rel});
					if (js.node.Fs.existsSync(root + "/.git") && js.node.Fs.existsSync(dir))
						js.node.Fs.watch(dir, (_, name) -> {
							var path = js.node.Path.join(dir, $v{file});
							if (name == $v{file} &&js.node.Fs.existsSync(path))
								s.replaceSync(js.node.Fs.readFileSync(path, {encoding: "utf8"}));
						});
				});
			}
			init.push(macro s);
			fields.push((macro class {
				static var styleSheet : js.html.CSSStyleSheet = $b{init};
			}).fields[0]);
		}

		var ctor = Lambda.find(fields, f -> f.name == "new");
		if (ctor == null) {
			ctor = {
				name: "new",
				access: [APublic],
				pos: Context.currentPos(),
				kind: FFun({args: [], expr: macro super()}),
			};
			fields.push(ctor);
		}

		switch (ctor.kind) {
			case FFun(fn):
				var exprs = switch (fn.expr.expr) {
					case EBlock(el): el;
					default: [fn.expr];
				}
				// The DOM runs the constructor through the es6 wrapper of `register`, with `new.target` undefined
				var msg = 'Use ${path.join(".")}.create() instead of new';
				exprs.unshift(macro if (js.Syntax.code("new.target") != null) throw $v{msg});
				fn.expr = {expr: EBlock(exprs), pos: fn.expr.pos};
			default:
		}
		return fields;
	}
}
#end
