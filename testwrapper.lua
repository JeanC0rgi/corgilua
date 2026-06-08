-- PSMGenericClient.lua
-- LuaJIT FFI translation of the AutoIt PSM Generic Client DLL Wrapper

local ffi = require("ffi")

--============================================================
-- Consts
--============================================================
local DISPATCHER_UTILS_DLL       = "PSMDispatcherUtils.dll"
local DISPATCHER_UTILS_DRIVER_DLL = "PSMGenericClientDriver.dll"
local INVALID_HANDLE_VALUE_INTERNAL = -1
local LOG_LEVEL_ERROR            = 0
local LOG_LEVEL_TRACE            = 1
local MIN_ARGUMENTS_NUMBER        = 1
local TEST_MODE                   = "/test"

--============================================================
-- Enums
--============================================================
local PSM_ERROR_SUCCESS          = 0
local PSM_ERROR_GENERAL_ERROR    = 1
local PSM_ERROR_ALREADY_LOADED    = 2
local PSM_ERROR_LOAD_FAILED       = 3
local PSM_ERROR_FAILED_TO_CALL    = 4
local PSM_ERROR_CALL_FAILED       = 5

--============================================================
-- Globals
--============================================================
local g_DllHandle = nil
local g_PSMLastError = ""

--============================================================
-- FFI declarations
--============================================================
ffi.cdef[[
typedef unsigned long DWORD;
typedef int BOOL;

DWORD __cdecl SendPID(DWORD dwPID);
DWORD __cdecl LogWrite(char* szString, DWORD dwStringLength, DWORD dwLogLevel);
DWORD __cdecl MapTSDrives(void);
DWORD __cdecl GetSessionPropertyBufferLength(char* szPropertyName, DWORD dwPropertyNameLength, DWORD* dwLength);
DWORD __cdecl GetSessionProperty(char* szPropertyName, DWORD dwPropertyNameLength, char* szBuffer, DWORD dwBufferSize);
DWORD __cdecl FinalizeDispatcher(void);
]]

--============================================================
-- Internal helpers
--============================================================
local function setPSMError(szError, nRC)
    g_PSMLastError = szError or ""
    return nRC or PSM_ERROR_GENERAL_ERROR
end

local function isLoaded()
    return g_DllHandle ~= nil
end

local function loadDll(dllPath)
    local ok, lib = pcall(ffi.load, dllPath)
    if not ok then
        return nil, lib
    end
    return lib
end

local function callBoolLike(result)
    -- AutoIt compares result to True; in C a non-zero DWORD usually means success
    return result ~= 0
end

--============================================================
-- Public API
--============================================================
local PSMGenericClient = {}

function PSMGenericClient.Init(cmdLine)
    local PSMTestMode = false
    local PSMComponentsFolder
    local DispatcherUtilsDLL

    cmdLine = cmdLine or arg or {}

    -- AutoIt uses $CmdLine[0] = number of args, $CmdLine[1].. etc.
    -- In Lua, arg[1] is usually the first argument; arg[0] is script name.
    -- We'll support both an AutoIt-like table and standard Lua arg.
    local argc = cmdLine.n or (#cmdLine)
    local function getArg(i)
        -- supports both:
        -- AutoIt-like: cmdLine[1] is first user arg
        -- Lua standard: arg[1] is first user arg, arg[0] is script name
        return cmdLine[i]
    end

    if argc < MIN_ARGUMENTS_NUMBER then
        return setPSMError(
            string.format("Invalid number of command line arguments (received %d, expecting %d)",
                argc, MIN_ARGUMENTS_NUMBER),
            PSM_ERROR_GENERAL_ERROR
        )
    end

    -- Handle components folder
    PSMComponentsFolder = getArg(1)
    if not PSMComponentsFolder or PSMComponentsFolder == "" then
        return setPSMError("Invalid components folder argument received (nil/empty)", PSM_ERROR_GENERAL_ERROR)
    end

    local f = io.open(PSMComponentsFolder, "rb")
    if not f then
        return setPSMError(
            string.format("Invalid components folder argument received (%s)", tostring(PSMComponentsFolder)),
            PSM_ERROR_GENERAL_ERROR
        )
    end
    f:close()

    -- Handle test mode
    if argc == MIN_ARGUMENTS_NUMBER + 1 then
        if getArg(2) == TEST_MODE then
            PSMTestMode = true
        end
    end

    if isLoaded() then
        return setPSMError("DLL already loaded", PSM_ERROR_ALREADY_LOADED)
    end

    if not PSMTestMode then
        DispatcherUtilsDLL = DISPATCHER_UTILS_DLL
    else
        DispatcherUtilsDLL = DISPATCHER_UTILS_DRIVER_DLL
    end

    local dllPath = PSMComponentsFolder .. DispatcherUtilsDLL
    local lib, err = loadDll(dllPath)
    if not lib then
        return setPSMError("Failed to load DLL " .. dllPath .. " (" .. tostring(err) .. ")", PSM_ERROR_LOAD_FAILED)
    end

    g_DllHandle = lib
    return PSM_ERROR_SUCCESS
end

function PSMGenericClient.Term()
    -- AutoIt: ToolTip("")
    -- No direct equivalent needed in Lua.

    PSMGenericClient.FinalizeDispatcher()

    if isLoaded() then
        -- ffi.load handles unloading automatically when GC collects the library;
        -- keeping explicit nil here matches the AutoIt lifecycle.
        g_DllHandle = nil
    end
end

function PSMGenericClient.IsInitialized()
    return isLoaded()
end

function PSMGenericClient.PSMGetLastErrorString()
    return "PSMGenericClientWrapper error: " .. g_PSMLastError
end

function PSMGenericClient.SendPID(pid)
    if not isLoaded() then
        return setPSMError("DLL not initialized", PSM_ERROR_GENERAL_ERROR)
    end

    local ok, result = pcall(function()
        return g_DllHandle.SendPID(ffi.new("unsigned long", pid))
    end)

    if not ok then
        return setPSMError("Failed to call DLL function SendPID (" .. tostring(result) .. ")", PSM_ERROR_FAILED_TO_CALL)
    end

    if not callBoolLike(result) then
        return setPSMError("DLL function SendPID failed", PSM_ERROR_CALL_FAILED)
    end

    return PSM_ERROR_SUCCESS
end

function PSMGenericClient.LogWrite(sMessage, logLevel)
    if not isLoaded() then
        return setPSMError("DLL not initialized", PSM_ERROR_GENERAL_ERROR)
    end

    sMessage = tostring(sMessage or "")
    logLevel = tonumber(logLevel or LOG_LEVEL_TRACE) or LOG_LEVEL_TRACE

    local msgLen = #sMessage
    local msgBuf = ffi.new("char[?]", msgLen + 1)
    ffi.copy(msgBuf, sMessage, msgLen)

    local ok, result = pcall(function()
        return g_DllHandle.LogWrite(msgBuf, ffi.new("unsigned long", msgLen), ffi.new("unsigned long", logLevel))
    end)

    if not ok then
        return setPSMError("Failed to call DLL function LogWrite (" .. tostring(result) .. ")", PSM_ERROR_FAILED_TO_CALL)
    end

    if not callBoolLike(result) then
        return setPSMError("DLL function LogWrite failed", PSM_ERROR_CALL_FAILED)
    end

    return PSM_ERROR_SUCCESS
end

function PSMGenericClient.MapTSDrives()
    if not isLoaded() then
        return setPSMError("DLL not initialized", PSM_ERROR_GENERAL_ERROR)
    end

    local ok, result = pcall(function()
        return g_DllHandle.MapTSDrives()
    end)

    if not ok then
        return setPSMError("Failed to call DLL function MapTSDrives (" .. tostring(result) .. ")", PSM_ERROR_FAILED_TO_CALL)
    end

    if not callBoolLike(result) then
        return setPSMError("DLL function MapTSDrives failed", PSM_ERROR_CALL_FAILED)
    end

    return PSM_ERROR_SUCCESS
end

function PSMGenericClient.GetSessionPropertyBufferLength(sessionPropertyName)
    if not isLoaded() then
        return nil, setPSMError("DLL not initialized", PSM_ERROR_GENERAL_ERROR)
    end

    sessionPropertyName = tostring(sessionPropertyName or "")
    local nameLen = #sessionPropertyName

    local pSessionPropertyName = ffi.new("char[?]", nameLen + 1)
    ffi.copy(pSessionPropertyName, sessionPropertyName, nameLen)

    local pLength = ffi.new("unsigned long[1]")

    local ok, result = pcall(function()
        return g_DllHandle.GetSessionPropertyBufferLength(
            pSessionPropertyName,
            ffi.new("unsigned long", nameLen),
            pLength
        )
    end)

    if not ok then
        return nil, setPSMError(
            "Failed to call DLL function GetSessionPropertyBufferLength (" .. tostring(result) .. ")",
            PSM_ERROR_FAILED_TO_CALL
        )
    end

    if not callBoolLike(result) then
        return nil, setPSMError(
            "DLL function GetSessionPropertyBufferLength failed",
            PSM_ERROR_CALL_FAILED
        )
    end

    return tonumber(pLength[0])
end

function PSMGenericClient.GetSessionProperty(sessionPropertyName)
    if not isLoaded() then
        return nil, setPSMError("DLL not initialized", PSM_ERROR_GENERAL_ERROR)
    end

    local dwLength, err = PSMGenericClient.GetSessionPropertyBufferLength(sessionPropertyName)
    if not dwLength then
        return nil, setPSMError("Failed to get dispatcher parameters (error: " .. g_PSMLastError .. ")", err)
    end

    sessionPropertyName = tostring(sessionPropertyName or "")
    local nameLen = #sessionPropertyName

    local pSessionPropertyName = ffi.new("char[?]", nameLen + 1)
    ffi.copy(pSessionPropertyName, sessionPropertyName, nameLen)

    local pBuffer = ffi.new("char[?]", dwLength)

    local ok, result = pcall(function()
        return g_DllHandle.GetSessionProperty(
            pSessionPropertyName,
            ffi.new("unsigned long", nameLen),
            pBuffer,
            ffi.new("unsigned long", dwLength)
        )
    end)

    if not ok then
        return nil, setPSMError(
            "Failed to call DLL function GetSessionProperty (" .. tostring(result) .. ")",
            PSM_ERROR_FAILED_TO_CALL
        )
    end

    if not callBoolLike(result) then
        return nil, setPSMError(
            "DLL function GetSessionProperty failed",
            PSM_ERROR_CALL_FAILED
        )
    end

    return ffi.string(pBuffer)
end

function PSMGenericClient.FinalizeDispatcher()
    if not isLoaded() then
        return setPSMError("DLL not initialized", PSM_ERROR_GENERAL_ERROR)
    end

    local ok, result = pcall(function()
        return g_DllHandle.FinalizeDispatcher()
    end)

    if not ok then
        return setPSMError("Failed to call DLL function FinalizeDispatcher (" .. tostring(result) .. ")", PSM_ERROR_FAILED_TO_CALL)
    end

    if not callBoolLike(result) then
        return setPSMError("DLL function FinalizeDispatcher failed", PSM_ERROR_CALL_FAILED)
    end

    return PSM_ERROR_SUCCESS
end

--============================================================
-- Export constants too (optional)
--============================================================
PSMGenericClient.CONST = {
    DISPATCHER_UTILS_DLL = DISPATCHER_UTILS_DLL,
    DISPATCHER_UTILS_DRIVER_DLL = DISPATCHER_UTILS_DRIVER_DLL,
    INVALID_HANDLE_VALUE_INTERNAL = INVALID_HANDLE_VALUE_INTERNAL,
    LOG_LEVEL_ERROR = LOG_LEVEL_ERROR,
    LOG_LEVEL_TRACE = LOG_LEVEL_TRACE,
    MIN_ARGUMENTS_NUMBER = MIN_ARGUMENTS_NUMBER,
    TEST_MODE = TEST_MODE,

    PSM_ERROR_SUCCESS = PSM_ERROR_SUCCESS,
    PSM_ERROR_GENERAL_ERROR = PSM_ERROR_GENERAL_ERROR,
    PSM_ERROR_ALREADY_LOADED = PSM_ERROR_ALREADY_LOADED,
    PSM_ERROR_LOAD_FAILED = PSM_ERROR_LOAD_FAILED,
    PSM_ERROR_FAILED_TO_CALL = PSM_ERROR_FAILED_TO_CALL,
    PSM_ERROR_CALL_FAILED = PSM_ERROR_CALL_FAILED,
}

return PSMGenericClient