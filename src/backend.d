module backend;

//import std.concurrency: spawn, thisTid, Tid;

// backend получает от фронтенда пользовательский ввод, обрабатывает данные
// в соотвествии с бизнес-логикой и отправляет их фронтенду
class BackEnd
{
private:
	string url_, cache_path_;
public:

	this(double lon, double lat, string url, string cache_path)
	{
		url_ = url;
		cache_path_ = cache_path;
	}

	// run backend in other thread
	void runAsync()
	{

	}

	void close()
	{
		
	}
}
