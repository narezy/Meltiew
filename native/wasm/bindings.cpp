// WebAssembly build of the Meltiew VM for the game server (Node).
// Same core as the client's GDExtension, so scripts behave identically on both sides.
#include "../core/mvm.h"

#include <emscripten/bind.h>

#include <string>

class VM
{
public:
    explicit VM(int memoryLimitMb)
        : vm(mvm::create(size_t(memoryLimitMb) * 1024 * 1024))
    {
    }
    ~VM()
    {
        mvm::destroy(vm);
    }
    std::string run(const std::string& chunkname, const std::string& source)
    {
        return mvm::run(vm, chunkname, source);
    }
    void sandbox()
    {
        mvm::sandbox(vm);
    }
    // Returns the result; ok() tells whether it is a result or an error message.
    std::string call(const std::string& name, const std::string& arg, double timeLimit)
    {
        std::string result;
        lastOk = mvm::call(vm, name.c_str(), arg, timeLimit, result);
        return result;
    }
    bool ok() const
    {
        return lastOk;
    }
    double memoryUsed() const
    {
        return double(mvm::memory_used(vm));
    }

private:
    mvm::VM* vm;
    bool lastOk = true;
};

EMSCRIPTEN_BINDINGS(meltiew_luau)
{
    emscripten::class_<VM>("VM")
        .constructor<int>()
        .function("run", &VM::run)
        .function("sandbox", &VM::sandbox)
        .function("call", &VM::call)
        .function("ok", &VM::ok)
        .function("memoryUsed", &VM::memoryUsed);
}
