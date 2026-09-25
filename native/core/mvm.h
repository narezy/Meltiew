// Meltiew VM: a sandboxed Luau state shared by the game client (GDExtension)
// and the game server (WebAssembly). The host talks to Luau through strings only:
// it runs the runtime prelude once, then calls prelude functions with a string
// argument and gets a string back (JSON on both sides).
#pragma once

#include <cstddef>
#include <string>

namespace mvm
{

struct VM;

// memory_limit is in bytes; allocations beyond it fail with a Luau memory error.
VM* create(size_t memory_limit);
void destroy(VM* vm);

// Runs `source` as a chunk with full access to globals (used for the runtime prelude).
// Returns an empty string on success, otherwise the error message.
std::string run(VM* vm, const std::string& chunkname, const std::string& source);

// Makes built-in libraries and globals read-only. Call once after the prelude.
void sandbox(VM* vm);

// Calls the global function `name` with one string argument. On success `result` holds
// the returned string (empty if the function returned nothing) and true is returned.
// On failure `result` holds the error. `time_limit` (seconds, 0 = none) stops runaway
// scripts such as `while true do end` with a "script timeout" error.
bool call(VM* vm, const char* name, const std::string& arg, double time_limit, std::string& result);

size_t memory_used(VM* vm);

} // namespace mvm
