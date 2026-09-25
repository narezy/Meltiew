#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/string.hpp>

namespace mvm
{
struct VM;
}

// Luau for GDScript. One LuauVM = one sandboxed Luau state (client scripts of a place,
// or server scripts during a Studio play test). See native/core/mvm.h.
class LuauVM : public godot::RefCounted
{
    GDCLASS(LuauVM, godot::RefCounted)

public:
    LuauVM();
    ~LuauVM() override;

    // Creates the state; memory_limit_mb caps what scripts can allocate.
    bool open(int memory_limit_mb);
    void close();
    // Runs trusted code with full globals (the runtime prelude). Returns "" or the error.
    godot::String run(const godot::String& chunkname, const godot::String& source);
    void sandbox();
    // Calls a global function with one string; returns its string result.
    // On error returns "" and get_error() holds the message.
    godot::String call_function(const godot::String& name, const godot::String& arg, double time_limit);
    godot::String get_error() const;
    int64_t memory_used() const;

protected:
    static void _bind_methods();

private:
    mvm::VM* vm = nullptr;
    godot::String error;
};
