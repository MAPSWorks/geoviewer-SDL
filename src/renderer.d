module renderer;

import std.string: toStringz;
import std.conv: text;

import derelict.sdl2.sdl: SDL_GetError;
import derelict.opengl3.gl3;
import glamour.vao: VAO;
import glamour.shader: Shader;
import glamour.vbo: Buffer, ElementBuffer;

import std.stdio;
		
class Renderer
{
private:
	uint width_, height_;

	float[] vertices;
	ushort[] indices;
	GLint position_;

	VAO vao_;
	Shader program_;
	Buffer vbo_;
	ElementBuffer ibo_;

	static immutable string example_program_src_ = `
		#version 120
		vertex:
		attribute vec2 position;
		void main(void)
		{
		    gl_Position = vec4(position, 0, 1);
		}
		fragment:
		void main(void)
		{
		    gl_FragColor = vec4(1.0, 0.0, 0.0, 1.0);
		}
		`;

public:
	this(uint width, uint heigth)
	{
		vertices = [ -0.3, -0.3,  0.3, -0.3,  -0.3, 0.3,  0.3, 0.3];
	    indices = [0, 1, 2, 3];

	    vao_ = new VAO();
	    vao_.bind();

	    // Create VBO
		vbo_ = new Buffer(vertices);

	    // Create IBO
		ibo_ = new ElementBuffer(indices);

		// Create program
	    program_ = new Shader("example_program", example_program_src_);
	 	program_.bind();
	    position_ = program_.get_attrib_location("position");
	}

	void draw()
	{
		glClearColor(1, 0.9, 0.8, 1);
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
        
        vbo_.bind();
        glEnableVertexAttribArray(position_);
     
		glVertexAttribPointer(position_, 2, GL_FLOAT, GL_FALSE, 0, null);
     
        ibo_.bind();
     
        glDrawElements(GL_TRIANGLE_STRIP, 4, GL_UNSIGNED_SHORT, null);
     
        glDisableVertexAttribArray(position_);
	}

	void close()
	{
		// free resources
        ibo_.remove();
        vbo_.remove();
        program_.remove();
        vao_.remove();
	}
}