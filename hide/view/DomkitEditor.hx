package hide.view;

private typedef CompPackage = {
	var name : String;
	var pack : String;
	var subs : Map<String,CompPackage>;
	var comps : Array<String>;
	var ?isComp : Bool;
}

private typedef CompDef = {
	var name : String;
	var full : String;
	var file : String;
	var ?cssFile : { file : String, line : Int, len : Int, event : hide.tools.FileWatcher.FileWatchEvent };
	var event : hide.tools.FileWatcher.FileWatchEvent;
}

class DomkitEditor extends hide.ui.View<{ ?comp : String }> {

	static var R_PACKAGE = ~/package[ \t\r\n]+([A-Za-z0-9_\.]+)/;
	static var R_COMP_HX = ~/static[ \t\r\n]+var[ \t\r\n]+SRC[ \t\r\n]+=[ \t\r\n]+<([a-zA-Z0-9_\-]+)/;
	static var R_CSS_COMP_NAME = ~/(?<![#\.:@\-])\b([A-Za-z][A-Za-z0-9\-]*)/;

	var comps : Map<String,CompDef>;
	var compsRoot : CompPackage;
	var dmlEditor : hide.comp.DomkitEditor;
	var cssEditor : hide.comp.DomkitEditor;
	var tree : hide.comp.FancyTree<CompPackage>;
	var onBeforeOpen : Void -> Bool;

	function collectComponents() {
		comps = new Map();
		var path : Array<String> = config.get("haxe.classPath");
		for( dir in path )
			browseHxRec(dir);
		compsRoot = {
			pack : "",
			name : "",
			subs : new Map(),
			comps : [],
		};
		for( c in comps ) {
			var path = c.full.split(".");
			path.pop();
			var cur = compsRoot;
			for( p in path ) {
				var s = cur.subs.get(p);
				if( s == null ) {
					s = {
						name : p,
						pack : (cur.pack == "" ? p : cur.pack +"."+p),
						subs : new Map(),
						comps : [],
					}
					cur.subs.set(p, s);
				}
				cur = s;
			}
			cur.comps.push(c.name);
		};
		while( compsRoot.comps.length == 0 && Lambda.array(compsRoot.subs).length == 1 )
			compsRoot = compsRoot.subs.iterator().next();
	}

	function collectCssFiles() {
		var path : Array<String> = config.get("domkit.components");
		for( dir in path )
			browseCssRec(dir);
	}

	function browseHxRec( dir : String ) {
		var path = ide.getPath(dir);
		if( !sys.FileSystem.isDirectory(path) )
			return false;
		ide.fileWatcher.register(path, checkComponents, true, element);
		for( f in sys.FileSystem.readDirectory(path) ) {
			var relPath = dir + "/" + f;
			if( browseHxRec(relPath) )
				continue;
			if( !StringTools.endsWith(f,".hx") )
				continue;
			var path = ide.getPath(relPath);
			var ev = ide.fileWatcher.register(path, checkComponents, true, element);
			var content = sys.io.File.getContent(path);
			var pack = null;
			if( R_PACKAGE.match(content) )
				pack = R_PACKAGE.matched(1);
			while( R_COMP_HX.match(content) ) {
				var name = R_COMP_HX.matched(1);
				comps.set(name,{
					name : name,
					full : pack == null ? name : pack+"."+name,
					file : path,
					event : ev,
				});
				content = R_COMP_HX.matchedRight();
			}
		}
		return true;
	}

	function browseCssRec( dir : String ) {
		var path = ide.getPath(dir);
		if( !sys.FileSystem.isDirectory(path) )
			return false;
		ide.fileWatcher.register(path, checkComponents, true, element);
		for( f in sys.FileSystem.readDirectory(path) ) {
			var relPath = dir + "/" + f;
			if( browseCssRec(relPath) )
				continue;
			if( !StringTools.endsWith(f,".less") )
				continue;
			var path = ide.getPath(relPath);
			var content = sys.io.File.getContent(path);
			var lines = content.split("\r\n").join("\n").split("\n");
			var event = null;
			for( i => l in lines ) {
				if( l.charCodeAt(0) != " ".code && l.charCodeAt(0) != "\t".code ) {
					var len = 1;
					var j = i + 1;
					while( j < lines.length ) {
						var c = lines[j].charCodeAt(0);
						if( c != " ".code || c != "\t".code )
							break;
						j++;
						len++;
					}
					var reg = R_CSS_COMP_NAME;
					while( reg.match(l) ) {
						var name = reg.matched(1);
						var c = comps.get(name);
						if( c != null && (c.cssFile == null || c.cssFile.len < len) ) {
							if( event == null )
								event = ide.fileWatcher.register(path,checkComponents,true,element);
							c.cssFile = { file : path, line : i, len : len, event : event };
						}
						l = reg.matchedRight();
					}
				}
			}
		}
		return true;
	}

	function checkComponents() {
		rebuild();
	}

	override function onDisplay() {
		collectComponents();
		collectCssFiles();
		var root = new Element('
		<div class="domkitEditor">
			<div class="editors">
				<div class="left panel">
					<div class="editor dmlEditor top">
						<span>
							DML
							<input id="format" type="button" value="Format"/>
						</span>
					</div>
				</div>
				<div class="right panel">
					<div class="editor cssEditor top">
						<span>CSS</span>
					</div>
				</div>
				<div class="tree panel">
				</div>
			</div>
		</div>
		');
		root.appendTo(element);
		tree = new hide.comp.FancyTree(root.find(".tree"),{ search : true });
		tree.getChildren = function(p) {
			if( p == null ) p = compsRoot;
			var subs = Lambda.array(p.subs);
			subs.sort(function(s1,s2) return Reflect.compare(s1.name, s2.name));
			p.comps.sort(Reflect.compare);
			for( c in p.comps )
				subs.push({ name : c, pack : p.pack+"."+c, subs : [], comps : [], isComp : true });
			return subs;
		};
		tree.getName = function(p) return p.name;
		tree.getUniqueName = function(p) return p.pack;
		tree.getIcon = function(p) return '<div class="ico ico-${p.isComp?"code":"folder"}"/>';
		tree.onDoubleClick = function(p) {
			if( p.isComp ) openComponent(p.name);
		};
		tree.rebuildTree();
		if( state.comp != null )
			openComponent(state.comp);
	}

	function detectPadding( content : String ) {
		var windowsLine = false;
		var winLines = content.split("\r\n");
		var lines = content.split("\n");
		if( winLines.length >= lines.length * 0.8 )
			windowsLine = true;
		var lines = winLines.join("\n").split("\n");
		function getTabs(line) {
			var tabCount = 0;
			var spaceCount = 0;
			if( lines.length > line ) {
				while( lines[line].charCodeAt(tabCount) == '\t'.code ) tabCount++;
				while( lines[line].charCodeAt(tabCount+spaceCount) == ' '.code ) spaceCount++;
				for( i in line+1...lines.length ) {
					while( tabCount > 0 && lines[i].charCodeAt(tabCount-1) != '\t'.code ) tabCount--;
					while( spaceCount > 0 && lines[i].charCodeAt(spaceCount + tabCount-1) != ' '.code ) spaceCount--;
				}
			}
			return { line : line, tab : tabCount, sp : spaceCount };
		}
		var tabs = getTabs(0);
		if( tabs.tab + tabs.sp == 0 )
			tabs = getTabs(1);
		for( i in tabs.line...lines.length )
			lines[i] = lines[i].substr(tabs.sp + tabs.tab);
		return {
			content : lines.join("\n"),
			format : function(content) {
				var lines = StringTools.trim(content).split("\r\n").join("\n").split("\n");
				var prefix = "";
				for( i in 0...tabs.tab ) prefix += "\t";
				for( i in 0...tabs.sp ) prefix += " ";
				for( i in tabs.line...lines.length ) lines[i] = prefix + lines[i];
				return lines.join(windowsLine ? "\r\n" : "\n");
			},
		};
	}

	function openComponent( name : String ) {
		var comp = comps.get(name);
		if( comp == null )
			return;
		if( onBeforeOpen != null && !onBeforeOpen() )
			return;
		dmlEditor?.remove();
		cssEditor?.remove();
		var defaultCss = '${comp.name} {\n}';
		var pos = getFileLocation(comp);
		var rawContent = sys.io.File.getContent(comp.file).substr(pos.start, pos.length);
		var rawCss = comp.cssFile == null ? defaultCss : sys.io.File.getContent(comp.cssFile.file);
		var inf = detectPadding(rawContent);
		var content = inf.content;
		onBeforeOpen = function() {
			if( dmlEditor.code != content || cssEditor.code != rawCss )
				return ide.confirm("Changes haven't been saved, continue ?");
			return true;
		};
		dmlEditor = new hide.comp.DomkitEditor(config, DML, content, element.find(".dmlEditor"));
		dmlEditor.onSave = function() {
			content = dmlEditor.code;
			rawContent = inf.format(dmlEditor.code);
			var pos = getFileLocation(comp);
			var data = sys.io.File.getContent(comp.file);
			data = data.substr(0, pos.start) + rawContent + data.substr(pos.start+pos.length);
			sys.io.File.saveContent(comp.file, data);
			ide.fileWatcher.ignorePrevChange(comp.event);
		};
		cssEditor = new hide.comp.DomkitEditor(config, Less, rawCss, element.find(".cssEditor"));
		cssEditor.onSave = function() {
			if( comp.cssFile == null ) {
				var path : Array<String> = config.get("domkit.components");
				if( path.length == 0 ) {
					ide.error('"domkit.components" path is not set in res/props.json');
					return;
				}
				var path = ide.getPath(path[0]+"/"+comp.name+".less");
				if( sys.FileSystem.exists(path) ) {
					ide.error(path+" already exists. Can't save");
					return;
				}
				sys.io.File.saveContent(path,"");
				comp.cssFile = { file : path, len : 0, line : 0, event : null };
			}
			rawCss = cssEditor.code;
			var css = StringTools.trim(rawCss);
			if( css == defaultCss ) {
				sys.FileSystem.deleteFile(comp.cssFile.file);
				comp.cssFile = null;
			} else {
				sys.io.File.saveContent(comp.cssFile.file,css);
				if( comp.cssFile.event != null )
					ide.fileWatcher.ignorePrevChange(comp.cssFile.event);
			}
		};
		if( comp.cssFile != null ) cssEditor.setCursor(comp.cssFile.line);
		cssEditor.focus();
		cssEditor.gotoComponent = dmlEditor.gotoComponent = openComponent;
		state.comp = name;
		saveState();
	}

	function getFileLocation( c : CompDef ) {
		var content = sys.io.File.getContent(c.file);
		var pos = 0;
		while( R_COMP_HX.match(content) ) {
			var p = R_COMP_HX.matchedPos();
			var name = R_COMP_HX.matched(1);
			if( name == c.name ) {
				var start = pos + p.pos + p.len - (name.length + 1);
				var end = content.indexOf("</"+name+">");
				if( end < 0 ) break;
				return { start : start, length : (pos + end + name.length + 3) - start };
			}
			pos += p.pos + p.len;
			content = R_COMP_HX.matchedRight();
		}
		throw 'Component ${c.name} not found in '+c.file;
	}

	static var _ = hide.ui.View.register(DomkitEditor);

}