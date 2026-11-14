// --ironbrigade_dump_stacks_at=<seconds>: at that many seconds after start, and every 10 s after
// it, writes the host call stack of every thread to stacks.txt beside the executable (module +
// offset per frame). The recompiled guest functions are host functions, so the frames of
// ironbrigade.exe resolve to sub_8XXXXXXX names with the link map
// (tools/map_symbolize.py build/game/ironbrigade.map ...): shows what each guest thread is
// waiting in when the game hangs.
//
// Each thread is suspended while its stack is unwound with RtlLookupFunctionEntry /
// RtlVirtualUnwind into a fixed buffer (no allocation, no locks while another thread is
// suspended); the file is written after all threads are resumed.

#include <rex/cvar.h>

REXCVAR_DEFINE_INT32(ironbrigade_dump_stacks_at, 0, "IronBrigade",
                     "Seconds after start to write every thread's host stack to stacks.txt "
                     "(then every 10 s); 0: off");

#if defined(_WIN32)
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <tlhelp32.h>

#include <cstdio>
#include <cstring>
#include <thread>
#include <vector>

namespace {

constexpr int kMaxFrames = 48;
constexpr int kMaxThreads = 256;

struct ThreadStack {
  DWORD tid;
  int count;
  DWORD64 frames[kMaxFrames];
};

int Unwind(HANDLE thread, DWORD64* frames) {
  CONTEXT ctx{};
  ctx.ContextFlags = CONTEXT_FULL;
  if (!GetThreadContext(thread, &ctx)) return 0;
  int n = 0;
  while (n < kMaxFrames && ctx.Rip) {
    frames[n++] = ctx.Rip;
    DWORD64 image_base = 0;
    PRUNTIME_FUNCTION fn = RtlLookupFunctionEntry(ctx.Rip, &image_base, nullptr);
    if (!fn) {
      // A leaf function: the return address is at the stack pointer.
      if (IsBadReadPtr(reinterpret_cast<void*>(ctx.Rsp), 8)) break;
      ctx.Rip = *reinterpret_cast<DWORD64*>(ctx.Rsp);
      ctx.Rsp += 8;
      continue;
    }
    void* handler_data = nullptr;
    DWORD64 establisher = 0;
    RtlVirtualUnwind(UNW_FLAG_NHANDLER, image_base, ctx.Rip, fn, &ctx, &handler_data, &establisher,
                     nullptr);
  }
  return n;
}

void DumpAll(int round) {
  static ThreadStack stacks[kMaxThreads];
  int count = 0;
  const DWORD self = GetCurrentThreadId(), pid = GetCurrentProcessId();
  HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
  if (snap == INVALID_HANDLE_VALUE) return;
  std::vector<DWORD> tids;
  tids.reserve(kMaxThreads);
  THREADENTRY32 te{};
  te.dwSize = sizeof(te);
  for (BOOL ok = Thread32First(snap, &te); ok; ok = Thread32Next(snap, &te))
    if (te.th32OwnerProcessID == pid && te.th32ThreadID != self) tids.push_back(te.th32ThreadID);
  CloseHandle(snap);
  for (DWORD tid : tids) {
    if (count >= kMaxThreads) break;
    HANDLE h = OpenThread(THREAD_SUSPEND_RESUME | THREAD_GET_CONTEXT | THREAD_QUERY_INFORMATION,
                          FALSE, tid);
    if (!h) continue;
    if (SuspendThread(h) != DWORD(-1)) {
      stacks[count].tid = tid;
      stacks[count].count = Unwind(h, stacks[count].frames);
      ++count;
      ResumeThread(h);
    }
    CloseHandle(h);
  }
  wchar_t path[MAX_PATH];
  DWORD n = GetModuleFileNameW(nullptr, path, MAX_PATH);
  while (n && path[n - 1] != L'\\') --n;
  wcscpy_s(path + n, MAX_PATH - n, L"stacks.txt");
  FILE* f = _wfopen(path, L"a");
  if (!f) return;
  fprintf(f, "== round %d\n", round);
  for (int t = 0; t < count; ++t) {
    fprintf(f, "thread %lu\n", stacks[t].tid);
    for (int i = 0; i < stacks[t].count; ++i) {
      HMODULE mod = nullptr;
      char name[MAX_PATH] = "?";
      if (GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                                 GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                             reinterpret_cast<LPCSTR>(stacks[t].frames[i]), &mod))
        GetModuleFileNameA(mod, name, MAX_PATH);
      const char* base = strrchr(name, '\\');
      fprintf(f, "  %s+0x%llx\n", base ? base + 1 : name,
              static_cast<unsigned long long>(stacks[t].frames[i] -
                                              reinterpret_cast<DWORD64>(mod)));
    }
  }
  fclose(f);
}

}  // namespace

void InstallStackDump() {
  const int at = REXCVAR_GET(ironbrigade_dump_stacks_at);
  if (at <= 0) return;
  std::thread([at] {
    Sleep(DWORD(at) * 1000);
    for (int round = 0; round < 6; ++round) {
      DumpAll(round);
      Sleep(10000);
    }
  }).detach();
}

#else
void InstallStackDump() {}
#endif
