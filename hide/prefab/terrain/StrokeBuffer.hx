package hide.prefab.terrain;

class StrokeBuffer {
	public var tex : h3d.mat.Texture;
	public var x : Int;
	public var y : Int;
	public var used : Bool;
	public var prevTex : h3d.mat.Texture;
	public var tempTex : h3d.mat.Texture;
	public var format : hxd.PixelFormat;

	public function new(size, x, y, format){
		this.format = format;
		tex = new h3d.mat.Texture(size,size, [Target], format);
		tempTex = new h3d.mat.Texture(size,size, [Target], format);
		tex.filter = Linear;
		tempTex.filter = Linear;
		this.x = x;
		this.y = y;
		used = false;
	}

	public function refresh(size){
		if(tex != null) tex.dispose();
		if(tempTex != null) tempTex.dispose();
		tex = new h3d.mat.Texture(size, size, [Target], format);
		tempTex = new h3d.mat.Texture(size, size, [Target], format);
		tex.filter = Linear;
		tempTex.filter = Linear;
	}

	public function reset(){
		used = false;
		if(tex != null) tex.clear(0);
		if(tempTex != null) tempTex.clear(0);
		if(prevTex != null) prevTex.clear(0);
	}
}

class StrokeBufferArray{

	public var strokeBuffers(default, null) : Array<StrokeBuffer> = [];
	var texSize = 0;
	var format : hxd.PixelFormat;

	public function new(format, texSize){
		this.format = format;
		this.texSize = texSize;
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

	public function refresh(size){
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
