module camera;

import std.typecons: Tuple;
import std.math: pow, round, log2;
import std.conv: to;

import derelict.opengl3.gl3: glViewport;
import gl3n.linalg: vec3, vec3d, mat4;

import tile: world2tile, tile2world;

class Camera
{
protected:
	mat4 modelmatrix_;
	double scale_;
	double scale_min_;
	double scale_max_;

	uint zoom_; // see slippy tiles
	double aspect_ratio_;
	uint viewport_width_, viewport_height_;

	vec3d eyes_; // coordinates of veiwer's eyes
	bool scrolling_enabled_;

	abstract void computeModelViewMatrix();
public:

	this(uint width, uint height, double scale_min, double scale_max)
	{
		scale_ = 1.;
		scale_min_ = scale_min;
		scale_max_ = scale_max;
		eyes_ = vec3d(0, 0, 1);
		resize(width, height);
		computeModelViewMatrix();
	}

	final @property scaleMin(double value) { scale_min_ = value; }
	final @property scaleMin() { return scale_min_; }

	final @property scaleMax(double value) { scale_max_ = value; }
	final @property scaleMax() { return scale_max_; }

	abstract vec3d mouse2world(vec3d xy);
	abstract vec3d world2mouse(vec3d xyz);

	abstract Tuple!(int, "x", int, "y", int, "zoom")[] getViewableTiles();

	// for convenience
	vec3d mouse2world(double x, double y, double zoom)
	{
		return mouse2world(vec3d(x, y, zoom));
	}

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
		computeModelViewMatrix();
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
				auto old_position = mouse2world( old_mouse_x, old_mouse_y, zoom_ );

				auto current_position = mouse2world( mouse_x, mouse_y, zoom_ );

				// correct current globe states using difference tween old and new marker coordinates
				vec3d new_eyes;
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

	@property zoom() { return zoom_; }
	@property eyes() { return eyes_; }
	@property eyes(vec3d eyes) { eyes_ = eyes; computeModelViewMatrix(); }
	@property viewportHeight() { return viewport_height_; }
	@property viewportWidth() { return viewport_width_; }
}

class Camera2D: Camera
{
protected:

	override void computeModelViewMatrix()
	{
		// set the matrix
		auto world = mat4.identity.translate(-eyes_.x, -eyes_.y, 0);
		auto size = 1 / scale_;
        auto view = mat4.look_at(vec3(0, 0, size), vec3(0, 0, 0), vec3(0, 1., 0));
		auto projection = mat4.orthographic(-size, size, size/aspect_ratio_, -size/aspect_ratio_, size, -size);
		modelmatrix_ = projection * view * world;

		zoom_ = log2(scale_).to!int;
	}

public:

	this(uint width, uint height, double min_scale = 1, double max_scale = 65536*4)
	{
		super(width, height, min_scale, max_scale);
	}

	override vec3d mouse2world(vec3d xyz)
	{
		// normalize
        xyz.x /= viewportWidth/2;
        xyz.y /= viewportHeight/2;

		// translate to center
		xyz.x -= 1;
        xyz.y -= 1;
		// invert y coordinate
		xyz.y *= -1;
		// scale
		xyz.x /= scale_;
        xyz.y /= scale_*aspect_ratio_;
		// translate to camera coordinate system
		xyz.x = eyes.x + xyz.x;
		xyz.y = eyes.y - xyz.y;
		xyz.z = zoom_;
		return xyz;
	}

	override vec3d world2mouse(vec3d xyz)
	{
		assert(0);
	}

	/// using camera creates list of tiles that
    /// are viewable from the camera at the moment
    override Tuple!(int, "x", int, "y", int, "zoom")[] getViewableTiles()
    {
        auto left_top = super.mouse2world(0., 0., 0.).world2tile;
        auto right_bottom = super.mouse2world(viewportWidth, viewportHeight, 0.).world2tile;

        int n = pow(2, zoom);

        Tuple!(int, "x", int, "y", int, "zoom")[] result;

        auto x_left = (left_top.x - 1).round.to!int;
        auto x_right = right_bottom.x.to!int + 1;
        auto y_top = (left_top.y - 1).round.to!int;
        auto y_bottom = right_bottom.y.to!int + 1;

        assert((x_right - x_left) > 0, "right coordinate should be greater than left one");
        assert((y_bottom - y_top) > 0, "bottom coordinate should be greater than top one");
        result.length = (x_right - x_left)*(y_bottom - y_top);

        int i;
        foreach(x; x_left..x_right)
        {
            foreach(y; y_top..y_bottom)
            {
                if(y>=0 && y < n)
                    result[i++] = Tuple!(int, "x", int, "y", int, "zoom")(x, y, zoom);
            }
        }
        result.length = i;

        return result;
    }
}

unittest
{
    auto cam = new Camera2D(400, 300, 1);

    auto w = cam.mouse2world(vec3d(.0, .0, cam.zoom));

    assert(w.x >= -1 && w.x <= 1);
    assert(w.y >= -1 && w.y <= 1);
    assert(w.z == cam.zoom);

    w = cam.mouse2world(vec3d(399, 299, cam.zoom));

    assert(w.x >= -1 && w.x <= 1);
    assert(w.y >= -1 && w.y <= 1);
    assert(w.z == cam.zoom);
}

alias Camera2D Camera3D;
