module renderer;

import std.string: toStringz;
import std.conv: text, to;
import std.stdio: writeln, writefln, stderr;
import std.exception: enforce;
import std.range: iota;
import std.array: array;
import std.math: pow;

import derelict.sdl2.sdl: SDL_GetError;
import derelict.opengl3.gl3;
import glamour.vao: VAO;
import glamour.shader: Shader;
import glamour.vbo: Buffer, ElementBuffer;
import glamour.texture: Texture2D;
import gl3n.linalg: vec3d;

import tile: Tile;
import camera: Camera, Camera2D, Camera3D;

// class describing slippy tile from opengl point of view
private class GLTile
{
	VAO vao;
	Buffer vertices;
	Buffer tex_coords;
	ElementBuffer indices;
	Texture2D texture;

	void remove()
	{
		vertices.remove();
		indices.remove();
		tex_coords.remove();
		texture.remove();
		vao.remove();
	}
}

private class RendererWithCamera
{
private:
	Camera2D camera_2d_;
	Camera3D camera_3d_;
	enum CameraMode { mode2D, mode3D };
	CameraMode camera_mode_;

public:

	@property Camera camera()
	{
		final switch(camera_mode_)
		{
			case CameraMode.mode2D:
				return camera_2d_;
			case CameraMode.mode3D:
				return camera_3d_;
		}
	}

	alias camera this;
}

class Renderer : RendererWithCamera
{
private:
	uint width_, height_;

	GLint position_, tex_coord_;

	Shader program_;

	immutable enum tileAmount = 1024;
	size_t downloading_total_; // total tiles to be downloaded
	GLTile[] current_set_, // current tile set, that's being rendered
		downloading_set_; // set of downloading tiles that after finishing will replace current tile set

	static immutable string example_program_src_ = `
		#version 120
		vertex:
		in vec2 in_position;
		in vec2 in_coord;

		// mvpmatrix is the result of multiplying the model, view, and projection matrices */
		uniform mat4 mvpmatrix;

		out vec2 texCoord;
		void main(void)
		{
		    gl_Position = mvpmatrix * vec4(in_position, 0, 1);
			texCoord = in_coord;
		}
		fragment:
		in vec2 texCoord;
		out vec4 outputColor;

		uniform sampler2D gSampler;

		void main(void)
		{
			outputColor = texture2D(gSampler, texCoord);
		}
		`;
/*
uniform int multiplicationFactor = 8;
		uniform float threshold = 0.1;

		in vec2 texCoord;
		out vec4 colorOut;

		void main() {
		    // multiplicationFactor scales the number of stripes
		    vec2 t = texCoord * multiplicationFactor ;

		    // the threshold constant defines the with of the lines
		    if (fract(t.s) < threshold  || fract(t.t) < threshold )
		        colorOut = vec4(0.0, 0.0, 1.0, 1.0);
		    else
		        discard;
		}
*/


public:
	this(uint width, uint height)
	{
		// Create program
	    program_ = new Shader("example_program", example_program_src_);
	 	program_.bind();
	    position_ = program_.get_attrib_location("in_position");
	    tex_coord_ = program_.get_attrib_location("in_coord");
	    camera_2d_ = new Camera2D(width, height);
        camera_2d_.scale = pow(2, 7); // set 7th zoom
	    camera_2d_.eyes = vec3d(0.5, 0.5, 0); // set camera to the center
	    camera_3d_ = new Camera3D(width, height, 1.0);
	    camera_mode_ = CameraMode.mode2D;
	}

	void draw(uint mouse_x, uint mouse_y)
	{
		auto matrix = camera.getModelViewMatrix();
		/* Bind our modelmatrix variable to be a uniform called mvpmatrix in our shaderprogram */
      	glUniformMatrix4fv(glGetUniformLocation(program_, "mvpmatrix"), 1, GL_TRUE, matrix.value_ptr);

		glClearColor(1, 0.9, 0.8, 1);
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

        uint element_count;
        foreach(gltile; current_set_)
        {
        	gltile.vao.bind();
        	gltile.texture.bind_and_activate();
        	element_count = (gltile.indices.length/ushort.sizeof).to!int; // TODO: using conv.to is not optimal for release version
        	glDrawElements(GL_TRIANGLE_STRIP, element_count, GL_UNSIGNED_SHORT, null);
			gltile.texture.unbind();
        	gltile.vao.unbind();
        }

        foreach(gltile; downloading_set_)
        {
        	gltile.vao.bind();
        	gltile.texture.bind_and_activate();
        	element_count = (gltile.indices.length/ushort.sizeof).to!int; // TODO: using conv.to is not optimal for release version
        	glDrawElements(GL_TRIANGLE_STRIP, element_count, GL_UNSIGNED_SHORT, null);
			gltile.texture.unbind();
        	gltile.vao.unbind();
        }
	}

	void close()
	{
		// free resources
		foreach(gltile; current_set_)
			gltile.remove();
		foreach(gltile; downloading_set_)
			gltile.remove();

        program_.remove();
	}

	/// make downloaded set null and
	/// reserve place for it
	void startTileset(size_t amount)
	{
		if(amount > tileAmount)
		{
			stderr.writefln("Too much tiles in set (max %s): %s", tileAmount, amount);
			amount = tileAmount;
		}
		current_set_ ~= downloading_set_; // add already downloaded tiles to the current
		downloading_set_ = null;
		downloading_total_ = amount;
		downloading_set_.reserve(amount);
	}

	/// make downloaded set the current set
	/// and the current set make null
	void finishTileset()
	{
		auto tmp_set = current_set_;
		current_set_ = downloading_set_;
		downloading_set_ = null;
		foreach(gltile; tmp_set)
			gltile.remove();
	}

	/// add tile to downloaded set, if tile amount
	/// is more than tileAmount value ignore excessive tiles
	void setTile(Tile tile)
	{
		if(downloading_set_.length == tileAmount)
			return;

		enforce(tile);
		auto gltile = new GLTile();
		gltile.vao = new VAO();

		// create texture using tile data
		gltile.texture = new Texture2D();
		with(tile) gltile.texture.set_data(data, internal_format, tile.width, height, format, type);
		gltile.texture.set_parameter(GL_TEXTURE_MIN_FILTER, GL_LINEAR);
		gltile.texture.set_parameter(GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        gltile.texture.set_parameter(GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        gltile.texture.set_parameter(GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);

		gltile.vertices = new Buffer(tile.vertices);
	    gltile.tex_coords = new Buffer(tile.tex_coords);
	    gltile.indices = new ElementBuffer([0, 1, 2, 3].to!(ushort[]));

	    // start compiling to VAO
	    gltile.vao.bind();

		gltile.vertices.bind();
        glEnableVertexAttribArray(position_);
		glVertexAttribPointer(position_, 2, GL_FLOAT, GL_FALSE, 0, null);

        gltile.indices.bind();

        gltile.tex_coords.bind();
        glEnableVertexAttribArray(tex_coord_);
        glVertexAttribPointer(tex_coord_, 2, GL_FLOAT, GL_FALSE, 0, null);

        gltile.vao.unbind();
        // finish compiling to VAO

        downloading_set_ ~= gltile;

        //writefln("downloaded: %3.2f %%", downloading_set_.length*100/downloading_total_.to!float);

        if(downloading_set_.length == downloading_total_)
        	finishTileset();
	}
}
