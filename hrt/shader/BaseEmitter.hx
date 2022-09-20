package hrt.shader;

class BaseEmitter extends hxsl.Shader {

	static var SRC = {

		@perInstance @param var lifeTime : Float;
		@perInstance @param var life : Float;
        @perInstance @param var random : Float; 

        var particleRandom : Float;
        var particleLifeTime : Float;

        // Each particle as a random value asigned on spawn
        var particleLife : Float;

        function __init__() {
            particleRandom = random;
            particleLifeTime = lifeTime;
            particleLife = life;
        }
	};

}