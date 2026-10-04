program filedirs;

{ Create EleBBS 0.11b1 file areas (FILES.RA + FILES.ELE, FILES.RDX rebuilt)
  for every directory under START_DIR that directly holds files with the
  chosen extensions (video files by default).
  Record layouts follow FILESrecord and EleFilesRecord in struct.250 of the
  EleBBS 0.11b1 source (github.com/mbek/elebbs, commit 0d026e2).
  Builds for Win32 and Linux; platform code lives in platform_*.inc.

  Copyright (C) 2026 Martin Kazmaier.
  This program may be distributed under the terms of the Q Public License
  version 1.0; see the LICENSE file. }

{$mode objfpc}{$H+}
{$IFDEF WINDOWS}
{$APPTYPE CONSOLE}
{$ENDIF}

uses
{$IFDEF WINDOWS}
  Windows,
{$ELSE}
  BaseUnix, Unix,
{$ENDIF}
  SysUtils;

const
  AppVersion = '0.2.0';

  NameLen = 40;
  FilePathLen = 40;
  PasswordLen = 15;
  ExportUrlLen = 250;
  FtpPathLen = 250;
  FtpLoginLen = 35;
  FtpPasswordLen = 35;
  MaxAreaNum = 65535;

  ConfigSysPathOffset = 1056;
  ConfigSysPathLen = 60;

  DefaultCodePage = 437;
  LinkNameWidth = 6;

{$IFDEF WINDOWS}
  PathSepChar = '\';
  CaseInsensitivePaths = True;
  DefaultSystemDir = 'c:\ele';
  EnvVarCount = 3;
  EnvVars: array[0..EnvVarCount - 1] of String = ('ELEBBS', 'RA', 'ELE');
  EnvPrefix = '%';
  EnvSuffix = '%';
  ExampleLinkDir = 'C:\ELE\MEDIA';
{$ELSE}
  PathSepChar = '/';
  CaseInsensitivePaths = False;
  DefaultSystemDir = '';
  EnvVarCount = 5;
  EnvVars: array[0..EnvVarCount - 1] of String = ('ELEBBS', 'RA', 'ELE', 'elebbs', 'ele');
  EnvPrefix = '$';
  EnvSuffix = '';
  ExampleLinkDir = '/ele/media';
{$ENDIF}

type
  TFlagType = array[1..4] of Byte;

  TFilesRecord = packed record
    AreaNum: Word;
    Unused: Word;
    Name: String[40];
    Attrib: Byte;
    FilePath: String[40];
    KillDaysDL: Word;
    KillDaysFD: Word;
    PassWord: String[15];
    MoveArea: Word;
    Age: Byte;
    ConvertExt: Byte;
    Group: Word;
    Attrib2: Byte;
    DefCost: Word;
    UploadArea: Word;
    UploadSecurity: Word;
    UploadFlags: TFlagType;
    UploadNotFlags: TFlagType;
    Security: Word;
    Flags: TFlagType;
    NotFlags: TFlagType;
    ListSecurity: Word;
    ListFlags: TFlagType;
    ListNotFlags: TFlagType;
    AltGroup: array[1..3] of Word;
    Device: Byte;
    FreeSpace: array[1..13] of Byte;
  end;

  TEleFilesRecord = packed record
    AreaNum: LongInt;
    ExportURL: String[250];
    ftpPath: String[250];
    ftpLoginName: String[35];
    ftpPassword: String[35];
    Attribute: Byte;
    FreeSpace: array[1..140] of LongInt;
  end;

  EMd = class(Exception)
  public
    WMsg: UnicodeString;
    constructor CreateW(const AMsg: UnicodeString);
  end;

  TUStrArray = array of UnicodeString;

  TAreaFiles = record
    FilesRa, FilesEle, FilesRdx: UnicodeString;
    RaData, EleData: TBytes;
    Ra: array of TFilesRecord;
    Ele: array of TEleFilesRecord;
    Warnings: TUStrArray;
  end;

  TPlanned = record
    Index: Integer;
    Ra: TFilesRecord;
    Ele: TEleFilesRecord;
    SourceDir: UnicodeString;
    TruncatedName: Boolean;
    LinkPath: UnicodeString;
    LinkExists: Boolean;
  end;

  TSkipped = record
    SourceDir, Reason: UnicodeString;
  end;

  TPlan = record
    New: array of TPlanned;
    Skipped: array of TSkipped;
  end;

  TExisting = record
    Keys, Descs: TUStrArray;
  end;

var
  CodePage: Cardinal = DefaultCodePage;

constructor EMd.CreateW(const AMsg: UnicodeString);
begin
  inherited Create(String(AMsg));
  WMsg := AMsg;
end;

{ ---- string and path helpers ---- }

procedure AddStr(var a: TUStrArray; const s: UnicodeString);
begin
  SetLength(a, Length(a) + 1);
  a[High(a)] := s;
end;

function TrimW(const s: UnicodeString): UnicodeString;
var
  a, b: Integer;
begin
  a := 1;
  b := Length(s);
  while (a <= b) and (s[a] <= ' ') do Inc(a);
  while (b >= a) and (s[b] <= ' ') do Dec(b);
  Result := Copy(s, a, b - a + 1);
end;

function PadRight(const s: UnicodeString; width: Integer): UnicodeString;
begin
  Result := s;
  while Length(Result) < width do Result := Result + ' ';
end;

function PadLeft(const s: UnicodeString; width: Integer): UnicodeString;
begin
  Result := s;
  while Length(Result) < width do Result := ' ' + Result;
end;

function IsSep(c: WideChar): Boolean;
begin
{$IFDEF WINDOWS}
  Result := (c = '\') or (c = '/');
{$ELSE}
  Result := c = '/';
{$ENDIF}
end;

function IsRootPath(const s: UnicodeString): Boolean;
begin
{$IFDEF WINDOWS}
  Result := (Length(s) = 3) and (s[2] = ':') and IsSep(s[3]);
{$ELSE}
  Result := s = '/';
{$ENDIF}
end;

function IsAbsolute(const p: UnicodeString): Boolean;
begin
{$IFDEF WINDOWS}
  Result := ((Length(p) >= 3) and (p[2] = ':') and IsSep(p[3]))
         or ((Length(p) >= 2) and IsSep(p[1]) and IsSep(p[2]));
{$ELSE}
  Result := (p <> '') and (p[1] = '/');
{$ENDIF}
end;

function StripTrailingSeps(const s: UnicodeString): UnicodeString;
begin
  Result := s;
  while (Length(Result) > 0) and IsSep(Result[Length(Result)]) do
    SetLength(Result, Length(Result) - 1);
end;

{ Drops trailing separators except on a root like C:\ or /. }
function TidyDir(const s: UnicodeString): UnicodeString;
begin
  Result := s;
  if not IsRootPath(Result) and (StripTrailingSeps(Result) <> '') then
    Result := StripTrailingSeps(Result);
end;

function JoinPath(const dir, name: UnicodeString): UnicodeString;
begin
  if (dir <> '') and IsSep(dir[Length(dir)]) then
    Result := dir + name
  else
    Result := dir + PathSepChar + name;
end;

function LastSepPos(const s: UnicodeString): Integer;
begin
  Result := Length(s);
  while (Result > 0) and not IsSep(s[Result]) do Dec(Result);
end;

function FileNameOf(const p: UnicodeString): UnicodeString;
begin
  Result := Copy(p, LastSepPos(p) + 1, MaxInt);
end;

function DirOf(const p: UnicodeString): UnicodeString;
begin
  Result := Copy(p, 1, LastSepPos(p));
end;

{ File names EleBBS creates: upper case on Windows, lower case on Linux. }
function NativeName(const name: UnicodeString): UnicodeString; forward;

{$IFDEF WINDOWS}
{$I platform_win.inc}
{$ELSE}
{$I platform_unix.inc}
{$ENDIF}

function NativeName(const name: UnicodeString): UnicodeString;
begin
  if CaseInsensitivePaths then Result := UpperW(name) else Result := LowerW(name);
end;

procedure Say(const s: UnicodeString);
begin
  WriteTo(False, s);
end;

procedure Complain(const s: UnicodeString);
begin
  WriteTo(True, s);
end;

function Representable(const s: UnicodeString): Boolean;
var
  b: TBytes;
begin
  b := EncodeCP(s);
  if Length(b) = 0 then
    Exit(s = '');
  Result := DecodeCP(@b[0], Length(b)) = s;
end;

{ Pascal String[N]: one length byte, then N zero-padded character bytes. }

function GetPStr(const field; maxLen: Integer): UnicodeString;
var
  p: PByte;
  n: Integer;
begin
  p := @field;
  n := p^;
  if n > maxLen then n := maxLen;
  Result := DecodeCP(p + 1, n);
end;

procedure SetPStr(var field; maxLen: Integer; const value: UnicodeString);
var
  p: PByte;
  b: TBytes;
  n: Integer;
begin
  p := @field;
  b := EncodeCP(value);
  n := Length(b);
  if n > maxLen then n := maxLen;
  FillChar(field, maxLen + 1, 0);
  p^ := n;
  if n > 0 then
    Move(b[0], (p + 1)^, n);
end;

procedure NormalizePStr(var field; maxLen: Integer);
var
  p: PByte;
begin
  p := @field;
  if p^ > maxLen then p^ := maxLen;
  if p^ < maxLen then
    FillChar((p + 1 + p^)^, maxLen - p^, 0);
end;

{ Write to a temp file next to the target, then rename it into place. }
procedure AtomicWrite(const p: UnicodeString; const data: TBytes);
var
  tmp: UnicodeString;
begin
  tmp := p + '.' + UnicodeString(IntToHex(Random($7FFFFFFF), 8)) + '.tmp';
  try
    WriteAllBytes(tmp, data);
  except
    RemoveFileW(tmp);
    raise;
  end;
  if IsFile(p) then CopyMode(p, tmp);
  if not RenameReplace(tmp, p) then
  begin
    RemoveFileW(tmp);
    raise EMd.CreateW(p + ': ' + LastErrorText);
  end;
end;

{ ---- paths as EleBBS stores them ---- }

{ Normalize a stored or scanned path so equal directories compare equal:
  trailing separators are ignored, and on Windows also case, / vs \ and
  8.3 vs long names. }
function ComparablePath(const path: UnicodeString): UnicodeString;
var
  s, long: UnicodeString;
  i: Integer;
begin
  s := TrimW(path);
  if s = '' then Exit('');
{$IFDEF WINDOWS}
  for i := 1 to Length(s) do
    if s[i] = '/' then s[i] := '\';
{$ENDIF}
  long := LongPath(s);
  if long <> '' then s := long;
  if IsAbsolute(s) then s := FullPath(s);
  if CaseInsensitivePaths then s := LowerW(s);
  Result := StripTrailingSeps(s);
  if Result = '' then Result := s;
end;

{ EleBBS builds file names as FilePath + FileName, so keep a trailing separator. }
function FormatAreaPath(const dir: UnicodeString; upper: Boolean): UnicodeString;
begin
  Result := StripTrailingSeps(dir) + PathSepChar;
  if upper then Result := UpperW(Result);
end;

function FitsFilePath(const s: UnicodeString): Boolean;
begin
  Result := (Length(s) <= FilePathLen) and Representable(s);
end;

{ A FilePath that fits in String[40] and in the code page, or '' if none. }
function FitAreaPath(const dir: UnicodeString; upper: Boolean): UnicodeString;
var
  short: UnicodeString;
begin
  Result := FormatAreaPath(dir, upper);
  if FitsFilePath(Result) then Exit;
  short := ShortPath(dir);
  if (short <> '') and (short <> dir) then
  begin
    Result := FormatAreaPath(short, upper);
    if FitsFilePath(Result) then Exit;
  end;
  Result := '';
end;

{ Order follows EleBBS 0.11b1: ReadConfigRA looks in the current dir first,
  then GetSysEnv checks ELEBBS, RA and ELE. Returns '' if nothing is found
  and there is no built-in default. }
function ResolveSystemDir(const option: UnicodeString; out source: UnicodeString): UnicodeString;
var
  cwd, v: UnicodeString;
  i: Integer;
begin
  if option <> '' then
  begin
    source := '--elebbs-dir';
    Exit(option);
  end;
  cwd := CurrentDir;
  if FindFileCI(cwd, 'CONFIG.RA') <> '' then
  begin
    source := 'current directory (contains CONFIG.RA)';
    Exit(cwd);
  end;
  for i := 0 to EnvVarCount - 1 do
  begin
    v := TrimW(GetEnvW(UnicodeString(EnvVars[i])));
    if v <> '' then
    begin
      source := EnvPrefix + UnicodeString(EnvVars[i]) + EnvSuffix;
      Exit(v);
    end;
  end;
  source := 'built-in default';
  Result := DefaultSystemDir;
end;

{ ---- scanning ---- }

const
  DefaultExtensions = 'avi,mkv,mov,mp4,mpg';

var
  Extensions: TUStrArray;

{ "mkv, .MP4,avi" -> ('.mkv', '.mp4', '.avi'); False if the list has no entries. }
function ParseExtensions(const list: UnicodeString; var exts: TUStrArray): Boolean;
var
  i: Integer;
  item: UnicodeString;
begin
  SetLength(exts, 0);
  item := '';
  for i := 1 to Length(list) + 1 do
    if (i > Length(list)) or (list[i] = ',') then
    begin
      item := LowerW(TrimW(item));
      while (item <> '') and ((item[1] = '*') or (item[1] = '.')) do
        item := Copy(item, 2, MaxInt);
      if item <> '' then AddStr(exts, '.' + item);
      item := '';
    end
    else
      item := item + list[i];
  Result := Length(exts) > 0;
end;

function ExtensionList: UnicodeString;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to High(Extensions) do
  begin
    if Result <> '' then Result := Result + ', ';
    Result := Result + Extensions[i];
  end;
end;

function HasWantedExt(const name: UnicodeString): Boolean;
var
  i, j: Integer;
  ext: UnicodeString;
begin
  Result := False;
  i := Length(name);
  while (i > 0) and (name[i] <> '.') and not IsSep(name[i]) do Dec(i);
  if (i = 0) or (name[i] <> '.') then Exit;
  j := 1;
  while (j < i) and (name[j] = '.') do Inc(j);
  if j >= i then Exit;
  ext := LowerW(Copy(name, i, MaxInt));
  for j := 0 to High(Extensions) do
    if ext = Extensions[j] then Exit(True);
end;

procedure SortCaseless(var a: TUStrArray);
var
  i, j: Integer;
  v, k: UnicodeString;
begin
  for i := 1 to High(a) do
  begin
    v := a[i];
    k := LowerW(v);
    j := i - 1;
    while (j >= 0) and (LowerW(a[j]) > k) do
    begin
      a[j + 1] := a[j];
      Dec(j);
    end;
    a[j + 1] := v;
  end;
end;

{ Top-down walk: a directory is listed before its subdirectories. }
procedure FindMatchingDirs(const dir: UnicodeString; follow: Boolean; var found: TUStrArray);
var
  subs, files: TUStrArray;
  i: Integer;
begin
  if not ListDir(dir, follow, subs, files) then Exit;
  for i := 0 to High(files) do
    if HasWantedExt(files[i]) then
    begin
      AddStr(found, dir);
      Break;
    end;
  SortCaseless(subs);
  for i := 0 to High(subs) do
    FindMatchingDirs(JoinPath(dir, subs[i]), follow, found);
end;

function TidySegment(const s: UnicodeString): UnicodeString;
var
  i, cut: Integer;
begin
  Result := '';
  cut := Pos('-', s);
  if cut = 0 then cut := Length(s) + 1;
  for i := 1 to cut - 1 do
    if not ((s[i] = ' ') and ((Result = '') or (Result[Length(Result)] = ' '))) then
      Result := Result + s[i];
  while (Result <> '') and ((Result[Length(Result)] = ' ') or (Result[Length(Result)] = '-')
    or (Result[Length(Result)] = '_')) do
    SetLength(Result, Length(Result) - 1);
  while (Result <> '') and ((Result[1] = '-') or (Result[1] = '_')) do
    Result := TrimW(Copy(Result, 2, MaxInt));
end;

{ Drops "(...)" and "[...]" parts and anything after a hyphen in each path
  segment, e.g. "Alien (1979) [1080p]" -> "Alien", "Heat - BluRay" -> "Heat".
  Falls back to the original name if nothing would be left. }
function StripBracketed(const name: UnicodeString): UnicodeString;
var
  i, depth: Integer;
  bare, seg: UnicodeString;
begin
  bare := '';
  depth := 0;
  for i := 1 to Length(name) do
    if (name[i] = '(') or (name[i] = '[') then
      Inc(depth)
    else if ((name[i] = ')') or (name[i] = ']')) and (depth > 0) then
      Dec(depth)
    else if depth = 0 then
      bare := bare + name[i];

  Result := '';
  seg := '';
  for i := 1 to Length(bare) + 1 do
    if (i > Length(bare)) or IsSep(bare[i]) then
    begin
      seg := TidySegment(seg);
      if seg <> '' then
        if Result = '' then Result := seg else Result := Result + PathSepChar + seg;
      seg := '';
    end
    else
      seg := seg + bare[i];
  if Result = '' then Result := name;
end;

function RawAreaName(const dir, root: UnicodeString; relative: Boolean): UnicodeString;
var
  prefix: UnicodeString;
begin
  Result := FileNameOf(StripTrailingSeps(dir));
  if Result = '' then Result := dir;
  if relative and (dir <> root) then
  begin
    prefix := JoinPath(root, '');
    if Copy(dir, 1, Length(prefix)) = prefix then
      Result := Copy(dir, Length(prefix) + 1, MaxInt);
  end;
end;

function AreaName(const dir, root: UnicodeString; relative: Boolean): UnicodeString;
begin
  Result := StripBracketed(RawAreaName(dir, root, relative));
end;

{ ---- FILES.RA / FILES.ELE / FILES.RDX ---- }

function ReadConfigSysPath(const cfg: TBytes): UnicodeString;
begin
  if Length(cfg) < ConfigSysPathOffset + ConfigSysPathLen + 1 then
    Exit('');
  Result := GetPStr(cfg[ConfigSysPathOffset], ConfigSysPathLen);
end;

{ SetFilesEleDefaults in areadef.pas. }
function EleDefaults(areaNum: LongInt): TEleFilesRecord;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.AreaNum := areaNum;
  SetPStr(Result.ftpLoginName, FtpLoginLen, 'anonymous');
  SetPStr(Result.ftpPassword, FtpPasswordLen, 'john.doe@elebbs.bbs');
end;

{ Finds FILES.RA / FILES.ELE like OpenRaFile in filerout.pas: the system dir
  first, then CONFIG.RA's SysPath. Missing files are placed next to FILES.RA. }
procedure LocateAreaFiles(const sysDir: UnicodeString; var af: TAreaFiles);
var
  search: TUStrArray;
  config, sp: UnicodeString;

  function Lookup(const name: UnicodeString): UnicodeString;
  var
    i: Integer;
  begin
    for i := 0 to High(search) do
      if IsDir(search[i]) then
      begin
        Result := FindFileCI(search[i], name);
        if Result <> '' then Exit;
      end;
    Result := '';
  end;

begin
  SetLength(search, 0);
  AddStr(search, sysDir);
  config := FindFileCI(sysDir, 'CONFIG.RA');
  if config <> '' then
  begin
    sp := TrimW(ReadConfigSysPath(ReadAllBytes(config)));
    if sp <> '' then AddStr(search, sp);
  end;
  af.FilesRa := Lookup('FILES.RA');
  if af.FilesRa = '' then af.FilesRa := JoinPath(sysDir, NativeName('FILES.RA'));
  af.FilesEle := Lookup('FILES.ELE');
  if af.FilesEle = '' then af.FilesEle := JoinPath(DirOf(af.FilesRa), NativeName('FILES.ELE'));
  af.FilesRdx := FindFileCI(DirOf(af.FilesRa), 'FILES.RDX');
  if af.FilesRdx = '' then af.FilesRdx := JoinPath(DirOf(af.FilesRa), NativeName('FILES.RDX'));
end;

procedure LoadAreaFiles(const sysDir: UnicodeString; var af: TAreaFiles);
var
  raCount, eleCount, missing: Integer;
begin
  if not IsDir(sysDir) then
    raise EMd.CreateW('EleBBS system dir not found: ' + sysDir);
  LocateAreaFiles(sysDir, af);
  SetLength(af.RaData, 0);
  SetLength(af.EleData, 0);
  if IsFile(af.FilesRa) then af.RaData := ReadAllBytes(af.FilesRa);
  if IsFile(af.FilesEle) then af.EleData := ReadAllBytes(af.FilesEle);

  if Length(af.RaData) mod SizeOf(TFilesRecord) <> 0 then
    raise EMd.CreateW(FileNameOf(af.FilesRa) + ' is ' + IntToStr(Length(af.RaData))
      + ' bytes, not a multiple of the ' + IntToStr(SizeOf(TFilesRecord))
      + '-byte record size; refusing to touch it');
  if Length(af.EleData) mod SizeOf(TEleFilesRecord) <> 0 then
    raise EMd.CreateW(FileNameOf(af.FilesEle) + ' is ' + IntToStr(Length(af.EleData))
      + ' bytes, not a multiple of the ' + IntToStr(SizeOf(TEleFilesRecord))
      + '-byte record size; refusing to touch it');

  raCount := Length(af.RaData) div SizeOf(TFilesRecord);
  eleCount := Length(af.EleData) div SizeOf(TEleFilesRecord);
  if eleCount > raCount then
    raise EMd.CreateW(FileNameOf(af.FilesEle) + ' has ' + IntToStr(eleCount) + ' records but '
      + FileNameOf(af.FilesRa) + ' has ' + IntToStr(raCount)
      + '; the files are out of sync. Open the file areas in ELCONFIG to repair them first.');

  SetLength(af.Ra, raCount);
  if raCount > 0 then Move(af.RaData[0], af.Ra[0], raCount * SizeOf(TFilesRecord));
  SetLength(af.Ele, eleCount);
  if eleCount > 0 then Move(af.EleData[0], af.Ele[0], eleCount * SizeOf(TEleFilesRecord));

  SetLength(af.Warnings, 0);
  if not IsFile(af.FilesRa) then
    AddStr(af.Warnings, af.FilesRa + ' does not exist yet; it will be created');
  missing := raCount - eleCount;
  if missing > 0 then
    AddStr(af.Warnings, FileNameOf(af.FilesEle) + ' is ' + IntToStr(missing)
      + ' record(s) shorter than ' + FileNameOf(af.FilesRa)
      + '; EleBBS default FILES.ELE records will be added for those indexes first');
end;

procedure AddExisting(var ex: TExisting; const key, desc: UnicodeString);
var
  i: Integer;
begin
  if key = '' then Exit;
  for i := 0 to High(ex.Keys) do
    if ex.Keys[i] = key then Exit;
  AddStr(ex.Keys, key);
  AddStr(ex.Descs, desc);
end;

function FindExisting(const ex: TExisting; const key: UnicodeString): Integer;
begin
  for Result := 0 to High(ex.Keys) do
    if ex.Keys[Result] = key then Exit;
  Result := -1;
end;

{ Duplicates: FILES.RA FilePath (or where it links to), or FILES.ELE ftpPath
  when it is a local path. }
procedure CollectExisting(const af: TAreaFiles; var ex: TExisting);
var
  i: Integer;
  ftp, path, desc: UnicodeString;
begin
  for i := 0 to High(af.Ra) do
  begin
    path := GetPStr(af.Ra[i].FilePath, FilePathLen);
    desc := FileNameOf(af.FilesRa) + ' record ' + IntToStr(i + 1) + ' (area '
      + IntToStr(af.Ra[i].AreaNum) + ', ''' + GetPStr(af.Ra[i].Name, NameLen) + ''')';
    AddExisting(ex, ComparablePath(path), desc);
    if (TrimW(path) <> '') and IsLink(path) then
      AddExisting(ex, ComparablePath(FinalPath(path)), desc + ' via symlink ' + path);
  end;
  for i := 0 to High(af.Ele) do
  begin
    ftp := GetPStr(af.Ele[i].ftpPath, FtpPathLen);
    if LowerW(Copy(ftp, 1, 6)) = 'ftp://' then Continue;
    AddExisting(ex, ComparablePath(ftp),
      FileNameOf(af.FilesEle) + ' record ' + IntToStr(i + 1) + ' (ftpPath)');
  end;
end;

function FindTemplate(const af: TAreaFiles; areaNum: Integer; out ra: TFilesRecord; out ele: TEleFilesRecord): Boolean;
var
  i: Integer;
begin
  for i := 0 to High(af.Ra) do
    if af.Ra[i].AreaNum = areaNum then
    begin
      ra := af.Ra[i];
      if i <= High(af.Ele) then
        ele := af.Ele[i]
      else
        ele := EleDefaults(ra.AreaNum);
      Exit(True);
    end;
  Result := False;
end;

function LinkName(areaNum: Integer): UnicodeString;
begin
  Result := UnicodeString(IntToStr(areaNum));
  while Length(Result) < LinkNameWidth - 1 do Result := '0' + Result;
  Result := 'A' + Result;
end;

procedure MakePlan(const af: TAreaFiles; const dirs, names: TUStrArray;
  useTemplate: Boolean; const tplRa: TFilesRecord; const tplEle: TEleFilesRecord;
  security: Integer; upperPaths: Boolean; const linkDir: UnicodeString; var plan: TPlan);
var
  ex: TExisting;
  used: array of Boolean;
  nextFree, nextIndex, i, k: Integer;
  key, filePath, linkPath: UnicodeString;
  p: TPlanned;
  nameBytes: TBytes;

  procedure Skip(const dir, reason: UnicodeString);
  begin
    SetLength(plan.Skipped, Length(plan.Skipped) + 1);
    plan.Skipped[High(plan.Skipped)].SourceDir := dir;
    plan.Skipped[High(plan.Skipped)].Reason := reason;
  end;

begin
  SetLength(ex.Keys, 0);
  SetLength(ex.Descs, 0);
  CollectExisting(af, ex);

  SetLength(used, MaxAreaNum + 1);
  for i := 0 to High(af.Ra) do used[af.Ra[i].AreaNum] := True;
  for i := 0 to High(af.Ele) do
    if (af.Ele[i].AreaNum >= 0) and (af.Ele[i].AreaNum <= MaxAreaNum) then
      used[af.Ele[i].AreaNum] := True;
  nextFree := 1;
  nextIndex := Length(af.Ra);

  for i := 0 to High(dirs) do
  begin
    key := ComparablePath(dirs[i]);
    k := FindExisting(ex, key);
    if k >= 0 then
    begin
      Skip(dirs[i], 'already an area: ' + ex.Descs[k]);
      Continue;
    end;
    while (nextFree <= MaxAreaNum) and used[nextFree] do Inc(nextFree);
    if nextFree > MaxAreaNum then
    begin
      Skip(dirs[i], 'no free area numbers left (max 65535)');
      Continue;
    end;
    p.LinkPath := '';
    p.LinkExists := False;
    filePath := FitAreaPath(dirs[i], upperPaths);
    if (filePath = '') and (linkDir <> '') then
    begin
      linkPath := JoinPath(linkDir, LinkName(nextFree));
      if PathExists(linkPath) then
      begin
        if ComparablePath(FinalPath(linkPath)) <> key then
        begin
          Skip(dirs[i], linkPath + ' already exists and doesn''t point to this folder');
          Continue;
        end;
        p.LinkExists := True;
      end;
      p.LinkPath := linkPath;
      filePath := FormatAreaPath(linkPath, upperPaths);
    end;
    if filePath = '' then
    begin
      if not Representable(FormatAreaPath(dirs[i], upperPaths)) then
        Skip(dirs[i], 'path has characters code page ' + IntToStr(CodePage) + ' can''t store')
      else
        Skip(dirs[i], 'path too long: ' + FormatAreaPath(dirs[i], upperPaths) + ' is '
          + IntToStr(Length(FormatAreaPath(dirs[i], upperPaths)))
          + ' characters, EleBBS allows 40 (use --link-dir)');
      Continue;
    end;

    if useTemplate then
    begin
      p.Ra := tplRa;
      NormalizePStr(p.Ra.PassWord, PasswordLen);
      p.Ele := tplEle;
      SetPStr(p.Ele.ExportURL, ExportUrlLen, '');
      SetPStr(p.Ele.ftpPath, FtpPathLen, '');
      NormalizePStr(p.Ele.ftpLoginName, FtpLoginLen);
      NormalizePStr(p.Ele.ftpPassword, FtpPasswordLen);
    end
    else
    begin
      FillChar(p.Ra, SizeOf(p.Ra), 0);
      p.Ele := EleDefaults(0);
    end;
    p.Ra.AreaNum := nextFree;
    p.Ele.AreaNum := nextFree;
    SetPStr(p.Ra.Name, NameLen, names[i]);
    SetPStr(p.Ra.FilePath, FilePathLen, filePath);
    if security >= 0 then
    begin
      p.Ra.Security := security;
      p.Ra.ListSecurity := security;
    end;
    nameBytes := EncodeCP(names[i]);
    p.TruncatedName := Length(nameBytes) > NameLen;
    p.Index := nextIndex;
    p.SourceDir := dirs[i];

    SetLength(plan.New, Length(plan.New) + 1);
    plan.New[High(plan.New)] := p;
    used[nextFree] := True;
    AddExisting(ex, key, 'new area ' + IntToStr(nextFree));
    Inc(nextIndex);
  end;
end;

{ GenerateRDXFiles in gencfg.pas: entry AreaNum-1 holds the 1-based FILES.RA
  record index of that area; unused numbers hold 0. }
function BuildRdx(const areaNums: array of Integer): TBytes;
var
  table: array of Word;
  maxArea, i: Integer;
begin
  maxArea := 0;
  for i := 0 to High(areaNums) do
    if areaNums[i] > maxArea then maxArea := areaNums[i];
  SetLength(table, maxArea);
  for i := 0 to High(table) do table[i] := 0;
  for i := 0 to High(areaNums) do
    if areaNums[i] > 0 then
      table[areaNums[i] - 1] := NtoLE(Word((i + 1) and $FFFF));
  SetLength(Result, maxArea * 2);
  if maxArea > 0 then Move(table[0], Result[0], maxArea * 2);
end;

function BackupFiles(const af: TAreaFiles): TUStrArray;
var
  stamp, target: UnicodeString;
  files: array[0..2] of UnicodeString;
  i: Integer;
begin
  SetLength(Result, 0);
  stamp := UnicodeString(FormatDateTime('yyyymmdd"-"hhnnss', Now));
  files[0] := af.FilesRa;
  files[1] := af.FilesEle;
  files[2] := af.FilesRdx;
  for i := 0 to 2 do
    if IsFile(files[i]) then
    begin
      target := files[i] + '.' + stamp + '.bak';
      if not CopyFileTo(files[i], target) then
        raise EMd.CreateW('backing up ' + files[i] + ' failed: ' + LastErrorText);
      AddStr(Result, target);
    end;
end;

procedure AppendBytes(var dst: TBytes; const src; size: Integer);
var
  old: Integer;
begin
  if size <= 0 then Exit;
  old := Length(dst);
  SetLength(dst, old + size);
  Move(src, dst[old], size);
end;

{ FILES.RA is written first: if the run dies before FILES.ELE is written, the
  ELE file is merely short, which both EleBBS and this tool can repair. }
procedure WritePlan(const af: TAreaFiles; const plan: TPlan);
var
  raOut, eleOut: TBytes;
  pad: TEleFilesRecord;
  areaNums: array of Integer;
  i, n: Integer;
begin
  raOut := Copy(af.RaData, 0, Length(af.RaData));
  eleOut := Copy(af.EleData, 0, Length(af.EleData));
  for i := Length(af.Ele) to High(af.Ra) do
  begin
    pad := EleDefaults(af.Ra[i].AreaNum);
    AppendBytes(eleOut, pad, SizeOf(pad));
  end;
  for i := 0 to High(plan.New) do
  begin
    AppendBytes(raOut, plan.New[i].Ra, SizeOf(TFilesRecord));
    AppendBytes(eleOut, plan.New[i].Ele, SizeOf(TEleFilesRecord));
  end;
  if Length(raOut) div SizeOf(TFilesRecord) <> Length(eleOut) div SizeOf(TEleFilesRecord) then
    raise EMd.CreateW('internal error: FILES.RA and FILES.ELE record counts differ');

  n := Length(af.Ra) + Length(plan.New);
  SetLength(areaNums, n);
  for i := 0 to High(af.Ra) do areaNums[i] := af.Ra[i].AreaNum;
  for i := 0 to High(plan.New) do areaNums[Length(af.Ra) + i] := plan.New[i].Ra.AreaNum;

  AtomicWrite(af.FilesRa, raOut);
  try
    AtomicWrite(af.FilesEle, eleOut);
  except
    AtomicWrite(af.FilesRa, af.RaData);
    raise;
  end;
  AtomicWrite(af.FilesRdx, BuildRdx(areaNums));
end;

procedure RemoveLinks(const created: TUStrArray);
var
  i: Integer;
begin
  for i := 0 to High(created) do
    RemoveLink(created[i]);
end;

{ Directory symlinks for areas whose real path doesn't fit FilePath. Already
  created links are removed again if one of them fails. }
function CreateLinks(const linkDir: UnicodeString; const plan: TPlan): TUStrArray;
var
  i: Integer;
  err: UnicodeString;
begin
  SetLength(Result, 0);
  for i := 0 to High(plan.New) do
  begin
    if (plan.New[i].LinkPath = '') or plan.New[i].LinkExists then Continue;
    if not IsDir(linkDir) and not MakeDir(linkDir) then
      raise EMd.CreateW('cannot create ' + linkDir + ': ' + LastErrorText);
    if not MakeDirLink(plan.New[i].LinkPath, plan.New[i].SourceDir, err) then
    begin
      RemoveLinks(Result);
      raise EMd.CreateW('cannot create symlink ' + plan.New[i].LinkPath + ' -> '
        + plan.New[i].SourceDir + ': ' + err);
    end;
    AddStr(Result, plan.New[i].LinkPath);
  end;
end;

{ ---- command line ---- }

const
  Usage = 'usage: filedirs [-h] [--elebbs-dir DIR] [--dry-run] [--name-style {leaf,relative}]'
    + LineEnding + '                [--no-backup] [--template-area N] [--security LEVEL]'
    + LineEnding + '                [--uppercase-paths] [--encoding CP] [--follow-symlinks]'
    + LineEnding + '                [--link-dir DIR] [--ext LIST] [--version] start_dir';

procedure PrintHelp;
var
  envs: UnicodeString;
  i: Integer;
begin
  envs := '';
  for i := 0 to EnvVarCount - 1 do
    envs := envs + EnvPrefix + UnicodeString(EnvVars[i]) + EnvSuffix + ', ';
  Say(Usage);
  Say('');
  Say('Scan a directory tree for folders that directly contain files with the given');
  Say('extensions (default: ' + DefaultExtensions + ') and add each one as an EleBBS 0.11b1');
  Say('file area in FILES.RA and FILES.ELE.');
  Say('');
  Say('positional arguments:');
  Say('  start_dir             directory to scan recursively');
  Say('');
  Say('options:');
  Say('  -h, --help            show this help message and exit');
  Say('  --elebbs-dir DIR      EleBBS system dir holding CONFIG.RA, CONFIG.ELE, FILES.RA');
  Say('                        and FILES.ELE (default: current dir if it has CONFIG.RA,');
  if DefaultSystemDir <> '' then
    Say('                        then ' + envs + 'then ' + DefaultSystemDir + ')')
  else
    Say('                        then ' + Copy(envs, 1, Length(envs) - 2) + ')');
  Say('  --dry-run             print the planned areas without writing');
  Say('  --name-style {leaf,relative}');
  Say('                        area name: the directory''s path after START_DIR');
  Say('                        (relative, default) or just its own name (leaf)');
  Say('  --no-backup           don''t copy FILES.RA, FILES.ELE and FILES.RDX to *.bak');
  Say('                        before writing');
  Say('  --template-area N     copy security, flags, group and other settings from');
  Say('                        existing area number N');
  Say('  --security LEVEL      download and list security level for new areas (EleBBS');
  Say('                        default: 0)');
  Say('  --uppercase-paths     store paths in upper case, DOS style');
  Say('  --encoding CP         code page for names and paths in the records (default:');
{$IFDEF WINDOWS}
  Say('                        cp437)');
{$ELSE}
  Say('                        cp437, the only one built in on Linux)');
{$ENDIF}
  Say('  --follow-symlinks     descend into symlinked directories');
  Say('  --link-dir DIR        for folders whose path won''t fit in 40 characters, create');
  Say('                        a directory symlink ' + JoinPath('DIR', 'A<area number>') + ' pointing to');
  Say('                        the folder and store that instead, e.g.');
  Say('                        --link-dir ' + ExampleLinkDir
{$IFDEF WINDOWS}
    + ' (needs admin rights or Developer Mode)'
{$ENDIF}
    );
  Say('  --ext LIST            comma-separated file extensions to look for, any case,');
  Say('                        e.g. --ext mkv,mp4,avi,m4v (default: ' + DefaultExtensions + ')');
  Say('  --version             show program''s version number and exit');
end;

procedure UsageError(const msg: UnicodeString);
begin
  Complain(Usage);
  Complain('filedirs: error: ' + msg);
  Halt(2);
end;

function ParseInt(const opt, value: UnicodeString; lo, hi: Integer): Integer;
begin
  if not TryStrToInt(String(value), Result) then
    UsageError('argument ' + opt + ': invalid int value: ''' + value + '''');
  if (Result < lo) or (Result > hi) then
    UsageError('argument ' + opt + ': must be between ' + IntToStr(lo) + ' and ' + IntToStr(hi));
end;

function ParseCodePage(const value: UnicodeString): Cardinal;
var
  s: UnicodeString;
  n: Integer;
begin
  s := LowerW(TrimW(value));
  if Copy(s, 1, 2) = 'cp' then s := Copy(s, 3, MaxInt);
  if not TryStrToInt(String(s), n) or not ValidCodePage(n) then
    UsageError('argument --encoding: unknown or unsupported code page: ''' + value + '''');
  Result := n;
end;

function RunMain: Integer;
var
  args: TUStrArray;
  i, eq: Integer;
  a, opt, value: UnicodeString;
  hasValue, optionsDone: Boolean;
  startArg, elebbsDir, sysDir, source, start: UnicodeString;
  dryRun, relative, backup, upperPaths, follow, useTemplate: Boolean;
  templateArea, security: Integer;
  af: TAreaFiles;
  tplRa: TFilesRecord;
  tplEle: TEleFilesRecord;
  dirs, names, backups, links: TUStrArray;
  plan: TPlan;
  note, line, linkDir: UnicodeString;

  function TakeValue: UnicodeString;
  begin
    if hasValue then Exit(value);
    Inc(i);
    if i > High(args) then UsageError('argument ' + opt + ': expected one argument');
    Result := args[i];
  end;

begin
  startArg := '';
  elebbsDir := '';
  linkDir := '';
  dryRun := False;
  relative := True;
  backup := True;
  upperPaths := False;
  follow := False;
  templateArea := 0;
  security := -1;
  optionsDone := False;

  ParseExtensions(DefaultExtensions, Extensions);

  args := GetArgs;
  i := 0;
  while i <= High(args) do
  begin
    a := args[i];
    if not optionsDone and (a = '--') then
      optionsDone := True
    else if not optionsDone and (Length(a) > 1) and (a[1] = '-') then
    begin
      opt := a;
      value := '';
      hasValue := False;
      eq := Pos('=', a);
      if (Copy(a, 1, 2) = '--') and (eq > 0) then
      begin
        opt := Copy(a, 1, eq - 1);
        value := Copy(a, eq + 1, MaxInt);
        hasValue := True;
      end;
      if (opt = '-h') or (opt = '--help') then
      begin
        PrintHelp;
        Exit(0);
      end
      else if opt = '--version' then
      begin
        Say('filedirs ' + AppVersion);
        Exit(0);
      end
      else if opt = '--elebbs-dir' then elebbsDir := TakeValue
      else if opt = '--dry-run' then dryRun := True
      else if opt = '--name-style' then
      begin
        value := TakeValue;
        if value = 'relative' then relative := True
        else if value = 'leaf' then relative := False
        else UsageError('argument --name-style: invalid choice: ''' + value + ''' (choose from ''leaf'', ''relative'')');
      end
      else if opt = '--no-backup' then backup := False
      else if opt = '--template-area' then templateArea := ParseInt(opt, TakeValue, 1, MaxAreaNum)
      else if opt = '--security' then security := ParseInt(opt, TakeValue, 0, 65535)
      else if opt = '--uppercase-paths' then upperPaths := True
      else if opt = '--encoding' then CodePage := ParseCodePage(TakeValue)
      else if opt = '--follow-symlinks' then follow := True
      else if opt = '--link-dir' then linkDir := TakeValue
      else if opt = '--ext' then
      begin
        if not ParseExtensions(TakeValue, Extensions) then
          UsageError('argument --ext: no extensions given');
      end
      else UsageError('unrecognized arguments: ' + a);
    end
    else if startArg = '' then
      startArg := a
    else
      UsageError('unrecognized arguments: ' + a);
    Inc(i);
  end;

  if startArg = '' then
    UsageError('the following arguments are required: start_dir');

  start := TidyDir(FullPath(startArg));
  if not IsDir(start) then
  begin
    Complain('error: start dir not found: ' + startArg);
    Exit(2);
  end;

  if linkDir <> '' then
  begin
    linkDir := TidyDir(FullPath(linkDir));
    if Length(FormatAreaPath(JoinPath(linkDir, LinkName(1)), upperPaths)) > FilePathLen then
      UsageError('argument --link-dir: ' + linkDir + ' is too long; links like '
        + FormatAreaPath(JoinPath(linkDir, LinkName(1)), upperPaths) + ' must fit in 40 characters');
    if not Representable(linkDir) then
      UsageError('argument --link-dir: ' + linkDir + ' has characters code page '
        + IntToStr(CodePage) + ' can''t store');
  end;

  sysDir := ResolveSystemDir(elebbsDir, source);
  if sysDir = '' then
  begin
    Complain('error: no EleBBS system dir found; pass --elebbs-dir DIR or set ' + EnvPrefix + 'ELEBBS' + EnvSuffix);
    Exit(1);
  end;
  sysDir := TidyDir(sysDir);
  try
    LoadAreaFiles(sysDir, af);
    useTemplate := templateArea > 0;
    if useTemplate and not FindTemplate(af, templateArea, tplRa, tplEle) then
      raise EMd.CreateW('template area ' + IntToStr(templateArea) + ' not found in ' + FileNameOf(af.FilesRa));
  except
    on e: EMd do
    begin
      Complain('error: ' + e.WMsg);
      Exit(1);
    end;
  end;

  Say('EleBBS system dir: ' + sysDir + ' (from ' + source + ')');
  Say('  ' + af.FilesRa + ': ' + IntToStr(Length(af.Ra)) + ' area(s)');
  Say('  ' + af.FilesEle + ': ' + IntToStr(Length(af.Ele)) + ' record(s)');
  for i := 0 to High(af.Warnings) do
    Complain('warning: ' + af.Warnings[i]);

  SetLength(dirs, 0);
  FindMatchingDirs(start, follow, dirs);
  SetLength(names, Length(dirs));
  for i := 0 to High(dirs) do
    names[i] := AreaName(dirs[i], start, relative);

  if not useTemplate then
  begin
    FillChar(tplRa, SizeOf(tplRa), 0);
    FillChar(tplEle, SizeOf(tplEle), 0);
  end;
  SetLength(plan.New, 0);
  SetLength(plan.Skipped, 0);
  MakePlan(af, dirs, names, useTemplate, tplRa, tplEle, security, upperPaths, linkDir, plan);

  Say('');
  if Length(dirs) = 1 then
    Say('Found 1 directory with ' + ExtensionList + ' files under ' + start)
  else
    Say('Found ' + IntToStr(Length(dirs)) + ' directories with ' + ExtensionList + ' files under ' + start);

  if Length(plan.New) > 0 then
  begin
    Say('');
    if dryRun then line := 'Would add ' else line := 'Adding ';
    Say(line + IntToStr(Length(plan.New)) + ' area(s):');
    Say('  ' + PadLeft('rec', 5) + '  ' + PadLeft('area', 5) + '  ' + PadRight('name', 40) + '  path');
    for i := 0 to High(plan.New) do
    begin
      if plan.New[i].TruncatedName then note := '  (name truncated)' else note := '';
      if plan.New[i].LinkPath <> '' then
        note := note + '  (symlink to ' + plan.New[i].SourceDir + ')';
      Say('  ' + PadLeft(IntToStr(plan.New[i].Index + 1), 5)
        + '  ' + PadLeft(IntToStr(plan.New[i].Ra.AreaNum), 5)
        + '  ' + PadRight(GetPStr(plan.New[i].Ra.Name, NameLen), 40)
        + '  ' + GetPStr(plan.New[i].Ra.FilePath, FilePathLen) + note);
    end;
  end;
  if Length(plan.Skipped) > 0 then
  begin
    Say('');
    Say('Skipped ' + IntToStr(Length(plan.Skipped)) + ':');
    for i := 0 to High(plan.Skipped) do
      Say('  ' + RawAreaName(plan.Skipped[i].SourceDir, start, True) + ': ' + plan.Skipped[i].Reason);
  end;

  if Length(plan.New) = 0 then
  begin
    Say('');
    Say('Nothing to add.');
    Exit(0);
  end;
  if dryRun then
  begin
    Say('');
    Say('Dry run: no files were changed.');
    Exit(0);
  end;

  SetLength(links, 0);
  try
    links := CreateLinks(linkDir, plan);
  except
    on e: EMd do
    begin
      Complain('error: ' + e.WMsg);
      Complain('No files were changed.');
      Exit(1);
    end;
  end;
  if Length(links) > 0 then
    Say('Created ' + IntToStr(Length(links)) + ' symlink(s) in ' + linkDir);

  try
    if backup then
    begin
      backups := BackupFiles(af);
      for i := 0 to High(backups) do
        Say('Backed up to ' + backups[i]);
    end;
    WritePlan(af, plan);
  except
    on e: EMd do
    begin
      RemoveLinks(links);
      Complain('error: writing area files failed: ' + e.WMsg);
      Exit(1);
    end;
  end;

  Say('');
  Say('Wrote ' + IntToStr(Length(plan.New)) + ' area(s). ' + FileNameOf(af.FilesRa) + ' and '
    + FileNameOf(af.FilesEle) + ' now hold ' + IntToStr(Length(af.Ra) + Length(plan.New))
    + ' records each; ' + FileNameOf(af.FilesRdx) + ' was rebuilt.');
  Result := 0;
end;

begin
  if (SizeOf(TFilesRecord) <> 168) or (SizeOf(TEleFilesRecord) <> 1139) then
  begin
    Complain('internal error: record sizes don''t match EleBBS 0.11b1');
    Halt(3);
  end;
  Randomize;
  ExitCode := RunMain;
end.
