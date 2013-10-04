module camera;

import std.typecons: Tuple;

import derelict.opengl3.gl3: glViewport;
import gl3n.linalg;

class Camera
{
protected:
	mat4 modelmatrix_;
	double scale_;
	double world_width_; // world height is computed using aspect ratio
	double scale_min_;
	double scale_max_;

	uint zoom_; // see slippy tiles
	double aspect_ratio_;
	uint viewport_width_, viewport_height_;

	vec3 eyes_; // coordinates of veiwer's eyes
	bool scrolling_enabled_;

	abstract void computeModelViewMatrix();
public:

	this(uint width, uint height, double world_width, double scale_min = 0.5, double scale_max = 1.5)
	{
		scale_ = 1.0;
		world_width_ = world_width;
		scale_min_ = scale_min;
		scale_max_ = scale_max;
		eyes_ = vec3(0, 0, 1);
		resize(width, height);
	}

	final @property scaleMin(double value) { scale_min_ = value; }
	final @property scaleMin() { return scale_min_; }

	final @property scaleMax(double value) { scale_max_ = value; }
	final @property scaleMax() { return scale_max_; }

	abstract vec3 mouse2world(vec2 xy);
	abstract vec2 world2mouse(vec3 xyz);

	/// The function multiplies scale by the factor
	/// it allows to increase or decrease the scale.
	final void multiplyScale(double factor) {
		auto new_value = scale_ * factor;
		if (new_value <= scale_max_ && new_value >= scale_min_) {
			scale_ = new_value;
			computeModelViewMatrix();
		}
	}

	final @property scale()
	{
		return scale_;
	}

	final @property scale(double value)
	{
		if(value >= scale_min_ && value <= scale_max_)
		scale_ = value;
	}

	final @property scrollingEnabled() { return scrolling_enabled_; }
	final @property scrollingEnabled(bool value) { scrolling_enabled_ = value; }

	/// moves camera according to mouse move
	final bool doScrolling(uint mouse_x, uint mouse_y) {
		static uint old_mouse_x, old_mouse_y;
		auto changed = false;
			
		// if scrolling is enabled
		if (scrolling_enabled_) {
			// and marker coord is changed
			if ((mouse_x != old_mouse_x) || (mouse_y != old_mouse_y)) 
			{
				// calculate old marker coordinates using old mouse coordinates
				auto old_position = mouse2world(vec2(old_mouse_x, old_mouse_y));
				auto current_position = mouse2world(vec2(mouse_x, mouse_y));
				
				// correct current globe states using difference tween old and new marker coordinates
				vec3 new_eyes;
				new_eyes.x = eyes_.x - (current_position.x - old_position.x);
				new_eyes.y = eyes_.y - (current_position.y - old_position.y);
				new_eyes.z = eyes_.z - (current_position.z - old_position.z);
				eyes_ = new_eyes;

				computeModelViewMatrix();

				changed = true;
			}
		}
		old_mouse_x = mouse_x;
		old_mouse_y = mouse_y;

		return changed;
	}

	/// The function change the size of the viewport_ for example when window size changed
	final void resize(uint width, uint height) {
		assert(width);
		assert(height);
		viewport_width_ = width;
		viewport_height_ = height;
		aspect_ratio_ = cast(double) viewport_width_/viewport_height_;
		computeModelViewMatrix();
	}
	
	final mat4 getModelViewMatrix() 
	{
		return modelmatrix_;
	}

	@property eyes() { return eyes_; };
}

class Camera2D: Camera
{
protected:

	override void computeModelViewMatrix()
	{
		// set the matrix
		auto world = mat4.identity.translate(-eyes_.x, eyes_.y, -eyes_.z); // invert y coordinate
		auto view = mat4.look_at(vec3(0, 0, 1), vec3(0, 0, 0), vec3(0, 1., 0));
		auto size = scale_ * world_width_ / 2;
		auto projection = mat4.orthographic(-size * aspect_ratio_, size * aspect_ratio_, -size, size, 2*size, 0);
		modelmatrix_ = projection * view * world;
	}

public:

	this(uint width, uint height, double world_width, double min_scale = 0.5, double max_scale = 1.5)
	{
		super(width, height, world_width, min_scale, max_scale);
	}

	override vec3 mouse2world(vec2 xy)
	{
		return vec3(xy.x.to!double, xy.y.to!double, 0.)*(scale_*aspect_ratio_*world_width_/viewport_width_);
	}

	override vec2 world2mouse(vec3 xyz)
	{
		return vec2(xyz.x.to!uint, xyz.y.to!uint)*(scale_*aspect_ratio_*world_width_/viewport_width_);
	}
}

alias Camera2D Camera3D;
