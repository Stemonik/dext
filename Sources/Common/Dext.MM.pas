{***************************************************************************}
{                                                                           }
{           Dext Framework                                                  }
{                                                                           }
{           Copyright (C) 2025 Cesar Romero & Dext Contributors             }
{                                                                           }
{           Licensed under the Apache License, Version 2.0 (the "License"); }
{           you may not use this file except in compliance with the License.}
{           You may obtain a copy of the License at                         }
{                                                                           }
{               http://www.apache.org/licenses/LICENSE-2.0                  }
{                                                                           }
{           Unless required by applicable law or agreed to in writing,      }
{           software distributed under the License is distributed on an     }
{           "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,    }
{           either express or implied. See the License for the specific     }
{           language governing permissions and limitations under the        }
{           License.                                                        }
{                                                                           }
{***************************************************************************}
{                                                                           }
{  Author:  Cesar Romero                                                    }
{  Created: 2025-12-14                                                      }
{                                                                           }
{  Description:                                                             }
{    Memory manager wrapper for Dext applications.                          }
{    This unit should be the FIRST unit in the uses clause of any Dext      }
{    application to enable enhanced memory management features.             }
{                                                                           }
{    To enable FastMM5, add the following to your project options or        }
{    include file:                                                          }
{      $DEFINE DEXT_USE_FASTMM5                                             }
{                                                                           }
{    Alternatively, set the conditional in Project Options:                 }
{      Project > Options > Delphi Compiler > Conditional defines            }
{      Add: DEXT_USE_FASTMM5                                                }
{                                                                           }
{    To use mimalloc (Microsoft, MIT license) instead, define               }
{    DEXT_USE_MIMALLOC (Windows only) and deploy mimalloc.dll and           }
{    mimalloc-redirect.dll (official x64 release) next to the executable.   }
{    The two defines are exclusive.                                         }
{                                                                           }
{***************************************************************************}
unit Dext.MM;

interface

{$I Dext.inc}

{.$DEFINE DEXT_USE_FASTMM5}
{.$DEFINE DEXT_USE_MIMALLOC}

{$IF DEFINED(DEXT_USE_FASTMM5) AND DEFINED(DEXT_USE_MIMALLOC)}
  {$MESSAGE ERROR 'Dext.MM: define DEXT_USE_FASTMM5 or DEXT_USE_MIMALLOC, not both'}
{$IFEND}
{$IF DEFINED(DEXT_USE_MIMALLOC) AND NOT DEFINED(MSWINDOWS)}
  {$MESSAGE ERROR 'Dext.MM: DEXT_USE_MIMALLOC is supported on Windows only'}
{$IFEND}

{$IFDEF DEXT_USE_FASTMM5}
uses
  FastMM5;
{$ENDIF}

/// <summary>
///   Enables memory leak reporting on application shutdown.
///   Only effective when FastMM5 is enabled via DEXT_USE_FASTMM5 define.
///   With DEXT_USE_MIMALLOC there is no leak report: the report belongs to
///   the RTL memory manager, which then holds no block. Use mimalloc for
///   release builds and the default manager to look for leaks.
/// </summary>
procedure EnableMemoryLeakReporting;

/// <summary>
///   Disables memory leak reporting on application shutdown.
/// </summary>
procedure DisableMemoryLeakReporting;

/// <summary>
///   Returns True if FastMM5 is active (DEXT_USE_FASTMM5 is defined).
/// </summary>
function IsFastMMEnabled: Boolean;

/// <summary>
///   Returns True if mimalloc is the memory manager of the process:
///   DEXT_USE_MIMALLOC is defined and Dext.MM installed it. It is not
///   installed when another unit allocated before Dext.MM (Dext.MM is then
///   not the first unit): a block allocated by the RTL manager and freed by
///   mimalloc would corrupt the heap, so the RTL manager stays.
/// </summary>
function IsMiMallocEnabled: Boolean;

/// <summary>
///   The version of the loaded mimalloc (for example 252 for 2.5.2), or 0
///   when mimalloc is not active.
/// </summary>
function MiMallocVersion: Integer;

implementation

{$IFDEF DEXT_USE_FASTMM5}
uses
  System.SysUtils;
{$ENDIF}

{$IFDEF DEXT_USE_MIMALLOC}
const
  MiMallocDll = 'mimalloc.dll';

// Static imports: without the DLLs the executable does not start, and
// Windows says which DLL is missing.
function mi_malloc(ASize: NativeUInt): Pointer; cdecl; external MiMallocDll;
function mi_zalloc(ASize: NativeUInt): Pointer; cdecl; external MiMallocDll;
function mi_realloc(P: Pointer; ASize: NativeUInt): Pointer; cdecl;
  external MiMallocDll;
procedure mi_free(P: Pointer); cdecl; external MiMallocDll;
function mi_version: Integer; cdecl; external MiMallocDll;

var
  GMiMallocActive: Boolean;

function MiGetMem(Size: NativeInt): Pointer;
begin
  Result := mi_malloc(Size);
end;

function MiFreeMem(P: Pointer): Integer;
begin
  mi_free(P);
  Result := 0;
end;

function MiReallocMem(P: Pointer; Size: NativeInt): Pointer;
begin
  Result := mi_realloc(P, Size);
end;

function MiAllocMem(Size: NativeInt): Pointer;
begin
  Result := mi_zalloc(Size);
end;

function MiNoExpectedLeak(P: Pointer): Boolean;
begin
  // Expected leaks are a feature of the RTL memory manager.
  Result := False;
end;

procedure InstallMiMalloc;
var
  Manager: TMemoryManagerEx;
  State: TMemoryManagerState;
  I: Integer;
  LiveBlocks: NativeUInt;
begin
  // Install only while the RTL manager holds no block: as the first unit,
  // Dext.MM runs before anything else allocates.
  GetMemoryManagerState(State);
  LiveBlocks := State.AllocatedMediumBlockCount + State.AllocatedLargeBlockCount;
  for I := Low(State.SmallBlockTypeStates) to High(State.SmallBlockTypeStates) do
    Inc(LiveBlocks, State.SmallBlockTypeStates[I].AllocatedBlockCount);
  if LiveBlocks <> 0 then
    Exit;
  Manager.GetMem := MiGetMem;
  Manager.FreeMem := MiFreeMem;
  Manager.ReallocMem := MiReallocMem;
  Manager.AllocMem := MiAllocMem;
  Manager.RegisterExpectedMemoryLeak := MiNoExpectedLeak;
  Manager.UnregisterExpectedMemoryLeak := MiNoExpectedLeak;
  SetMemoryManager(Manager);
  GMiMallocActive := True;
end;
{$ENDIF}

procedure EnableMemoryLeakReporting;
begin
{$IFDEF DEXT_USE_FASTMM5}
  // File-only output: no message box so console apps don't hang
  FastMM5.FastMM_EnterDebugMode;
  FastMM5.FastMM_OutputDebugStringEvents :=
    [mmetUnexpectedMemoryLeakDetail,
     mmetUnexpectedMemoryLeakSummary];
  // Write .leak report next to the executable
  FastMM5.FastMM_LogToFileEvents :=
    [mmetUnexpectedMemoryLeakDetail,
     mmetUnexpectedMemoryLeakSummary];
  // Never show message boxes (would block console / automated runs)
  FastMM5.FastMM_MessageBoxEvents := [];
  {$IFDEF DEXT_ENABLE_DB_SQLITE}
  // Register SQLite :memory: memory leak
  FastMM_RegisterExpectedMemoryLeak(200, 1);
  {$ENDIF}
  ReportMemoryLeaksOnShutdown := True;
{$ELSE}
  System.ReportMemoryLeaksOnShutdown := True;
{$ENDIF}
end;

procedure DisableMemoryLeakReporting;
begin
{$IFDEF DEXT_USE_FASTMM5}
  ReportMemoryLeaksOnShutdown := False;
{$ELSE}
  System.ReportMemoryLeaksOnShutdown := False;
{$ENDIF}
end;

function IsFastMMEnabled: Boolean;
begin
{$IFDEF DEXT_USE_FASTMM5}
  Result := True;
{$ELSE}
  Result := False;
{$ENDIF}
end;

function IsMiMallocEnabled: Boolean;
begin
{$IFDEF DEXT_USE_MIMALLOC}
  Result := GMiMallocActive;
{$ELSE}
  Result := False;
{$ENDIF}
end;

function MiMallocVersion: Integer;
begin
{$IFDEF DEXT_USE_MIMALLOC}
  if GMiMallocActive then
    Result := mi_version
  else
    Result := 0;
{$ELSE}
  Result := 0;
{$ENDIF}
end;

initialization
  {$IFDEF DEXT_USE_MIMALLOC}
  // Before anything else: from here on every allocation goes to mimalloc.
  InstallMiMalloc;
  {$ENDIF}
  {$IFDEF DEBUG}
  EnableMemoryLeakReporting;
  {$ENDIF}

end.
