// Registers WhisperSTT (whisper.cpp in-process speech recognition, whisper_stt.h).
#include "whisper_stt.h"

#include <gdextension_interface.h>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

using namespace godot;

void initialize_whisper_stt(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(WhisperSTT);
}

void uninitialize_whisper_stt(ModuleInitializationLevel p_level) {
}

extern "C" {
GDExtensionBool GDE_EXPORT whisper_stt_library_init(GDExtensionInterfaceGetProcAddress p_get_proc_address,
		const GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	godot::GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
	init_obj.register_initializer(initialize_whisper_stt);
	init_obj.register_terminator(uninitialize_whisper_stt);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}
}
