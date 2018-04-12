module sdlapp;

import std.conv: text, to;
import std.string: toStringz;
import std.datetime: dur, StopWatch;
import core.thread: Thread;

import derelict.sdl2.sdl;
import derelict.opengl;

class SDLApp
{
protected:
    SDL_Window* sdl_window_;
    SDL_GLContext gl_context_;

    int mouse_x_, mouse_y_;

    MouseMotionHandler mouse_motion_handler_;
    MouseWheelHandler mouse_wheel_handler_;
    DrawHandler draw_handler_;

public:

    alias void delegate(int x, int y, bool rbtn_pressed) MouseMotionHandler;
    alias void delegate(int x, int y) MouseWheelHandler;
    alias void delegate() DrawHandler;

    @property mouseMotionHandler(MouseMotionHandler handler) { mouse_motion_handler_ = handler; }
    @property mouseWheelHandler(MouseWheelHandler handler) { mouse_wheel_handler_ = handler; }
    @property drawHandler(DrawHandler handler) { draw_handler_ = handler; }

    this(string title, uint width, uint height)
    {
        DerelictSDL2.load(SharedLibVersion(2, 0, 0));
        DerelictGL3.load();

        if (SDL_Init(SDL_INIT_VIDEO) < 0)
            throw new Exception("Failed to initialize SDL: " ~ SDL_GetError().text);

        scope(failure) SDL_Quit();

        // Set OpenGL version
        SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3);
        SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 2);

        // Set OpenGL attributes
        SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);
        SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE, 24);

        sdl_window_ = SDL_CreateWindow(title.toStringz,
            SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
            width, height, SDL_WINDOW_OPENGL | SDL_WINDOW_SHOWN);

        if (!sdl_window_)
            throw new Exception("Failed to create a SDL window: " ~ SDL_GetError().text);
        scope(failure) SDL_DestroyWindow(sdl_window_);

        gl_context_ = SDL_GL_CreateContext(sdl_window_);
        if (gl_context_ is null)
            throw new Exception("Failed to create a OpenGL context: " ~ SDL_GetError().text);
        scope(failure) SDL_GL_DeleteContext(gl_context_);

        DerelictGL3.reload();
}

    void close()
    {
        /* Delete our opengl context, destroy our window, and shutdown SDL */
        SDL_GL_DeleteContext(gl_context_);
        SDL_DestroyWindow(sdl_window_);
        SDL_Quit();
    }

    // run frontend in the current thread
    void run()
    {
        enum FRAMES_PER_SECOND = 60;

        //The frame rate regulator
        StopWatch fps;
        fps.start();
        while(true)
        {

            // process events from OS, if result is
            // false then break loop
            if(!processEvents())
                break;

            if(draw_handler_)
                draw_handler_();

            SDL_GL_SwapWindow(sdl_window_);

            auto t = fps.peek.msecs;
            if(t < 1000 / FRAMES_PER_SECOND)
            {
                //Sleep the remaining frame time
                auto delay = (1000 / FRAMES_PER_SECOND) - t;
                Thread.sleep(dur!"msecs"(delay));
            }
            //reset the frame timer
            fps.reset();
        }
    }

    bool processEvents()
    {
        bool is_running = true;
        // handle all SDL events that we might've received in this loop iteration
        SDL_Event event;
        while (SDL_PollEvent(&event)) {
            switch(event.type){
                // user has clicked on the window's close button
                case SDL_QUIT:
                    is_running = false;
                    break;
                case SDL_KEYUP:
                    switch (event.key.keysym.sym) {
                        // if user presses ESCAPE key - stop running
                        case SDLK_ESCAPE:
                            is_running = false;
                            break;
                        default:{}
                    }
                    break;
                case SDL_KEYDOWN:
                    switch (event.key.keysym.sym) {
                        case SDLK_UP:
                            break;
                        case SDLK_DOWN:
                            break;
                        case SDLK_RIGHT:
                            break;
                        case SDLK_LEFT:
                            break;
                        default:{}
                    }
                    break;
                case SDL_MOUSEMOTION:
                    mouse_x_ = event.motion.x;
                    mouse_y_ = event.motion.y;

                    if(mouse_motion_handler_)
                        mouse_motion_handler_(mouse_x_, mouse_y_, (event.motion.state & SDL_BUTTON_RMASK) != 0);
                break;
                case SDL_MOUSEBUTTONDOWN:
                    break;
                case SDL_MOUSEWHEEL:
                    if(mouse_wheel_handler_)
                        mouse_wheel_handler_(event.wheel.x, event.wheel.y);
                    break;
                default:
                    break;
            }
        }
        return is_running;
    }
}
