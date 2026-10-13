unit Dext.MM.Tests;

interface

uses
  System.SysUtils,
  System.Classes,
  Dext.Testing.Attributes,
  Dext.Assertions,
  Dext.MM;

type
  /// <summary>
  ///   Dext.MM with and without DEXT_USE_MIMALLOC. The same tests run in both
  ///   builds: the first one checks that the build has the manager it asked
  ///   for, the others exercise the active manager (the RTL one, or mimalloc
  ///   when the suite is compiled with -DDEXT_USE_MIMALLOC and the DLLs are
  ///   next to the executable).
  /// </summary>
  [TestFixture('Dext.MM - the memory manager, with and without mimalloc')]
  TDextMMTests = class
  public
    [Test('IsMiMallocEnabled and MiMallocVersion follow DEXT_USE_MIMALLOC')]
    procedure Mode_FollowsTheDefine;
    [Test('GetMem, ReallocMem (growing and shrinking), AllocMem zeroed, FreeMem')]
    procedure Blocks_RoundTrip;
    [Test('Strings and objects are allocated and freed by the active manager')]
    procedure StringsAndObjects;
    [Test('Blocks allocated on four threads and freed on another one')]
    procedure Threads_AllocateHere_FreeThere;
  end;

implementation

const
  Workers = 4;
  PerWorker = 5000;

var
  // The blocks allocated by each worker thread.
  GBlocks: array[0..Workers - 1] of TArray<Pointer>;

function MakeWorker(AIndex: Integer): TThread;
begin
  Result := TThread.CreateAnonymousThread(
    procedure
    var
      K: Integer;
    begin
      SetLength(GBlocks[AIndex], PerWorker);
      for K := 0 to PerWorker - 1 do
      begin
        GetMem(GBlocks[AIndex][K], 16 + (K mod 512));
        PByte(GBlocks[AIndex][K])^ := Byte(AIndex);
      end;
    end);
  Result.FreeOnTerminate := False;
end;

{ TDextMMTests }

procedure TDextMMTests.Mode_FollowsTheDefine;
begin
{$IFDEF DEXT_USE_MIMALLOC}
  Should(IsMiMallocEnabled).BeTrue;
  Should(IsMemoryManagerSet).BeTrue;
  Should(MiMallocVersion >= 100).BeTrue.Because('mimalloc 1.x or later');
{$ELSE}
  Should(IsMiMallocEnabled).BeFalse;
  Should(MiMallocVersion).Be(0);
{$ENDIF}
end;

procedure TDextMMTests.Blocks_RoundTrip;
var
  P: PByte;
  Z: PByte;
  I: Integer;
  AllZero: Boolean;
begin
  GetMem(P, 100);
  try
    for I := 0 to 99 do
      P[I] := Byte(I);
    // Growing keeps the content.
    ReallocMem(P, 1024 * 1024);
    for I := 0 to 99 do
      Should(Integer(P[I])).Be(I);
    // Shrinking keeps it too.
    ReallocMem(P, 50);
    for I := 0 to 49 do
      Should(Integer(P[I])).Be(I);
  finally
    FreeMem(P);
  end;

  Z := AllocMem(64 * 1024);
  try
    AllZero := True;
    for I := 0 to 64 * 1024 - 1 do
      if Z[I] <> 0 then
        AllZero := False;
    Should(AllZero).BeTrue;
  finally
    FreeMem(Z);
  end;
end;

procedure TDextMMTests.StringsAndObjects;
var
  List: TStringList;
  I: Integer;
begin
  List := TStringList.Create;
  try
    for I := 1 to 20000 do
      List.Add(StringOfChar('x', I mod 300) + IntToStr(I));
    Should(List.Count).Be(20000);
    Should(List[19999].EndsWith('20000')).BeTrue;
    List.Clear;
  finally
    List.Free;
  end;
end;

procedure TDextMMTests.Threads_AllocateHere_FreeThere;
var
  Threads: array[0..Workers - 1] of TThread;
  W, I: Integer;
  Freed: Integer;
begin
  for W := 0 to Workers - 1 do
    Threads[W] := MakeWorker(W);
  for W := 0 to Workers - 1 do
    Threads[W].Start;
  for W := 0 to Workers - 1 do
  begin
    Threads[W].WaitFor;
    Threads[W].Free;
  end;
  // Every block is freed on this thread, not on the one that allocated it.
  Freed := 0;
  for W := 0 to Workers - 1 do
  begin
    for I := 0 to PerWorker - 1 do
    begin
      Should(Integer(PByte(GBlocks[W][I])^)).Be(W);
      FreeMem(GBlocks[W][I]);
      Inc(Freed);
    end;
    GBlocks[W] := nil;
  end;
  Should(Freed).Be(Workers * PerWorker);
end;

end.
