unit Dext.Json.NotMapped.Tests;

interface

uses
  System.SysUtils,
  Dext.Testing.Attributes,
  Dext.Assertions,
  Dext.Json,
  Dext.Json.Types,
  Dext.Entity.Attributes;

type
  /// [NotMapped] is about the database only: the JSON is left to [JsonIgnore].
  TJsonNotMappedRow = class
  private
    FCode: string;
    FTotal: Integer;
    FHidden: string;
    FComputed: Integer;
    FCommand: string;
  public
    property Code: string read FCode write FCode;
    // Not in the database, in the JSON both ways
    [NotMapped]
    property Total: Integer read FTotal write FTotal;
    // Neither in the database nor in the JSON
    [NotMapped, JsonIgnore]
    property Hidden: string read FHidden write FHidden;
    // A computed value in the response, never read from a request
    [NotMapped, JsonIgnore(TJsonIgnoreMode.OnRead)]
    property Computed: Integer read FComputed write FComputed;
    // A parameter read from a request, never stored nor returned
    [NotMapped, JsonIgnore(TJsonIgnoreMode.OnWrite)]
    property Command: string read FCommand write FCommand;
  end;

  /// The same, as a record.
  TJsonNotMappedRecord = record
    Code: string;
    [NotMapped]
    Total: Integer;
    [NotMapped, JsonIgnore]
    Hidden: string;
  end;

  /// A back-reference kept out of the JSON with [JsonIgnore], as it must be
  /// now that [NotMapped] alone no longer does it.
  TJsonNotMappedNode = class
  private
    FName: string;
    FBack: TJsonNotMappedNode;
  public
    property Name: string read FName write FName;
    [NotMapped, JsonIgnore]
    property Back: TJsonNotMappedNode read FBack write FBack;
  end;

  [TestFixture('JSON - [NotMapped] is about the database only')]
  TJsonNotMappedTests = class
  public
    [Test('A [NotMapped] class property is written')]
    procedure Class_NotMapped_Written;
    [Test('A [NotMapped] class property is read')]
    procedure Class_NotMapped_Read;
    [Test('A [NotMapped] record field is written and read')]
    procedure Record_NotMapped_WrittenAndRead;
    [Test('[NotMapped, JsonIgnore]: neither written nor read')]
    procedure NotMappedJsonIgnore_Neither;
    [Test('[NotMapped, JsonIgnore(OnRead)]: written, not read')]
    procedure NotMappedOnRead_WrittenNotRead;
    [Test('[NotMapped, JsonIgnore(OnWrite)]: read, not written')]
    procedure NotMappedOnWrite_ReadNotWritten;
    [Test('A back-reference with [NotMapped, JsonIgnore] is not followed')]
    procedure BackReference_NotFollowed;
  end;

implementation

{ TJsonNotMappedTests }

procedure TJsonNotMappedTests.Class_NotMapped_Written;
var
  R: TJsonNotMappedRow;
begin
  R := TJsonNotMappedRow.Create;
  try
    R.Code := 'C';
    R.Total := 7;
    Should(TDextJson.Serialize(R)).Contain('"Total":7');
  finally
    R.Free;
  end;
end;

procedure TJsonNotMappedTests.Class_NotMapped_Read;
var
  R: TJsonNotMappedRow;
begin
  R := TDextJson.Deserialize<TJsonNotMappedRow>('{"Code":"C","Total":7}');
  try
    Should(R.Code).Be('C');
    Should(R.Total).Be(7);
  finally
    R.Free;
  end;
end;

procedure TJsonNotMappedTests.Record_NotMapped_WrittenAndRead;
var
  R: TJsonNotMappedRecord;
begin
  R := TDextJson.Deserialize<TJsonNotMappedRecord>(
    '{"Code":"C","Total":7,"Hidden":"h"}');
  Should(R.Code).Be('C');
  Should(R.Total).Be(7);
  Should(R.Hidden).Be('');
  R.Hidden := 'h';
  Should(TDextJson.Serialize<TJsonNotMappedRecord>(R))
    .Be('{"Code":"C","Total":7}');
end;

procedure TJsonNotMappedTests.NotMappedJsonIgnore_Neither;
var
  R: TJsonNotMappedRow;
begin
  R := TDextJson.Deserialize<TJsonNotMappedRow>('{"Code":"C","Hidden":"h"}');
  try
    Should(R.Hidden).Be('');
    R.Hidden := 'h';
    Should(TDextJson.Serialize(R)).NotContain('Hidden');
  finally
    R.Free;
  end;
end;

procedure TJsonNotMappedTests.NotMappedOnRead_WrittenNotRead;
var
  R: TJsonNotMappedRow;
begin
  R := TDextJson.Deserialize<TJsonNotMappedRow>('{"Code":"C","Computed":5}');
  try
    Should(R.Computed).Be(0);
    R.Computed := 9;
    Should(TDextJson.Serialize(R)).Contain('"Computed":9');
  finally
    R.Free;
  end;
end;

procedure TJsonNotMappedTests.NotMappedOnWrite_ReadNotWritten;
var
  R: TJsonNotMappedRow;
begin
  R := TDextJson.Deserialize<TJsonNotMappedRow>('{"Code":"C","Command":"go"}');
  try
    Should(R.Command).Be('go');
    Should(TDextJson.Serialize(R)).NotContain('Command');
  finally
    R.Free;
  end;
end;

procedure TJsonNotMappedTests.BackReference_NotFollowed;
var
  N: TJsonNotMappedNode;
begin
  N := TJsonNotMappedNode.Create;
  try
    N.Name := 'n';
    N.Back := N;
    Should(TDextJson.Serialize(N)).Be('{"Name":"n"}');
  finally
    N.Free;
  end;
end;

end.
