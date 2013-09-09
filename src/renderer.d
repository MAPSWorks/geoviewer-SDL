module renderer;

import std.string: toStringz;
import std.conv: text;

import derelict.sdl2.sdl: SDL_GetError;
import derelict.opengl3.gl3;
import glamour.vao: VAO;
import glamour.shader: Shader;
import glamour.vbo: Buffer, ElementBuffer;
import glamour.texture: Texture2D;

import std.stdio;
		
class Renderer
{
private:
	uint width_, height_;

	float[] vertices_, texture_coords_;
	ushort[] indices_;
	GLint position_, tex_coord_;

	VAO vao_;
	Shader program_;
	Buffer vbo_, tbo_;
	ElementBuffer ibo_;
	Texture2D texture_;

	static immutable string example_program_src_ = `
		#version 120
		vertex:
		in vec2 position;
		in vec2 inCoord;

		out vec2 texCoord;
		void main(void)
		{
		    gl_Position = vec4(position, 0, 1);
			texCoord = inCoord;
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
	this(uint width, uint heigth)
	{
		vertices_ = [ -0.3, -0.3,  0.3, -0.3,  -0.3, 0.3,  0.3, 0.3 ];
	    indices_ = [0, 1, 2, 3];
		texture_coords_ = [ 0.00, 0.00,  01.00, 0.00,  0.00, 01.00,  01.00, 01.00 ];

	    vao_ = new VAO();
	    vao_.bind();

	    // Create VBO
		vbo_ = new Buffer(vertices_);

	    // Create IBO
		ibo_ = new ElementBuffer(indices_);

		// Create buffer object for texture coordinates
		tbo_ = new Buffer(texture_coords_);
		texture_ = Texture2D.from_image("cache/nodata.png");
		texture_.set_parameter(GL_TEXTURE_MIN_FILTER, GL_LINEAR);
		texture_.set_parameter(GL_TEXTURE_MAG_FILTER, GL_LINEAR);

		// Create program
	    program_ = new Shader("example_program", example_program_src_);
	 	program_.bind();
	    position_ = program_.get_attrib_location("position");
	    tex_coord_ = program_.get_attrib_location("inCoord");
	}

	void draw()
	{
		glClearColor(1, 0.9, 0.8, 1);
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
        
        vbo_.bind();
        glEnableVertexAttribArray(position_);
     
		glVertexAttribPointer(position_, 2, GL_FLOAT, GL_FALSE, 0, null);
     
        ibo_.bind();

        tbo_.bind();
        texture_.bind_and_activate();
        glEnableVertexAttribArray(tex_coord_);
        glVertexAttribPointer(tex_coord_, 2, GL_FLOAT, GL_FALSE, 0, null);
     
        glDrawElements(GL_TRIANGLE_STRIP, 4, GL_UNSIGNED_SHORT, null);
     
        glDisableVertexAttribArray(tex_coord_);     
        glDisableVertexAttribArray(position_);
	}

	void close()
	{
		// free resources
		texture_.remove();
		tbo_.remove();
        ibo_.remove();
        vbo_.remove();
        program_.remove();
        vao_.remove();
	}
}