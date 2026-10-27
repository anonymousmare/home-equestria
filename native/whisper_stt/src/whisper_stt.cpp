#include "whisper_stt.h"

#include <godot_cpp/core/class_db.hpp>

#include <whisper.h>

#include <cmath>
#include <cstring>

using namespace godot;

namespace {

uint32_t u32(const uint8_t *p) { return uint32_t(p[0]) | uint32_t(p[1]) << 8 | uint32_t(p[2]) << 16 | uint32_t(p[3]) << 24; }
uint16_t u16(const uint8_t *p) { return uint16_t(p[0] | p[1] << 8); }

// RIFF/WAVE 16-bit PCM to mono float at 16 kHz. Empty on a format it does not read.
std::vector<float> decode(const PackedByteArray &wav) {
	std::vector<float> out;
	const uint8_t *data = wav.ptr();
	const size_t size = size_t(wav.size());
	if (size < 12 || std::memcmp(data, "RIFF", 4) != 0 || std::memcmp(data + 8, "WAVE", 4) != 0) {
		return out;
	}
	int channels = 0, rate = 0, bits = 0;
	const uint8_t *pcm = nullptr;
	size_t pcm_bytes = 0;
	for (size_t at = 12; at + 8 <= size;) {
		const uint32_t length = u32(data + at + 4);
		const uint8_t *body = data + at + 8;
		const size_t available = std::min<size_t>(length, size - at - 8);
		if (std::memcmp(data + at, "fmt ", 4) == 0 && available >= 16) {
			if (u16(body) != 1) {
				return out;
			}
			channels = u16(body + 2);
			rate = int(u32(body + 4));
			bits = u16(body + 14);
		} else if (std::memcmp(data + at, "data", 4) == 0) {
			pcm = body;
			pcm_bytes = available;
		}
		at += 8 + size_t(length) + (length & 1);
	}
	if (pcm == nullptr || channels < 1 || rate < 1000 || bits != 16) {
		return out;
	}
	const size_t frames = pcm_bytes / (2 * size_t(channels));
	std::vector<float> mono(frames);
	for (size_t i = 0; i < frames; i++) {
		float sum = 0.0f;
		for (int c = 0; c < channels; c++) {
			sum += float(int16_t(u16(pcm + (i * channels + c) * 2))) / 32768.0f;
		}
		mono[i] = sum / float(channels);
	}
	if (rate == WHISPER_SAMPLE_RATE) {
		return mono;
	}
	const double step = double(rate) / WHISPER_SAMPLE_RATE;
	const size_t count = size_t(double(frames) / step);
	out.resize(count);
	for (size_t i = 0; i < count; i++) {
		const double source = double(i) * step;
		const size_t a = size_t(source);
		const size_t b = std::min(a + 1, frames - 1);
		const float t = float(source - double(a));
		out[i] = mono[a] * (1.0f - t) + mono[b] * t;
	}
	return out;
}

} // namespace

void WhisperSTT::_bind_methods() {
	ClassDB::bind_method(D_METHOD("load_model", "path"), &WhisperSTT::load_model);
	ClassDB::bind_method(D_METHOD("has_model"), &WhisperSTT::has_model);
	ClassDB::bind_method(D_METHOD("start", "wav", "prompt", "threads"), &WhisperSTT::start);
	ClassDB::bind_method(D_METHOD("is_running"), &WhisperSTT::is_running);
	ClassDB::bind_method(D_METHOD("take_text"), &WhisperSTT::take_text);
	ClassDB::bind_method(D_METHOD("error"), &WhisperSTT::error);
	ClassDB::bind_method(D_METHOD("cancel"), &WhisperSTT::cancel);
}

WhisperSTT::~WhisperSTT() {
	cancel();
	if (context != nullptr) {
		whisper_free(context);
	}
}

void WhisperSTT::join() {
	if (worker.joinable()) {
		worker.join();
	}
}

Error WhisperSTT::load_model(const String &path) {
	cancel();
	if (context != nullptr) {
		whisper_free(context);
		context = nullptr;
	}
	whisper_context_params params = whisper_context_default_params();
	params.use_gpu = false;
	context = whisper_init_from_file_with_params(path.utf8().get_data(), params);
	return context != nullptr ? OK : ERR_FILE_CANT_OPEN;
}

bool WhisperSTT::has_model() const {
	return context != nullptr;
}

Error WhisperSTT::start(const PackedByteArray &wav, const String &prompt, int threads) {
	if (context == nullptr) {
		return ERR_UNCONFIGURED;
	}
	if (running.load()) {
		return ERR_BUSY;
	}
	join();
	std::vector<float> samples = decode(wav);
	if (samples.size() < WHISPER_SAMPLE_RATE / 10) {
		return ERR_INVALID_DATA;
	}
	{
		std::lock_guard<std::mutex> guard(lock);
		text.clear();
		failure.clear();
	}
	aborting = false;
	running = true;
	const std::string initial = prompt.utf8().get_data();
	worker = std::thread([this, samples = std::move(samples), initial, threads]() {
		whisper_full_params params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
		params.n_threads = std::max(1, threads);
		params.language = "en";
		params.no_timestamps = true;
		params.print_progress = false;
		params.print_realtime = false;
		params.print_timestamps = false;
		params.print_special = false;
		params.initial_prompt = initial.empty() ? nullptr : initial.c_str();
		params.abort_callback = [](void *flag) { return static_cast<std::atomic<bool> *>(flag)->load(); };
		params.abort_callback_user_data = &aborting;
		const int result = whisper_full(context, params, samples.data(), int(samples.size()));
		std::string words;
		if (result == 0) {
			for (int i = 0; i < whisper_full_n_segments(context); i++) {
				words += whisper_full_get_segment_text(context, i);
			}
		}
		{
			std::lock_guard<std::mutex> guard(lock);
			text = words;
			if (result != 0) {
				failure = aborting.load() ? "cancelled" : "Speech recognition could not read this recording.";
			}
		}
		running = false;
	});
	return OK;
}

bool WhisperSTT::is_running() const {
	return running.load();
}

String WhisperSTT::take_text() {
	if (running.load()) {
		return String();
	}
	join();
	std::lock_guard<std::mutex> guard(lock);
	return String::utf8(text.c_str()).strip_edges();
}

String WhisperSTT::error() {
	std::lock_guard<std::mutex> guard(lock);
	return String::utf8(failure.c_str());
}

void WhisperSTT::cancel() {
	aborting = true;
	join();
	running = false;
}
