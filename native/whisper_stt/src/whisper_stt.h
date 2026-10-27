// WhisperSTT: whisper.cpp inside the game process, for platforms that cannot run the bundled
// whisper-cli program (Android/Quest blocks executing files from app storage). Player bug board
// #13, dev 2026-10-26: "On-device whisper for Quest". One recording at a time on its own thread.
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/string.hpp>

#include <atomic>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

struct whisper_context;

namespace godot {

class WhisperSTT : public RefCounted {
	GDCLASS(WhisperSTT, RefCounted)

	whisper_context *context = nullptr;
	std::thread worker;
	std::atomic<bool> running{ false };
	std::atomic<bool> aborting{ false };
	std::mutex lock;
	std::string text;
	std::string failure;

	void join();

protected:
	static void _bind_methods();

public:
	~WhisperSTT();
	// Loads (or replaces) the model from a real file path, not res://.
	Error load_model(const String &path);
	bool has_model() const;
	// 16-bit PCM WAV, any rate and channel count; mixed to mono and resampled to 16 kHz.
	Error start(const PackedByteArray &wav, const String &prompt, int threads);
	bool is_running() const;
	// The finished transcript, or "" while running; error() says why a run failed.
	String take_text();
	String error();
	void cancel();
};

} // namespace godot
