unit Dext.Server.HttpSys.Receives.Tests;

interface

uses
  Dext.Testing.Attributes,
  Dext.Server.Engine.Types;

type
  /// <summary>
  ///   OutstandingReceives sets the total number of http.sys receives kept
  ///   posted, independently of the worker count. A worker posts a
  ///   replacement receive as soon as one completes, so fewer receives than
  ///   workers must still let every worker serve a request at the same time
  ///   (the extra workers are there for handlers that block on a database or
  ///   a remote call). Each test starts a real HTTP.sys listener on 127.0.0.1
  ///   whose handler blocks until the test releases it, and counts how many
  ///   requests are inside the handler at once.
  /// </summary>
  [TestFixture('HTTP.sys - outstanding receives independent of the workers')]
  THttpSysReceivesTests = class
  private
    procedure ServeBlocked(const AOptions: TServerEngineOptions; ARequests,
      AExpectedAtOnce: Integer); overload;
    procedure ServeBlocked(AWorkers, AReceives, ARequests,
      AExpectedAtOnce: Integer); overload;
  public
    [Test('OutstandingReceives defaults to 0 (automatic), OutstandingReceiveDepth to 2, and both can be set')]
    procedure TestOptionDefaultAndSetter;
    [Test('Four workers with ONE receive serve four blocked requests at once')]
    procedure TestFourWorkersOneReceive;
    [Test('Two workers with eight receives serve every request, two at a time')]
    procedure TestTwoWorkersEightReceives;
    // The defaults
    [Test('Default: four workers and one receive per logical processor')]
    procedure TestDefaultCounts;
    [Test('IoThreadCount set: those workers, and workers x depth receives as before')]
    procedure TestIoThreadsSet_WorkersTimesDepth;
    [Test('IoThreadCount and OutstandingReceiveDepth set: workers x depth, from 1 to 8')]
    procedure TestDepthSet_WorkersTimesDepth;
    [Test('Automatic workers: OutstandingReceiveDepth is not used, one receive per logical processor')]
    procedure TestAutomaticWorkers_DepthNotUsed;
    [Test('OutstandingReceives set: exactly that many receives')]
    procedure TestReceivesSet_Exactly;
    [Test('With the default options, four blocked requests per logical processor are served at once')]
    procedure TestDefaultServesFourPerProcessorAtOnce;
  end;

implementation

uses
  System.Classes,
  System.SyncObjs,
  System.SysUtils,
  System.Net.HttpClient,
  Dext.Assertions,
  Dext.Web,
  Dext.Web.Interfaces,
  Dext.Threading.ProcessorGroups,
  Dext.Server.HttpSys;

const
  TestPort = 9221;
  WaitMs = 10000;

{ THttpSysReceivesTests }

procedure THttpSysReceivesTests.TestOptionDefaultAndSetter;
var
  Options: TServerEngineOptions;
begin
  Options := TServerEngineOptions.Default;
  Should(Options.OutstandingReceives).Be(0);
  Should(Options.OutstandingReceiveDepth).Be(2);
  Options := Options.WithOutstandingReceives(8).WithOutstandingReceiveDepth(3);
  Should(Options.OutstandingReceives).Be(8);
  Should(Options.OutstandingReceiveDepth).Be(3);
end;

procedure THttpSysReceivesTests.TestDefaultCounts;
var
  Cpu: Integer;
begin
  Cpu := GetSystemLogicalProcessorCount;
  Should(HttpSysWorkerCount(TServerEngineOptions.Default)).Be(4 * Cpu);
  Should(HttpSysReceiveCount(TServerEngineOptions.Default, 4 * Cpu)).Be(Cpu);
end;

procedure THttpSysReceivesTests.TestIoThreadsSet_WorkersTimesDepth;
var
  Options: TServerEngineOptions;
begin
  // The depth keeps its default, 2: the same receives as before.
  Options := TServerEngineOptions.Default.WithIoThreads(3);
  Should(HttpSysWorkerCount(Options)).Be(3);
  Should(HttpSysReceiveCount(Options, 3)).Be(6);
end;

procedure THttpSysReceivesTests.TestAutomaticWorkers_DepthNotUsed;
var
  Options: TServerEngineOptions;
  Cpu: Integer;
begin
  Cpu := GetSystemLogicalProcessorCount;
  Options := TServerEngineOptions.Default.WithOutstandingReceiveDepth(5);
  Should(HttpSysWorkerCount(Options)).Be(4 * Cpu);
  Should(HttpSysReceiveCount(Options, 4 * Cpu)).Be(Cpu);
end;

procedure THttpSysReceivesTests.TestDepthSet_WorkersTimesDepth;
var
  Options: TServerEngineOptions;
begin
  Options := TServerEngineOptions.Default.WithIoThreads(3)
    .WithOutstandingReceiveDepth(2);
  Should(HttpSysReceiveCount(Options, 3)).Be(6);
  Options := Options.WithOutstandingReceiveDepth(20);
  Should(HttpSysReceiveCount(Options, 3)).Be(24);
end;

procedure THttpSysReceivesTests.TestReceivesSet_Exactly;
var
  Options: TServerEngineOptions;
begin
  Options := TServerEngineOptions.Default.WithOutstandingReceives(5)
    .WithOutstandingReceiveDepth(2);
  Should(HttpSysReceiveCount(Options, 3)).Be(5);
  Should(HttpSysReceiveCount(Options, 40)).Be(5);
end;

procedure THttpSysReceivesTests.TestDefaultServesFourPerProcessorAtOnce;
var
  Cpu: Integer;
begin
  Cpu := GetSystemLogicalProcessorCount;
  ServeBlocked(TServerEngineOptions.Default.WithBindAddress('127.0.0.1'),
    4 * Cpu, 4 * Cpu);
end;

procedure THttpSysReceivesTests.ServeBlocked(AWorkers, AReceives, ARequests,
  AExpectedAtOnce: Integer);
begin
  ServeBlocked(TServerEngineOptions.Default.WithBindAddress('127.0.0.1')
    .WithIoThreads(AWorkers).WithOutstandingReceiveDepth(1)
    .WithOutstandingReceives(AReceives), ARequests, AExpectedAtOnce);
end;

procedure THttpSysReceivesTests.ServeBlocked(
  const AOptions: TServerEngineOptions; ARequests, AExpectedAtOnce: Integer);
var
  App: IWebApplication;
  Release, AllIn: TEvent;
  InFlight, MaxInFlight, Ok: Integer;
  Clients: array of TThread;
  I: Integer;
  ReachedExpected: Boolean;
begin
  InFlight := 0;
  MaxInFlight := 0;
  Ok := 0;
  Release := TEvent.Create(nil, True, False, '');
  AllIn := TEvent.Create(nil, True, False, '');
  App := WebApplication;
  try
    App.GetApplicationBuilder.Use(
      procedure(Ctx: IHttpContext; Next: TRequestDelegate)
      var
        Now, Seen: Integer;
      begin
        Now := TInterlocked.Increment(InFlight);
        repeat
          Seen := MaxInFlight;
        until (Now <= Seen) or
          (TInterlocked.CompareExchange(MaxInFlight, Now, Seen) = Seen);
        if Now >= AExpectedAtOnce then
          AllIn.SetEvent;
        Release.WaitFor(WaitMs);
        TInterlocked.Decrement(InFlight);
        Ctx.Response.Write('ok');
      end);
    App.UseNativeServer(AOptions);
    App.Start(TestPort);
    try
      SetLength(Clients, ARequests);
      for I := 0 to ARequests - 1 do
      begin
        Clients[I] := TThread.CreateAnonymousThread(
          procedure
          var
            Client: THTTPClient;
          begin
            Client := THTTPClient.Create;
            try
              Client.ConnectionTimeout := WaitMs;
              Client.ResponseTimeout := WaitMs * 3;
              if Client.Get('http://127.0.0.1:' + IntToStr(TestPort) +
                '/blocked').StatusCode = 200 then
                TInterlocked.Increment(Ok);
            finally
              Client.Free;
            end;
          end);
        Clients[I].FreeOnTerminate := False;
        Clients[I].Start;
      end;
      // Every worker busy at once before anyone is released.
      ReachedExpected := AllIn.WaitFor(WaitMs) = wrSignaled;
      Release.SetEvent;
      for I := 0 to ARequests - 1 do
      begin
        Clients[I].WaitFor;
        Clients[I].Free;
      end;
      Should(ReachedExpected).BeTrue;
      Should(MaxInFlight).Be(AExpectedAtOnce);
      Should(Ok).Be(ARequests);
    finally
      App.Stop;
    end;
  finally
    App := nil;
    AllIn.Free;
    Release.Free;
  end;
end;

procedure THttpSysReceivesTests.TestFourWorkersOneReceive;
begin
  ServeBlocked(4, 1, 4, 4);
end;

procedure THttpSysReceivesTests.TestTwoWorkersEightReceives;
begin
  ServeBlocked(2, 8, 6, 2);
end;

end.
