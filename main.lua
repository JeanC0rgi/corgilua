local ffi = require("ffi")
local kernel32 = ffi.load("kernel32")
local user32 = ffi.load("user32")


ffi.cdef[[
typedef int BOOL;
typedef void* HWND;

typedef unsigned int UINT;
typedef unsigned long DWORD;
typedef unsigned short WORD;
typedef unsigned long ULONG_PTR;

typedef BOOL (__stdcall *EnumWindowsProc)(HWND, void*);

BOOL EnumWindows(EnumWindowsProc lpEnumFunc, void* lParam);
int GetWindowTextA(HWND hWnd, char* lpString, int nMaxCount);
int SetForegroundWindow(HWND hWnd);
int ShowWindow(HWND hWnd, int nCmdShow);



int GetWindowThreadProcessId(void* hWnd, void* lpdwProcessId);
int GetCurrentThreadId(void);
int AttachThreadInput(int idAttach, int idAttachTo, int fAttach);


void keybd_event(unsigned char bVk, unsigned char bScan,
                 unsigned long dwFlags, unsigned long dwExtraInfo);


HWND FindWindowExA(HWND hwndParent, HWND hwndChildAfter,
                   const char* lpszClass, const char* lpszWindow);

int SendMessageA(HWND hWnd, unsigned int Msg, int wParam, int lParam);


typedef struct {
    WORD wVk;
    WORD wScan;
    DWORD dwFlags;
    DWORD time;
    ULONG_PTR dwExtraInfo;
} KEYBDINPUT;

typedef struct {
    DWORD type;
    KEYBDINPUT ki;
} INPUT;

UINT SendInput(UINT nInputs, INPUT *pInputs, int cbSize);



int OpenClipboard(void* hWndNewOwner);
int EmptyClipboard();
void* SetClipboardData(unsigned int uFormat, void* hMem);
int CloseClipboard();
void* GlobalAlloc(unsigned int uFlags, size_t dwBytes);
void* GlobalLock(void* hMem);
int GlobalUnlock(void* hMem);

]]


-- define press FIRST
local function press(vk)
    user32.keybd_event(vk, 0, 0, 0)   -- key down
    user32.keybd_event(vk, 0, 2, 0)   -- key up
end

-- THEN use it
local VK_SHIFT = 0x10

local INPUT_KEYBOARD = 1
local KEYEVENTF_UNICODE = 0x0004
local KEYEVENTF_KEYUP   = 0x0002

local function type_char(c)
    local input = ffi.new("INPUT[2]")

    -- zero memory (VERY IMPORTANT)
    ffi.fill(input, ffi.sizeof(input), 0)

    -- key down
    input[0].type = 1
    input[0].ki.wScan = string.byte(c)
    input[0].ki.dwFlags = 0x0004  -- KEYEVENTF_UNICODE

    -- key up
    input[1].type = 1
    input[1].ki.wScan = string.byte(c)
    input[1].ki.dwFlags = 0x0004 + 0x0002

    user32.SendInput(2, input, ffi.sizeof(input[0]))
end

local function type_text(text)
    for i = 1, #text do
        type_char(text:sub(i, i))
    end
end




local CF_TEXT = 1
local GMEM_MOVEABLE = 0x0002

local function set_clipboard(text)
    user32.OpenClipboard(nil)
    user32.EmptyClipboard()

    local size = #text + 1
    local hMem = kernel32.GlobalAlloc(GMEM_MOVEABLE, size)
    local ptr = kernel32.GlobalLock(hMem)

    ffi.copy(ptr, text)
    kernel32.GlobalUnlock(hMem)

    user32.SetClipboardData(CF_TEXT, hMem)
    user32.CloseClipboard()
end



-- Launch KeePass
os.execute('start "" "C:\\Program Files\\KeePass Password Safe 2\\KeePass.exe"')

-- small delay so window appears
os.execute("ping 127.0.0.1 -n 2 > nul")

local hwnd_found = nil
local BM_CLICK = 0x00F5

local callback
callback = ffi.cast("EnumWindowsProc", function(hwnd, lParam)
    local buffer = ffi.new("char[256]")
    
    user32.GetWindowTextA(hwnd, buffer, 256)
    local title = ffi.string(buffer)

    --print("TITLE:", title)


    -- DEBUG (optional)
    -- print(title)

    if title:find("Open Database") and title:find(".kdbx") then
        hwnd_found = hwnd
        return 0 -- stop enumeration
	end

    return 1 -- continue
end)

user32.EnumWindows(callback, nil)
-- fake input
user32.keybd_event(0x12, 0, 0, 0)
user32.keybd_event(0x12, 0, 2, 0)

-- attach threads
local currentThread = kernel32.GetCurrentThreadId()
local windowThread = user32.GetWindowThreadProcessId(hwnd_found, nil)

user32.AttachThreadInput(currentThread, windowThread, 1)

-- focus
user32.ShowWindow(hwnd_found, 5)
user32.SetForegroundWindow(hwnd_found)

-- detach
user32.AttachThreadInput(currentThread, windowThread, 0)

-- escape
-- make sure window is active (optional but good)
user32.ShowWindow(hwnd_found, 5)
user32.SetForegroundWindow(hwnd_found)


if hwnd_found ~= nil then
	
	-- 1. Wait for the window to appear

    os.execute("ping 127.0.0.1 -n 2 > nul")


    user32.ShowWindow(hwnd_found, 5)
    user32.SetForegroundWindow(hwnd_found)

    -- small delay (important)
    os.execute("ping 127.0.0.1 -n 1 > nul")

    -- type password
	
	set_clipboard("xxxxxxxxx")

	-- paste (CTRL + V)
	user32.keybd_event(0x11, 0, 0, 0)   -- CTRL down
	user32.keybd_event(0x56, 0, 0, 0)   -- V down
	user32.keybd_event(0x56, 0, 2, 0)   -- V up
	user32.keybd_event(0x11, 0, 2, 0)   -- CTRL up

	
	
    os.execute("ping 127.0.0.1 -n 1 > nul")

    -- press ENTER
    press(0x0D)  -- VK_RETURN
	
	-- for security reason
	set_clipboard("")
end



