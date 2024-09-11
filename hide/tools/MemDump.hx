package hide.tools;

class MemDump {

	public static function gpudump() {
		var engine = h3d.Engine.getCurrent();
		var sb = new StringBuf();
		var stats = engine.mem.allocStats();
		stats.sort((s1, s2) -> s1.size > s2.size ? -1 : 1);
		var total = 0;
		var textureSize = 0;
		var bufferSize = 0;
		for(s in stats) {
			var size = Std.int(s.size / 1024);
			total += size;
			if ( s.tex )
				textureSize += size;
			else
				bufferSize += size;
			sb.add((s.tex?"Texture ":"Buffer ")+'${s.position} #${s.count} ${Std.int(s.size/1024)}kb\n');
		}
		sb.add('TOTAL: ${total}kb\n');
		sb.add('TEXTURE TOTAL: ${textureSize}kb\n');
		sb.add('BUFFER TOTAL: ${bufferSize}kb\n');
		sb.add('\nDETAILS\n');
		for(s in stats) {
			sb.add('${s.position} #${s.count} ${Std.int(s.size/1024)}kb\n');
			s.stacks.sort((s1, s2) -> s1.size > s2.size ? -1 : 1);
			for (stack in s.stacks) {
				sb.add('\t#${stack.count} ${Std.int(stack.size/1024)}kb ${stack.stack.split('\n').join('\n\t\t')}\n');
			}
		}
		var dumpFolder = "../dump";
		if ( !sys.FileSystem.exists(dumpFolder) )
			sys.FileSystem.createDirectory(dumpFolder);
		var path = dumpFolder + "/gpudump.txt";
		sys.io.File.saveContent(path, sb.toString());	
		return path;
	}
}