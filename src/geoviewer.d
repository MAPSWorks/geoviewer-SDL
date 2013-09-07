module geoviewer;

import frontend: FrontEnd;
import backend: BackEnd;

class Geoviewer {
private:
	FrontEnd frontend_;
	BackEnd backend_;
public:

	this(uint width, uint height, double lon, double lat, string url, string cache_path)
	{
		backend_ = new BackEnd(lon, lat, url, cache_path);
		frontend_ = new FrontEnd(width, height);		
	}

	void run()
	{
		backend_.runAsync();
		frontend_.run();
	}

	void close() {
		frontend_.close();
		backend_.close();
	}
}