unit Dext.Json.EnumStyle.Tests;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Rtti,
  System.Generics.Collections,
  Dext.Testing.Attributes,
  Dext.Assertions,
  Dext.Core.Span,
  Dext.Json,
  Dext.Json.Types,
  Dext.Json.Utf8,
  Dext.Json.Utf8.Serializer;

type
  TJsonEnumStyleKind = (jekDraft, jekActive, jekClosed);

  /// A plain class with an enum property.
  TJsonEnumStyleRow = class
  private
    FName: string;
    FStatus: TJsonEnumStyleKind;
  public
    property Name: string read FName write FName;
    property Status: TJsonEnumStyleKind read FStatus write FStatus;
  end;

  /// The same, as a record.
  TJsonEnumStyleRecord = record
    Name: string;
    Status: TJsonEnumStyleKind;
  end;

  [TestFixture('JSON - EnumStyle on classes, records, arrays and the default settings')]
  TJsonEnumStyleTests = class
  private
    function Row: TJsonEnumStyleRow;
    function Rec: TJsonEnumStyleRecord;
  public
    [Test('TJsonSettings.Default writes enums as strings')]
    procedure Default_IsAsString;
    [Test('A class property follows EnumStyle')]
    procedure Class_FollowsEnumStyle;
    [Test('A record field follows EnumStyle')]
    procedure Record_FollowsEnumStyle;
    [Test('The UTF-8 entry points follow EnumStyle on classes and records')]
    procedure Utf8_FollowsEnumStyle;
    [Test('Array elements follow EnumStyle')]
    procedure Array_FollowsEnumStyle;
    [Test('List elements follow EnumStyle')]
    procedure List_FollowsEnumStyle;
    [Test('The global default settings reach Serialize without settings')]
    procedure GlobalDefault_ReachesSerialize;
    [Test('The global default settings reach a new TUtf8JsonWriter')]
    procedure GlobalDefault_ReachesWriter;
    [Test('A record written by TUtf8JsonWriter follows the writer settings')]
    procedure Writer_Record_FollowsWriterSettings;
    [Test('A class property reads an enum from its name and from its number')]
    procedure Class_ReadsNameAndNumber;
    [Test('A record field reads an enum from its name and from its number')]
    procedure Record_ReadsNameAndNumber;
    [Test('Array elements read an enum from its name and from its number')]
    procedure Array_ReadsNameAndNumber;
    [Test('A class written with EnumAsNumber reads back')]
    procedure Class_AsNumber_RoundTrip;
    [Test('A number outside the enum raises instead of becoming a value the enum does not have')]
    procedure NumberOutsideTheEnum_Raises;
    [Test('The UTF-8 record deserializer (body binding) reads an enum from its name and from its number')]
    procedure Utf8Record_ReadsNameAndNumber;
    [Test('The UTF-8 record deserializer refuses an unknown name and a number outside the enum')]
    procedure Utf8Record_RefusesWhatIsNotAValue;
  end;

implementation

function TJsonEnumStyleTests.Row: TJsonEnumStyleRow;
begin
  Result := TJsonEnumStyleRow.Create;
  Result.Name := 'x';
  Result.Status := jekClosed;
end;

function TJsonEnumStyleTests.Rec: TJsonEnumStyleRecord;
begin
  Result.Name := 'x';
  Result.Status := jekClosed;
end;

procedure TJsonEnumStyleTests.Default_IsAsString;
begin
  Should(Ord(TJsonSettings.Default.EnumStyle)).Be(Ord(TEnumStyle.AsString));
end;

procedure TJsonEnumStyleTests.Class_FollowsEnumStyle;
var
  R: TJsonEnumStyleRow;
begin
  R := Row;
  try
    Should(TDextJson.Serialize(R, TJsonSettings.Default))
      .Be('{"Name":"x","Status":"jekClosed"}');
    Should(TDextJson.Serialize(R, TJsonSettings.Default.EnumAsString))
      .Be('{"Name":"x","Status":"jekClosed"}');
    Should(TDextJson.Serialize(R, TJsonSettings.Default.EnumAsNumber))
      .Be('{"Name":"x","Status":2}');
  finally
    R.Free;
  end;
end;

procedure TJsonEnumStyleTests.Record_FollowsEnumStyle;
begin
  Should(TDextJson.Serialize<TJsonEnumStyleRecord>(Rec, TJsonSettings.Default))
    .Be('{"Name":"x","Status":"jekClosed"}');
  Should(TDextJson.Serialize<TJsonEnumStyleRecord>(Rec,
    TJsonSettings.Default.EnumAsString)).Be('{"Name":"x","Status":"jekClosed"}');
  Should(TDextJson.Serialize<TJsonEnumStyleRecord>(Rec,
    TJsonSettings.Default.EnumAsNumber)).Be('{"Name":"x","Status":2}');
end;

procedure TJsonEnumStyleTests.Utf8_FollowsEnumStyle;
var
  R: TJsonEnumStyleRow;
begin
  R := Row;
  try
    Should(TEncoding.UTF8.GetString(TDextJson.SerializeUtf8<TJsonEnumStyleRow>(R,
      TJsonSettings.Default.EnumAsNumber))).Be('{"Name":"x","Status":2}');
    Should(TEncoding.UTF8.GetString(TDextJson.SerializeUtf8<TJsonEnumStyleRow>(R,
      TJsonSettings.Default.EnumAsString))).Be('{"Name":"x","Status":"jekClosed"}');
  finally
    R.Free;
  end;
  Should(TEncoding.UTF8.GetString(TDextJson.SerializeUtf8<TJsonEnumStyleRecord>(Rec,
    TJsonSettings.Default.EnumAsNumber))).Be('{"Name":"x","Status":2}');
  Should(TEncoding.UTF8.GetString(TDextJson.SerializeUtf8<TJsonEnumStyleRecord>(Rec,
    TJsonSettings.Default.EnumAsString))).Be('{"Name":"x","Status":"jekClosed"}');
end;

procedure TJsonEnumStyleTests.Array_FollowsEnumStyle;
var
  A: TArray<TJsonEnumStyleKind>;
begin
  A := [jekActive, jekClosed];
  Should(TDextJson.Serialize<TArray<TJsonEnumStyleKind>>(A,
    TJsonSettings.Default.EnumAsString)).Be('["jekActive","jekClosed"]');
  Should(TDextJson.Serialize<TArray<TJsonEnumStyleKind>>(A,
    TJsonSettings.Default.EnumAsNumber)).Be('[1,2]');
end;

procedure TJsonEnumStyleTests.List_FollowsEnumStyle;
var
  L: TList<TJsonEnumStyleKind>;
begin
  L := TList<TJsonEnumStyleKind>.Create;
  try
    L.Add(jekActive);
    L.Add(jekClosed);
    Should(TDextJson.Serialize<TList<TJsonEnumStyleKind>>(L,
      TJsonSettings.Default.EnumAsString)).Be('["jekActive","jekClosed"]');
    Should(TDextJson.Serialize<TList<TJsonEnumStyleKind>>(L,
      TJsonSettings.Default.EnumAsNumber)).Be('[1,2]');
  finally
    L.Free;
  end;
end;

procedure TJsonEnumStyleTests.GlobalDefault_ReachesSerialize;
var
  Saved: TJsonSettings;
  R: TJsonEnumStyleRow;
begin
  Saved := TDextJson.GetDefaultSettings;
  R := Row;
  try
    TDextJson.SetDefaultSettings(TJsonSettings.Default.EnumAsNumber);
    Should(TDextJson.Serialize(R)).Be('{"Name":"x","Status":2}');
    TDextJson.SetDefaultSettings(TJsonSettings.Default.EnumAsString);
    Should(TDextJson.Serialize(R)).Be('{"Name":"x","Status":"jekClosed"}');
  finally
    TDextJson.SetDefaultSettings(Saved);
    R.Free;
  end;
end;

procedure TJsonEnumStyleTests.GlobalDefault_ReachesWriter;
var
  Saved: TJsonSettings;
  Stream: TMemoryStream;
  Writer: TUtf8JsonWriter;
  S: UTF8String;
begin
  Saved := TDextJson.GetDefaultSettings;
  Stream := TMemoryStream.Create;
  try
    // The opposite of TJsonSettings.Default on both sides of the change.
    if TJsonSettings.Default.EnumStyle = TEnumStyle.AsString then
      TDextJson.SetDefaultSettings(TJsonSettings.Default.EnumAsNumber)
    else
      TDextJson.SetDefaultSettings(TJsonSettings.Default.EnumAsString);
    Writer := TUtf8JsonWriter.Create(Stream);
    Writer.WriteValue(TValue.From<TJsonEnumStyleKind>(jekClosed));
    SetString(S, PAnsiChar(Stream.Memory), Stream.Size);
    if TDextJson.GetDefaultSettings.EnumStyle = TEnumStyle.AsNumber then
      Should(string(S)).Be('2')
    else
      Should(string(S)).Be('"jekClosed"');
  finally
    TDextJson.SetDefaultSettings(Saved);
    Stream.Free;
  end;
end;

procedure TJsonEnumStyleTests.Writer_Record_FollowsWriterSettings;
var
  Saved: TJsonSettings;
  Stream: TMemoryStream;
  Writer: TUtf8JsonWriter;
  S: UTF8String;
begin
  Saved := TDextJson.GetDefaultSettings;
  Stream := TMemoryStream.Create;
  try
    // Global and writer disagree: the writer must win.
    TDextJson.SetDefaultSettings(TJsonSettings.Default.EnumAsNumber);
    Writer := TUtf8JsonWriter.Create(Stream);
    Writer.Settings := TJsonSettings.Default.EnumAsString;
    Writer.WriteValue(TValue.From<TJsonEnumStyleRecord>(Rec));
    SetString(S, PAnsiChar(Stream.Memory), Stream.Size);
    Should(string(S)).Be('{"Name":"x","Status":"jekClosed"}');
  finally
    TDextJson.SetDefaultSettings(Saved);
    Stream.Free;
  end;
end;

procedure TJsonEnumStyleTests.Class_ReadsNameAndNumber;
var
  R: TJsonEnumStyleRow;
begin
  R := TDextJson.Deserialize<TJsonEnumStyleRow>('{"Name":"x","Status":"jekClosed"}');
  try
    Should(Ord(R.Status)).Be(Ord(jekClosed));
  finally
    R.Free;
  end;
  R := TDextJson.Deserialize<TJsonEnumStyleRow>('{"Name":"x","Status":2}');
  try
    Should(Ord(R.Status)).Be(Ord(jekClosed));
  finally
    R.Free;
  end;
end;

procedure TJsonEnumStyleTests.Record_ReadsNameAndNumber;
var
  R: TJsonEnumStyleRecord;
begin
  R := TDextJson.Deserialize<TJsonEnumStyleRecord>('{"Name":"x","Status":"jekClosed"}');
  Should(Ord(R.Status)).Be(Ord(jekClosed));
  R := TDextJson.Deserialize<TJsonEnumStyleRecord>('{"Name":"x","Status":2}');
  Should(Ord(R.Status)).Be(Ord(jekClosed));
end;

procedure TJsonEnumStyleTests.Array_ReadsNameAndNumber;
var
  A: TArray<TJsonEnumStyleKind>;
begin
  A := TDextJson.Deserialize<TArray<TJsonEnumStyleKind>>('["jekActive",2]');
  Should(Length(A)).Be(2);
  Should(Ord(A[0])).Be(Ord(jekActive));
  Should(Ord(A[1])).Be(Ord(jekClosed));
end;

procedure TJsonEnumStyleTests.Class_AsNumber_RoundTrip;
var
  R, Back: TJsonEnumStyleRow;
  Json: string;
begin
  R := Row;
  try
    Json := TDextJson.Serialize(R, TJsonSettings.Default.EnumAsNumber);
    Back := TDextJson.Deserialize<TJsonEnumStyleRow>(Json,
      TJsonSettings.Default.EnumAsNumber);
    try
      Should(Back.Name).Be('x');
      Should(Ord(Back.Status)).Be(Ord(jekClosed));
    finally
      Back.Free;
    end;
  finally
    R.Free;
  end;
end;

procedure TJsonEnumStyleTests.NumberOutsideTheEnum_Raises;
begin
  Should(
    procedure
    begin
      TDextJson.Deserialize<TArray<TJsonEnumStyleKind>>('[1,7]');
    end).Throw<EDextJsonException>;
  Should(
    procedure
    var
      R: TJsonEnumStyleRow;
    begin
      R := TDextJson.Deserialize<TJsonEnumStyleRow>('{"Name":"x","Status":7}');
      R.Free;
    end).Throw<EDextJsonException>;
end;

function Utf8Record(const AJson: string): TJsonEnumStyleRecord;
var
  Bytes: TBytes;
begin
  Bytes := TEncoding.UTF8.GetBytes(AJson);
  Result := TUtf8JsonSerializer.Deserialize<TJsonEnumStyleRecord>(
    TByteSpan.Create(@Bytes[0], Length(Bytes)));
end;

procedure TJsonEnumStyleTests.Utf8Record_ReadsNameAndNumber;
var
  R: TJsonEnumStyleRecord;
begin
  R := Utf8Record('{"Name":"x","Status":"jekClosed"}');
  Should(R.Name).Be('x');
  Should(Ord(R.Status)).Be(Ord(jekClosed));
  R := Utf8Record('{"Name":"x","Status":2}');
  Should(Ord(R.Status)).Be(Ord(jekClosed));
end;

procedure TJsonEnumStyleTests.Utf8Record_RefusesWhatIsNotAValue;
begin
  Should(
    procedure
    begin
      Utf8Record('{"Name":"x","Status":"jekUnknown"}');
    end).Throw<EUtf8SerializationException>;
  Should(
    procedure
    begin
      Utf8Record('{"Name":"x","Status":7}');
    end).Throw<EUtf8SerializationException>;
end;

end.
