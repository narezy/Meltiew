#include "mvm.h"

#include "lua.h"
#include "luacode.h"
#include "lualib.h"

#include <chrono>
#include <cstdlib>
#include <cstring>

namespace mvm
{

struct VM
{
    lua_State* L = nullptr;
    size_t used = 0;
    size_t limit = 0;
    double deadline = 0.0; // steady clock seconds, 0 = no limit
    unsigned ticks = 0;
};

static double now()
{
    using namespace std::chrono;
    return duration<double>(steady_clock::now().time_since_epoch()).count();
}

static void* alloc(void* ud, void* ptr, size_t osize, size_t nsize)
{
    VM* vm = static_cast<VM*>(ud);
    if (nsize == 0)
    {
        free(ptr);
        vm->used -= osize;
        return nullptr;
    }
    if (nsize > osize && vm->used + (nsize - osize) > vm->limit)
        return nullptr; // Luau turns this into a "not enough memory" error
    void* out = realloc(ptr, nsize);
    if (out)
        vm->used = vm->used - osize + nsize;
    return out;
}

static VM* vmOf(lua_State* L)
{
    void* ud = nullptr;
    lua_getallocf(L, &ud);
    return static_cast<VM*>(ud);
}

// Called at loop back edges and calls: stops scripts that run past the deadline.
static void interrupt(lua_State* L, int gc)
{
    if (gc >= 0)
        return;
    VM* vm = vmOf(L);
    if (vm->deadline <= 0.0 || (++vm->ticks & 255) != 0)
        return;
    if (now() > vm->deadline)
    {
        lua_rawcheckstack(L, 1);
        luaL_error(L, "script timeout: it ran too long without yielding (use task.wait() in loops)");
    }
}

// __compile(source, chunkname) -> function | (nil, error)
static int compileFn(lua_State* L)
{
    size_t len = 0;
    const char* source = luaL_checklstring(L, 1, &len);
    const char* chunkname = luaL_optstring(L, 2, "script");

    lua_CompileOptions options = {};
    options.optimizationLevel = 1;
    options.debugLevel = 1;

    size_t outsize = 0;
    char* bytecode = luau_compile(source, len, &options, &outsize);
    int status = luau_load(L, chunkname, bytecode, outsize, 0);
    free(bytecode);
    if (status != 0)
    {
        lua_pushnil(L);
        lua_insert(L, -2); // nil, error
        return 2;
    }
    return 1;
}

static int clockFn(lua_State* L)
{
    lua_pushnumber(L, now());
    return 1;
}

VM* create(size_t memory_limit)
{
    VM* vm = new VM();
    vm->limit = memory_limit;
    vm->L = lua_newstate(alloc, vm);
    if (!vm->L)
    {
        delete vm;
        return nullptr;
    }
    luaL_openlibs(vm->L);
    lua_callbacks(vm->L)->interrupt = interrupt;
    lua_pushcfunction(vm->L, compileFn, "__compile");
    lua_setglobal(vm->L, "__compile");
    lua_pushcfunction(vm->L, clockFn, "__clock");
    lua_setglobal(vm->L, "__clock");
    // Scripts get code only through the runtime (which sets their environment).
    lua_pushnil(vm->L);
    lua_setglobal(vm->L, "loadstring");
    return vm;
}

void destroy(VM* vm)
{
    if (!vm)
        return;
    if (vm->L)
        lua_close(vm->L);
    delete vm;
}

std::string run(VM* vm, const std::string& chunkname, const std::string& source)
{
    lua_State* L = vm->L;
    lua_CompileOptions options = {};
    options.optimizationLevel = 1;
    options.debugLevel = 1;
    size_t outsize = 0;
    char* bytecode = luau_compile(source.data(), source.size(), &options, &outsize);
    int status = luau_load(L, chunkname.c_str(), bytecode, outsize, 0);
    free(bytecode);
    if (status == 0)
        status = lua_pcall(L, 0, 0, 0);
    if (status != 0)
    {
        const char* msg = lua_tostring(L, -1);
        std::string err = msg ? msg : "error";
        lua_pop(L, 1);
        return err;
    }
    return std::string();
}

void sandbox(VM* vm)
{
    luaL_sandbox(vm->L);
}

bool call(VM* vm, const char* name, const std::string& arg, double time_limit, std::string& result)
{
    lua_State* L = vm->L;
    int top = lua_gettop(L);
    lua_getglobal(L, name);
    if (!lua_isfunction(L, -1))
    {
        lua_settop(L, top);
        result = std::string("no function ") + name;
        return false;
    }
    lua_pushlstring(L, arg.data(), arg.size());
    vm->deadline = time_limit > 0.0 ? now() + time_limit : 0.0;
    vm->ticks = 0;
    int status = lua_pcall(L, 1, 1, 0);
    vm->deadline = 0.0;
    size_t len = 0;
    const char* out = lua_tolstring(L, -1, &len);
    result = out ? std::string(out, len) : std::string();
    lua_settop(L, top);
    return status == 0;
}

size_t memory_used(VM* vm)
{
    return vm->used;
}

} // namespace mvm
