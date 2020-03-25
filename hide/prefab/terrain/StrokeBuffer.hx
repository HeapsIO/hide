package hide.prefab.terrain;

class StrokeBuffer {
	public var tex : h3d.mat.Texture;
	public var x : Int;
	public var y : Int;
	public var used : Bool;
	public var prevTex : h3d.mat.Texture;
	public var tempTex : h3d.mat.Texture;
	public var format : hxd.PixelFormat;

	public function new(size : h2d.col.IPoint, x, y, format){
		this.format = format;
		tex = new h3d.mat.Texture(size.x, size.y, [Target], format);
		tempTex = new h3d.mat.Texture(size.x, size.y, [Target], format);
		tex.filter = Linear;
		tempTex.filter = Linear;
		this.x = x;
		this.y = y;
		used = false;
	}

	public function dispose(){
		if(tex != null) tex.dispose();
		if(tempTex != null) tempTex.dispose();
	}

	public function refresh(size: h2d.col.IPoint){
		if(tex != null) tex.dispose();
		if(tempTex != null) tempTex.dispose();
		tex = new h3d.mat.Texture(size.x, size.y, [Target], format);
		tempTex = new h3d.mat.Texture(size.x, size.y, [Target], format);
		tex.filter = Linear;
		tempTex.filter = Linear;
		tex.preventAutoDispose();
		tempTex.preventAutoDispose();
		tex.realloc = null;
		tempTex.realloc = null;
	}

	public function reset(){
		used = false;
		if(tex != null) tex.clear(0);
		if(tempTex != null) tempTex.clear(0);
	}
}

class StrokeBufferArray{

	public var strokeBuffers(default, null) : Array<StrokeBuffer> = [];
	var texSize = new h2d.col.IPoint(0,0);
	var format : hxd.PixelFormat;

	public function new(format, texSize : h2d.col.IPoint ) {
		this.format = format;
		this.texSize = texSize;
	}

	public function dispose(){
		for(strokebuffer in strokeBuffers) strokebuffer.dispose();
	}

	public function getStrokeBuffer(x, y){
		for(strokebuffer in strokeBuffers)
			if((strokebuffer.x == x && strokebuffer.y == y) || strokebuffer.used == false){
				strokebuffer.x = x;
				strokebuffer.y = y;
				return strokebuffer;
			}
		var strokeBuffer = new StrokeBuffer(texSize, x, y, format);
		strokeBuffers.push(strokeBuffer);
		return strokeBuffer;
	}

	public function refresh( size : h2d.col.IPoint ){
		if(texSize == size) return;
		texSize = size;
		for(strokeBuffer in strokeBuffers)
			strokeBuffer.refresh(size);
	}

	public function reset(){
		for(strokeBuffer in strokeBuffers){
			strokeBuffer.reset();
		}
	}
}
