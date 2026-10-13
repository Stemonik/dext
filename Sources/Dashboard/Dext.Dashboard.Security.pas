unit Dext.Dashboard.Security;

/// <summary>
///   Keeps the dashboard API for the dashboard page. The dashboard listens on
///   localhost, which keeps the network out but not a web page open in a
///   browser on the same machine. Three checks, in order, on every request:
///   <para>1. the Host header must name this machine (localhost, 127.0.0.1 or
///   [::1], any port): a page from another site that rebinds its DNS name to
///   127.0.0.1 still sends its own name, and gets 403;</para>
///   <para>2. a request with a body must be application/json: a page from
///   another site then needs a CORS preflight, which the dashboard does not
///   grant, so it cannot post (415 otherwise);</para>
///   <para>3. everything but the page, its assets, /health and the posts that
///   applications and the IDE send must carry the dashboard token, which the
///   page receives as an HttpOnly, SameSite=Strict cookie: the browser sends
///   it with fetch, EventSource and the hub WebSocket of the page, and never
///   with a request from another site (403 otherwise).</para>
/// </summary>

interface

uses
  System.SysUtils,
  Dext.Web.Interfaces;

const
  /// <summary>The cookie that carries the dashboard token.</summary>
  DashboardCookieName = 'DextDashboard';

/// <summary>
///   The token of this dashboard process: 32 random bytes from the system
///   generator, in hex, created once.
/// </summary>
function DashboardToken: string;

/// <summary>
///   True when AHost names this machine: localhost, 127.0.0.1 or [::1], with
///   or without a port. An empty Host is refused.
/// </summary>
function IsLocalHostHeader(const AHost: string): Boolean;

/// <summary>True when AContentType is application/json (any parameters).</summary>
function IsJsonContentType(const AContentType: string): Boolean;

/// <summary>
///   True for a request that does not need the token: the page and its assets,
///   /health, and the posts that applications (telemetry) and the IDE
///   (projects, flush) send without a browser.
/// </summary>
function IsPublicDashboardRequest(const AMethod, APath: string): Boolean;

/// <summary>Compares two tokens in a time that does not depend on where they differ.</summary>
function SameDashboardToken(const A, B: string): Boolean;

/// <summary>
///   The decision for one request: 0 when it may go on, otherwise the status
///   to answer (403 or 415). ACookie is the value of the dashboard cookie
///   ('' when absent).
/// </summary>
function DashboardAccessStatus(const AMethod, APath, AHost, AContentType: string;
  ABodySize: Int64; const ACookie: string): Integer;

/// <summary>Gives the page the token cookie (call it when serving the page).</summary>
procedure SetDashboardCookie(const AResponse: IHttpResponse);

/// <summary>Registers the three checks. Register it before every other route.</summary>
procedure UseDashboardSecurity(const App: IApplicationBuilder);

implementation

uses
  System.Classes;

{$IFDEF MSWINDOWS}
const
  BCRYPT_USE_SYSTEM_PREFERRED_RNG = $00000002;

function BCryptGenRandom(hAlgorithm: Pointer; pbBuffer: PByte;
  cbBuffer: Cardinal; dwFlags: Cardinal): Integer; stdcall;
  external 'bcrypt.dll';
{$ENDIF}

var
  GToken: string;

procedure RandomBytes(var ABuffer: TBytes);
{$IFDEF POSIX}
var
  F: TFileStream;
{$ENDIF}
begin
{$IFDEF MSWINDOWS}
  if BCryptGenRandom(nil, @ABuffer[0], Length(ABuffer),
    BCRYPT_USE_SYSTEM_PREFERRED_RNG) <> 0 then
    raise Exception.Create('Dashboard: BCryptGenRandom failed');
{$ELSE}
  {$IFDEF POSIX}
  F := TFileStream.Create('/dev/urandom', fmOpenRead or fmShareDenyNone);
  try
    F.ReadBuffer(ABuffer[0], Length(ABuffer));
  finally
    F.Free;
  end;
  {$ELSE}
  raise Exception.Create('Dashboard: no secure random source on this platform');
  {$ENDIF}
{$ENDIF}
end;

function NewToken: string;
const
  Digits: array[0..15] of Char = ('0', '1', '2', '3', '4', '5', '6', '7',
    '8', '9', 'a', 'b', 'c', 'd', 'e', 'f');
var
  B: TBytes;
  I: Integer;
begin
  SetLength(B, 32);
  RandomBytes(B);
  SetLength(Result, 64);
  for I := 0 to 31 do
  begin
    Result[2 * I + 1] := Digits[B[I] shr 4];
    Result[2 * I + 2] := Digits[B[I] and $0F];
  end;
end;

function DashboardToken: string;
begin
  Result := GToken;
end;

function IsLocalHostHeader(const AHost: string): Boolean;
var
  Host: string;
  Colon: Integer;
begin
  Host := LowerCase(Trim(AHost));
  if Host = '' then
    Exit(False);
  if Host.StartsWith('[') then
  begin
    // [::1] or [::1]:port
    Colon := Host.IndexOf(']');
    if Colon < 0 then
      Exit(False);
    Host := Host.Substring(0, Colon + 1);
  end
  else
  begin
    Colon := Host.IndexOf(':');
    if Colon >= 0 then
      Host := Host.Substring(0, Colon);
  end;
  Result := (Host = 'localhost') or (Host = '127.0.0.1') or (Host = '[::1]');
end;

function IsJsonContentType(const AContentType: string): Boolean;
var
  MediaType: string;
  Semi: Integer;
begin
  MediaType := AContentType;
  Semi := MediaType.IndexOf(';');
  if Semi >= 0 then
    MediaType := MediaType.Substring(0, Semi);
  Result := SameText(Trim(MediaType), 'application/json');
end;

function IsPublicDashboardRequest(const AMethod, APath: string): Boolean;
var
  Path: string;
begin
  Path := LowerCase(APath);
  if SameText(AMethod, 'GET') or SameText(AMethod, 'HEAD') then
    Exit((Path = '/') or (Path = '/index.html') or (Path = '/main.css') or
      (Path = '/main.js') or (Path = '/i18n.js') or (Path = '/health'));
  if SameText(AMethod, 'POST') then
    // Sent by applications (Dext.Logging.Sinks.Sidecar, the test telemetry
    // listener) and by the IDE expert, which have no browser and no cookie.
    // They still go through the Host and the JSON checks.
    Exit((Path = '/api/telemetry/logs') or (Path = '/api/telemetry/events') or
      (Path = '/api/telemetry/metrics') or (Path = '/api/telemetry/flush') or
      (Path = '/api/ide/projects'));
  Result := False;
end;

function SameDashboardToken(const A, B: string): Boolean;
var
  I: Integer;
  Diff: Integer;
begin
  if (A = '') or (Length(A) <> Length(B)) then
    Exit(False);
  Diff := 0;
  for I := 1 to Length(A) do
    Diff := Diff or (Ord(A[I]) xor Ord(B[I]));
  Result := Diff = 0;
end;

function DashboardAccessStatus(const AMethod, APath, AHost, AContentType: string;
  ABodySize: Int64; const ACookie: string): Integer;
begin
  // 1. DNS rebinding: the Host header is the name the page used.
  if not IsLocalHostHeader(AHost) then
    Exit(403);
  // 2. A body that is not JSON could come from a form of another site,
  //    which needs no preflight.
  if (ABodySize > 0) and not IsJsonContentType(AContentType) then
    Exit(415);
  // 3. The token, except for what is public.
  if not IsPublicDashboardRequest(AMethod, APath) and
    not SameDashboardToken(GToken, ACookie) then
    Exit(403);
  Result := 0;
end;

procedure SetDashboardCookie(const AResponse: IHttpResponse);
var
  Options: TCookieOptions;
begin
  Options := TCookieOptions.Default;
  Options.Path := '/';
  Options.HttpOnly := True;
  Options.SameSite := 'Strict';
  AResponse.AppendCookie(DashboardCookieName, GToken, Options);
end;

// The size of the request body, from the headers: on Indy the body stream of
// a GET is its query string, so the stream size says nothing.
function RequestBodySize(const ARequest: IHttpRequest): Int64;
begin
  if ARequest.GetHeader('Transfer-Encoding') <> '' then
    Exit(1);
  Result := StrToInt64Def(Trim(ARequest.GetHeader('Content-Length')), 0);
end;

procedure UseDashboardSecurity(const App: IApplicationBuilder);
begin
  App.Use(
    procedure(Ctx: IHttpContext; Next: TRequestDelegate)
    var
      Cookie: string;
      Status: Integer;
    begin
      Cookie := '';
      if Ctx.Request.Cookies <> nil then
        Ctx.Request.Cookies.TryGetValue(DashboardCookieName, Cookie);
      Status := DashboardAccessStatus(Ctx.Request.Method, Ctx.Request.Path,
        Ctx.Request.GetHeader('Host'), Ctx.Request.GetHeader('Content-Type'),
        RequestBodySize(Ctx.Request), Cookie);
      if Status = 0 then
      begin
        Next(Ctx);
        Exit;
      end;
      Ctx.Response.StatusCode := Status;
      Ctx.Response.SetContentType('text/plain; charset=utf-8');
      if Status = 415 then
        Ctx.Response.Write('Unsupported Media Type: the dashboard API accepts ' +
          'application/json only')
      else
        Ctx.Response.Write('Forbidden: open the dashboard from its page on ' +
          'localhost');
    end);
end;

initialization
  GToken := NewToken;

end.
