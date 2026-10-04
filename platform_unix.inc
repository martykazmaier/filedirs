{ Linux/Unix implementation of the platform layer used by filedirs.pas.
  File names are treated as UTF-8. Only code page 437 is built in. }

const
  Cp437High: array[$80..$FF] of Word = (
    $00C7, $00FC, $00E9, $00E2, $00E4, $00E0, $00E5, $00E7, $00EA, $00EB, $00E8, $00EF, $00EE, $00EC, $00C4, $00C5,
    $00C9, $00E6, $00C6, $00F4, $00F6, $00F2, $00FB, $00F9, $00FF, $00D6, $00DC, $00A2, $00A3, $00A5, $20A7, $0192,
    $00E1, $00ED, $00F3, $00FA, $00F1, $00D1, $00AA, $00BA, $00BF, $2310, $00AC, $00BD, $00BC, $00A1, $00AB, $00BB,
    $2591, $2592, $2593, $2502, $2524, $2561, $2562, $2556, $2555, $2563, $2551, $2557, $255D, $255C, $255B, $2510,
    $2514, $2534, $252C, $251C, $2500, $253C, $255E, $255F, $255A, $2554, $2569, $2566, $2560, $2550, $256C, $2567,
    $2568, $2564, $2565, $2559, $2558, $2552, $2553, $256B, $256A, $2518, $250C, $2588, $2584, $258C, $2590, $2580,
    $03B1, $00DF, $0393, $03C0, $03A3, $03C3, $00B5, $03C4, $03A6, $0398, $03A9, $03B4, $221E, $03C6, $03B5, $2229,
    $2261, $00B1, $2265, $2264, $2320, $2321, $00F7, $2248, $00B0, $2219, $00B7, $221A, $207F, $00B2, $25A0, $00A0);

function ToSys(const s: UnicodeString): RawByteString;
begin
  Result := UTF8Encode(s);
end;

function FromSys(const s: RawByteString): UnicodeString;
begin
  Result := UTF8Decode(s);
end;

function LastErrorText: UnicodeString;
begin
  Result := TrimW(UnicodeString(SysErrorMessage(GetLastOSError)));
end;

procedure WriteTo(toErr: Boolean; const s: UnicodeString);
var
  u: RawByteString;
  fd: cint;
begin
  u := ToSys(s + #10);
  if toErr then fd := 2 else fd := 1;
  if Length(u) > 0 then
    FpWrite(fd, u[1], Length(u));
end;

function LowerW(const s: UnicodeString): UnicodeString;
var
  i: Integer;
begin
  Result := s;
  UniqueString(Result);
  for i := 1 to Length(Result) do
    if (Result[i] >= 'A') and (Result[i] <= 'Z') then
      Result[i] := WideChar(Ord(Result[i]) + 32);
end;

function UpperW(const s: UnicodeString): UnicodeString;
var
  i: Integer;
begin
  Result := s;
  UniqueString(Result);
  for i := 1 to Length(Result) do
    if (Result[i] >= 'a') and (Result[i] <= 'z') then
      Result[i] := WideChar(Ord(Result[i]) - 32);
end;

function ValidCodePage(cp: Integer): Boolean;
begin
  Result := cp = 437;
end;

function EncodeCP(const s: UnicodeString): TBytes;
var
  i, b: Integer;
  c: Word;
begin
  SetLength(Result, Length(s));
  for i := 1 to Length(s) do
  begin
    c := Ord(s[i]);
    if c < $80 then
      Result[i - 1] := c
    else
    begin
      Result[i - 1] := Ord('?');
      for b := $80 to $FF do
        if Cp437High[b] = c then
        begin
          Result[i - 1] := b;
          Break;
        end;
    end;
  end;
end;

function DecodeCP(p: PByte; len: Integer): UnicodeString;
var
  i: Integer;
begin
  SetLength(Result, len);
  for i := 0 to len - 1 do
    if p[i] < $80 then
      Result[i + 1] := WideChar(p[i])
    else
      Result[i + 1] := WideChar(Cp437High[p[i]]);
end;

function PathExists(const p: UnicodeString): Boolean;
var
  st: TStat;
begin
  Result := FpLstat(PChar(ToSys(p)), st) = 0;
end;

function IsDir(const p: UnicodeString): Boolean;
var
  st: TStat;
begin
  Result := (FpStat(PChar(ToSys(p)), st) = 0) and fpS_ISDIR(st.st_mode);
end;

function IsFile(const p: UnicodeString): Boolean;
var
  st: TStat;
begin
  Result := (FpStat(PChar(ToSys(p)), st) = 0) and not fpS_ISDIR(st.st_mode);
end;

function IsLink(const p: UnicodeString): Boolean;
var
  st: TStat;
  q: UnicodeString;
begin
  q := StripTrailingSeps(p);
  if q = '' then Exit(False);
  Result := (FpLstat(PChar(ToSys(q)), st) = 0) and fpS_ISLNK(st.st_mode);
end;

{ Subdirectories and files directly inside dir. Symlinked directories are only
  listed when follow is set; symlinked files count as files. }
function ListDir(const dir: UnicodeString; follow: Boolean; out subs, files: TUStrArray): Boolean;
var
  d: PDir;
  e: PDirent;
  name, full: UnicodeString;
  st: TStat;
begin
  SetLength(subs, 0);
  SetLength(files, 0);
  d := FpOpendir(PChar(ToSys(dir)));
  if d = nil then Exit(False);
  repeat
    e := FpReaddir(d^);
    if e = nil then Break;
    name := FromSys(RawByteString(PChar(@e^.d_name[0])));
    if (name = '.') or (name = '..') then Continue;
    full := JoinPath(dir, name);
    if FpLstat(PChar(ToSys(full)), st) <> 0 then Continue;
    if fpS_ISLNK(st.st_mode) then
    begin
      if FpStat(PChar(ToSys(full)), st) <> 0 then Continue;
      if fpS_ISDIR(st.st_mode) then
      begin
        if follow then AddStr(subs, name);
      end
      else
        AddStr(files, name);
    end
    else if fpS_ISDIR(st.st_mode) then
      AddStr(subs, name)
    else
      AddStr(files, name);
  until False;
  FpClosedir(d^);
  Result := True;
end;

{ Returns dir/name for the file whose name matches case-insensitively, or ''. }
function FindFileCI(const dir, name: UnicodeString): UnicodeString;
var
  subs, files: TUStrArray;
  i: Integer;
begin
  Result := JoinPath(dir, name);
  if IsFile(Result) then Exit;
  Result := '';
  if not ListDir(dir, False, subs, files) then Exit;
  for i := 0 to High(files) do
    if LowerW(files[i]) = LowerW(name) then
      Exit(JoinPath(dir, files[i]));
end;

function FullPath(const p: UnicodeString): UnicodeString;
begin
  Result := FromSys(ExpandFileName(ToSys(p)));
  if Result = '' then Result := p;
end;

function LongPath(const p: UnicodeString): UnicodeString;
begin
  Result := '';
end;

function ShortPath(const p: UnicodeString): UnicodeString;
begin
  Result := '';
end;

function CurrentDir: UnicodeString;
begin
  Result := FromSys(GetCurrentDir);
  if Result = '' then Result := '.';
end;

function GetEnvW(const name: UnicodeString): UnicodeString;
var
  v: PChar;
begin
  v := FpGetEnv(PChar(ToSys(name)));
  if v = nil then
    Result := ''
  else
    Result := FromSys(RawByteString(v));
end;

{ Where a path really leads once symlinks are followed; '' if it doesn't exist. }
function FinalPath(const p: UnicodeString): UnicodeString;
var
  buf: array[0..4095] of Char;
  n, hops: Integer;
  target: UnicodeString;
begin
  if not PathExists(p) then Exit('');
  Result := FullPath(p);
  if Result <> '/' then Result := StripTrailingSeps(Result);
  for hops := 1 to 40 do
  begin
    if not IsLink(Result) then Exit;
    n := FpReadlink(PChar(ToSys(Result)), @buf[0], Length(buf) - 1);
    if n <= 0 then Exit;
    buf[n] := #0;
    target := FromSys(RawByteString(PChar(@buf[0])));
    if (target = '') or (target[1] <> '/') then
      target := JoinPath(DirOf(Result), target);
    Result := FullPath(target);
    if Result <> '/' then Result := StripTrailingSeps(Result);
  end;
end;

function ReadAllBytes(const p: UnicodeString): TBytes;
var
  fd: cint;
  st: TStat;
  got, n: Int64;
begin
  SetLength(Result, 0);
  fd := FpOpen(PChar(ToSys(p)), O_RDONLY);
  if fd < 0 then
    raise EMd.CreateW('cannot read ' + p + ': ' + LastErrorText);
  try
    if FpFStat(fd, st) <> 0 then
      raise EMd.CreateW('cannot read ' + p + ': ' + LastErrorText);
    SetLength(Result, st.st_size);
    got := 0;
    while got < st.st_size do
    begin
      n := FpRead(fd, Result[got], st.st_size - got);
      if n <= 0 then
        raise EMd.CreateW('cannot read ' + p + ': ' + LastErrorText);
      Inc(got, n);
    end;
  finally
    FpClose(fd);
  end;
end;

procedure WriteAllBytes(const p: UnicodeString; const data: TBytes);
var
  fd: cint;
  done, n: Int64;
begin
  fd := FpOpen(PChar(ToSys(p)), O_WRONLY or O_CREAT or O_TRUNC, &644);
  if fd < 0 then
    raise EMd.CreateW(p + ': ' + LastErrorText);
  done := 0;
  while done < Length(data) do
  begin
    n := FpWrite(fd, data[done], Length(data) - done);
    if n <= 0 then
    begin
      FpClose(fd);
      raise EMd.CreateW(p + ': ' + LastErrorText);
    end;
    Inc(done, n);
  end;
  if FpFsync(fd) <> 0 then
  begin
    FpClose(fd);
    raise EMd.CreateW(p + ': ' + LastErrorText);
  end;
  FpClose(fd);
end;

{ Keep the permissions and owner of the file being replaced. }
procedure CopyMode(const src, dst: UnicodeString);
var
  st: TStat;
begin
  if FpStat(PChar(ToSys(src)), st) <> 0 then Exit;
  FpChmod(PChar(ToSys(dst)), st.st_mode and &7777);
  FpChown(PChar(ToSys(dst)), st.st_uid, st.st_gid);
end;

function RenameReplace(const src, dst: UnicodeString): Boolean;
begin
  Result := FpRename(PChar(ToSys(src)), PChar(ToSys(dst))) = 0;
end;

procedure RemoveFileW(const p: UnicodeString);
begin
  FpUnlink(PChar(ToSys(p)));
end;

function CopyFileTo(const src, dst: UnicodeString): Boolean;
begin
  try
    WriteAllBytes(dst, ReadAllBytes(src));
    CopyMode(src, dst);
    Result := True;
  except
    on EMd do Result := False;
  end;
end;

function MakeDir(const p: UnicodeString): Boolean;
begin
  Result := FpMkdir(PChar(ToSys(p)), &755) = 0;
end;

function MakeDirLink(const link, target: UnicodeString; out err: UnicodeString): Boolean;
begin
  err := '';
  Result := FpSymlink(PChar(ToSys(target)), PChar(ToSys(link))) = 0;
  if not Result then err := LastErrorText;
end;

procedure RemoveLink(const p: UnicodeString);
begin
  FpUnlink(PChar(ToSys(p)));
end;

function GetArgs: TUStrArray;
var
  i: Integer;
begin
  SetLength(Result, 0);
  for i := 1 to argc - 1 do
    AddStr(Result, FromSys(RawByteString(argv[i])));
end;
