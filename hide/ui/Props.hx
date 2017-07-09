package hide.ui;

typedef PropsDef = {

	public var autoSaveLayout : Null<Bool>;
	public var layouts : Array<{ name : String, state : Dynamic }>;

	public var currentProject : String;
	public var recentProjects : Array<String>;

	public var windowPos : { x : Int, y : Int, w : Int, h : Int, max : Bool };

}

class Props {


	var paths : {
		global : String,
		local : String,
		project : String,
	};

	// per user, all project
	public var global : PropsDef;
	// per project, all  users
	public var project : PropsDef;
	// per user, per project
	public var local : PropsDef;

	// current merge
	public var current : PropsDef;

	public function new( projectDir : String ) {
		var name = "hideProps.json";
		var path = js.Node.process.argv[0].split("\\").join("/").split("/");
		path.pop();
		var globalPath = path.join("/") + "/" + name;
		var projectPath = projectDir + "/" + name;
		var localPath = projectDir.split("\\").join("/").toLowerCase();
		paths = {
			global : globalPath,
			local : localPath,
			project : projectPath
		};
		load();
	}

	function load() {
		global = try haxe.Json.parse(sys.io.File.getContent(paths.global)) catch( e : Dynamic ) null;
		project = try haxe.Json.parse(sys.io.File.getContent(paths.project)) catch( e : Dynamic ) null;
		local = try haxe.Json.parse(js.Browser.window.localStorage.getItem(paths.local)) catch( e : Dynamic ) null;
		if( global == null ) global = cast {};
		if( project == null ) project = cast {};
		if( local == null ) local = cast {};
		if( global.currentProject == null || !sys.FileSystem.exists(global.currentProject) )
			global.currentProject = Sys.getCwd();
		sync();
	}

	public function sync() {
		current = {
			autoSaveLayout : true,
			layouts : [],
			currentProject : null,
			recentProjects : [],
			windowPos : null,
		};
		merge(global);
		merge(project);
		merge(local);
	}

	public function save() {
		sync();
		saveGlobals();
		var str = haxe.Json.stringify(project);
		if( str == '{}' )
			try sys.FileSystem.deleteFile(paths.project) catch(e:Dynamic) {}
		else
			sys.io.File.saveContent(paths.project, str);
		var str = haxe.Json.stringify(local);
		js.Browser.window.localStorage.setItem(paths.local, str);
	}

	public function saveGlobals() {
		var str = haxe.Json.stringify(global);
		sys.io.File.saveContent(paths.global, str);
	}

	function merge( props : PropsDef ) {
		for( f in Reflect.fields(props) ) {
			var v = Reflect.field(props,f);
			if( v == null ) {
				Reflect.deleteField(props,f);
				continue;
			}
			// remove if we are on default
			if( props == global && v == Reflect.field(current,f) ) {
				Reflect.deleteField(props,f);
				continue;
			}
			Reflect.setField(current, f, v);
		}
	}

}