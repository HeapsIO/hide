package hrt.shader;

class BaseEmitter extends hxsl.Shader {

	static var SRC = {

		@:import h3d.shader.BaseMesh;

		@perInstance @param var lifeTime : Float;
		@perInstance @param var life : Float;
        @perInstance @param var random : Float;

        @const @param var billboardMode : Bool;

        
        // Each particle as a random value asigned on spawn
        var particleRandom : Float;
        var particleLifeTime : Float;
        var particleLife : Float;


        function __init__() {
            particleRandom = random;
            particleLifeTime = lifeTime;
            particleLife = life;
        }

        function vertex() {
            if (billboardMode) {
                var newModelView = mat4(
                    vec4(camera.view[0].x, camera.view[1].x, camera.view[2].x, global.modelView[0].w),
                    vec4(camera.view[0].y, camera.view[1].y, camera.view[2].y, global.modelView[1].w),
                    vec4(camera.view[0].z, camera.view[1].z, camera.view[2].z, global.modelView[2].w),
                    vec4(0, 0, 0, 1)
                );
    
                // scale 
                newModelView = mat4(
                    vec4(length(global.modelView[0].xyz), 0.0, 0.0, 0.0),
                    vec4(0.0, length(global.modelView[1].xyz), 0.0, 0.0),
                    vec4(0.0, 0.0, length(global.modelView[2].xyz), 0.0),
                    vec4(0.0, 0.0, 0.0, 1.0)
                ) * newModelView;
    
                transformedPosition = relativePosition * newModelView.mat3x4();
                transformedNormal = (input.normal * newModelView.mat3()).normalize();
            }
        }
	};

}