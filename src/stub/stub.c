#include <stdint.h>

typedef unsigned char      u8;
typedef unsigned short     u16;
typedef unsigned int       u32;
typedef unsigned long long u64;
typedef int                i32;
typedef long long          i64;

#ifdef _WIN64
typedef unsigned long long uptr;
#else
typedef unsigned int       uptr;
#endif

#define HDR_MAGIC 0x3153434Du   /* "MCS1" */

typedef struct { /* 64 байта = первые 64 байта stub.bin */
    u32 magic;
    u32 flags;
    u32 n_imports;
    u32 n_va;
    u32 payload_rva;
    u32 payload_size;
    u32 imp_rva;
    u32 va_rva;
    u32 pool_rva;
    u32 iat_rva;
    u32 entry_rva;
    u32 reserved[5];
} BLOB_HDR;

typedef struct __attribute__((packed)) { /* "User32:MessageBoxA:21:4" */
    u32 dll_off;
    u32 fn_off;
    u32 patch_off;
    u32 disp;
    u8  is_ord;
} IMP_REC;                                 /* 17 байт */

typedef struct __attribute__((packed)) {   /* "VA:8:offset" */
    u32 off;
    u8  size;
} VA_REC;                                  /* 5 байт */

#ifdef _WIN64
typedef void* (*LLA_t)(const char*);       /* Win64: одно соглашение */
typedef void* (*GPA_t)(void*, const char*);
#else
typedef void* (__attribute__((stdcall)) *LLA_t)(const char*);
typedef void* (__attribute__((stdcall)) *GPA_t)(void*, const char*);
#endif

/* ---------------------------------------------------------------------------
 * ENTRY — top-level asm, лежит в .text на ФИКСИРОВАННОМ смещении 0x40
 * (первые 64 байта .text — место под BLOB_HDR, патчится генератором).
 * Самоопределение адреса: call/pop, base = pop-адрес - 5 - 64.
 * ------------------------------------------------------------------------- */
__asm__(
    ".text\n"
    ".globl sc_start\n"
    "sc_start:\n"
    ".space 64\n"                    /* BLOB_HDR, патчится генератором */
#ifdef _WIN64
    "sc_entry:\n"
    "  call 1f\n"                    /* 5 байт; пушит адрес следующей инсн. */
    "1: pop %rcx\n"                  /* rcx = sc_entry+6 */
    "  sub $69, %rcx\n"              /* 69 = 64(hdr) + 5(call) -> rcx = блоб  */
    "  jmp sc_main\n"                /* аргумент уже в rcx (Win64 ABI)        */
#else
    "sc_entry:\n"
    "  call 1f\n"
    "1: pop %eax\n"
    "  sub $69, %eax\n"
    "  push %eax\n"
    "  call _sc_main\n"              /* cdecl: база блоба как аргумент */
    "  add $4, %esp\n"
    "  ret\n"                        /* eax = результат sc_main */
#endif
);

/* ---------------------------------------------------------------------------
 * Утилиты без CRT (и без .rdata — всё, что нужно, на стеке)
 * ------------------------------------------------------------------------- */
static void st64(u8* p, u64 a, u64 b) {   /* 16 байт на стек, LE */
    for (int i = 0; i < 8; i++) { p[i]     = (u8)a; a >>= 8; }
    for (int i = 0; i < 8; i++) { p[8 + i] = (u8)b; b >>= 8; }
}

/* ---------------------------------------------------------------------------
 * PEB -> Ldr -> InMemoryOrderModuleList -> ищем "kernel32" (регистронезависимо,
 * по имени, НЕ по позиции в списке). gs:[0x60] / fs:[0x30].
 * ------------------------------------------------------------------------- */
static void* find_kernel32(void) {
    u16 want[8];                                   /* u16 "kernel32" */
    st64((u8*)want, 0x006E00720065006Bull,         /* 'k','e','r','n' */
                    0x00320033006C0065ull);        /* 'e','l','3','2' */

    uintptr_t peb;
#ifdef _WIN64
    __asm__ volatile ("mov %%gs:0x60, %0" : "=r"(peb));
    uintptr_t head = *(uintptr_t*)(peb + 0x18) + 0x20;  /* Ldr->InMemoryOrderModuleList */
    const unsigned int off_base = 0x20;                 /* DllBase    от узла списка */
    const unsigned int off_name = 0x48;                 /* BaseDllName от узла списка */
#else
    __asm__ volatile ("mov %%fs:0x30, %0" : "=r"(peb));
    uintptr_t head = *(uintptr_t*)(peb + 0x0C) + 0x1C;
    const unsigned int off_base = 0x10;
    const unsigned int off_name = 0x28;
#endif

    for (uintptr_t e = *(uintptr_t*)head; e && e != head; e = *(uintptr_t*)e) {
        u16 len = *(u16*)(e + off_name);
        u16* buf = *(u16**)(e + off_name + sizeof(void*));
        if (len < 16) continue;
        int ok = 1;
        for (int i = 0; i < 8; i++) {          /* 8 wchar, |0x20 = tolower */
            if ((u16)(buf[i] | 0x20) != want[i]) { ok = 0; break; }
        }
        if (ok) return (void*)*(uintptr_t*)(e + off_base);
    }
    return (void*)0;
}

/* ---------------------------------------------------------------------------
 * Ручной разбор export directory модуля (нужно только для kernel32, чтобы
 * достать LoadLibraryA/GetProcAddress; их экспорты не форвардятся).
 * ------------------------------------------------------------------------- */
static void* exp_find(void* mod, const u8* name) {
    u8* b = (u8*)mod;
    u8* nt = b + *(u32*)(b + 0x3C);              /* e_lfanew */
#ifdef _WIN64
    u8* opt = nt + 0x18;                         /* OptionalHeader */
    u32 exp_rva = *(u32*)(opt + 0x70);           /* DataDirectory[0] */
#else
    u8* opt = nt + 0x18;
    u32 exp_rva = *(u32*)(opt + 0x60);
#endif
    if (!exp_rva) return (void*)0;
    u8*  ex  = b + exp_rva;
    u32  n_names = *(u32*)(ex + 0x18);
    u32* names   = (u32*)(b + *(u32*)(ex + 0x20));
    u16* ords    = (u16*)(b + *(u32*)(ex + 0x24));
    u32* funcs   = (u32*)(b + *(u32*)(ex + 0x1C));

    for (u32 i = 0; i < n_names; i++) {
        const u8* en = b + names[i];
        u32 j = 0;
        while (en[j] && en[j] == name[j]) j++;
        if (en[j] == name[j])                    /* оба дошли до NUL */
            return (void*)(b + funcs[ords[i]]);
    }
    return (void*)0;
}

/* ---------------------------------------------------------------------------
 * ГЛАВНАЯ ФУНКЦИЯ. base = начало блоба (= sc_start).
 * ------------------------------------------------------------------------- */
__attribute__((noinline, used))
u32 sc_main(u8* base) {
    BLOB_HDR* h = (BLOB_HDR*)base;
    if (h->magic != HDR_MAGIC) return 0xFFFFFFFFu;

    u32 fails = 0;
    if (!(h->flags & 1)) {
        u8*      payload = base + h->payload_rva;
        u8*      iat     = base + h->iat_rva;
        IMP_REC* imp     = (IMP_REC*)(base + h->imp_rva);
        VA_REC*  va      = (VA_REC*)(base + h->va_rva);
        char*    pool    = (char*)(base + h->pool_rva);

        void* k32 = find_kernel32();
        if (!k32) return 0xFFFFFFFEu;

        /* "LoadLibraryA" / "GetProcAddress" — на стеке, чтобы не плодить .rdata */
        u8 nmLL[16], nmGPA[16];
        st64(nmLL,  0x7262694C64616F4Cull, 0x0000000041797261ull); /* "LoadLibr"|"aryA\0\0\0\0"  */
        st64(nmGPA, 0x41636F7250746547ull, 0x0000737365726464ull); /* "GetProcA"|"ddress\0\0"    */

        LLA_t fLL  = (LLA_t)exp_find(k32, nmLL);
        GPA_t fGPA = (GPA_t)exp_find(k32, nmGPA);
        if (!fLL || !fGPA) return 0xFFFFFFFDu;

        /* ---- импорты ---- */
        void* hmod = (void*)0;
        u32   last = 0xFFFFFFFFu;                /* кэш последней DLL */
        for (u32 i = 0; i < h->n_imports; i++) {
            IMP_REC* r = &imp[i];
            if (r->dll_off != last) { hmod = fLL(pool + r->dll_off); last = r->dll_off; }
            if (!hmod) { fails++; continue; }

            void* fn = fGPA(hmod, r->is_ord
                              ? (const char*)(uptr)r->fn_off
                              : pool + r->fn_off);
            if (!fn) { fails++; continue; }

            u8* site = payload + r->patch_off;
            u8  op   = site[-1];
            if (op == 0xE8 || op == 0xE9) {
#ifdef _WIN64
                /* танк: jmp qword [rip] ; адрес сразу за jmp'ом. Шаг 16. */
                iat[0] = 0xFF; iat[1] = 0x25;
                *(u32*)(iat + 2) = 0;
                *(u64*)(iat + 6) = (u64)(uptr)fn;
                *(i32*)site = (i32)((i64)(uptr)iat - (i64)(uptr)(site + r->disp));
                iat += 16;
#else
                /* x86: rel32 всегда дотянется, танк не нужен */
                *(i32*)site = (i32)((i64)(uptr)fn - (i64)(uptr)(site + r->disp));
#endif
            } else {
#ifdef _WIN64
                *(u64*)iat = (u64)(uptr)fn;      /* слот IAT */
                *(i32*)site = (i32)((i64)(uptr)iat - (i64)(uptr)(site + r->disp));
                iat += 8;
#else
                *(u32*)iat = (u32)(uptr)fn;      /* слот = fn (как NumPut pFunc,pEntry) */
                iat += 4;
#endif
            }
        }

        /* ---- VA-фиксы (val += base), НЕ идемпотентны — потому и guard ---- */
        for (u32 i = 0; i < h->n_va; i++) {
            u8* p = payload + va[i].off;
            if (va[i].size == 8) *(u64*)p += (u64)(uptr)payload;
            else                 *(u32*)p += (u32)(uptr)payload;
        }

        if (!fails) h->flags |= 1; /* пишем в свой же заголовок (RWX) */
    }

    if (h->entry_rva && !fails)
        return ((u32(*)(void))(base + h->entry_rva))();
    return fails;
}