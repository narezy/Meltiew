#include "luau_vm.h"

#include "../core/mvm.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

static std::string to_std(const String& s)
{
    CharString utf8 = s.utf8();
    return std::string(utf8.get_data(), utf8.length());
}

static String from_std(const std::string& s)
{
    return String::utf8(s.data(), int64_t(s.size()));
}

LuauVM::LuauVM() {}

LuauVM::~LuauVM()
{
    close();
}

bool LuauVM::open(int memory_limit_mb)
{
    close();
    vm = mvm::create(size_t(memory_limit_mb) * 1024 * 1024);
    return vm != nullptr;
}

void LuauVM::close()
{
    if (vm)
    {
        mvm::destroy(vm);
        vm = nullptr;
    }
}

String LuauVM::run(const String& chunkname, const String& source)
{
    if (!vm)
        return "vm is not open";
    return from_std(mvm::run(vm, to_std(chunkname), to_std(source)));
}

void LuauVM::sandbox()
{
    if (vm)
        mvm::sandbox(vm);
}

String LuauVM::call_function(const String& name, const String& arg, double time_limit)
{
    error = String();
    if (!vm)
    {
        error = "vm is not open";
        return String();
    }
    std::string result;
    std::string fname = to_std(name);
    if (!mvm::call(vm, fname.c_str(), to_std(arg), time_limit, result))
    {
        error = from_std(result);
        return String();
    }
    return from_std(result);
}

String LuauVM::get_error() const
{
    return error;
}

int64_t LuauVM::memory_used() const
{
    return vm ? int64_t(mvm::memory_used(vm)) : 0;
}

void LuauVM::_bind_methods()
{
    ClassDB::bind_method(D_METHOD("open", "memory_limit_mb"), &LuauVM::open);
    ClassDB::bind_method(D_METHOD("close"), &LuauVM::close);
    ClassDB::bind_method(D_METHOD("run", "chunkname", "source"), &LuauVM::run);
    ClassDB::bind_method(D_METHOD("sandbox"), &LuauVM::sandbox);
    ClassDB::bind_method(D_METHOD("call_function", "name", "arg", "time_limit"), &LuauVM::call_function);
    ClassDB::bind_method(D_METHOD("get_error"), &LuauVM::get_error);
    ClassDB::bind_method(D_METHOD("memory_used"), &LuauVM::memory_used);
}
