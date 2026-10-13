unit Dext.Dashboard.Security.Tests;

interface

uses
  Dext.Testing.Attributes;

type
  /// <summary>
  ///   The dashboard API is for the dashboard page only: Host on this
  ///   machine, a JSON body, and the token cookie the page receives. The
  ///   rules are checked one by one through DashboardAccessStatus; the last
  ///   test runs them on a real listener on 127.0.0.1 with a real HTTP
  ///   client that keeps cookies.
  /// </summary>
  [TestFixture('Dashboard - the API answers the dashboard page only')]
  TDashboardSecurityTests = class
  public
    [Test('Host: localhost, 127.0.0.1 and [::1] with or without a port; nothing else')]
    procedure TestLocalHostHeader;
    [Test('Content-Type: application/json with or without parameters; nothing else')]
    procedure TestJsonContentType;
    [Test('A foreign Host is refused even with the token (DNS rebinding)')]
    procedure TestForeignHostRefused;
    [Test('The API needs the token; the page, its assets and /health do not')]
    procedure TestTokenRequired;
    [Test('A body that is not JSON is refused (415), a request without a body is not')]
    procedure TestBodyMustBeJson;
    [Test('Applications and the IDE post telemetry and projects without the token, as JSON')]
    procedure TestApplicationPostsArePublic;
    [Test('The token: 64 hex characters from the system generator, the same for the process')]
    procedure TestToken;
    [Test('Real listener: the API refuses, the page gives the cookie, the API then answers')]
    procedure TestRealListener;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  IdTCPClient,
  IdGlobal,
  Dext.Assertions,
  Dext.Web,
  Dext.Web.Interfaces,
  Dext.Dashboard.Security;

const
  TestPort = 9241;
  LocalHost = 'localhost:3030';

/// A raw HTTP/1.1 request, so that the Host header and the Set-Cookie line are
/// exactly what goes on the wire (an HTTP client keeps Set-Cookie for its own
/// cookie store and does not let the Host change).
function RawRequest(const AMethod, APath, AHost, AExtraHeaders,
  ABody: string): string;
var
  C: TIdTCPClient;
  Req: string;
begin
  Req := AMethod + ' ' + APath + ' HTTP/1.1'#13#10 +
    'Host: ' + AHost + #13#10 +
    'Connection: close'#13#10 +
    AExtraHeaders;
  if ABody <> '' then
    Req := Req + 'Content-Length: ' + IntToStr(Length(UTF8String(ABody))) + #13#10;
  Req := Req + #13#10 + ABody;
  C := TIdTCPClient.Create(nil);
  try
    C.Host := '127.0.0.1';
    C.Port := TestPort;
    C.ConnectTimeout := 5000;
    C.ReadTimeout := 5000;
    C.Connect;
    C.IOHandler.Write(Req, IndyTextEncoding_UTF8);
    Result := C.IOHandler.AllData(IndyTextEncoding_UTF8);
  finally
    C.Free;
  end;
end;

function StatusLine(const AResponse: string): string;
var
  P: Integer;
begin
  P := Pos(#13#10, AResponse);
  if P > 0 then
    Result := Copy(AResponse, 1, P - 1)
  else
    Result := AResponse;
end;

{ TDashboardSecurityTests }

procedure TDashboardSecurityTests.TestLocalHostHeader;
begin
  Should(IsLocalHostHeader('localhost')).BeTrue;
  Should(IsLocalHostHeader('localhost:3030')).BeTrue;
  Should(IsLocalHostHeader('LOCALHOST:3030')).BeTrue;
  Should(IsLocalHostHeader('127.0.0.1:3030')).BeTrue;
  Should(IsLocalHostHeader('[::1]:3030')).BeTrue;
  Should(IsLocalHostHeader('[::1]')).BeTrue;
  Should(IsLocalHostHeader('')).BeFalse;
  Should(IsLocalHostHeader('evil.example')).BeFalse;
  Should(IsLocalHostHeader('evil.example:3030')).BeFalse;
  Should(IsLocalHostHeader('localhost.evil.example:3030')).BeFalse;
  Should(IsLocalHostHeader('127.0.0.1.nip.io:3030')).BeFalse;
  Should(IsLocalHostHeader('[::2]:3030')).BeFalse;
end;

procedure TDashboardSecurityTests.TestJsonContentType;
begin
  Should(IsJsonContentType('application/json')).BeTrue;
  Should(IsJsonContentType('application/json; charset=utf-8')).BeTrue;
  Should(IsJsonContentType(' Application/JSON ')).BeTrue;
  Should(IsJsonContentType('')).BeFalse;
  Should(IsJsonContentType('text/plain')).BeFalse;
  Should(IsJsonContentType('application/x-www-form-urlencoded')).BeFalse;
  Should(IsJsonContentType('multipart/form-data; boundary=x')).BeFalse;
end;

procedure TDashboardSecurityTests.TestForeignHostRefused;
begin
  Should(DashboardAccessStatus('GET', '/api/fs/read', 'evil.example:3030', '', 0,
    DashboardToken)).Be(403);
  Should(DashboardAccessStatus('GET', '/', 'evil.example:3030', '', 0, '')).Be(403);
  Should(DashboardAccessStatus('POST', '/api/telemetry/logs', 'evil.example:3030',
    'application/json', 10, '')).Be(403);
end;

procedure TDashboardSecurityTests.TestTokenRequired;
begin
  Should(DashboardAccessStatus('GET', '/api/fs/read', LocalHost, '', 0, '')).Be(403);
  Should(DashboardAccessStatus('GET', '/api/fs/read', LocalHost, '', 0,
    'wrong')).Be(403);
  Should(DashboardAccessStatus('GET', '/api/fs/read', LocalHost, '', 0,
    DashboardToken)).Be(0);
  Should(DashboardAccessStatus('GET', '/events', LocalHost, '', 0, '')).Be(403);
  Should(DashboardAccessStatus('POST', '/hubs/dashboard/negotiate', LocalHost, '',
    0, '')).Be(403);
  Should(DashboardAccessStatus('GET', '/reports/x.html', LocalHost, '', 0,
    '')).Be(403);
  // Public: the page, its assets, /health.
  Should(DashboardAccessStatus('GET', '/', LocalHost, '', 0, '')).Be(0);
  Should(DashboardAccessStatus('GET', '/index.html', LocalHost, '', 0, '')).Be(0);
  Should(DashboardAccessStatus('GET', '/main.js', LocalHost, '', 0, '')).Be(0);
  Should(DashboardAccessStatus('GET', '/health', LocalHost, '', 0, '')).Be(0);
end;

procedure TDashboardSecurityTests.TestBodyMustBeJson;
begin
  Should(DashboardAccessStatus('POST', '/api/tests/run', LocalHost, 'text/plain',
    20, DashboardToken)).Be(415);
  Should(DashboardAccessStatus('POST', '/api/tests/run', LocalHost,
    'application/x-www-form-urlencoded', 20, DashboardToken)).Be(415);
  Should(DashboardAccessStatus('POST', '/api/tests/run', LocalHost,
    'application/json', 20, DashboardToken)).Be(0);
  // No body (/api/env/scan, /sidecar/session): no content type needed.
  Should(DashboardAccessStatus('POST', '/api/env/scan', LocalHost, '', 0,
    DashboardToken)).Be(0);
end;

procedure TDashboardSecurityTests.TestApplicationPostsArePublic;
begin
  Should(DashboardAccessStatus('POST', '/api/telemetry/logs', LocalHost,
    'application/json', 50, '')).Be(0);
  Should(DashboardAccessStatus('POST', '/api/telemetry/events', LocalHost,
    'application/json', 50, '')).Be(0);
  Should(DashboardAccessStatus('POST', '/api/telemetry/metrics', LocalHost,
    'application/json', 50, '')).Be(0);
  Should(DashboardAccessStatus('POST', '/api/telemetry/flush', LocalHost, '', 0,
    '')).Be(0);
  Should(DashboardAccessStatus('POST', '/api/ide/projects', LocalHost,
    'application/json', 50, '')).Be(0);
  // Still JSON only.
  Should(DashboardAccessStatus('POST', '/api/telemetry/logs', LocalHost,
    'text/plain', 50, '')).Be(415);
  // Reading the telemetry back is for the page.
  Should(DashboardAccessStatus('GET', '/api/telemetry/history', LocalHost, '', 0,
    '')).Be(403);
end;

procedure TDashboardSecurityTests.TestToken;
var
  T: string;
  C: Char;
begin
  T := DashboardToken;
  Should(Length(T)).Be(64);
  for C in T do
    Should(CharInSet(C, ['0'..'9', 'a'..'f'])).BeTrue;
  Should(DashboardToken).Be(T);
  Should(SameDashboardToken(T, T)).BeTrue;
  Should(SameDashboardToken(T, T.Substring(1) + 'x')).BeFalse;
  Should(SameDashboardToken('', '')).BeFalse;
end;

procedure TDashboardSecurityTests.TestRealListener;
var
  App: IWebApplication;
  Resp: string;
  Cookie: string;
begin
  App := WebApplication;
  try
    UseDashboardSecurity(App.GetApplicationBuilder);
    App.GetApplicationBuilder.MapGet('/',
      procedure(Ctx: IHttpContext)
      begin
        SetDashboardCookie(Ctx.Response);
        Ctx.Response.Write('page');
      end);
    App.GetApplicationBuilder.MapGet('/api/secret',
      procedure(Ctx: IHttpContext)
      begin
        Ctx.Response.Write('secret');
      end);
    App.GetApplicationBuilder.MapPost('/api/telemetry/logs',
      procedure(Ctx: IHttpContext)
      begin
        Ctx.Response.Write('logged');
      end);
    // The default engine (Indy), as the dashboard: Http.Sys would itself
    // refuse a Host it has no URL prefix for, before the middleware.
    App.Start(TestPort);
    try
      Cookie := 'Cookie: ' + DashboardCookieName + '=' + DashboardToken + #13#10;

      // The API without the page: refused.
      Resp := RawRequest('GET', '/api/secret', 'localhost', '', '');
      Should(StatusLine(Resp)).Contain('403');

      // The page gives the cookie: the token, HttpOnly, SameSite=Strict.
      Resp := RawRequest('GET', '/', 'localhost', '', '');
      Should(StatusLine(Resp)).Contain('200');
      Should(Resp).Contain(DashboardCookieName + '=' + DashboardToken);
      Should(Resp).Contain('HttpOnly');
      Should(Resp).Contain('SameSite=Strict');

      // With the cookie the API answers.
      Resp := RawRequest('GET', '/api/secret', 'localhost', Cookie, '');
      Should(StatusLine(Resp)).Contain('200');
      Should(Resp).Contain('secret');
      // A GET with a query string has no body (Indy gives the query as the
      // body stream of a GET: the body is decided from the headers).
      Resp := RawRequest('GET', '/api/secret?path=x', 'localhost', Cookie, '');
      Should(StatusLine(Resp)).Contain('200');

      // The same request under another name (DNS rebinding): refused.
      Resp := RawRequest('GET', '/api/secret', 'evil.example:' + IntToStr(TestPort),
        Cookie, '');
      Should(StatusLine(Resp)).Contain('403');

      // An application posts telemetry as JSON, without any cookie...
      Resp := RawRequest('POST', '/api/telemetry/logs', 'localhost',
        'Content-Type: application/json'#13#10, '{"m":1}');
      Should(StatusLine(Resp)).Contain('200');
      // ...but not as text/plain, what a form of another site sends.
      Resp := RawRequest('POST', '/api/telemetry/logs', 'localhost',
        'Content-Type: text/plain'#13#10, '{"m":1}');
      Should(StatusLine(Resp)).Contain('415');
    finally
      App.Stop;
    end;
  finally
    App := nil;
  end;
end;

end.
